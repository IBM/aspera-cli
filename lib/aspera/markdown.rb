# frozen_string_literal: true

module Aspera
  # Formatting for Markdown
  class Markdown
    # Matches: **bold**, `code`, or an HTML entity (&amp;, &#169;, &#x1F4A9;)
    FORMATS = /(?:\*\*(?<bold>[^*]+?)\*\*)|(?:`(?<code>[^`]+)`)|&(?<entity>(?:[A-Za-z][A-Za-z0-9]{1,31}|#\d{1,7}|#x[0-9A-Fa-f]{1,6}));/m
    HTML_BREAK = '<br/>'

    class << self
      COL_WIDTH = 80
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
