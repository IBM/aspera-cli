# frozen_string_literal: true

module Aspera
  module Schema
    # Generate documentation from a JSON Schema: in terminal and in manual.
    # Information from `x-` extensions is provided by the caller (`annotate`).
    class Documentation
      # Map JSON Schema type names to user-friendly display names
      JSON_TYPE_TO_DOC = {
        'string'  => 'String',
        'integer' => 'Integer',
        'number'  => 'Number',
        'boolean' => 'Bool',
        'array'   => 'Array',
        'object'  => 'Hash'
      }.freeze
      COLUMNS = %w[name type description].freeze
      # @param formatter      [FormatterInterface] Formatter with methods: markdown_text, special_format
      # @param schema         [Reader]
      # @param code_highlight [Boolean] `true`: format name and type as code
      # @param annotate       [Proc, nil] Called with the schema of a property (`Hash`) and the formatter.
      #   Returns lines added to the description (`Array<String>`), or `nil` to hide the property.
      # @param extra_columns  [Hash{String => Proc}] Columns inserted before the description: name => Proc
      #   called with the schema of a property (`Hash`) and the formatter, returns the value of the cell.
      def initialize(formatter, schema, code_highlight: false, annotate: nil, extra_columns: {})
        @formatter = formatter
        @schema = schema
        @code_highlight = code_highlight
        @annotate = annotate
        @extra_columns = extra_columns
        @columns = COLUMNS.dup.insert(-2, *extra_columns.keys).freeze
        # Sections: each entry is {header: row_or_nil, rows: []}
        # A flat schema produces a single section with no header.
        @sections = [{header: nil, rows: []}]
      end

      def rows
        @sections.flat_map do |section|
          sorted = section[:rows].sort_by { |i| i['name'] }
          section[:header] ? [section[:header]] + sorted : sorted
        end
      end

      # @return [Array<String>]
      attr_reader :columns

      # First row is the titles (for Markdown table generation)
      # @return [Array<Array<String>>]
      def table
        [@columns] + rows.map { |row| @columns.map { |field| row[field] } }
      end

      # Generate a documentation table from a JSON schema
      #
      # Recursively processes a JSON schema to create a formatted table for manual documentation.
      # Handles nested objects, arrays, and extracts metadata (descriptions, types, enums, deprecations).
      #
      # @param schema [Reader] The JSON schema to process
      # @return [Documentation]
      def build(schema = nil)
        code = @code_highlight ? ->(c) { "`#{c}`" } : ->(c) { c }
        schema ||= @schema
        on_variant = ->(variant_reader, discriminant_property, discriminant_value) do
          title = variant_reader.current['title'] || variant_reader.current['description']
          header =
            if discriminant_property && discriminant_value
              desc = @formatter.markdown_text("`#{discriminant_value}`")
              desc += ": #{@formatter.markdown_text(title)}" if title
              {
                'name'        => @formatter.markdown_text("**#{discriminant_property}**"),
                'type'        => code.call(JSON_TYPE_TO_DOC['string']),
                'description' => desc
              }
            elsif title
              {'name' => @formatter.markdown_text("**#{title}**")}
            end
          @sections.push({header: header, rows: []})
        end
        schema.each_property(on_variant: on_variant) do |property_schema, _name, property_full_name, required|
          node = property_schema.current
          annotations = @annotate ? @annotate.call(node, @formatter) : []
          next if annotations.nil?
          item = {'name' => code.call(property_full_name)}
          item_type = type_text(node)
          item['type'] = code.call(item_type) unless item_type.nil?
          @extra_columns.each { |column, value| item[column] = value.call(node, @formatter) }
          description = []
          description.push("DEPRECATED: #{node['x-deprecation']}") if node.key?('x-deprecation')
          # Render Markdown formatting and split lines
          description.concat(@formatter.markdown_text(node['description']).split("\n")) if node.key?('description')
          description.push('Required.') if required
          description.push("Allowed values: #{node['enum'].map { |v| value_text(v) }.join(', ')}.") if node.key?('enum')
          description.push("Default: #{value_text(node['default'])}.") if node.key?('default')
          description.push("Example: #{value_text(node['example'])}.") if node.key?('example')
          description.concat(annotations)
          item['description'] = description unless description.empty?
          @sections.last[:rows].push(item)
        end
        self
      end

      private

      # @param node [Hash] Schema of a property
      # @return [String, nil] Readable type, from `type`, or else from the types of `oneOf` alternatives, `nil` if none
      def type_text(node)
        if node['type'].nil?
          types = Array(node['oneOf']).filter_map { |variant| type_text(variant) }.uniq
          return types.empty? ? nil : types.join(', ')
        end
        return node['type'].map { |t| JSON_TYPE_TO_DOC.fetch(t, t) }.join(', ') if node['type'].is_a?(Array)
        result = JSON_TYPE_TO_DOC.fetch(node['type'], node['type'])
        result = "#{result}[#{type_text(node['items'])}]" if node['type'].eql?('array') && node.dig('items', 'type').is_a?(String)
        result
      end

      # Format a schema value (enum, default, example) as code
      # @param value [Object] value from schema, `nil` for JSON `null`
      # @return [String]
      def value_text(value)
        return @formatter.special_format('null') if value.nil?
        @formatter.markdown_text("`#{value}`")
      end
    end
  end
end
