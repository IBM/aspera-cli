# frozen_string_literal: true

module Aspera
  # Formatting for Markdown
  class Markdown
    # Matches: **bold**, `code`, or an HTML entity (&amp;, &#169;, &#x1F4A9;)
    FORMATS = /(?:\*\*(?<bold>[^*]+?)\*\*)|(?:`(?<code>[^`]+)`)|&(?<entity>(?:[A-Za-z][A-Za-z0-9]{1,31}|#\d{1,7}|#x[0-9A-Fa-f]{1,6}));/m
    HTML_BREAK = '<br/>'

    class << self
      COL_WIDTH = 80

      # Convert a Markdown heading text to a GitHub-flavoured anchor.
      # Rules: downcase, keep letters/digits/spaces/hyphens, replace spaces with hyphens.
      # Duplicate anchors are disambiguated by appending -1, -2, … (pass a seen Hash to track).
      # @param text  [String]           raw heading text (without leading # and spaces)
      # @param seen  [Hash{String=>Integer}, nil]  mutable counter; pass the same Hash across a document
      # @return [String] anchor slug (without leading #)
      def heading_to_anchor(text, seen: nil)
        slug = text
          .downcase
          .gsub(/[`*_]/, '')           # strip inline code/bold/italic markers
          .gsub(/&[a-z]+;/, '')        # strip HTML entities
          .gsub(/[^\w\s-]/, '')        # keep word chars, spaces, hyphens
          .gsub(/\s+/, '-')            # spaces → hyphens
          .squeeze('-')                # collapse consecutive hyphens
          .strip
        if seen
          count = seen[slug].to_i
          seen[slug] = count + 1
          slug = "#{slug}-#{count}" if count > 0
        end
        slug
      end

      # Extract the table of contents from a Markdown document.
      # @param content [String]  full Markdown source
      # @return [Array<Hash>]   array of { level, title, anchor }
      HEADING_RE = /^(\#{1,6})\s+(.+)$/

      def toc(content)
        seen = {}
        content.each_line.filter_map do |line|
          m = line.match(HEADING_RE)
          next unless m
          title = m[2].strip
          {level: m[1].length, title: title, anchor: heading_to_anchor(title, seen: seen)}
        end
      end

      # Extract the content of a single section (heading + body until next heading of same/higher level).
      # @param content   [String]  full Markdown source
      # @param anchor    [String]  GitHub anchor slug (without #)
      # @return [String, nil]  the section content, or nil if not found
      def extract_section(content, anchor)
        seen = {}
        section_level = nil
        result = []
        content.each_line do |line|
          m = line.match(HEADING_RE)
          if m
            slug = heading_to_anchor(m[2].strip, seen: seen)
            if section_level.nil?
              # not yet found: check if this heading matches
              next unless slug == anchor
              section_level = m[1].length
            elsif m[1].length <= section_level
              # already in section: stop at same/higher level heading
              break
            end
          end
          result << line if section_level
        end
        result.empty? ? nil : result.join
      end

      # Generate markdown from the provided 2D table
      # @param table [Array<Array<String>>] 2D array of strings
      # @return [String] markdown table
      def table(table)
        # get max width of each columns
        col_widths = table.transpose.map do |col|
          [col.flat_map{ |c| c.to_s.delete('`').split(HTML_BREAK).map(&:size)}.max, COL_WIDTH].min
        end
        headings = table.shift
        table.unshift(col_widths.map{ |col_width| '-' * col_width})
        table.unshift(headings)
        lines = table.map{ |line| "| #{line.map{ |i| i.to_s.gsub('\\', '\\\\').gsub('|', '\|')}.join(' | ')} |\n"}
        lines[1] = lines[1].tr(' ', '-')
        return lines.join.chomp
      end

      # Generate markdown list from the provided list
      # @param items [Array<String>] list of items
      # @return [String] markdown unordered list
      def list(items)
        items.map{ |i| "- #{i}"}.join("\n")
      end

      # Generate a markdown heading
      # @param title [String] heading text
      # @param level [Integer] heading level (1–6)
      # @return [String] markdown heading
      def heading(title, level: 1)
        "#{'#' * level} #{title}\n\n"
      end

      # Generate a GitHub-flavoured admonition block
      # @param lines [Array<String>] lines of the admonition body
      # @param type [String] admonition type: NOTE, CAUTION, WARNING, IMPORTANT, TIP, INFO
      # @return [String] markdown admonition block
      def admonition(lines, type: 'INFO')
        "> [!#{type}]\n#{lines.map{ |l| "> #{l}"}.join("\n")}\n\n"
      end

      # Generate a fenced code block
      # @param lines [Array<String>] lines of code
      # @param type [String] language identifier for syntax highlighting
      # @return [String] markdown fenced code block
      def code(lines, type: 'shell')
        "```#{type}\n#{lines.join("\n")}\n```\n\n"
      end

      # Wrap text in inline code backticks
      # @param text [String] text to wrap
      # @return [String] inline code span
      def icode(text)
        "`#{text}`"
      end

      # Wrap text in a markdown paragraph (trailing blank line)
      # @param text [String] paragraph content
      # @return [String] paragraph with trailing newlines
      def paragraph(text)
        "#{text}\n\n"
      end
    end
  end
end
