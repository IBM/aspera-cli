# frozen_string_literal: true

require 'aspera/cli/option_value'
require 'aspera/cli/error'
require 'aspera/assert'

module Aspera
  module Cli
    # Declared options, and their lookup by name: long, short, or unique abbreviation.
    class OptionRegistry
      # @return [Hash{Symbol => OptionValue}] declared options, in declaration order
      attr_reader :options
      # @return [String] help section of options declared next
      attr_accessor :group

      def initialize
        @options = {}
        # Short option char -> option, e.g. {'h' => help option}
        @short_options = {}
        @group = 'global'
      end

      # Register a new option
      # @param option [OptionValue] option to register
      # @param short  [String, nil] short option char
      # @return [OptionValue] the option
      def add(option, short: nil)
        Aspera.assert(!@options.key?(option.option)) { "#{option.option} already declared" }
        option.group = @group
        option.short = short
        @options[option.option] = option
        @short_options[short] = option unless short.nil?
        option
      end

      # @param option_symbol [Symbol] option name
      # @return [Boolean] `true` if option is declared
      def declared?(option_symbol) = @options.key?(option_symbol)

      # @param option_symbol [Symbol] option name
      # @return [OptionValue] declared option
      # @raise [BadArgument] if option is not declared
      def fetch(option_symbol)
        Aspera.assert(@options.key?(option_symbol), type: BadArgument) { "Unknown option: #{option_symbol}" }
        @options[option_symbol]
      end

      # @param char [String] short option char
      # @return [OptionValue, nil] declared option, or `nil`
      def by_short(char) = @short_options[char]

      # Find long option by exact name, or by unique abbreviation.
      # @param name              [String]  option name with underscores
      # @param allow_abbreviation [Boolean] accept a unique prefix of a declared option
      # @return [OptionValue, nil] declared option, or `nil` if none matches (yet)
      # @raise [BadArgument] if abbreviation is ambiguous
      def by_long(name, allow_abbreviation: true)
        option = @options[name.to_sym]
        return option if !option.nil? || !allow_abbreviation
        candidates = @options.keys.select { |k| k.to_s.start_with?(name) }
        return if candidates.empty?
        Aspera.assert(candidates.length.eql?(1), type: BadArgument) do
          Parser.multi_choice_assert_msg("Ambiguous option: #{Parser.option_name_to_line(name)}", candidates.map { |c| Parser.option_name_to_line(c) })
        end
        @options[candidates.first]
      end
    end
  end
end
