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
        if sensitive && $stdin.tty?
          line = Environment.instance.hidden_silent ? silent_input : masked_input
          return line unless line.nil?
        end
        read_line
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

      # @return [String] Line read from standard input, without trailing newline
      def read_line
        line = $stdin.gets
        Aspera.assert_type(line, String) { 'Unexpected end of standard input' }
        line.chomp
      end

      # Read a line from the terminal without echoing it, and without any feedback (option `ui.hidden_silent`)
      # @return [String, nil] user input, or `nil` if the terminal cannot disable echo (input not read)
      def silent_input
        line = $stdin.noecho(&:gets)
        $stderr.print("\n")
        Aspera.assert_type(line, String) { 'Unexpected end of standard input' }
        line.chomp
      rescue Errno::ENODEV, Errno::ENOTTY
        nil
      end

      # Read a line from the terminal without echoing it, but show a mark instead:
      # a key while the input is empty (waiting for input), an ellipsis once not empty (the paste worked), without revealing the length of the input.
      # `terminal_supports_unicode?` checks `stdout`, but the mark is on `stderr`: use the locale only.
      # @return [String, nil] user input, or `nil` if the terminal has no raw mode (input not read)
      def masked_input
        unicode = Environment.unicode_environment?
        marks = {true => Environment.char('🔑', unicode: unicode), false => Environment.char('…', unicode: unicode)}
        line = +''
        $stderr.print(marks[true])
        begin
          $stdin.raw { |tty| read_masked(tty, line, marks) }
        rescue Errno::ENODEV, Errno::ENOTTY
          # e.g. a pseudo terminal without raw mode: erase the mark, the caller reads a line (echoed)
          $stderr.print("\b \b" * Unicode::DisplayWidth.of(marks[true]))
          return
        end
        line
      end

      # Read characters until end of line, showing the mark of `line` empty or not
      # @param tty   [IO]                  Terminal in raw mode
      # @param line  [String]              Input, filled
      # @param marks [Hash{Boolean=>String}] Mark shown when input is empty (`true`) or not
      # @return [nil]
      def read_masked(tty, line, marks)
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
        nil
      ensure
        $stderr.print("\n")
      end
    end
  end
end
