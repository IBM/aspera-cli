# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'

module Aspera
  module Cli
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
  end
end
