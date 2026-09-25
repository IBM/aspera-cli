# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/assert'

module Aspera
  module Cli
    # Exception raised when schema is asked (`help`)
    class SchemaRequest < Error
      # Value of option or argument that requests its schema
      KEYWORD = 'help'

      # @return [String, nil] path to schema file
      attr_reader :path

      # @param type [Symbol] :argument or :option
      # @param name [String] name of the option/argument
      # @param schema_path [String, nil] path to schema file, or `nil` if not available
      def initialize(type, name, schema_path)
        super("#{type}: #{name}")
        @path = schema_path
      end
    end

    # Values accepted for boolean options: `true`, `false`, `yes`, `no`
    module BoolValue
      # Symbol for `true`
      YES_SYM = :yes
      # Symbol for `false`
      NO_SYM = :no
      # Values meaning `false`
      FALSE_VALUES = [NO_SYM, false].freeze
      # Values meaning `true`
      TRUE_VALUES = [YES_SYM, true].freeze
      private_constant :FALSE_VALUES, :TRUE_VALUES
      # Boolean values
      # @return [Array<true, false, :yes, :no>]
      ALL = (TRUE_VALUES + FALSE_VALUES).freeze
      # `false` and `true`
      TYPES = [FalseClass, TrueClass].freeze
      # `:no` and `:yes`
      SYMBOLS = [NO_SYM, YES_SYM].freeze
      # @return [Boolean] `true` if value is a value for `true` in `ALL`
      def true?(enum)
        Aspera.assert_values(enum, ALL) { 'boolean' }
        TRUE_VALUES.include?(enum)
      end

      # @return [Boolean] `true` if value is a value for `true` or `false` in ALL
      def symbol?(sym)
        ALL.include?(sym)
      end
      module_function :true?, :symbol?
    end

    # Type specifiers for the `allowed:` parameter of option declarations.
    # Public API: STRING_ARRAY, SYMBOL_ARRAY, INTEGER, BOOLEAN, NONE.
    # Internal (do not pass as `allowed:`):
    #   ENUM   - derived internally when `allowed:` is an Array<Symbol> (enum list)
    #   STRING - the implicit default; equivalent to omitting `allowed:` entirely
    module Type
      # Option value is a String or Array of Strings (cumulative)
      STRING_ARRAY = [Array, String].freeze
      # Option value is a Symbol from a constrained list; use as prefix: SYMBOL_ARRAY + [:val1, :val2]
      SYMBOL_ARRAY = [Array, Symbol].freeze
      # Option value is coerced to Integer
      INTEGER = [Integer].freeze
      # Option value is a Boolean
      BOOLEAN = BoolValue::TYPES
      # Option has no value — it is a flag switch (e.g. `-N`, `--help`)
      NONE = [].freeze
      # Internal: derived when allowed: is an Array<Symbol>; do not pass directly
      ENUM   = [Symbol].freeze
      # Internal: implicit default (String); equivalent to omitting allowed: entirely
      STRING = [String].freeze
    end

    # Sources of option values.
    # A value is ignored if the option was already set from a source with higher priority.
    module OptionSource
      # Source -> priority (higher wins)
      PRIORITY = {
        default:       0,
        # Default preset for plugin (added with `override: false`)
        plugin_preset: 1,
        preset:        2,
        env:           3,
        cmdline:       4,
        # Set by code, or asked to user: same as command line
        code:          4,
        interactive:   4
      }.freeze

      class << self
        # @param source [Symbol] one of `PRIORITY` keys
        # @return [Integer] priority of source
        def priority(source)
          PRIORITY.fetch(source) { Aspera.error_unexpected_value(source) { 'option source' } }
        end
      end
    end
  end
end
