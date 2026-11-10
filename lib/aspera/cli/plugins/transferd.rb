# frozen_string_literal: true

require 'aspera/cli/plugins/base'
require 'aspera/cli/info'
require 'aspera/cli/special_values'
require 'aspera/ascp/installation'
require 'aspera/products/transferd_service'
require 'aspera/schema/documentation'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    module Plugins
      # Install the Transfer Daemon (`transferd`), run it as a system service, and query a running daemon
      class Transferd < Base
        application_name 'Transfer Daemon'

        class << self
          # Seam for the client commands: object that gives `info(params)`, `transfer_status(id, params)` and `transfer_cancel(id, params)`,
          # with `params` a Hash with `url`, and optional `api_key`, `ca_file`.
          # `nil` (default): `Agent::Transferd`, loaded on first use, because it requires the optional gem `grpc`.
          # @return [#info, #transfer_status, #transfer_cancel, nil]
          attr_accessor :daemon_client
        end

        command :install, description: 'Install the transfer daemon',
          arguments: [{name: :version, mandatory: false, default: nil}]
        command :list, description: 'List available SDK locations'
        command :service, description: 'Manage the transfer daemon as a system service'
        commands_under :service do
          service_config_arg = {name: :config, type: Hash, mandatory: false, default: {}, schema: Schema::Registry::TRANSFERD_SERVICE_CONFIG}
          command(
            :spec, description: 'Show the transfer daemon configuration schema',
            action: lambda do |**|
              builder = Schema::Documentation.new(TerminalFormatter, Schema::Registry.instance.reader('transferd')).build
              Result::ObjectList.new(builder.rows, fields: builder.columns)
            end
          )
          command(
            :install, description: 'Install the SDK if needed, then configure and start the service',
            arguments: [service_config_arg],
            action: ->(config:, **) { transferd_service_install(config) }
          )
          command(
            :configure, description: 'Configure the transfer daemon service',
            arguments: [service_config_arg],
            action: lambda do |config:, **|
              transferd_service do |host, sdk_folder, dry_run|
                steps = Products::TransferdService.configure(config, sdk_folder, host: host, dry_run: dry_run)
                Products::TransferdService.check_version(sdk_folder, host: host)
                transferd_service_steps(steps)
              end
            end
          )
          command(
            :status, description: 'Show the state of the service (the API key is not shown)',
            arguments: [service_config_arg],
            action: lambda do |config:, **|
              transferd_service { |host, sdk_folder, _dry_run| Result::SingleObject.new(Products::TransferdService.status(config, sdk_folder, host: host)) }
            end
          )
          command(
            :uninstall, description: 'Stop and remove the service (service.purge: also remove configuration and logs)',
            arguments: [service_config_arg],
            action: lambda do |config:, **|
              transferd_service do |host, _sdk_folder, dry_run|
                purge = Products::TransferdService.service_options(config)['purge'].eql?(true)
                transferd_service_steps(Products::TransferdService.uninstall(config, host: host, dry_run: dry_run, purge: purge))
              end
            end
          )
          command(
            :use, description: 'Use an installed version of the SDK (SDK folder named current), and restart the service',
            arguments: [{name: :version}, service_config_arg],
            action: lambda do |version:, config:, **|
              transferd_service do |host, sdk_folder, dry_run|
                transferd_service_steps(Products::TransferdService.use(config, sdk_folder, version, host: host, dry_run: dry_run))
              end
            end
          )
          command(
            :versions, description: 'List the installed versions of the SDK (SDK folder named current)',
            action: lambda do |**|
              sdk_folder = options.get_option(:sdk_folder, mandatory: true)
              Result::ObjectList.new(Products::TransferdService.versions(sdk_folder), fields: %w[version folder current])
            end
          )
        end
        command :info, description: 'Show information on a running daemon',
          action: ->(**) { Result::SingleObject.new(daemon_client.info(daemon_params)) }
        command :transfers, description: 'Query the transfers of a running daemon'
        commands_under :transfers do
          command(
            :show, description: 'Show the status of a transfer (the daemon keeps it for some time after its end)',
            arguments: [{name: :transfer_id}],
            action: ->(transfer_id:, **) { Result::SingleObject.new(daemon_client.transfer_status(transfer_id, daemon_params)) }
          )
          command(
            :cancel, description: 'Stop a transfer',
            arguments: [{name: :transfer_id}],
            action: lambda do |transfer_id:, **|
              daemon_client.transfer_cancel(transfer_id, daemon_params)
              Result::Status.new("Transfer #{transfer_id} stopped")
            end
          )
        end

        option :url,     description: 'Client commands: endpoint of the running daemon, e.g. 127.0.0.1:55002'
        option :api_key, description: 'Client commands: API key of the daemon, if its authentication is enabled'
        option :ca_file, description: 'Client commands: certificate authority (PEM file) of the daemon, if its TLS is enabled'

        # Install the transfer SDK (ascp + transferd) from a URL or using the default source.
        # Version defaults to `Info::SDK_VERSION`; pass `LATEST` as argument to install the latest available version.
        # Also called by the deprecated command `config ascp install`.
        # @param version [String, nil] version to install; nil means use the default SDK version
        # @return [Result::Status] installation result message
        def action_install(version: nil, **)
          asked_version = version.nil? ? Info::SDK_VERSION : version
          asked_version = nil if asked_version.eql?(SpecialValues::LATEST)
          name, ver, folder = Ascp::Installation.instance.install_sdk(url: sdk_url_option, version: asked_version)
          return Result::Status.new("Installed #{name} version #{ver} in #{folder}")
        end

        # @return [Result::ObjectList] The SDK locations
        def action_list(**)
          sdk_list = Ascp::Installation.instance.sdk_locations
          Result::ObjectList.new(sdk_list, fields: sdk_list.first.keys - ['url'])
        end

        private

        # @return [#info, #transfer_status, #transfer_cancel] The client of the daemon
        # @raise [Cli::Error] if the optional gem `grpc` is missing
        def daemon_client
          injected = self.class.daemon_client
          return injected unless injected.nil?
          begin
            require 'aspera/agent/transferd'
          rescue LoadError => e
            raise Cli::Error, "Commands that query a running daemon require the gem grpc (#{e.message}). Install it with: gem install grpc"
          end
          Agent::Transferd
        end

        # Parameters of the connection to the daemon: option `url` is mandatory, `api_key` and `ca_file` are optional.
        # Options `url`, `api_key` and `ca_file` have priority, else the same keys of option `transfer` are used, if its agent is `transferd`.
        # @return [Hash]
        def daemon_params
          from_transfer = transfer_agent_params
          params = %w[url api_key ca_file].to_h { |key| [key, options.get_option(key.to_sym) || from_transfer[key]] }.compact
          Aspera.assert(params.key?('url'), type: Cli::BadArgument) do
            "Missing option #{Parser.option_name_to_line(:url)} (or #{Parser.option_name_to_line(:transfer)} with agent transferd and key url)"
          end
          return params
        end

        # @return [Hash] Keys `url`, `api_key`, `ca_file` of option `transfer`, only if its agent is `transferd`, else empty
        def transfer_agent_params
          transfer_options = transfer.transfer_options
          return {} unless transfer_options['agent'].to_s.eql?('transferd')
          return transfer_options.slice('url', 'api_key', 'ca_file')
        end

        # @return [String, nil] Value of option `sdk_url`, or nil to select the archive from the SDK locations (`DEF`)
        def sdk_url_option
          sdk_url = options.get_option(:sdk_url, mandatory: true)
          return sdk_url.eql?(SpecialValues::DEF) ? nil : sdk_url
        end

        # Common processing of the commands of `transferd service` that act on the system.
        # Refuses to run if the system is not supported or the user is not root, unless `--dry-run=yes`.
        # @yieldparam host       [Products::TransferdService::Host] Access to the system
        # @yieldparam sdk_folder [String]  Option `sdk_folder`, or link `current` of the layout
        # @yieldparam dry_run    [Boolean] Option `dry_run`
        def transferd_service
          host = Products::TransferdService::Host.new
          dry_run = options.get_option(:dry_run)
          Products::TransferdService.assert_supported(host, dry_run: dry_run)
          sdk_folder = options.get_option(:sdk_folder, mandatory: true)
          Aspera.assert(!Ascp::Installation.product_selector?(sdk_folder), type: Cli::BadArgument) { 'The service requires a SDK folder, not a product' }
          yield(host, sdk_folder, dry_run)
        end

        # @param steps [Array<String>] Actions done, or to do with `--dry-run=yes`
        # @return [Result] The list of actions, or a message if there is nothing to do
        def transferd_service_steps(steps)
          steps.empty? ? Result::Status.new('Nothing to do') : Result::ValueList.new(steps, name: 'action')
        end

        # Implementation of `transferd service install`
        # With the layout (SDK folder named `current`), the SDK is installed in a folder of the version, next to the link.
        # @param config [Hash] `CONFIG`
        def transferd_service_install(config)
          transferd_service do |host, sdk_folder, dry_run|
            version = Products::TransferdService.service_options(config)['version'] || Info::SDK_VERSION
            sdk_url = sdk_url_option
            installation = Ascp::Installation.instance
            install_sdk =
              if Products::TransferdService.layout?(sdk_folder)
                ->(folder) { installation.install_sdk(url: sdk_url, version: version, folder: folder) }
              else
                -> { installation.install_sdk(url: sdk_url, version: version) }
              end
            steps = Products::TransferdService.install(config, sdk_folder, host: host, dry_run: dry_run, install_sdk: install_sdk, version: version)
            Products::TransferdService.check_version(sdk_folder, host: host)
            transferd_service_steps(steps)
          end
        end
      end
    end
  end
end
