# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/formatter_interface'
require 'aspera/markdown'
require 'aspera/assert'
require 'aspera/rainbow'
using Rainbow

module Aspera
  module Cli
    # Terminal formatter with ANSI colors and Unicode support
    # @see FormatterInterface
    # @see MarkdownFormatter (in build/lib/doc_helper.rb)
    module TerminalFormatter
      include FormatterInterface

      # Prefix for hint messages (evaluated on each call, as colors can be enabled or disabled by option)
      def hint
        'HINT:'.bg(:green).white.blink
      end

      # Format boolean with colored check mark, or Y and space without Unicode
      def tick(yes)
        result = Environment.char(yes ? '✓' : '✗')
        return result.green if yes
        result.red
      end

      # Format special values with colors (dim for empty, reverse for others)
      def special_format(what)
        result = "<#{what}>"
        %w[null empty].any? { |s| what.include?(s) } ? result.faint : result.inverse
      end

      # Convert Markdown inline markup to terminal format (**bold** -> blue, `code` -> bold)
      # @param text [String] text with Markdown inline markup
      # @return [String] text with terminal formatting
      def markdown_text(text)
        text.to_s.gsub(Markdown::INLINE_MARKUP_RE) do
          match = Regexp.last_match
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
      end

      module_function :hint, :tick, :special_format, :markdown_text
    end
  end
end
