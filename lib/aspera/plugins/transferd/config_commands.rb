# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../cli/deprecation'
require_relative 'commands'

module Aspera
  module Plugins
    module Transferd
      # Mounted on plugin config (manifest `mounts`), after the modules of bundle `transfer`: the deprecated command `config transferd`,
      # where config included it before the bundle (last command of config).
      module ConfigCommands
        class << self
          # Declare the deprecated command tree in the plugin class that includes the module
          # @param base [Class] Plugin class (config)
          def included(base)
            base.class_exec do
              # transferd sub-commands: moved to plugin `transferd`, kept as deprecated alias
              # `transferd_plugin`: method of config, also used by the deprecated `config ascp install`
              command :transferd, description: "Manage the transfer daemon (#{Cli::Deprecation.new(last: Cli::Plugins::Config::DEPRECATED_LAST, message: 'use plugin transferd')})",
                mount: {plugin: Commands, instance: :transferd_plugin, only: %i[install list service]}
            end
          end
        end
      end
    end
  end
end
