# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative '../environment'
require 'io/console'
require 'unicode/display_width'

module Aspera
  module Cli
    # Console input
    module Prompt
      extend self

      # Prompt user for console input
      # The prompt is displayed on `stderr`, like for sensitive input, so that `stdout` contains only results.
      # @param prompt [String]  prompt string to display
      # @param sensitive [Boolean] whether to hide typed input
      # @return [String] user input stripped of trailing newline
      def prompt_user_input(prompt, sensitive: false)
        $stderr.print("#{prompt}> ")
        return masked_input if sensitive && $stdin.tty?
        line = $stdin.gets
        Aspera.assert_type(line, String) { 'Unexpected end of standard input' }
        line.chomp
      end

      # Prompt user for input in a list of symbols
      # @param prompt [String] prompt to display
      # @param sym_list [Array] list of symbols to select from
      # @return [Symbol] selected symbol
      def prompt_user_input_in_list(prompt, sym_list)
        loop do
          input = prompt_user_input(prompt).to_sym
          return input if sym_list.any? { |a| a.eql?(input) }
          $stderr.puts("No such #{prompt}: #{input}, select one of: #{sym_list.join(', ')}") # rubocop:disable Style/StderrPuts
        end
      end

      private

      # Characters that erase the last one
      ERASE_CHARS = ["\u007f", "\b"].freeze

      # Read a line from the terminal without echoing it, but show a mark instead:
      # a key while the input is empty (waiting for input), an ellipsis once not empty (the paste worked), without revealing the length of the input.
      # `terminal_supports_unicode?` checks `stdout`, but the mark is on `stderr`: use the locale only.
      # @return [String] user input
      def masked_input
        unicode = Environment.unicode_environment?
        marks = {true => Environment.char('🔑', unicode: unicode), false => Environment.char('…', unicode: unicode)}
        line = +''
        $stderr.print(marks[true])
        $stdin.raw do |tty|
          loop do
            was_empty = line.empty?
            char = tty.getc
            case char
            when nil, "\r", "\n" then break
            when "\u0003" then raise Interrupt
            # end of input: Ctrl-D (Unix), Ctrl-Z (Windows)
            when "\u0004", "\u001a"
              break unless line.empty?
              raise Aspera::Error, 'Unexpected end of standard input'
            when *ERASE_CHARS then line.chop!
            # Ctrl-W: erase the last word (and spaces after it), like the terminal does
            when "\u0017" then line.sub!(/\S*\s*\z/, '')
            # Ctrl-U: erase all, e.g. to paste again
            when "\u0015" then line.clear
            else
              # ignore other control characters (and escape sequences start)
              line << char unless char.ord < 32
            end
            next if was_empty.eql?(line.empty?)
            # erase the previous mark (by its width on the terminal), and display the new one
            $stderr.print("\b \b" * Unicode::DisplayWidth.of(marks[was_empty]), marks[line.empty?])
          end
        end
        line
      ensure
        $stderr.print("\n")
      end
    end
  end
end
