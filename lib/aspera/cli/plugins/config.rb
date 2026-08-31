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
            Aspera.assert(Dir.exist?(user_home_folder), type: Cli::Error){"Home folder does not exist: #{user_home_folder}. Check your user environment."}
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

        option :preset,             description: 'Load the named option preset from current config file',             short: 'P', handler: :option_preset
        option :version_check_days, description: 'Period in days to check new version (zero to disable)',             allowed: Allowed::TYPES_INTEGER, default: DEFAULT_CHECK_NEW_VERSION_DAYS
        option :plugin_folder,      description: 'Folder where to find additional plugins',                           handler: :option_plugin_folder
        option :sdk_url,            description: 'Ascp: URL to get Aspera Transfer Executables',                      default: SpecialValues::DEF
        option :locations_url,      description: 'Ascp: URL to get download locations of Aspera Transfer Daemon',    handler: {o: Ascp::Installation.instance, m: :transferd_urls}
        option :sdk_folder,         description: 'Ascp: Path to folder with ascp (or product with "product:")',      handler: {o: Products::Transferd, m: :sdk_directory}
        option :smtp,               schema: Schema::Registry::SMTP_OPTIONS
        option :notify_to,          description: 'Email: Recipient for notification of transfers'
        option :notify_template,    description: 'Email: ERB template for notification of transfers'
        option :cache_tokens,       description: 'Save and reuse OAuth tokens', allowed: Allowed::TYPES_BOOLEAN, default: true, handler: :option_cache_tokens

        def initialize(**_)
          super
          @vault_instance = nil
          @sdk_default_location = false
          @option_cache_tokens = true
          # :no_default uses a &block callback - must stay imperative
          options.declare(:no_default, description: 'Do not load default configuration for plugin', allowed: Allowed::TYPES_NONE, short: 'N'){presets.use_plugin_defaults = false}
          # Declare wizard options (Wizard#initialize calls options.declare internally)
          @wizard = Wizard.new(self, context.main_folder)
          options.parse_options!
          set_sdk_dir
          # HTTP options: declare metadata (class method), then bind to the instance
          Http.declare_options(options)
          context.http_config.bind_options(options)
          options.parse_options!
        end

        # DSL command declarations - replaces ACTIONS + execute_action
        # :preset is an opaque action: execute_preset handles all sub-dispatch internally
        command :preset, description: 'Manage presets of options', action: ->{execute_preset}
        command(
          :open, description: 'Open the configuration file in the default editor',
          action: lambda do
            Environment.instance.open_editor(context.presets.config_file.to_s)
            Result::Nothing.new
          end
        )
        command :documentation, description: 'Open the documentation in the default browser',
          arguments: [ArgumentSpec.new(name: :section, type: String, mandatory: false)]
        command :genkey, description: 'Generate a new RSA private key',
          arguments: [
            ArgumentSpec.new(name: :private_key_path, type: String),
            ArgumentSpec.new(name: :private_key_length, type: Integer, mandatory: false, default: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH)
          ]
        command :pubkey, description: 'Display the public key of an RSA private key',
          arguments: [ArgumentSpec.new(name: :private_key_pem, type: String)],
          action: ->(private_key_pem){Result::Text.new(OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s)}
        command :remote_certificate, description: 'Retrieve the certificate chain of a remote HTTPS server'
        command :echo, description: 'Display the value of a given argument',
          arguments: [ArgumentSpec.new(name: :value, type: nil)],
          action: ->(value){Result.auto(value)}
        command :download, description: 'Download a file from a URL',
          arguments: [
            ArgumentSpec.new(name: :file_url,  type: String),
            ArgumentSpec.new(name: :file_dest, type: String, mandatory: false)
          ]
        command :tokens, description: 'Manage OAuth tokens'
        command :plugins, description: 'Manage CLI plugins'
        command :detect, description: 'Detect the Aspera product from a URL (interactive)'
        command :wizard, description: 'Run the setup wizard for an Aspera product (interactive)'
        command :coffee, description: 'Display a coffee image', action: ->{Result::Image.new(COFFEE_IMAGE_URL)}
        command :image, description: 'Display an image',
          arguments: [ArgumentSpec.new(name: :image_uri, type: nil)],
          action: ->(image_uri){Result::Image.new(image_uri)}
        command :ascp, description: 'Manage the transfer SDK (ascp/transferd)', action: ->{execute_action_ascp}
        command :agents, description: 'Display transfer agent information', action: ->{execute_action_agents}
        command :sync, description: 'Manage Aspera Sync operations'
        command :transferd, description: 'Manage the transfer daemon (transferd)', action: ->{execute_action_transferd}
        command :gem, description: 'Display gem information'
        command :folder, description: 'Display the configuration folder path', action: ->{Result::Text.new(context.main_folder)}
        command :file, description: 'Display the configuration file path', action: ->{Result::Text.new(context.presets.config_file)}
        command(
          :email_test, description: 'Send a test email',
          action: lambda do
            context.mailer.send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
            Result::Nothing.new
          end
        )
        command :smtp_settings, description: 'Display the current SMTP settings', action: ->{Result::SingleObject.new(context.mailer.email_settings)}
        command(
          :proxy_check, description: 'Check the proxy returned by the PAC script for a given URL',
          arguments: [ArgumentSpec.new(name: :server_url, type: String)],
          action: lambda do |server_url|
            raise Cli::BadArgument, 'No PAC script configured, use --fpac' if context.pac_executor.nil?
            Result::ValueList.new(context.pac_executor.get_proxies(server_url), name: 'proxy')
          end
        )
        command :check_update, description: 'Check if a newer version of the gem is available', action: ->{Result::SingleObject.new(check_gem_version)}
        command :initdemo, description: 'Initialize the demo server preset'
        command :vault, description: 'Manage the secrets vault', action: ->{execute_vault}
        command :commands, description: 'List all available commands across all plugins'
        command :test, description: 'Internal test commands'
        command :platform, description: 'Display the current platform/architecture', action: ->{Result::Text.new(Environment.instance.architecture)}
        command :completion, description: 'Generate shell completion scripts'

        # remote_certificate sub-commands
        commands_under(:remote_certificate) do
          command :chain, description: 'Display the full certificate chain as PEM',
            arguments: [ArgumentSpec.new(name: :remote_url, type: String)]
          command :only, description: 'Display only the server certificate as PEM',
            arguments: [ArgumentSpec.new(name: :remote_url, type: String)]
          command :name, description: 'Display the CN of the server certificate',
            arguments: [ArgumentSpec.new(name: :remote_url, type: String)]
        end

        # tokens sub-commands
        commands_under(:tokens) do
          command(
            :flush, description: 'Delete all cached OAuth tokens',
            action: lambda do
              require 'aspera/api/node'
              Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
            end
          )
          command(
            :list, description: 'List all cached OAuth tokens',
            action: lambda do
              require 'aspera/api/node'
              Result::ObjectList.new(OAuth::Factory.instance.persisted_tokens)
            end
          )
          command :show, description: 'Show details of a cached OAuth token',
            arguments: [ArgumentSpec.new(name: :token_id, type: :identifier)]
        end

        # plugins sub-commands
        commands_under(:plugins) do
          command :list, description: 'List all available plugins'
          command :create, description: 'Create a new plugin skeleton file',
            arguments: [
              ArgumentSpec.new(name: :name,   type: String),
              ArgumentSpec.new(name: :folder, type: String, mandatory: false)
            ]
        end

        # sync sub-commands
        commands_under(:sync) do
          command(
            :spec, description: 'Display the sync configuration schema',
            action: lambda do
              builder = Schema::Documentation.new(TerminalFormatter, Sync::Operations::CONF_SCHEMA, include_option: true).build
              Result::ObjectList.new(builder.rows, fields: builder.columns)
            end
          )
          command :admin, description: 'Run sync admin operations', action: ->{execute_sync_admin}
          command :translate, description: 'Translate async-style arguments to sync config format',
            arguments: [ArgumentSpec.new(name: :async_arguments, type: String, multiple: true)],
            action: ->(async_arguments){Result::SingleObject.new(Sync::Operations.args_to_conf(async_arguments))}
        end

        # gem sub-commands
        commands_under(:gem) do
          command :path,    description: 'Display the gem source root path',    action: ->{Result::Text.new(self.class.gem_src_root)}
          command :version, description: 'Display the gem version',             action: ->{Result::Text.new(Cli::VERSION)}
          command :name,    description: 'Display the gem name',                action: ->{Result::Text.new(Info::GEM_NAME)}
        end

        # test sub-commands
        commands_under(:test) do
          command :throw, description: 'Raise an exception (for testing)',
            arguments: [
              ArgumentSpec.new(name: :exception_class_name, type: String),
              ArgumentSpec.new(name: :exception_text,       type: String)
            ]
          command :web, description: 'Test web browser interaction', action: -> {}
        end

        # completion sub-commands
        commands_under(:completion) do
          command :bash, description: 'Generate bash completion script',
            arguments: [ArgumentSpec.new(name: :words, type: String, multiple: true, mandatory: false)]
        end

        attr_accessor :option_cache_tokens

        attr_reader :gem_url

        def option_plugin_folder=(value)
          value = [value] unless value.is_a?(Array)
          Aspera.assert_array_all(value, String){'plugin folder(s)'}
          value.each{ |f| Plugins::Factory.instance.add_lookup_folder(f)}
        end

        def option_plugin_folder
          return Plugins::Factory.instance.lookup_folders
        end

        def option_preset; 'write-only option'; end

        def option_preset=(value)
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

        def action_documentation(section = nil)
          section = "##{section}" unless section.nil?
          Environment.instance.open_uri("#{Info::DOC_URL}#{section}")
          Result::Nothing.new
        end

        def action_genkey(private_key_path, private_key_length = OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH)
          OAuth::Jwt.generate_rsa_private_key(path: private_key_path, length: private_key_length)
          Result::Status.new("Generated #{private_key_length} bit RSA key: #{private_key_path}")
        end

        def action_remote_certificate_chain(remote_url)
          remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
          raise "No certificate found for #{remote_url}" unless remote_chain&.first
          Result::Text.new(remote_chain.map(&:to_pem).join("\n"))
        end

        def action_remote_certificate_only(remote_url)
          remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
          raise "No certificate found for #{remote_url}" unless remote_chain&.first
          Result::Text.new(remote_chain.first.to_pem)
        end

        def action_remote_certificate_name(remote_url)
          remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
          raise "No certificate found for #{remote_url}" unless remote_chain&.first
          Result::Text.new(remote_chain.first.subject.to_a.find{ |name, _, _| name == 'CN'}[1])
        end

        def action_download(file_url, file_dest = nil)
          file_url = file_url.chomp
          file_dest = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), file_url.gsub(%r{.*/}, '')) if file_dest.nil?
          Log.log.info("Downloading: #{file_url}")
          Rest.new(base_url: file_url).call(operation: 'GET', save_to_file: file_dest)
          Result::Status.new("Saved to: #{file_dest}")
        end

        def action_tokens_show(token_id)
          require 'aspera/api/node'
          data = OAuth::Factory.instance.get_token_info(token_id)
          raise Cli::Error, 'Unknown identifier' if data.nil?
          Result::SingleObject.new(data)
        end

        def action_plugins_list
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

        def action_plugins_create(plugin_name, destination_folder = nil)
          plugin_name = plugin_name.downcase
          destination_folder ||= File.join(context.main_folder, ASPERA_PLUGINS_FOLDERNAME)
          plugin_file = File.join(destination_folder, "#{plugin_name}.rb")
          content = <<~END_OF_PLUGIN_CODE
            require 'aspera/cli/plugins/base'
            module Aspera
              module Cli
                module Plugins
                  class #{plugin_name.snake_to_capital} < Base
                    command :example, description: 'example command', action: :action_example
                    def action_example
                      Result::Status.new('You called plugin #{plugin_name}')
                    end
                  end
                end
              end
            end
          END_OF_PLUGIN_CODE
          File.write(plugin_file, content)
          Result::Status.new("Created #{plugin_file}")
        end

        def action_detect
          options.ask_missing_mandatory = true
          apps = @wizard.identify_plugins_for_url.freeze
          Result::ObjectList.new(apps)
        end

        def action_wizard
          options.ask_missing_mandatory = true
          apps = @wizard.identify_plugins_for_url.freeze
          @wizard.find(apps)
        end

        def action_initdemo
          cp = presets.config_presets
          if cp.key?(DEMO_PRESET)
            Log.log.warn{"Demo server preset already present: #{DEMO_PRESET}"}
          else
            Log.log.info{"Creating Demo server preset: #{DEMO_PRESET}"}
            cp[DEMO_PRESET] = {
              'url'                                    => "ssh://#{DEMO_SERVER}.asperasoft.com:33001",
              'username'                               => ASPERA,
              'ssAP'.downcase.reverse + 'drow'.reverse => DEMO_SERVER + ASPERA # cspell:disable-line
            }
          end
          cp[PresetManager::Key::DEFAULTS] ||= {}
          if cp[PresetManager::Key::DEFAULTS].key?(SERVER_COMMAND)
            Log.log.warn{"Server default preset already set to: #{cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND]}"}
            Log.log.warn{"Use #{DEMO_PRESET} for demo: -P#{DEMO_PRESET}"} unless
              DEMO_PRESET.eql?(cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND])
          else
            cp[PresetManager::Key::DEFAULTS][SERVER_COMMAND] = DEMO_PRESET
            Log.log.info{"Setting server default preset to : #{DEMO_PRESET}"}
          end
          Result::Status.new('Done')
        end

        def action_commands
          commands = Plugins::Factory.instance.plugin_list.flat_map do |name|
            plugin_class = Plugins::Factory.instance.plugin_class(name)
            reg = plugin_class.command_registry
            reg.all_paths.reject{ |path| reg.children_of(path).any?}.map do |path|
              "#{name} #{path.join(' ')}"
            end
          end
          Result::ValueList.new(commands, name: 'command')
        end

        def action_test_throw(exception_class_name, exception_text)
          type = Object.const_get(exception_class_name)
          Aspera.assert(type <= Exception){"#{type} is not an exception: #{type.class}"}
          raise type, exception_text
        end

        def action_completion_bash(words = nil)
          if words.nil?
            Plugins::Factory.instance.plugin_list.each{ |p| puts p}
          else
            Log.log.warn('only first level completion so far')
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
