# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../agent/factory'
require_relative '../../schema/registry'
require_relative '../../schema/reader'
require_relative '../../schema/documentation'
require_relative '../../ascp/session_errors'

module Aspera
  module Plugins
    module Transfer
      # Mounted on plugin config (manifest `mounts`): ASCP / Transferd related actions
      module AscpActions
        TRANSFERD_APP_NAME = 'sdk'

        # Mapping from agent symbol to schema key in options.schema.yaml
        # Agents without dedicated schema (connect, desktop) are omitted.
        AGENT_SCHEMA_KEY = {
          direct:    Schema::Registry::DIRECT_AGENT_OPTIONS,
          node:      Schema::Registry::NODE_AGENT_OPTIONS,
          httpgw:    Schema::Registry::HTTPGW_AGENT_OPTIONS,
          transferd: Schema::Registry::TRANSFERD_AGENT_OPTIONS
        }.freeze
        private_constant :AGENT_SCHEMA_KEY

        # Set the SDK directory, checking default and former locations
        # If a product is selected for `ascp`, the SDK directory is still needed (keys, conf, transferd)
        def set_sdk_dir
          sdk_folder = options.get_option(:sdk_folder)
          product_selected = Ascp::Installation.product_selector?(sdk_folder)
          return unless sdk_folder.nil? || product_selected
          @sdk_default_location = true
          Log.log.debug('SDK folder is not set, checking default')
          sdk_dir = self.class.default_app_main_folder(app_name: TRANSFERD_APP_NAME)
          Log.log.debug { "Checking: #{sdk_dir}" }
          if !Dir.exist?(sdk_dir)
            Log.log.debug { "No such folder: #{sdk_dir}" }
            former_sdk_folder = File.join(self.class.default_app_main_folder(app_name: Cli::Info::CMD_NAME), TRANSFERD_APP_NAME)
            Log.log.debug { "Checking: #{former_sdk_folder}" }
            sdk_dir = former_sdk_folder if Dir.exist?(former_sdk_folder)
          end
          Log.log.debug { "Using: #{sdk_dir}" }
          if product_selected
            Products::Transferd.sdk_directory = sdk_dir
          else
            options.set_option(:sdk_folder, sdk_dir, source: :default)
          end
        end

        def action_ascp_info(**)
          Secret::Hider.instance.add_secret_keys(Ascp::DataRepository::ELEMENTS)
          data = Ascp::Installation.instance.ascp_info
          data['ts'] = transfer.user_transfer_spec
          Ascp::DataRepository::ELEMENTS.each_with_object(data) { |i, h| h[i.to_s] = Ascp::DataRepository.instance.item(i) }
          Cli::Result::SingleObject.new(data)
        end

        def action_ascp_schema(agent_name: nil, **)
          schema = Aspera::Transfer::Spec::SCHEMA.current.merge({'$comment'=>'DO NOT EDIT, this file was generated from the YAML.'})
          schema['properties'] = schema['properties'].select { |_k, v| Aspera::Transfer::CommandLineBuilder.supported_by_agent(agent_name, v) } unless agent_name.nil?
          schema['properties'] = schema['properties'].sort.to_h
          Cli::Result::SingleObject.new(schema)
        end

        # @param kind [Symbol] `management`: codes of the management port, `session`: codes of sessions, as `errcode` in logs
        def action_ascp_errors(kind: :management, **)
          return Cli::Result::ObjectList.new(Ascp::SessionErrors.list) if kind.eql?(:session)
          error_data = []
          Ascp::Management::ERRORS.each_pair do |code, prop|
            error_data.push(code: code, mnemonic: prop[:c], retry: prop[:r], info: prop[:a])
          end
          Cli::Result::ObjectList.new(error_data)
        end

        # @param agent [Symbol] Name of an agent
        # @return [String, nil] Schema of the parameters of the agent: built-in agent, or options schema declared by the bundle that provides it; `nil` if none
        def agent_schema_key(agent)
          return AGENT_SCHEMA_KEY[agent] unless Aspera::Agent::Factory.instance.provided?(agent)
          # Component added to `TransferAgentOptions` variants, see `Schema::Registry#add_variants`
          component = "#{agent.to_s.snake_to_capital}AgentOptions"
          return unless Schema::Registry.instance.reader(Schema::Registry::OPTIONS)['components']['schemas'].key?(component)
          "#{Schema::Registry::OPTIONS}:components.schemas.#{component}"
        end
        private :agent_schema_key

        def action_agents_list(**)
          rows = Aspera::Agent::Factory::ALL.map do |sym, names|
            schema_key = agent_schema_key(sym)
            param_names =
              if schema_key
                Schema::Registry.instance.reader(schema_key).current['properties']&.keys&.sort&.join(', ') || ''
              else
                ''
              end
            {
              'name'       => sym.to_s,
              'short'      => names[:short].to_s,
              'parameters' => param_names
            }
          end.sort_by { |r| r['name'] }
          Cli::Result::ObjectList.new(rows, fields: %w[name short parameters])
        end

        def action_agents_show(agent_name:, **)
          names = Aspera::Agent::Factory::ALL[agent_name]
          schema_key = agent_schema_key(agent_name)
          Cli::Result::SingleObject.new({
            'name'        => agent_name.to_s,
            'short'       => names[:short].to_s,
            'description' => schema_key ? Schema::Registry.instance.reader(schema_key).current['description'].to_s : '(no configurable parameters)'
          })
        end

        def action_agents_parameters(agent_name:, **)
          schema_key = agent_schema_key(agent_name)
          return Cli::Result::Nothing.new if schema_key.nil?
          builder = Schema::Documentation.new(Cli::TerminalFormatter, Schema::Registry.instance.reader(schema_key)).build
          Cli::Result::ObjectList.new(builder.rows, fields: builder.columns)
        end
      end
    end
  end
end
