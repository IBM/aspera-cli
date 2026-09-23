# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/dot_container'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # Positional (non-option) command line token.
    class Argument
      # @return [String] the raw argument value
      attr_reader :value
      # @return [Option, nil] option token claiming this token as its value (`--opt value` form)
      attr_accessor :owner
      # @return [Boolean] `true` once used, as positional argument or as option value
      attr_accessor :consumed

      def initialize(value)
        @value = value
        @owner = nil
        @consumed = false
      end

      # @return [Boolean] `true` if available as positional argument
      def positional? = !@consumed && @owner.nil?

      # @return [String] raw argument value
      def to_s = @value
    end

    # Option command line token (long or short form).
    class Option
      # @return [String] raw token as it appeared in argv (e.g. "--log-level=debug", "-Pval")
      attr_reader :raw
      # @return [String, nil] option name with underscores (e.g. "log_level"), nil for short options
      attr_reader :name
      # @return [String, nil] single-char short option letter (e.g. "P"), nil for long options
      attr_reader :short_char
      # @return [Array<String>, nil] sub-keys for dot-path notation (e.g. ["field"] for --custom.field)
      attr_reader :dot_path
      # @return [String, nil] value given in the same token (`--opt=val` or `-Oval`)
      attr_reader :inline_value
      # @return [Argument, nil] next token, claimed as value when there is no inline value (`--opt val` or `-O val`)
      attr_accessor :value_token
      # @return [Boolean] `true` once applied to a declared option
      attr_accessor :consumed
      # @return [Symbol, nil] option this token was resolved to, when `name` is an abbreviation
      attr_accessor :abbreviation_of

      def initialize(raw:, name: nil, short_char: nil, dot_path: nil, inline_value: nil)
        @raw          = raw
        @name         = name
        @short_char   = short_char
        @dot_path     = dot_path
        @inline_value = inline_value
        @value_token  = nil
        @consumed     = false
        @abbreviation_of = nil
      end

      # @return [Boolean] `true` if value is in the same token
      def inline? = !@inline_value.nil?

      # @return [String, nil] inline value, or value of next token
      def value = @inline_value || @value_token&.value

      # @return [String] raw token, followed by its separate value if any
      def to_s = @value_token.nil? ? @raw : "#{@raw} #{@value_token.value}"

      class << self
        # @param token [String] command line token
        # @return [Boolean] `true` if token is an option, i.e. not `-`, `--`, or a negative number
        def option?(token)
          token.match?(/\A-\D/) && !token.eql?(STOP)
        end

        # Build an Option from a raw token
        # @param raw [String] e.g. "--log-level=debug", "--custom.field", "-P", "-Pval"
        # @return [Option]
        def parse(raw)
          if raw.start_with?(PREFIX)
            name_raw, value = raw.delete_prefix(PREFIX).split(VALUE_SEP, 2)
            root, *dot_path = name_raw.to_s.split(DotContainer::SEPARATOR)
            new(raw: raw, name: root.to_s.gsub(NAME_SEP_LINE, NAME_SEP_SYMBOL), dot_path: dot_path.empty? ? nil : dot_path, inline_value: value)
          else
            new(raw: raw, short_char: raw[1], inline_value: raw.length > 2 ? raw[2..] : nil)
          end
        end
      end

      # Option name separator on command line (e.g. `--option-name`, the `-` between words)
      NAME_SEP_LINE   = '-'
      # Option name separator in code/symbol (e.g. `:option_name`, the `_` between words)
      NAME_SEP_SYMBOL = '_'
      # Separator between option name and its inline value (e.g. `--opt=val`, the `=`)
      VALUE_SEP = '='
      # Long-option prefix (e.g. `--opt`)
      PREFIX = '--'
      # When alone, stops option processing: following tokens are positional arguments
      STOP = '--'
    end

    # Command line split in tokens, in original order.
    # Tokens are never removed, only marked as consumed, so that positions are kept.
    #
    # An option without inline value claims the next token as its value (`--opt val`, `-O val`),
    # unless that token looks like an option.
    # If the option turns out to be a flag, the claimed token is given back to positional arguments.
    class CommandLine
      # @param argv [Array<String>] command line arguments
      def initialize(argv)
        # @type [Array<Option, Argument>]
        @tokens = []
        # Option token being applied (used by `@:` extended value)
        @current_option = nil
        # When set, only positional arguments after this token are available
        @arguments_after = nil
        process_options = true
        argv.each do |value|
          if process_options && value.eql?(Option::STOP)
            process_options = false
          elsif process_options && Option.option?(value)
            @tokens.push(Option.parse(value))
          else
            argument = Argument.new(value)
            previous = @tokens.last
            if process_options && previous.is_a?(Option) && !previous.inline? && previous.value_token.nil?
              previous.value_token = argument
              argument.owner = previous
            end
            @tokens.push(argument)
          end
        end
        Log.log.trace1 { "arguments=#{pending_arguments},options=#{pending_options}" }
      end

      # @return [Array<Option>] option tokens whose name was resolved as an abbreviation
      def abbreviated_option_tokens
        @tokens.select { |t| t.is_a?(Option) && !t.abbreviation_of.nil? }
      end

      # @return [Array<Option>] option tokens not applied yet
      def pending_option_tokens
        @tokens.select { |t| t.is_a?(Option) && !t.consumed }
      end

      # Mark option token as applied, and get its value.
      # @param tok         [Option]  option token
      # @param takes_value [Boolean] `false` for flags: claimed token is given back to positional arguments
      # @return [String, nil] value, or `nil` for flags
      # @raise [BadArgument] if option takes a value and none was given
      def consume(tok, takes_value:)
        tok.consumed = true
        return release(tok) unless takes_value
        return tok.inline_value if tok.inline?
        Aspera.assert(!tok.value_token.nil?, type: BadArgument) { "Option #{tok.raw} requires a value" }
        tok.value_token.consumed = true
        tok.value_token.value
      end

      # Execute block with `tok` as current option
      # @param tok [Option] option token being applied
      def with_current_option(tok)
        @current_option = tok
        yield
      ensure
        @current_option = nil
      end

      # Execute block with only positional arguments after current option available, if any
      def with_arguments_after_current_option
        @arguments_after = @current_option
        yield
      ensure
        @arguments_after = nil
      end

      # @return [Array<String>] values of available positional arguments
      def pending_arguments
        positional_tokens.map(&:value)
      end

      # @return [Array<String>] options not applied yet, with their value if separate
      def pending_options
        pending_option_tokens.map(&:to_s)
      end

      # Consume positional arguments.
      # @param multiple [false, true, String] consumption mode:
      #   false  — consume exactly one token
      #   true   — consume all remaining tokens
      #   String — consume up to the marker token (marker is consumed too, not returned), or all if absent
      # @return [Array<String>] consumed values
      def shift_arguments(multiple)
        arg_tokens = positional_tokens
        selected =
          case multiple
          when false then arg_tokens.first(1)
          when true then arg_tokens
          when String
            index = arg_tokens.index { |t| t.value.eql?(multiple) }
            arg_tokens[index].consumed = true unless index.nil?
            arg_tokens.take(index || arg_tokens.length)
          else Aspera.error_unexpected_value(multiple) { 'multiple' }
          end
        selected.each { |t| t.consumed = true }
        selected.map(&:value)
      end

      # Add an argument before the available positional arguments
      # @param value [String] argument value
      def unshift_argument(value)
        index = @tokens.index { |t| t.is_a?(Argument) && t.positional? } || @tokens.length
        @tokens.insert(index, Argument.new(value))
      end

      # Consume all long options with a value, whether applied or not.
      # @yieldparam tok [Option] long option token with a value
      def each_long_option_with_value
        @tokens.each do |tok|
          next unless tok.is_a?(Option) && tok.short_char.nil? && !tok.value.nil?
          yield(tok)
          tok.consumed = true
          tok.value_token&.consumed = true
        end
      end

      private

      # Give back claimed token to positional arguments.
      # @param tok [Option] flag option token
      # @return [nil]
      def release(tok)
        value_token = tok.value_token
        return if value_token.nil?
        index = @tokens.index { |t| t.equal?(value_token) }
        Aspera.assert(@tokens[index + 1..].none? { |t| t.is_a?(Argument) && t.consumed && t.owner.nil? }) do
          "Flag #{tok.raw} declared after following positional arguments were used"
        end
        value_token.owner = nil
        tok.value_token = nil
      end

      # @return [Array<Argument>] available positional arguments, in order
      def positional_tokens
        start = @arguments_after.nil? ? 0 : @tokens.index { |t| t.equal?(@arguments_after) } + 1
        @tokens[start..].select { |t| t.is_a?(Argument) && t.positional? }
      end
    end
  end
end
