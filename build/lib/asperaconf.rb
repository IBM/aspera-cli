#!/usr/bin/env ruby
# frozen_string_literal: true

module Aspera
  module Conf
    # ═════════════════════════════════════════════════════════════════════════════
    # CommentParser
    #
    # Parses the structured comments that aspera.conf places after each element.
    #
    # Comment anatomy in aspera.conf:
    #
    #   <level>log</level>
    #     <ǃ-- Logging Level: Lookup disable, log, dbg1 or dbg2 -->    ← primary
    #     <ǃ-- asconfigurator -x "set_logging_data;level,<value>" -->  ← tool hint (skip)
    #     <ǃ-- Amount of detail in logging. -->                        ← description
    #
    # The primary comment encodes:
    #   - Optional marker  : "Not defined by default."
    #   - Human label      : "Logging Level"
    #   - Type / enum hint : "32 bit unsigned int" | "Boolean true or false" |
    #                        "Lookup val1, val2 or val3" | "Character string" | …
    # ═════════════════════════════════════════════════════════════════════════════
    class CommentParser
      attr_reader :optional, # true if "Not defined by default."
        :label,        # human-readable field label
        :raw_type,     # raw type string from primary comment
        :enum_values,  # Array of allowed string values (may be empty)
        :description   # Array of descriptive sentences

      def initialize(comments)
        @optional    = false
        @label       = nil
        @raw_type    = nil
        @enum_values = []
        @description = []
        parse(comments)
      end

      private

      def parse(comments)
        return if comments.empty?

        primary = comments.first.dup

        # ── Optional marker ──────────────────────────────────────────────────
        if primary.include?('Not defined by default')
          @optional = true
          primary = primary.sub('Not defined by default.', '').strip
        end

        # ── Primary comment patterns ─────────────────────────────────────────
        #
        # "Label: Lookup val1, val2 or val3"  → true enum constraint
        if primary =~ /\A(.+?):\s*(Lookup\s+.+)\z/i
          @label       = ::Regexp.last_match(1).strip
          @enum_values = parse_lookup(::Regexp.last_match(2))
          @raw_type    = +'lookup'

        # "Label: Type  Preset: DisplayName"  → free-text field with a named sentinel.
        # Preset values are display aliases (e.g. "Unlimited" meaning 0, "Disabled"
        # meaning 0) — NOT real enum constraints. Keep them in description only.
        elsif primary =~ /\A(.+?):\s*(.+?)\s+Presets?:\s*(.+)\z/i
          @label       = ::Regexp.last_match(1).strip
          @raw_type    = ::Regexp.last_match(2).strip
          @description << "Preset display values: #{::Regexp.last_match(3).strip}."

        # "Label: Type"
        elsif primary =~ /\A(.+?):\s*(.+)\z/
          @label    = ::Regexp.last_match(1).strip
          @raw_type = ::Regexp.last_match(2).strip
        end

        # Strip quoted annotation from raw_type  e.g. 32 bit signed int "some note"
        @raw_type&.gsub!(/"[^"]*"/, '')
        @raw_type&.strip!

        # ── Follow-up comments ────────────────────────────────────────────────
        comments[1..].each do |c|
          c = c.strip
          next if c.empty?
          next if c.start_with?('asconfigurator')   # tool hint — not useful for docs
          next if c.start_with?('Subtype:')         # internal sub-classification
          next if c.start_with?('Description if empty:')

          if c =~ /\AChoices:\s*(.+)\z/i
            @enum_values = parse_enum_list(::Regexp.last_match(1))
          elsif c =~ /\ALookup\s+(.+)\z/i
            @enum_values = parse_lookup("Lookup #{::Regexp.last_match(1)}")
          elsif c =~ /\ARange:\s*(.+)\z/
            # Keep range as part of description for documentation purposes
            @description << "Range: #{::Regexp.last_match(1).strip}"
          else
            cleaned = c.gsub(/\s+/, ' ').strip
            @description << cleaned unless cleaned.empty?
          end
        end
      end

      # Parse "Lookup val1, val2 or val3"  or  "val1, val2, val3"
      def parse_lookup(str)
        str = str.sub(/\ALookup\s+/i, '')
        parse_enum_list(str)
      end

      # Split on ", " or " or " separators
      def parse_enum_list(str)
        str.split(/,\s*|\s+or\s+/).map(&:strip).reject(&:empty?)
      end
    end

    # ═════════════════════════════════════════════════════════════════════════════
    # TypeMapper
    #
    # Converts the raw type strings from aspera.conf comments into XSD types.
    #
    # Design note: many numeric fields also accept sentinel strings like
    # "Unlimited", "Disabled", "Undefined", "AS_NULL", so xs:string is used
    # universally. The raw_type description is preserved in xs:documentation.
    # ═════════════════════════════════════════════════════════════════════════════
    module TypeMapper
      class << self
        # Maps raw_type string → XSD base type string (always xs:string for safety)
        def xsd_base(raw_type)
          'xs:string' # all fields may carry sentinel strings like "Unlimited"
        end

        def boolean?(raw_type)
          raw_type.to_s.downcase.include?('boolean')
        end

        # A concise type label for xs:documentation
        def summary(raw_type)
          return if raw_type.nil? || raw_type == 'lookup'
          case raw_type.downcase
          when /32 bit unsigned/           then 'uint32'
          when /64 bit unsigned/           then 'uint64'
          when /32 bit signed/             then 'int32'
          when /64 bit signed/             then 'int64'
          when /boolean/                   then 'boolean (true|false)'
          when /double precision float/    then 'float'
          when /character string/          then 'string'
          when /octal/                     then 'octal string'
          when /time value/                then 'time string (e.g. 01:00:00)'
          when /bits per second/           then 'bits/sec string (e.g. 100K)'
          when /cron/                      then 'cron/range schedule'
          else raw_type
          end
        end
      end
    end

    # ═════════════════════════════════════════════════════════════════════════════
    # XSDWriter
    #
    # Stateful DSL that builds an indented XSD document as an array of lines.
    #
    # Generates an annotated XSD schema from a documented aspera.conf sample XML.
    # Extracts field types, enum values, defaults, and descriptions directly from
    # the inline XML comments, so the schema and documentation stay in sync.
    #
    # Validate with Nokogiri:
    #   schema = Nokogiri::XML::Schema(File.read('aspera_conf.xsd'))
    #   errors = schema.validate(Nokogiri::XML(File.read('aspera.conf')))
    #   errors.each { |e| puts e.message }
    # ═════════════════════════════════════════════════════════════════════════════
    class XSDWriter
      INDENT_NUM = 2
      INDENT_CHAR = ' '

      def initialize
        @lines = []
        @depth = 0
      end

      def to_s
        @lines.join("\n").concat("\n")
      end

      # ── Document skeleton ──────────────────────────────────────────────────
      def header
        line('<?xml version="1.0" encoding="UTF-8"?>')
        line('<xs:schema')
        line('    xmlns:xs="http://www.w3.org/2001/XMLSchema"')
        line('    elementFormDefault="qualified"')
        line('    version="1.0">')
        blank
      end

      def footer
        line('</xs:schema>')
      end

      # ── Element open/close ─────────────────────────────────────────────────
      def open_element(name, min_occurs: nil, max_occurs: nil, type: nil, default: nil)
        attrs = " name=\"#{name}\""
        attrs += " type=\"#{type}\"" if type
        attrs += " default=\"#{escape(default)}\"" if default
        attrs += " minOccurs=\"#{min_occurs}\"" unless min_occurs.nil?
        attrs += " maxOccurs=\"#{max_occurs}\"" unless max_occurs.nil?
        line("<xs:element#{attrs}>")
        @depth += 1
      end

      def close_element
        @depth -= 1
        line('</xs:element>')
      end

      # ── Annotation (documentation block) ──────────────────────────────────
      def annotation(parts)
        text = parts.compact.reject(&:empty?).join(' ').strip
        return if text.empty?
        line('<xs:annotation>')
        @depth += 1
        line("<xs:documentation>#{escape(text)}</xs:documentation>")
        @depth -= 1
        line('</xs:annotation>')
      end

      # ── Complex type ───────────────────────────────────────────────────────
      def open_complex_type
        line('<xs:complexType>')
        @depth += 1
      end

      def close_complex_type
        @depth -= 1
        line('</xs:complexType>')
      end

      # ── Content models ─────────────────────────────────────────────────────

      # xs:all — unordered, each child appears 0 or 1 times
      # XSD 1.0 restriction: child maxOccurs must be 1
      def open_all
        line('<xs:all>')
        @depth += 1
      end

      def close_all
        @depth -= 1
        line('</xs:all>')
      end

      # xs:sequence — ordered children; used when a child repeats (maxOccurs > 1)
      def open_sequence
        line('<xs:sequence>')
        @depth += 1
      end

      def close_sequence
        @depth -= 1
        line('</xs:sequence>')
      end

      # ── Simple type / restrictions ─────────────────────────────────────────
      def open_simple_type
        line('<xs:simpleType>')
        @depth += 1
      end

      def close_simple_type
        @depth -= 1
        line('</xs:simpleType>')
      end

      def restriction_enum(values)
        line('<xs:restriction base="xs:string">')
        @depth += 1
        values.each{ |v| line("<xs:enumeration value=\"#{escape(v)}\"/>")}
        @depth -= 1
        line('</xs:restriction>')
      end

      # ── Attribute ──────────────────────────────────────────────────────────
      def attribute(name, type: 'xs:string', use: 'optional', fixed: nil)
        extra = fixed ? " fixed=\"#{escape(fixed)}\"" : ''
        line("<xs:attribute name=\"#{name}\" type=\"#{type}\" use=\"#{use}\"#{extra}/>")
      end

      def blank
        # @lines << ''
      end

      private

      def line(str)
        @lines << "#{INDENT_CHAR * (INDENT_NUM * @depth)}#{str}"
      end

      def escape(str)
        str.to_s
          .gsub('&', '&amp;')
          .gsub('<', '&lt;')
          .gsub('>', '&gt;')
          .gsub('"', '&quot;')
      end
    end

    # ═════════════════════════════════════════════════════════════════════════════
    # Generator
    #
    # Walks the Nokogiri DOM, associates comments with elements, and drives
    # XSDWriter to produce the schema.
    # ═════════════════════════════════════════════════════════════════════════════
    class Generator
      # Elements known to repeat inside their parent
      REPEATING = %w[trunk log_setting path rule filter opt command restriction].freeze

      def initialize(xml_string)
        require 'nokogiri'
        @doc     = Nokogiri::XML(xml_string){ |c| c.default_xml.noblanks}
        @version = extract_version
        @xsd     = XSDWriter.new
      end

      def generate
        @xsd.header
        process_element(@doc.root, root: true)
        @xsd.blank
        @xsd.footer
        @xsd.to_s
      end

      private

      # ── Build version ─────────────────────────────────────────────────────
      #
      # The first child comment of <conf> carries the build version:
      #   <ǃ-- Build version 4.4.7.2228 -->
      def extract_version
        @doc.root.children.each do |node|
          next unless node.is_a?(Nokogiri::XML::Comment)
          m = node.content.strip.match(/Build version\s+([\d.]+)/i)
          return m[1] if m
        end
        'unknown'
      end

      # ── Comment association ────────────────────────────────────────────────
      #
      # Comments in aspera.conf are siblings of the element they describe,
      # positioned immediately after it in the parent's child list.
      # We collect all contiguous comment/text siblings until the next element.
      def comments_for(elem)
        result = []
        node   = elem.next_sibling
        while node
          case node
          when Nokogiri::XML::Comment
            result << node.content.strip
          when Nokogiri::XML::Text
            next  # skip whitespace
          when Nokogiri::XML::Element
            break # reached next peer element
          end
          node = node.next_sibling
        end
        result
      end

      # ── Element classification ─────────────────────────────────────────────
      def complex?(elem)
        elem.element_children.any?
      end

      # Element has sibling(s) with the same name, or is in the known-repeating list
      def repeating?(elem)
        return true if REPEATING.include?(elem.name)
        siblings = elem.parent&.element_children&.map(&:name) || []
        siblings.count(elem.name) > 1
      end

      # Has any element child that can repeat (affects xs:all vs xs:sequence choice)
      def has_repeating_children?(elem)
        elem.element_children.any?{ |c| repeating?(c)}
      end

      # An element with attributes in the source XML needs mixed content handling
      def has_attributes?(elem)
        elem.attributes.any?
      end

      # ── Occurrence derivation ──────────────────────────────────────────────
      def occurrences(elem, info, root:)
        return [nil, nil] if root

        min = info.optional || elem.text.strip == 'AS_NULL' ? 0 : 1
        max = repeating?(elem) ? 'unbounded' : nil # nil = default (1)
        [min, max]
      end

      # ── Documentation assembly ─────────────────────────────────────────────
      # Enum values are intentionally omitted from the text: they are already
      # expressed as xs:enumeration restrictions and repeating them in
      # xs:documentation would be redundant noise.
      def doc_parts(elem, info)
        parts = []

        # Human label (skip if it's just the element name reformatted)
        parts << "#{info.label}." if info.label && info.label.downcase.tr(' _', '') != elem.name.downcase.tr('_', '')

        # Type summary — only for free-text fields (enum fields are self-describing)
        type_summary = TypeMapper.summary(info.raw_type)
        parts << "Type: #{type_summary}." if type_summary && info.enum_values.empty?

        # Default value is expressed as xs:element @default — not repeated here.
        # (Only valid for leaf/simple-type elements; complex elements carry no default.)

        # Narrative description from follow-up comments
        parts.concat(info.description)

        parts
      end

      # ── Core recursive processor ────────────────────────────────────────────
      def process_element(elem, root: false)
        info = CommentParser.new(comments_for(elem))
        min_occ, max_occ = occurrences(elem, info, root: root)

        if root
          emit_root(elem)
        elsif complex?(elem)
          emit_complex(elem, info, min_occ, max_occ)
        else
          emit_leaf(elem, info, min_occ, max_occ)
        end
      end

      # ── Root element (`<conf version="2">`) ───────────────────────────────
      def emit_root(elem)
        @xsd.open_element(elem.name)
        @xsd.annotation(['Root configuration element for Aspera transfer software.',
                         "Build version #{@version}."])
        @xsd.open_complex_type
        emit_children(elem)
        # Emit attributes defined on the root element
        elem.attributes.each do |name, attr|
          @xsd.attribute(name, type: 'xs:string', use: 'required', fixed: attr.value)
        end
        @xsd.close_complex_type
        @xsd.close_element
      end

      # ── Complex element (has child elements) ──────────────────────────────
      def emit_complex(elem, info, min_occ, max_occ)
        @xsd.blank
        @xsd.open_element(elem.name, min_occurs: min_occ, max_occurs: max_occ)
        @xsd.annotation(doc_parts(elem, info))
        @xsd.open_complex_type

        # Attributes on this element (e.g. <schedule format="ranges">)
        elem.attributes.each_key do |name|
          @xsd.attribute(name, type: 'xs:string')
        end

        emit_children(elem)
        @xsd.close_complex_type
        @xsd.close_element
      end

      # ── Leaf element (text content only) ──────────────────────────────────
      def emit_leaf(elem, info, min_occ, max_occ)
        # Determine enum values; inject true/false for boolean fields
        enum_vals = info.enum_values.dup
        enum_vals = %w[true false] if enum_vals.empty? && TypeMapper.boolean?(info.raw_type)

        # Default value: omit AS_NULL (means "not set") and empty strings.
        # Also omit if the value isn't a member of the enum — this can happen when
        # the XML stores a numeric value (e.g. 0) that the comment describes with a
        # named alias (e.g. "Unlimited"). XSD requires @default to satisfy the type.
        default_val = elem.text.strip
        default_val = nil if default_val.empty? || default_val == 'AS_NULL'
        default_val = nil if enum_vals.any? && !enum_vals.include?(default_val)
        # Free-text element → xs:string with documentation
        @xsd.open_element(
          elem.name,
          min_occurs: min_occ,
          max_occurs: max_occ,
          type: enum_vals.any? ? nil : 'xs:string',
          default: default_val
        )
        @xsd.annotation(doc_parts(elem, info))
        # Element with constrained values → inline simpleType
        if enum_vals.any?
          @xsd.open_simple_type
          @xsd.restriction_enum(enum_vals)
          @xsd.close_simple_type
        end
        @xsd.close_element
      end

      # ── Child dispatcher ───────────────────────────────────────────────────
      def emit_children(parent)
        children = parent.element_children
        return if children.empty?

        # xs:all — unordered, each child 0..1.   Great for config files.
        # xs:sequence — ordered, supports maxOccurs="unbounded" on children.
        # Use sequence only when a child must repeat.
        if has_repeating_children?(parent)
          @xsd.open_sequence
          children.each{ |child| process_element(child)}
          @xsd.close_sequence
        else
          @xsd.open_all
          children.each{ |child| process_element(child)}
          @xsd.close_all
        end
      end
    end
  end
end
