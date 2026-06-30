# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/formatter_interface'
require 'aspera/markdown'
require 'aspera/assert'

module Aspera
  module Cli
    # Terminal formatter with ANSI colors and Unicode support
    # @see FormatterInterface
    # @see MarkdownFormatter (in build/lib/doc_helper.rb)
    module TerminalFormatter
      HINT = 'HINT:'.bg_green.gray.blink.freeze
      include FormatterInterface

      # Format boolean with colored symbol (✓/✗ or Y/ )
      def tick(yes)
        result =
          if Environment.terminal_supports_unicode?
            yes ? "\u2713" : "\u2717"
          else
            yes ? 'Y' : ' '
          end
        return result.green if yes
        return result.red
      end

      # Format special values with colors (dim for empty, reverse for others)
      def special_format(what)
        result = "<#{what}>"
        return %w[null empty].any?{ |s| what.include?(s)} ? result.dim : result.reverse_color
      end

      # Prepare table row for terminal display (word wrap arrays)
      def check_row(row)
        row.each_key do |k|
          row[k] = row[k].map{ |i| WordWrap.ww(i.to_s, 120).chomp}.join("\n") if row[k].is_a?(Array)
        end
      end

      # Convert Markdown to terminal format (**bold** -> blue, `code` -> bold)
      # @param match [MatchData, String]
      def markdown_text(match)
        if match.is_a?(String)
          match = Markdown::FORMATS.match(match)
          Aspera.assert(match, 'markdown text does not match any known format')
        end
        Aspera.assert_type(match, MatchData)
        if match[:entity]
          Aspera.assert_values(match[:entity], %w[bsol])
          '\\'
        elsif match[:bold]
          match[:bold].to_s.blue
        elsif match[:code]
          match[:code].to_s.bold
        else
          Aspera.error_unexpected_value(match.to_s)
        end
      end

      module_function :tick, :special_format, :check_row, :markdown_text
    end
  end
end
