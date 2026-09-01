# frozen_string_literal: true

require 'aspera/agent/factory'
require 'aspera/schema/registry'
require 'aspera/schema/reader'

module Aspera
  module Cli
    # Mixin for Config plugin: ASCP / Transferd related actions
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
      def set_sdk_dir
        sdk_dir = Products::Transferd.sdk_directory rescue nil
        if sdk_dir.nil?
          @sdk_default_location = true
          Log.log.debug('SDK folder is not set, checking default')
          sdk_dir = self.class.default_app_main_folder(app_name: TRANSFERD_APP_NAME)
          Log.log.debug{"Checking: #{sdk_dir}"}
          if !Dir.exist?(sdk_dir)
            Log.log.debug{"No such folder: #{sdk_dir}"}
            former_sdk_folder = File.join(self.class.default_app_main_folder(app_name: Info::CMD_NAME), TRANSFERD_APP_NAME)
            Log.log.debug{"Checking: #{former_sdk_folder}"}
            sdk_dir = former_sdk_folder if Dir.exist?(former_sdk_folder)
          end
          Log.log.debug{"Using: #{sdk_dir}"}
          Products::Transferd.sdk_directory = sdk_dir
        end
      end

      # Install the transfer SDK (ascp + transferd) from a URL or using the default source.
      # Version defaults to +Info::SDK_VERSION+; pass +LATEST+ as argument to install the latest available version.
      # @param version [String, nil] version to install; nil means use the default SDK version
      # @return [Result::Status] installation result message
      def install_transfer_sdk(version: nil)
        asked_version = version.nil? ? Info::SDK_VERSION : version
        asked_version = nil if asked_version.eql?(SpecialValues::LATEST)
        sdk_url = options.get_option(:sdk_url, mandatory: true)
        sdk_url = nil if sdk_url.eql?(SpecialValues::DEF)
        name, ver, folder = Ascp::Installation.instance.install_sdk(url: sdk_url, version: asked_version)
        return Result::Status.new("Installed #{name} version #{ver} in #{folder}")
      end

      def action_ascp_show(**)
        Result::Text.new(Ascp::Installation.instance.path(:ascp))
      end

      def action_ascp_info(**)
        data = Ascp::Installation.instance.ascp_info
        data['ts'] = transfer.user_transfer_spec
        DataRepository::ELEMENTS.each_with_object(data){ |i, h| h[i.to_s] = DataRepository.instance.item(i)}
        SecretHider::ADDITIONAL_KEYS_TO_HIDE.concat(DataRepository::ELEMENTS.map(&:to_s))
        Result::SingleObject.new(data)
      end

      def action_ascp_install(version: nil, **)
        install_transfer_sdk(version: version)
      end

      def action_ascp_spec(**)
        builder = Schema::Documentation.new(TerminalFormatter, Transfer::Spec::SCHEMA, include_option: true, agent_columns: true).build
        Result::ObjectList.new(builder.rows, fields: builder.columns)
      end

      def action_ascp_schema(agent_name: nil, **)
        schema = Transfer::Spec::SCHEMA.current.merge({'$comment'=>'DO NOT EDIT, this file was generated from the YAML.'})
        schema['properties'] = schema['properties'].select{ |_k, v| CommandLineBuilder.supported_by_agent(agent_name, v)} unless agent_name.nil?
        schema['properties'] = schema['properties'].sort.to_h
        Result::SingleObject.new(schema)
      end

      def action_ascp_errors(**)
        error_data = []
        Ascp::Management::ERRORS.each_pair do |code, prop|
          error_data.push(code: code, mnemonic: prop[:c], retry: prop[:r], info: prop[:a])
        end
        Result::ObjectList.new(error_data)
      end

      def action_ascp_products_list(**)
        Result::ObjectList.new(Ascp::Installation.instance.installed_products, fields: %w[name app_root])
      end

      def action_agents_list(**)
        rows = Agent::Factory::ALL.map do |sym, names|
          schema_key = AGENT_SCHEMA_KEY[sym]
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
        end.sort_by{ |r| r['name']}
        Result::ObjectList.new(rows, fields: %w[name short parameters])
      end

      def action_agents_show(agent_name:, **)
        names = Agent::Factory::ALL[agent_name]
        schema_key = AGENT_SCHEMA_KEY[agent_name]
        agent_info = {
          'name'        => agent_name.to_s,
          'short'       => names[:short].to_s,
          'description' => schema_key ? Schema::Registry.instance.reader(schema_key).current['description'].to_s : '(no configurable parameters)'
        }
        if schema_key
          properties = Schema::Registry.instance.reader(schema_key).current['properties'] || {}
          rows = properties.map do |pname, pdef|
            row = {'parameter' => pname, 'type' => pdef['type'].to_s, 'description' => pdef['description'].to_s}
            row['required'] = (Schema::Registry.instance.reader(schema_key).current['required'] || []).include?(pname) ? 'yes' : 'no'
            row['default']  = pdef.key?('default') ? pdef['default'].inspect : ''
            row['enum']     = pdef.key?('enum')    ? pdef['enum'].join(', ') : ''
            row
          end
          return Result::ObjectList.new(rows, fields: %w[parameter required type default enum description])
        end
        Result::SingleObject.new(agent_info)
      end

      def action_agents_parameters(agent_name:, **)
        schema_key = AGENT_SCHEMA_KEY[agent_name]
        return Result::Nothing.new if schema_key.nil?
        properties = Schema::Registry.instance.reader(schema_key).current['properties'] || {}
        rows = properties.map do |pname, pdef|
          {'name' => pname, 'type' => pdef['type'].to_s, 'description' => pdef['description'].to_s}
        end
        Result::ObjectList.new(rows, fields: %w[name type description])
      end

      def action_transferd_install(**)
        install_transfer_sdk
      end

      def action_transferd_list(**)
        sdk_list = Ascp::Installation.instance.sdk_locations
        Result::ObjectList.new(sdk_list, fields: sdk_list.first.keys - ['url'])
      end
    end
  end
end
