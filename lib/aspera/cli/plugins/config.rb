# frozen_string_literal: true

# cspell:ignore initdemo genkey pubkey asperasoft filelists
require 'aspera/cli/bootstrapper'
require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/plugins/factory'
require 'aspera/cli/extended_value'
require 'aspera/cli/special_values'
require 'aspera/cli/version'
require 'aspera/cli/formatter'
require 'aspera/cli/info'
require 'aspera/cli/wizard'
require 'aspera/cli/sync_actions'
require 'aspera/cli/ascp_actions'
require 'aspera/cli/preset_actions'
require 'aspera/cli/vault_manager'
require 'aspera/cli/transfer_actions'
require 'aspera/cli/gem_checker'
require 'aspera/ascp/installation'
require 'aspera/sync/operations'
require 'aspera/products/transferd'
require 'aspera/transfer/spec'
require 'aspera/schema/documentation'
require 'aspera/keychain/macos_security'
require 'aspera/environment'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/data_repository'
require 'aspera/rest'
require 'aspera/oauth/jwt'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/string_ext'
require 'openssl'
require 'digest'
require 'open3'
require 'net/http'

module Aspera
  module Cli
    module Plugins
      # Manage the CLI config file
      class Config < Base
        include SyncActions
        include VaultManager
        include GemChecker
        include AscpActions
        include PresetActions
        include TransferActions

        class << self
          # Folder containing plugins in the gem's main folder
          def gem_plugins_folder
            File.dirname(File.expand_path(__FILE__))
          end

          # @return [String] main folder where code is, i.e. .../lib
          # Go up as many times as englobing modules (not counting class, as it is a file)
          def gem_src_root
            # Module.nesting[2] is Cli::Plugins
            File.expand_path(Module.nesting[2].to_s.gsub('::', '/').gsub(%r{[^/]+}, '..'), gem_plugins_folder)
          end

          # Deep clone hash so that it does not get modified in case of display and secret hide
          def deep_clone(val)
            return Marshal.load(Marshal.dump(val))
          end

          # @return [String] product family folder (~/.aspera)
          def module_family_folder
            user_home_folder = Dir.home
            Aspera.assert(Dir.exist?(user_home_folder), type: Cli::Error) { "Home folder does not exist: #{user_home_folder}. Check your user environment." }
            return File.join(user_home_folder, ASPERA_HOME_FOLDER_NAME)
          end

          # @return [String] Product config folder (~/.aspera/<name>)
          def default_app_main_folder(app_name:)
            Aspera.assert_type(app_name, String)
            Aspera.assert(!app_name.empty?, 'app_name must not be empty')
            return File.join(module_family_folder, app_name)
          end
        end

        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
        private_constant :DEFAULT_CHECK_NEW_VERSION_DAYS

        option :preset,             description: 'Load the named option preset from current config file',             short: 'P', handler: :load_preset
        option :version_check_days, description: 'Period in days to check new version (zero to disable)',             allowed: Type::INTEGER, default: DEFAULT_CHECK_NEW_VERSION_DAYS
        option :plugin_folder,      description: 'Folder where to find additional plugins',                           handler: :add_plugin_folders
        option :sdk_url,            description: 'Ascp: URL to get Aspera Transfer Executables',                      default: SpecialValues::DEF
        option :locations_url,      description: 'Ascp: URL to get download locations of Aspera Transfer Daemon',    default: Ascp::Installation.instance.transferd_urls, handler: Ascp::Installation.instance.method(:transferd_urls=)
        option :sdk_folder,         description: 'Ascp: Path to folder with ascp (or product with "product:")',      handler: Ascp::Installation.instance.method(:sdk_folder=)
        option :smtp,               schema: Schema::Registry::SMTP_OPTIONS
        option :notify_to,          description: 'Email: Recipient for notification of transfers'
        option :notify_template,    description: 'Email: ERB template for notification of transfers'
        option :cache_tokens,       description: 'Save and reuse OAuth tokens', allowed: Type::BOOLEAN, default: true
        option :expand_mounts,      description: 'Commands: list commands of sub-trees provided by another plugin', allowed: Type::BOOLEAN, default: false
        option :no_default,         description: 'Do not load default configuration for plugin', allowed: Type::NONE, short: 'N', handler: -> { presets.use_plugin_defaults = false }

        def initialize(**_)
          super
          @vault_instance = nil
          @sdk_default_location = false
          # Declare wizard options (Wizard#initialize calls options.declare internally)
          @wizard = Wizard.new(self, context.main_folder)
          # HTTP options: declare metadata (class method), then bind to the instance
          Http.declare_options(options)
          context.http_config.bind_options(options)
          # Values set through handlers are used below (sdk_folder)
          options.parse_options!
          set_sdk_dir
        end

        command :preset, description: 'Manage configuration presets'
        commands_under :preset do
          command :list,     description: 'List all presets', action: ->(**) { Result::ValueList.new(presets.config_presets.keys, name: 'name') }
          command :overview, description: 'Show all options from all presets'
          command :lookup,   description: 'Find preset matching URL and username'
          command :secure,   description: 'Move secrets to vault',
            arguments: [{name: :config_name, mandatory: false}]
          command :show,       description: 'Show a preset',
            arguments: [{name: :name, type: :identifier}]
          command :delete,     description: 'Delete a preset',
            arguments: [{name: :name, type: :identifier}]
          command :get,        description: 'Show a single parameter of a preset',
            arguments: [{name: :name, type: :identifier}, {name: :param_name}]
          command :unset,      description: 'Remove a parameter from a preset',
            arguments: [{name: :name, type: :identifier}, {name: :param_name}]
          command :set, description: 'Set a parameter in a preset',
            arguments: [{name: :name, type: :identifier}, {name: :param_name},
                        {name: :param_value, type: nil}]
          command :initialize, description: 'Initialize a preset with a value',
            arguments: [{name: :name, type: :identifier}, {name: :preset, type: Hash}]
          command :update,     description: 'Update a preset with current option values',
            arguments: [{name: :name, type: :identifier}]
          command :ask,        description: 'Ask for option values interactively',
            arguments: [{name: :name, type: :identifier},
                        {name: :option_names, multiple: true, interactive: true}]
        end
        command(
          :open, description: 'Open the configuration file in the default editor',
          action: lambda do |**|
            Environment.instance.open_editor(context.presets.config_file.to_s)
            Result::Nothing.new
          end
        )
        command :documentation, description: 'Open the documentation in the default browser',
          arguments: [
            {name: :location, type: Symbol, mandatory: false, default: :github, allowed: %i[github local toc]},
            {name: :section, mandatory: false}
          ]
        command(
          :genkey, description: 'Generate a new RSA private key',
          arguments: [
            {name: :private_key_path},
            {name: :private_key_length, type: Integer, mandatory: false, default: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH}
          ],
          action: lambda do |private_key_path:, private_key_length: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH, **|
            OAuth::Jwt.generate_rsa_private_key(path: private_key_path, length: private_key_length)
            Result::Status.new("Generated #{private_key_length} bit RSA key: #{private_key_path}")
          end
        )
        command :pubkey, description: 'Show the public key of an RSA private key',
          arguments: [{name: :private_key_pem}],
          action: ->(private_key_pem:, **) { Result::Text.new(OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s) }
        command :remote_certificate, description: 'Retrieve the certificate chain of a remote HTTPS server'
        command :echo, description: 'Show the value of a given argument',
          arguments: [{name: :value, type: nil}],
          action: ->(value:, **) { Result.auto(value) }
        command :download, description: 'Download a file from a URL',
          arguments: [
            {name: :file_url},
            {name: :file_dest, mandatory: false}
          ]
        command :tokens, description: 'Manage OAuth tokens'
        command :plugins, description: 'Manage CLI plugins'
        command :detect, description: 'Detect the Aspera product from a URL (interactive)',
          arguments: [{name: :url, interactive: true}, {name: :plugin_name, mandatory: false, default: nil}],
          action: ->(url:, plugin_name: nil, **) { Result::ObjectList.new(@wizard.identify_plugins_for_url(url: url, plugin_name: plugin_name).freeze) }
        command(
          :wizard, description: 'Run the setup wizard for an Aspera product (interactive)',
          arguments: [{name: :url, interactive: true}, {name: :plugin_name, mandatory: false, default: nil},
                      {name: :preset_name, mandatory: false, default: ''}],
          action: lambda do |url:, plugin_name: nil, preset_name: '', **|
            apps = @wizard.identify_plugins_for_url(url: url, plugin_name: plugin_name).freeze
            @wizard.find(apps, preset_name: preset_name)
          end
        )
        command :coffee, description: 'Show a coffee image', action: ->(**) { Result::Image.new(COFFEE_IMAGE_URL) }
        command :image, description: 'Show an image',
          arguments: [{name: :image_uri, type: nil}],
          action: ->(image_uri:, **) { Result::Image.new(image_uri) }
        command :sync, description: 'Manage Aspera Sync operations'
        command :gem, description: 'Show gem information'
        command :folder, description: 'Show the configuration folder path', action: ->(**) { Result::Text.new(context.main_folder) }
        command :file, description: 'Show the configuration file path', action: ->(**) { Result::Text.new(context.presets.config_file) }
        command(
          :email_test, description: 'Send a test email',
          action: lambda do |**|
            context.mailer.send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
            Result::Nothing.new
          end
        )
        command :smtp_settings, description: 'Show the current SMTP settings', action: ->(**) { Result::SingleObject.new(context.mailer.email_settings) }
        command(
          :proxy_check, description: 'Check the proxy returned by the PAC script for a given URL',
          arguments: [{name: :server_url}],
          action: lambda do |server_url:, **|
            Aspera.assert(!context.pac_executor.nil?, type: Cli::BadArgument) { 'No PAC script configured, use --fpac' }
            Result::ValueList.new(context.pac_executor.get_proxies(server_url), name: 'proxy')
          end
        )
        command :check_update, description: 'Check if a newer version of the gem is available', action: ->(**) { Result::SingleObject.new(check_gem_version) }
        command :initdemo, description: 'Initialize the demo server preset'
        command :vault, description: 'Manage secrets in the vault'
        commands_under :vault do
          command :info,     description: 'Show vault information',
            action: ->(**) { Result::SingleObject.new(vault_required.info) }
          command :ids,      description: 'List secret labels in the vault',
            action: ->(**) { Result::ObjectList.new(vault_required.ids) }
          command :list,     description: 'List all secrets with full details',
            action: ->(**) { Result::ObjectList.new(vault_required.all) }
          command(
            :show,     description: 'Show a secret by label (or id)',
            arguments: [{name: :label}, {name: :id, mandatory: false, default: nil}],
            action: lambda do |label:, id: nil, **|
              v = vault_required
              kwargs = id && v.method(:get).parameters.any? { |_t, n| n == :id } ? {id: id} : {}
              Result::SingleObject.new(v.get(label: label, **kwargs))
            end
          )
          command(
            :create,   description: 'Add a new secret to the vault',
            arguments: [{name: :secret, type: Hash, schema: Schema::Registry::VAULT_SECRET}],
            action: lambda do |secret:, **|
              vault_required.set(secret.symbolize_keys)
              Result::Status.new('Secret added')
            end
          )
          command :delete, description: 'Delete a secret by label (or id)',
            arguments: [{name: :label}, {name: :id, mandatory: false, default: nil}]
          command(
            :password, description: 'Change the vault password',
            arguments: [{name: :new_password}],
            action: lambda do |new_password:, **|
              Aspera.assert(vault_required.respond_to?(:change_password), 'Vault does not support password change')
              vault_required.change_password(new_password)
              Result::Status.new('Vault password updated')
            end
          )
          command :import, description: 'Import secrets from a JSON array (supports --bulk)',
            arguments: [{name: :secrets, type: Array, schema: {type: 'array', items: {'$ref' => Schema::Registry::VAULT_SECRET}}}]
        end
        command :commands, description: 'List all available commands, of all plugins or only the given one, optionally under a command path',
          arguments: [{name: :plugin_name, mandatory: false, default: nil},
                      {name: :command_path, multiple: true, mandatory: false, default: nil}]
        command :options, description: 'List all options available for a plugin',
          arguments: [{name: :plugin_name}]
        command :test, description: 'Internal test commands'
        command :platform, description: 'Show the current platform/architecture', action: ->(**) { Result::Text.new(Environment.instance.architecture) }
        command :completion, description: 'Generate shell completion scripts'

        # remote_certificate sub-commands
        commands_under :remote_certificate do
          command(
            :chain, description: 'Show the full certificate chain as PEM',
            arguments: [{name: :remote_url}],
            action: lambda do |remote_url:, **|
              remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
              Aspera.assert(remote_chain&.first) { "No certificate found for #{remote_url}" }
              Result::Text.new(remote_chain.map(&:to_pem).join("\n"))
            end
          )
          command(
            :only, description: 'Show only the server certificate as PEM',
            arguments: [{name: :remote_url}],
            action: lambda do |remote_url:, **|
              remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
              Aspera.assert(remote_chain&.first) { "No certificate found for #{remote_url}" }
              Result::Text.new(remote_chain.first.to_pem)
            end
          )
          command(
            :name, description: 'Show the CN of the server certificate',
            arguments: [{name: :remote_url}],
            action: lambda do |remote_url:, **|
              remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
              Aspera.assert(remote_chain&.first) { "No certificate found for #{remote_url}" }
              Result::Text.new(remote_chain.first.subject.to_a.find { |name, _, _| name == 'CN' }[1])
            end
          )
        end

        # tokens sub-commands
        commands_under :tokens do
          command(
            :flush, description: 'Delete all cached OAuth tokens',
            action: lambda do |**|
              require 'aspera/api/node'
              Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
            end
          )
          command(
            :list, description: 'List all cached OAuth tokens',
            action: lambda do |**|
              require 'aspera/api/node'
              Result::ObjectList.new(OAuth::Factory.instance.persisted_tokens)
            end
          )
          command :show, description: 'Show details of a cached OAuth token',
            arguments: [{name: :token_id, type: :identifier}]
        end

        # plugins sub-commands
        commands_under :plugins do
          command :list, description: 'List all available plugins'
          command :create, description: 'Create a new plugin skeleton file',
            arguments: [
              {name: :name},
              {name: :folder, mandatory: false}
            ]
        end

        # ascp sub-commands
        command :ascp, description: 'Manage FASP/ascp transfer engine'
        commands_under :ascp do
          command :show,    description: 'Show ascp binary path', action: ->(**) { Result::Text.new(Ascp::Installation.instance.path(:ascp)) }
          command :info,    description: 'Show ascp and transfer spec information'
          command :install, description: 'Install the transfer SDK',
            arguments: [{name: :version, mandatory: false, default: nil}],
            action: ->(version: nil, **) { install_transfer_sdk(version: version) }
          command(
            :spec, description: 'Show the transfer spec schema',
            action: lambda do |**|
              builder = Schema::Documentation.new(TerminalFormatter, Transfer::Spec::SCHEMA, include_option: true, agent_columns: true).build
              Result::ObjectList.new(builder.rows, fields: builder.columns)
            end
          )
          command :schema, description: 'Show the transfer spec JSON schema',
            arguments: [{name: :agent_name, allowed: Agent::Factory::ALL.keys, mandatory: false, default: nil}]
          command :errors,   description: 'Show FASP error codes'
          command :products, description: 'Manage installed Aspera products'
          commands_under :products do
            command :list, description: 'List installed Aspera products',
              action: ->(**) { Result::ObjectList.new(Ascp::Installation.instance.installed_products, fields: %w[name app_root]) }
          end
        end

        # agents sub-commands
        command :agents, description: 'Manage transfer agents'
        commands_under :agents do
          command :list,       description: 'List all transfer agents'
          command :show,       description: 'Show details for a transfer agent',
            arguments: [{name: :agent_name, allowed: Agent::Factory::ALL.keys}]
          command :parameters, description: 'Show configurable parameters for a transfer agent',
            arguments: [{name: :agent_name, allowed: Agent::Factory::ALL.keys}]
        end

        # transfer async management sub-commands
        command :transfer, description: 'Manage asynchronous transfers'
        commands_under :transfer do
          command(
            :list, description: 'List all async transfer jobs',
            action: lambda do |**|
              rows = async_transfer_store.list
              Result::ObjectList.new(rows, fields: %w[job_id agent_type status started_at ended_at bytes_transferred transfer_id])
            end
          )
          command :status,  description: 'Show status of an async transfer job',
            arguments: [{name: :job_id}]
          command :cleanup, description: 'Remove completed/failed/cancelled transfer entries'
        end

        # transferd sub-commands
        command :transferd, description: 'Manage the transfer daemon (transferd)'
        commands_under :transferd do
          command :install, description: 'Install the transfer daemon', action: ->(**) { install_transfer_sdk }
          command(
            :list, description: 'List available SDK locations',
            action: lambda do |**|
              sdk_list = Ascp::Installation.instance.sdk_locations
              Result::ObjectList.new(sdk_list, fields: sdk_list.first.keys - ['url'])
            end
          )
        end

        # sync sub-commands
        commands_under :sync do
          command(
            :spec, description: 'Show the sync configuration schema',
            action: lambda do |**|
              builder = Schema::Documentation.new(TerminalFormatter, Sync::Operations::CONF_SCHEMA, include_option: true).build
              Result::ObjectList.new(builder.rows, fields: builder.columns)
            end
          )
          command :admin, description: 'Manage sync database (admin operations)'
          SyncActions.register_sync_admin_commands(self, :admin)
          command :translate, description: 'Translate async-style arguments to sync config format',
            arguments: [{name: :async_arguments, multiple: true}],
            action: ->(async_arguments:, **) { Result::SingleObject.new(Sync::Operations.args_to_conf(async_arguments)) }
        end

        # gem sub-commands
        commands_under :gem do
          command :path,    description: 'Show the gem source root path',    action: ->(**) { Result::Text.new(self.class.gem_src_root) }
          command :version, description: 'Show the gem version',             action: ->(**) { Result::Text.new(Cli::VERSION) }
          command :name,    description: 'Show the gem name',                action: ->(**) { Result::Text.new(Info::GEM_NAME) }
        end

        # test sub-commands
        commands_under :test do
          command(
            :throw, description: 'Raise an exception (for testing)',
            arguments: [
              {name: :exception_class_name},
              {name: :exception_text}
            ],
            action: lambda do |exception_class_name:, exception_text:, **|
              type = Object.const_get(exception_class_name)
              Aspera.assert(type <= Exception) { "#{type} is not an exception: #{type.class}" }
              raise type, exception_text
            end
          )
          command :web, description: 'Test web browser interaction', action: ->(**) {}
        end

        # completion sub-commands
        commands_under :completion do
          command :bash, description: 'Generate bash completion script',
            arguments: [{name: :words, multiple: true, mandatory: false}]
        end

        attr_reader :gem_url

        # Handler of option `plugin_folder`
        # @param value [String, Array<String>] folder(s) where to find plugins
        def add_plugin_folders(value)
          value = [value] unless value.is_a?(Array)
          Aspera.assert_array_all(value, String) { 'plugin folder(s)' }
          value.each { |f| Plugins::Factory.instance.add_lookup_folder(f) }
        end

        # Handler of option `preset`
        # @param value [String, Hash] preset name, or set of option values
        def load_preset(value)
          case value
          when Hash
            options.add_option_preset(value, 'set')
          when String
            options.add_option_preset(presets.by_name(value), 'set_by_name')
          else
            raise BadArgument, 'Preset definition must be a String for preset name, or Hash for set of values'
          end
        end

        # DSL handlers - one method per leaf command

        def action_documentation(location: :github, section: nil, **)
          case location
          when :github
            section = "##{section}" unless section.nil?
            Environment.instance.open_uri("#{Info::DOC_URL}#{section}")
            return Result::Nothing.new
          when :toc, :local
            require 'aspera/markdown'
            local_doc = File.join(self.class.gem_src_root, '..', 'docs', 'README.md')
            Aspera.assert(File.exist?(local_doc), type: Cli::Error) { "Local documentation not found: #{local_doc}" }
            content = File.read(local_doc)
            if location == :toc
              entries = Markdown.toc(content)
              return Result::ObjectList.new(entries, fields: %w[level title anchor])
            end
            # :local
            if section
              text = Markdown.extract_section(content, section)
              Aspera.assert(!text.nil?, type: Cli::Error) { "Section not found: #{section}" }
              return Result::Text.new(text)
            end
            if Environment.instance.url_method.eql?(:graphical)
              Environment.instance.open_uri("file://#{local_doc}")
              return Result::Nothing.new
            end
            return Result::Text.new(content)
          end
        end

        def action_download(file_url:, file_dest: nil, **)
          file_url = file_url.chomp
          file_dest = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), file_url.gsub(%r{.*/}, '')) if file_dest.nil?
          Log.log.info("Downloading: #{file_url}")
          Rest.new(base_url: file_url).call(operation: 'GET', save_to: file_dest)
          Result::Status.new("Saved to: #{file_dest}")
        end

        def action_tokens_show(token_id:, **)
          require 'aspera/api/node'
          data = OAuth::Factory.instance.get_token_info(token_id)
          Aspera.assert(!data.nil?, type: Cli::Error) { 'Unknown identifier' }
          Result::SingleObject.new(data)
        end

        def action_plugins_list(**)
          result = Plugins::Factory.instance.plugin_list.map do |name|
            plugin_class = Plugins::Factory.instance.plugin_class(name)
            {
              plugin: name,
              detect: TerminalFormatter.tick(plugin_class.respond_to?(:detect)),
              wizard: TerminalFormatter.tick(plugin_class.method_defined?(:wizard)),
              path:   Plugins::Factory.instance.plugin_source(name)
            }
          end
          Result::ObjectList.new(result, fields: %w[plugin detect wizard path])
        end

        def action_plugins_create(name:, folder: nil, **)
          plugin_name = name.downcase
          destination_folder = folder || File.join(context.main_folder, ASPERA_PLUGINS_FOLDERNAME)
          plugin_file = File.join(destination_folder, "#{plugin_name}.rb")
          content = <<~END_OF_PLUGIN_CODE
            require 'aspera/cli/plugins/base'
            module Aspera
              module Cli
                module Plugins
                  class #{plugin_name.snake_to_capital} < Base
                    command :example, description: 'example command', action: ->(**) { Result::Status.new('You called plugin #{plugin_name}') }
                  end
                end
              end
            end
          END_OF_PLUGIN_CODE
          File.write(plugin_file, content)
          Result::Status.new("Created #{plugin_file}")
        end

        def action_initdemo(**)
          cp = presets.config_presets
          if cp.key?(DEMO_PRESET)
            Log.log.warn { "Demo server preset already present: #{DEMO_PRESET}" }
          else
            Log.log.info { "Creating Demo server preset: #{DEMO_PRESET}" }
            cp[DEMO_PRESET] = {
              'url'                                    => "ssh://#{DEMO_SERVER}.asperasoft.com:33001",
              'username'                               => ASPERA,
              'ssAP'.downcase.reverse + 'drow'.reverse => DEMO_SERVER + ASPERA # cspell:disable-line
            }
          end
          cp[PresetManager::Key::DEFAULTS] ||= {}
          if cp[PresetManager::Key::DEFAULTS].key?(SERVER_COMMAND)
            Log.log.warn { "Server default preset already set to: #{cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND]}" }
            Log.log.warn { "Use #{DEMO_PRESET} for demo: -P#{DEMO_PRESET}" } unless
              DEMO_PRESET.eql?(cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND])
          else
            cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND] = DEMO_PRESET
            Log.log.info { "Setting server default preset to : #{DEMO_PRESET}" }
          end
          Result::Status.new('Done')
        end

        def action_commands(plugin_name: nil, command_path: nil, **)
          plugin_names = Plugins::Factory.instance.plugin_list
          unless plugin_name.nil?
            Aspera.assert_values(plugin_name.to_sym, plugin_names, type: Cli::BadArgument)
            plugin_names = [plugin_name.to_sym]
          end
          prefix = Array(command_path).map(&:to_sym)
          Aspera.assert(prefix.empty? || plugin_names.length.eql?(1), type: Cli::BadArgument) { 'command path requires a plugin name' }
          expand_mounts = options.get_option(:expand_mounts)
          commands = plugin_names.flat_map do |name|
            reg = Plugins::Factory.instance.plugin_class(name).command_registry
            Aspera.assert(prefix.empty? || reg[prefix], type: Cli::BadArgument) { "no such command: #{name} #{prefix.join(' ')}" }
            paths = prefix.empty? || reg.children_of(prefix).any? ? reg.leaf_paths(prefix, expand_mounts: expand_mounts) : [prefix]
            paths.map do |path|
              mount = expand_mounts ? nil : reg.mount_at(path)
              description = reg[path]&.description.to_s
              if mount
                target = mount.plugin.name.split('::').last.downcase
                description = "#{description} (see: #{command_syntax(target, mount.registry, mount.at)})"
              end
              {
                syntax:      command_syntax(name, reg, path) + (mount ? ' <command...>' : ''),
                description: description
              }
            end
          end
          Result::ObjectList.new(commands, fields: %w[syntax description])
        end

        # Build syntax by interleaving each path segment with the arguments declared on that node
        # @param name [String, Symbol]       plugin name
        # @param reg  [CommandRegistry]      registry of plugin
        # @param path [Array<Symbol>]        command path
        # @return [String] e.g. `node access_keys do <access_key_id> ls <path>`
        def command_syntax(name, reg, path)
          tokens = [name.to_s]
          path.each_index do |i|
            tokens << path[i].to_s
            reg.arguments_at(path[0, i + 1]).each { |a| tokens << a.syntax }
          end
          tokens.join(' ')
        end

        def action_options(plugin_name:, **)
          # Instantiate the plugin so that it registers all its options in context.options
          Plugins::Factory.instance.create(plugin_name.to_sym, context: context)
          rows = context.options.declared_options.map do |sym, opt|
            row = {
              option:      "--#{sym.to_s.tr('_', '-')}",
              description: opt.description.to_s
            }
            row[:allowed]    = opt.values.join('|') if opt.values&.any?
            row[:deprecated] = opt.deprecation      if opt.deprecation
            row
          end
          Result::ObjectList.new(rows, fields: %w[option description allowed deprecated])
        end

        def action_completion_bash(words: nil, **)
          if words.nil? || words.empty?
            # Level 0: propose plugin names
            Plugins::Factory.instance.plugin_list.each { |p| puts p }
          else
            plugin_sym = words.first.to_sym
            plugin_class = begin
              Plugins::Factory.instance.plugin_class(plugin_sym)
            rescue StandardError
              Process.exit(0)
            end
            # Navigate into the registry using remaining words as path
            path = words[1..].map(&:to_sym)
            plugin_class.command_registry.children_of(path).each_key { |k| puts k }
          end
          Process.exit(0)
        end

        # Folder in $HOME for application files (~/.aspera)
        ASPERA_HOME_FOLDER_NAME = '.aspera'
        # Default config file name
        DEFAULT_CONFIG_FILENAME = 'config.yaml'
        CONF_GLOBAL_SYM = :config
        # Folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME = 'plugins'
        PERSISTENCY_FOLDER = 'persist_store'
        FILE_LIST_FOLDER_NAME = 'filelists'
        REST_EXCEPTIONS_LOG_FILENAME = 'rest_exceptions.log'
        ASPERA = 'aspera'
        SERVER_COMMAND = 'server'
        DEMO_SERVER = 'demo'
        DEMO_PRESET = 'demoserver' # cspell: disable-line
        EMAIL_TEST_TEMPLATE = <<~END_OF_TEMPLATE
          From: <%=from_name%> <<%=from_email%>>
          To: <<%=to%>>
          Subject: #{Info::GEM_NAME} email test

          This email was sent to test #{Info::CMD_NAME}.
        END_OF_TEMPLATE
        # Special extended values
        EXTEND_PRESET = :preset
        EXTEND_VAULT = :vault
        COFFEE_IMAGE_URL = 'https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg'
        private_constant :ASPERA_HOME_FOLDER_NAME,
          :DEFAULT_CONFIG_FILENAME,
          :CONF_GLOBAL_SYM,
          :ASPERA_PLUGINS_FOLDERNAME,
          :PERSISTENCY_FOLDER,
          :FILE_LIST_FOLDER_NAME,
          :REST_EXCEPTIONS_LOG_FILENAME,
          :ASPERA,
          :SERVER_COMMAND,
          :DEMO_SERVER,
          :DEMO_PRESET,
          :EMAIL_TEST_TEMPLATE,
          :EXTEND_PRESET,
          :EXTEND_VAULT,
          :COFFEE_IMAGE_URL
      end
    end
  end
end
