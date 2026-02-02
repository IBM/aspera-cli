# frozen_string_literal: true

module Aspera
  # Formatting for Markdown
  class Markdown
    # Matches: **bold**, `code`, or an HTML entity (&amp;, &#169;, &#x1F4A9;)
    FORMATS = /(?:\*\*(?<bold>[^*]+?)\*\*)|(?:`(?<code>[^`]+)`)|&(?<entity>(?:[A-Za-z][A-Za-z0-9]{1,31}|#\d{1,7}|#x[0-9A-Fa-f]{1,6}));/m
    HTML_BREAK = '<br/>'

    class << self
      # Generate markdown from the provided 2D table
      def table(table)
        # get max width of each columns
        col_widths = table.transpose.map do |col|
          [col.flat_map{ |c| c.to_s.delete('`').split(HTML_BREAK).map(&:size)}.max, 80].min
        end
        headings = table.shift
        table.unshift(col_widths.map{ |col_width| '-' * col_width})
        table.unshift(headings)
        lines = table.map{ |line| "| #{line.map{ |i| i.to_s.gsub('\\', '\\\\').gsub('|', '\|')}.join(' | ')} |\n"}
        lines[1] = lines[1].tr(' ', '-')
        return lines.join.chomp
      end

      # Generate markdown list from the provided list
      def list(items)
        items.map{ |i| "- #{i}"}.join("\n")
      end

      def heading(title, level: 1)
        "#{'#' * level} #{title}\n\n"
      end

      # type: NOTE CAUTION WARNING IMPORTANT TIP INFO
      def admonition(lines, type: 'INFO')
        "> [!{type}]\n#{lines.map{ |l| "> #{l}"}.join("\n")}\n\n"
      end

      def code(lines, type: 'shell')
        "```#{type}\n#{lines.join("\n")}\n```\n\n"
      end

      def paragraph(text)
        "#{text}\n\n"
      end
    end
  end
end
