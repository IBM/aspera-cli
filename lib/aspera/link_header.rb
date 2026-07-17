# frozen_string_literal: true

require 'strscan'

module Aspera
  # Parse and represent an HTTP Link header as per RFC 8288.
  # Inspired by the link_header gem, with the following fixes:
  #   - rel lookup is case-insensitive (RFC 7230: parameter names are case-insensitive)
  #   - uses StringScanner so commas inside <URI> are never mistaken for entry separators
  #   - no external dependency
  class LinkHeader
    # A single link entry: one URI and its attribute pairs.
    class Link
      attr_reader :href, :attr_pairs

      def initialize(href, attr_pairs)
        @href = href
        @attr_pairs = attr_pairs
      end

      # Retrieve an attribute value by name, case-insensitively.
      def [](key)
        pair = @attr_pairs.detect { |k, _v| k.casecmp?(key) }
        pair&.last
      end
    end

    attr_reader :links

    def initialize(links = [])
      @links = links
    end

    # Return the href of the first link whose +rel+ attribute matches +rel+.
    # Comparison is case-insensitive per RFC 7230 §3.2 and RFC 8288 §3.
    # Returns nil if no link with that relation exists.
    # @param rel [String]
    # @return [String, nil]
    def find_href(rel: 'next')
      @links.detect { |link| link['rel']&.casecmp?(rel) }&.href
    end

    class << self
      # Parse a raw Link header value into a +LinkHeader+ instance.
      # Uses StringScanner so that commas inside <URI> are not treated as separators.
      # @param raw [String, nil]
      # @return [LinkHeader]
      def parse(raw)
        return new unless raw && !raw.empty?

        links = []
        scanner = StringScanner.new(raw)

        while scanner.scan(HREF_RE)
          href  = scanner[1].strip
          attrs = []
          while scanner.scan(ATTR_RE)
            key   = scanner[1]
            # scanner[2] = full match (token or "quoted"), scanner[3] = content inside double-quotes
            value = scanner[3] || scanner[2]
            attrs << [key, value]
            break unless scanner.scan(SEMI_RE)
          end
          links << Link.new(href, attrs)
          break unless scanner.scan(COMMA_RE)
        end

        new(links)
      end

      private :new
    end

    # RFC 2616 token: any char except separators
    TOKEN_RE  = /[^()<>@,;:\"\[\]?={}\s]+/  # RFC 2616 token
    QUOTED_RE = /"((?:[^"\\]|\\.)*)"/       # double-quoted string with backslash escapes
    HREF_RE   = /\s*<([^>]*)>\s*;?\s*/      # <URI> possibly followed by ;
    ATTR_RE   = /(#{TOKEN_RE})\s*=\s*(#{TOKEN_RE}|#{QUOTED_RE})\s*/ # key=value or key="value"
    SEMI_RE   = /;\s*/                       # parameter separator
    COMMA_RE  = /,\s*/                       # link entry separator
  end
end
