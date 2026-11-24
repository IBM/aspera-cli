# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'assert'
require_relative 'environment'
require_relative 'rainbow'
require 'io/console'
require 'unicode/display_width'

using Rainbow

module Aspera
  # Console input
  module Prompt
    extend self

    # Prompt user for console input
    # The prompt is displayed on `stderr`, like for sensitive input, so that `stdout` contains only results.
    # @param prompt    [String]    prompt string to display
    # @param sensitive [Boolean]   whether to hide typed input
    # @param validate  [Proc, nil] Called with the input: raises `ParameterError` (with the reason) if the input is not valid. Its result is not used.
    #   On a terminal, hidden input shows whether it is valid, and if not, the error is displayed and the input is asked again.
    # @return [String] user input stripped of trailing newline
    def prompt_user_input(prompt, sensitive: false, validate: nil)
      loop do
        line = read_input(prompt, sensitive, validate)
        begin
          validate&.call(line)
          return line
        rescue ParameterError => e
          # not a terminal: nobody to ask again
          raise unless $stdin.tty?
          $stderr.puts("#{e.message}. Try again, or Ctrl-C to stop.".red) # rubocop:disable Style/StderrPuts
        end
      end
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

    # Mark of an input checked with `validate`, if valid (`true`) or not: Unicode character, ASCII equivalent, color
    CHECK_MARKS = {
      true  => {unicode: '✓', ascii: 'valid', color: :green},
      false => {unicode: '✗', ascii: 'invalid', color: :red}
    }.freeze

    # Mark shown instead of a hidden input
    Mark = Data.define(:text, :color) do
      # @return [String] Text to display, colored if `color` is set (and colors are enabled)
      def to_s = color.nil? ? text : text.color(color)

      # @return [String] Characters that erase the mark, by its width on the terminal
      def erase = "\b \b" * Unicode::DisplayWidth.of(text)
    end
    private_constant :ERASE_CHARS, :CHECK_MARKS, :Mark

    # @param prompt    [String]    prompt string to display
    # @param sensitive [Boolean]   whether to hide typed input
    # @param validate  [Proc, nil] Checks the input, for the mark of hidden input
    # @return [String] user input stripped of trailing newline
    def read_input(prompt, sensitive, validate)
      $stderr.print("#{prompt}> ")
      if sensitive && $stdin.tty?
        line = Environment.instance.hidden_silent ? silent_input : masked_input(validate)
        return line unless line.nil?
      end
      read_line
    end

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

    # Read a line from the terminal without echoing it, but show a mark instead, without revealing the length of the input:
    # a key while the input is empty (waiting for input), then an ellipsis (the paste worked),
    # or, if the input is checked (`validate`), a check mark if it is valid, else a cross.
    # `terminal_supports_unicode?` checks `stdout`, but the mark is on `stderr`: use the locale only.
    # @param validate [Proc, nil] Checks the input
    # @return [String, nil] user input, or `nil` if the terminal has no raw mode (input not read)
    def masked_input(validate)
      unicode = Environment.unicode_environment?
      line = +''
      mark_of = ->(text) { input_mark(text, validate, unicode) }
      shown = mark_of.call(line)
      $stderr.print(shown)
      begin
        $stdin.raw { |tty| read_masked(tty, line, shown, &mark_of) }
      rescue Errno::ENODEV, Errno::ENOTTY
        # e.g. a pseudo terminal without raw mode: erase the mark, the caller reads a line (echoed)
        $stderr.print(shown.erase)
        return
      end
      line
    end

    # @param line     [String]    Input
    # @param validate [Proc, nil] Checks the input
    # @param unicode  [Boolean]   `true` if Unicode is supported
    # @return [Mark] Mark of the input
    def input_mark(line, validate, unicode)
      return Mark.new(Environment.char('🔑', unicode: unicode), nil) if line.empty?
      return Mark.new(Environment.char('…', unicode: unicode), nil) if validate.nil?
      check = CHECK_MARKS[valid?(line, validate)]
      Mark.new(check[unicode ? :unicode : :ascii], check[:color])
    end

    # @return [Boolean] `true` if `validate` accepts the input
    def valid?(line, validate)
      validate.call(line)
      true
    rescue ParameterError
      false
    end

    # Read characters until end of line, and update the mark when the input changes
    # @param tty   [IO]     Terminal in raw mode
    # @param line  [String] Input, filled
    # @param shown [Mark]   Mark displayed
    # @yieldparam  text [String] Input
    # @yieldreturn [Mark] Mark of the input
    # @return [nil]
    def read_masked(tty, line, shown)
      loop do
        before = line.dup
        char = tty.getc
        case char
        when nil, "\r", "\n" then break
        when "\u0003" then raise Interrupt
        # end of input: Ctrl-D (Unix), Ctrl-Z (Windows)
        when "\u0004", "\u001a"
          break unless line.empty?
          raise ParameterError, 'Unexpected end of standard input'
        when *ERASE_CHARS then line.chop!
        # Ctrl-W: erase the last word (and spaces after it), like the terminal does
        when "\u0017" then line.sub!(/\S*\s*\z/, '')
        # Ctrl-U: erase all, e.g. to paste again
        when "\u0015" then line.clear
        else
          # ignore other control characters (and escape sequences start)
          line << char unless char.ord < 32
        end
        next if line.eql?(before)
        mark = yield(line)
        next if mark.eql?(shown)
        $stderr.print(shown.erase, mark)
        shown = mark
      end
      nil
    ensure
      # raw mode: no output processing, a line feed alone does not go back to the first column
      $stderr.print("\r\n")
    end
  end
end
