# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../option'
require_relative '../../assert'

module Aspera
  module Cli
    class Option
      # Sources of option values.
      # A value is ignored if the option was already set from a source with higher priority.
      module Source
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
end
