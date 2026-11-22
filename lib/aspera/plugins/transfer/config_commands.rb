# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../agent/factory'
require_relative '../../ascp/installation'
require_relative '../../log'
require_relative '../../schema/documentation'
require_relative '../../sync/operations'
require_relative '../../transfer/command_line_builder'
require_relative '../../transfer/spec'
require_relative '../../cli/deprecation'
require_relative '../../cli/result'
require_relative '../../cli/terminal_formatter'

module Aspera
  module Plugins
    module Transfer
      # Mounted on plugin config (manifest `mounts`), after the modules that give the actions and the DSL methods `ascp_logs_commands` and `sync_admin_commands`:
      # command trees `sync`, `ascp`, `agents` and the deprecated `transfer`.
      # `sync` is placed before `gem`, the other trees where config includes the mounts: the command tree of config is the same as before the bundle.
      module ConfigCommands
        class << self
          # Declare the command trees in the plugin class that includes the module
          # @param base [Class] Plugin class (config)
          def included(base)
            base.class_exec do
              command :sync, description: 'Manage Aspera Sync operations', before: :gem

              # ascp sub-commands
              command :ascp, description: 'Manage FASP/ascp transfer engine'
              commands_under :ascp do
                command :show,    description: 'Show ascp binary path', action: ->(**) { Cli::Result::Text.new(Ascp::Installation.instance.path(:ascp)) }
                command :info,    description: 'Show ascp and transfer spec information'
                command :install, description: "Install the transfer SDK (#{Cli::Deprecation.new(last: Cli::Plugins::Config::DEPRECATED_LAST, message: 'use transferd install')})",
                  arguments: [{name: :version, mandatory: false, default: nil}],
                  action: ->(version: nil, **) { transferd_plugin(command: 'config ascp install', replacement: 'transferd install').action_install(version: version) }
                command(
                  :spec, description: 'Show the transfer spec schema',
                  arguments: [{name: :agent_name, allowed: -> { Aspera::Agent::Factory::ALL.keys + [Aspera::Transfer::Spec::DOC_OVERVIEW] }, mandatory: false, default: nil}],
                  action: lambda do |agent_name: nil, **|
                    builder = Schema::Documentation.new(Cli::TerminalFormatter, Aspera::Transfer::Spec::SCHEMA, **Aspera::Transfer::Spec.doc_options(agent_name)).build
                    Cli::Result::ObjectList.new(builder.rows, fields: builder.columns)
                  end
                )
                command :schema, description: 'Show the transfer spec JSON schema',
                  arguments: [{name: :agent_name, allowed: -> { Aspera::Agent::Factory::ALL.keys }, mandatory: false, default: nil}]
                command :errors,   description: 'Show FASP error codes: of the management port (default), or of sessions (errcode in logs)',
                  arguments: [{name: :kind, allowed: %i[management session], mandatory: false, default: :management}]
                ascp_logs_commands :logs
                commands_under :logs do
                  command :find, description: 'Find the ascp log files of this system: of installed products, and default locations', action: :action_ascp_logs_find
                end
                command :products, description: 'Manage installed Aspera products'
                commands_under :products do
                  command :list, description: 'List installed Aspera products',
                    action: ->(**) { Cli::Result::ObjectList.new(Ascp::Installation.instance.installed_products, fields: %w[name app_root]) }
                end
              end

              # agents sub-commands
              command :agents, description: 'Manage transfer agents'
              commands_under :agents do
                command :list,       description: 'List all transfer agents'
                command :show,       description: 'Show details for a transfer agent',
                  arguments: [{name: :agent_name, allowed: -> { Aspera::Agent::Factory::ALL.keys }}]
                command :parameters, description: 'Show configurable parameters for a transfer agent',
                  arguments: [{name: :agent_name, allowed: -> { Aspera::Agent::Factory::ALL.keys }}]
              end

              # async transfer jobs: moved to `agents jobs`, `transfer` is kept as deprecated alias
              commands_under %i[agents jobs], description: 'Manage asynchronous transfer jobs' do
                command(
                  :list, description: 'List all async transfer jobs',
                  action: lambda do |**|
                    rows = async_transfer_store.list
                    Cli::Result::ObjectList.new(rows, fields: %w[job_id agent_type status started_at ended_at bytes_transferred transfer_id])
                  end
                )
                command :status,  description: 'Show status of an async transfer job',
                  arguments: [{name: :job_id, complete: :transfer_job}]
                command :cleanup, description: 'Remove completed/failed/cancelled transfer entries'
              end
              command :transfer, description: "Manage asynchronous transfers (#{Cli::Deprecation.new(last: Cli::Plugins::Config::DEPRECATED_LAST, message: 'use agents jobs')})",
                setup: :deprecated_transfer_setup, mount: {plugin: self, at: %i[agents jobs], instance: :itself}

              # sync sub-commands
              commands_under :sync do
                command(
                  :spec, description: 'Show the sync configuration schema',
                  action: lambda do |**|
                    builder = Schema::Documentation.new(Cli::TerminalFormatter, Sync::Operations::CONF_SCHEMA, annotate: Aspera::Transfer::CommandLineBuilder.method(:doc_lines)).build
                    Cli::Result::ObjectList.new(builder.rows, fields: builder.columns)
                  end
                )
                sync_admin_commands :admin
                command :translate, description: 'Translate async-style arguments to sync config format',
                  arguments: [{name: :async_arguments, multiple: true}],
                  action: ->(async_arguments:, **) { Cli::Result::SingleObject.new(Sync::Operations.args_to_conf(async_arguments)) }
              end
            end
          end
        end

        # Setup of the deprecated `config transfer` (alias of `config agents jobs`, same plugin)
        def deprecated_transfer_setup(**)
          Log.log.warn { "Command config transfer is #{Cli::Deprecation.new(last: Cli::Plugins::Config::DEPRECATED_LAST, message: 'use config agents jobs')}" }
          {}
        end
      end
    end
  end
end
