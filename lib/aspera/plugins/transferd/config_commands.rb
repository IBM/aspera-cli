# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../cli/deprecation'
require_relative '../../log'
require_relative 'commands'

module Aspera
  module Plugins
    module Transferd
      # Mounted on plugin config (manifest `mounts`), after the modules of bundle `xfer`: the deprecated command `config transferd`,
      # where config included it before the bundle (last command of config).
      module ConfigCommands
        # Instance of the plugin of this bundle (`Commands`, the class of the mount), for the deprecated command `config transferd`
        # @return [Commands] Plugin instance
        def transferd_commands_plugin(**)
          Log.log.warn { "Command config transferd is #{Cli::Deprecation.new(last: Cli::Plugins::Config::DEPRECATED_LAST, message: 'use transferd')}" }
          Commands.new(context: context)
        end

        class << self
          # Declare the deprecated command tree in the plugin class that includes the module
          # @param base [Class] Plugin class (config)
          def included(base)
            base.class_exec do
              # transferd sub-commands: moved to plugin `transferd`, kept as deprecated alias
              # `transferd_commands_plugin`: instance of `Commands`, the class that declares the command tree
              command :transferd, description: "Manage the transfer daemon (#{Cli::Deprecation.new(last: Cli::Plugins::Config::DEPRECATED_LAST, message: 'use plugin transferd')})",
                mount: {plugin: Commands, instance: :transferd_commands_plugin, only: %i[install list service]}
            end
          end
        end
      end
    end
  end
end
