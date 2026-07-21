# frozen_string_literal: true

module Aspera
  module Cli
    # Mixin for Config plugin: ASCP / Transferd related actions
    module AscpActions
      TRANSFERD_APP_NAME = 'sdk'

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

      def install_transfer_sdk
        asked_version = options.get_next_argument('transferd version', mandatory: false)
        sdk_url = options.get_option(:sdk_url, mandatory: true)
        sdk_url = nil if sdk_url.eql?(SpecialValues::DEF)
        name, version, folder = Ascp::Installation.instance.retrieve_sdk(url: sdk_url, version: asked_version)
        return Result::Status.new("Installed #{name} version #{version} in #{folder}")
      end

      def execute_action_ascp
        command = options.get_next_command(%i[show products info install spec schema errors])
        case command
        when :show
          return Result::Text.new(Ascp::Installation.instance.path(:ascp))
        when :info
          data = Ascp::Installation.instance.ascp_info
          data['ts'] = transfer.user_transfer_spec
          DataRepository::ELEMENTS.each_with_object(data){ |i, h| h[i.to_s] = DataRepository.instance.item(i)}
          SecretHider::ADDITIONAL_KEYS_TO_HIDE.concat(DataRepository::ELEMENTS.map(&:to_s))
          return Result::SingleObject.new(data)
        when :products
          command = options.get_next_command(%i[list])
          case command
          when :list
            return Result::ObjectList.new(Ascp::Installation.instance.installed_products, fields: %w[name app_root])
          end
        when :install
          return install_transfer_sdk
        when :spec
          builder = Schema::Documentation.new(TerminalFormatter, Transfer::Spec::SCHEMA, include_option: true, agent_columns: true).build
          return Result::ObjectList.new(builder.rows, fields: builder.columns)
        when :schema
          schema = Transfer::Spec::SCHEMA.current.merge({'$comment'=>'DO NOT EDIT, this file was generated from the YAML.'})
          agent = options.get_next_argument('transfer agent name', mandatory: false)
          schema['properties'] = schema['properties'].select{ |_k, v| CommandLineBuilder.supported_by_agent(agent, v)} unless agent.nil?
          schema['properties'] = schema['properties'].sort.to_h
          return Result::SingleObject.new(schema)
        when :errors
          error_data = []
          Ascp::Management::ERRORS.each_pair do |code, prop|
            error_data.push(code: code, mnemonic: prop[:c], retry: prop[:r], info: prop[:a])
          end
          return Result::ObjectList.new(error_data)
        else Aspera.error_unexpected_value(command)
        end
        Aspera.error_unreachable_line
      end

      def execute_action_transferd
        command = options.get_next_command(%i[list install])
        case command
        when :install
          return install_transfer_sdk
        when :list
          sdk_list = Ascp::Installation.instance.sdk_locations
          return Result::ObjectList.new(
            sdk_list,
            fields: sdk_list.first.keys - ['url']
          )
        else Aspera.error_unexpected_value(command)
        end
        Aspera.error_unreachable_line
      end
    end
  end
end
