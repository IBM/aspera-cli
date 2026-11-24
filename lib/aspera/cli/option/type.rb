# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../bool_value'
require_relative '../option'

module Aspera
  module Cli
    class Option
      # Type specifiers for the `allowed:` parameter of option declarations.
      # Public API: STRING_ARRAY, SYMBOL_ARRAY, INTEGER, FLOAT, BOOLEAN, NONE.
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
        # Option value is coerced to Float
        FLOAT = [Float].freeze
        # Option value is a Boolean
        BOOLEAN = BoolValue::TYPES
        # Option has no value — it is a flag switch (e.g. `-N`, `--help`)
        NONE = [].freeze
        # Internal: derived when allowed: is an Array<Symbol>; do not pass directly
        ENUM   = [Symbol].freeze
        # Internal: implicit default (String); equivalent to omitting allowed: entirely
        STRING = [String].freeze
      end
    end
  end
end
