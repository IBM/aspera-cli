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

        def initialize(**_)
          super
          @vault_instance = nil
          @pac_exec = nil
          @sdk_default_location = false
          @option_cache_tokens = true
          # Declare generic plugin options (only after bootstrap has registered handlers)
          Base.declare_options(options)
          # Configuration options
          options.declare(:no_default, 'Do not load default configuration for plugin', allowed: Allowed::TYPES_NONE, short: 'N'){presets.use_plugin_defaults = false}
          options.declare(:preset, 'Load the named option preset from current config file', short: 'P', handler: {o: self, m: :option_preset})
          options.declare(:version_check_days, 'Period in days to check new version (zero to disable)', allowed: Allowed::TYPES_INTEGER, default: DEFAULT_CHECK_NEW_VERSION_DAYS)
          options.declare(:plugin_folder, 'Folder where to find additional plugins', handler: {o: self, m: :option_plugin_folder})
          # Declare wizard options
          @wizard = Wizard.new(self, context.main_folder)
          # Transfer SDK options
          options.declare(:sdk_url, 'Ascp: URL to get Aspera Transfer Executables', default: SpecialValues::DEF)
          options.parse_options!
          set_sdk_dir
          options.declare(:locations_url, 'Ascp: URL to get download locations of Aspera Transfer Daemon', handler: {o: Ascp::Installation.instance, m: :transferd_urls})
          options.declare(:sdk_folder, 'Ascp: Path to folder with ascp (or product with "product:")', handler: {o: Products::Transferd, m: :sdk_directory})
          # Email options
          options.declare(:smtp, allowed: Hash, schema: Schema::Registry::SMTP_OPTIONS)
          options.declare(:notify_to, 'Email: Recipient for notification of transfers')
          options.declare(:notify_template, 'Email: ERB template for notification of transfers')
          # HTTP options — declared by HttpConfig itself
          context.http_config.declare_options(options)
          options.declare(:cache_tokens, 'Save and reuse OAuth tokens', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :option_cache_tokens})
          options.parse_options!
        end

        public

        # DSL command declarations — replaces ACTIONS + execute_action
        # :preset is an opaque handler: execute_preset handles all sub-dispatch internally
        command :preset,
          description: 'Manage presets of options'
        command :open,
          description: 'Open the configuration file in the default editor'
        command :documentation,
          description: 'Open the documentation in the default browser',
          arguments: [ArgumentSpec.new(name: :section, type: String, mandatory: false)]
        command :genkey,
          description: 'Generate a new RSA private key',
          arguments: [
            ArgumentSpec.new(name: :private_key_path, type: String),
            ArgumentSpec.new(name: :private_key_length, type: Integer, mandatory: false, default: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH)
          ]
        command :pubkey,
          description: 'Display the public key of an RSA private key',
          arguments: [ArgumentSpec.new(name: :private_key_pem, type: String)]
        command :remote_certificate,
          description: 'Retrieve the certificate chain of a remote HTTPS server'
        command :echo,
          description: 'Display the value of a given argument',
          arguments: [ArgumentSpec.new(name: :value, type: nil)]
        command :download,
          description: 'Download a file from a URL',
          arguments: [
            ArgumentSpec.new(name: :file_url,  type: String),
            ArgumentSpec.new(name: :file_dest, type: String, mandatory: false)
          ]
        command :tokens,
          description: 'Manage OAuth tokens'
        command :plugins,
          description: 'Manage CLI plugins'
        command :detect,
          description: 'Detect the Aspera product from a URL (interactive)'
        command :wizard,
          description: 'Run the setup wizard for an Aspera product (interactive)'
        command :coffee,
          description: 'Display a coffee image'
        command :image,
          description: 'Display an image',
          arguments: [ArgumentSpec.new(name: :image_uri, type: nil)]
        command :ascp,
          description: 'Manage the transfer SDK (ascp/transferd)'
        command :agents,
          description: 'Display transfer agent information'
        command :sync,
          description: 'Manage Aspera Sync operations'
        command :transferd,
          description: 'Manage the transfer daemon (transferd)'
        command :gem,
          description: 'Display gem information'
        command :folder,
          description: 'Display the configuration folder path'
        command :file,
          description: 'Display the configuration file path'
        command :email_test,
          description: 'Send a test email'
        command :smtp_settings,
          description: 'Display the current SMTP settings'
        command :proxy_check,
          description: 'Check the proxy returned by the PAC script for a given URL',
          arguments: [ArgumentSpec.new(name: :server_url, type: String)]
        command :check_update,
          description: 'Check if a newer version of the gem is available'
        command :initdemo,
          description: 'Initialize the demo server preset'
        command :vault,
          description: 'Manage the secrets vault'
        command :test,
          description: 'Internal test commands'
        command :platform,
          description: 'Display the current platform/architecture'
        command :completion,
          description: 'Generate shell completion scripts'

        # remote_certificate sub-commands
        commands_under(:remote_certificate) do
          command :chain,
            description: 'Display the full certificate chain as PEM',
            arguments: [ArgumentSpec.new(name: :remote_url, type: String)]
          command :only,
            description: 'Display only the server certificate as PEM',
            arguments: [ArgumentSpec.new(name: :remote_url, type: String)]
          command :name,
            description: 'Display the CN of the server certificate',
            arguments: [ArgumentSpec.new(name: :remote_url, type: String)]
        end

        # tokens sub-commands
        commands_under(:tokens) do
          command :flush,
            description: 'Delete all cached OAuth tokens'
          command :list,
            description: 'List all cached OAuth tokens'
          command :show,
            description: 'Show details of a cached OAuth token',
            arguments: [ArgumentSpec.new(name: :token_id, type: :identifier)]
        end

        # plugins sub-commands
        commands_under(:plugins) do
          command :list,
            description: 'List all available plugins'
          command :create,
            description: 'Create a new plugin skeleton file',
            arguments: [
              ArgumentSpec.new(name: :name,   type: String),
              ArgumentSpec.new(name: :folder, type: String, mandatory: false)
            ]
        end

        # sync sub-commands
        commands_under(:sync) do
          command :spec,
            description: 'Display the sync configuration schema'
          command :admin,
            description: 'Run sync admin operations'
          command :translate,
            description: 'Translate async-style arguments to sync config format',
            arguments: [ArgumentSpec.new(name: :async_arguments, type: String, multiple: true)]
        end

        # gem sub-commands
        commands_under(:gem) do
          command :path,    description: 'Display the gem source root path'
          command :version, description: 'Display the gem version'
          command :name,    description: 'Display the gem name'
        end

        # test sub-commands
        commands_under(:test) do
          command :throw,
            description: 'Raise an exception (for testing)',
            arguments: [
              ArgumentSpec.new(name: :exception_class_name, type: String),
              ArgumentSpec.new(name: :exception_text,       type: String)
            ]
          command :web,
            description: 'Test web browser interaction'
        end

        # completion sub-commands
        commands_under(:completion) do
          command :bash,
            description: 'Generate bash completion script',
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

        # DSL handlers — one method per leaf command

        def handle_open
          Environment.instance.open_editor(context.presets.config_file.to_s)
          Result::Nothing.new
        end

        def handle_documentation(section = nil)
          section = "##{section}" unless section.nil?
          Environment.instance.open_uri("#{Info::DOC_URL}#{section}")
          Result::Nothing.new
        end

        def handle_genkey(private_key_path, private_key_length = OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH)
          OAuth::Jwt.generate_rsa_private_key(path: private_key_path, length: private_key_length)
          Result::Status.new("Generated #{private_key_length} bit RSA key: #{private_key_path}")
        end

        def handle_pubkey(private_key_pem)
          Result::Text.new(OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s)
        end

        def handle_remote_certificate_chain(remote_url)
          remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
          raise "No certificate found for #{remote_url}" unless remote_chain&.first
          Result::Text.new(remote_chain.map(&:to_pem).join("\n"))
        end

        def handle_remote_certificate_only(remote_url)
          remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
          raise "No certificate found for #{remote_url}" unless remote_chain&.first
          Result::Text.new(remote_chain.first.to_pem)
        end

        def handle_remote_certificate_name(remote_url)
          remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
          raise "No certificate found for #{remote_url}" unless remote_chain&.first
          Result::Text.new(remote_chain.first.subject.to_a.find{ |name, _, _| name == 'CN'}[1])
        end

        def handle_echo(value)
          Result.auto(value)
        end

        def handle_download(file_url, file_dest = nil)
          file_url = file_url.chomp
          file_dest = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), file_url.gsub(%r{.*/}, '')) if file_dest.nil?
          Log.log.info("Downloading: #{file_url}")
          Rest.new(base_url: file_url).call(operation: 'GET', save_to_file: file_dest)
          Result::Status.new("Saved to: #{file_dest}")
        end

        # preset — all sub-actions delegate to execute_preset (which consumes the sub-command itself)
        def handle_preset
          execute_preset
        end

        def handle_tokens_flush
          require 'aspera/api/node'
          Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
        end

        def handle_tokens_list
          require 'aspera/api/node'
          Result::ObjectList.new(OAuth::Factory.instance.persisted_tokens)
        end

        def handle_tokens_show(token_id)
          require 'aspera/api/node'
          data = OAuth::Factory.instance.get_token_info(token_id)
          raise Cli::Error, 'Unknown identifier' if data.nil?
          Result::SingleObject.new(data)
        end

        def handle_plugins_list
          result = []
          Plugins::Factory.instance.plugin_list.each do |name|
            plugin_class = Plugins::Factory.instance.plugin_class(name)
            result.push({
              plugin: name,
              detect: TerminalFormatter.tick(plugin_class.respond_to?(:detect)),
              wizard: TerminalFormatter.tick(plugin_class.method_defined?(:wizard)),
              path:   Plugins::Factory.instance.plugin_source(name)
            })
          end
          Result::ObjectList.new(result, fields: %w[plugin detect wizard path])
        end

        def handle_plugins_create(plugin_name, destination_folder = nil)
          plugin_name = plugin_name.downcase
          destination_folder ||= File.join(context.main_folder, ASPERA_PLUGINS_FOLDERNAME)
          plugin_file = File.join(destination_folder, "#{plugin_name}.rb")
          content = <<~END_OF_PLUGIN_CODE
            require 'aspera/cli/plugins/base'
            module Aspera
              module Cli
                module Plugins
                  class #{plugin_name.snake_to_capital} < Base
                    command :example, description: 'example command', handler: :handle_example
                    def handle_example
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

        def handle_detect
          options.ask_missing_mandatory = true
          apps = @wizard.identify_plugins_for_url.freeze
          Result::ObjectList.new(apps)
        end

        def handle_wizard
          options.ask_missing_mandatory = true
          apps = @wizard.identify_plugins_for_url.freeze
          @wizard.find(apps)
        end

        def handle_coffee
          Result::Image.new(COFFEE_IMAGE_URL)
        end

        def handle_image(image_uri)
          Result::Image.new(image_uri)
        end

        def handle_ascp
          execute_action_ascp
        end

        def handle_agents
          execute_action_agents
        end

        def handle_sync_spec
          SyncActions.declare_options(options)
          builder = Schema::Documentation.new(TerminalFormatter, Sync::Operations::CONF_SCHEMA, include_option: true).build
          Result::ObjectList.new(builder.rows, fields: builder.columns)
        end

        def handle_sync_admin
          SyncActions.declare_options(options)
          execute_sync_admin
        end

        def handle_sync_translate(async_arguments)
          Result::SingleObject.new(Sync::Operations.args_to_conf(async_arguments))
        end

        def handle_transferd
          execute_action_transferd
        end

        def handle_gem_path
          Result::Text.new(self.class.gem_src_root)
        end

        def handle_gem_version
          Result::Text.new(Cli::VERSION)
        end

        def handle_gem_name
          Result::Text.new(Info::GEM_NAME)
        end

        def handle_folder
          Result::Text.new(context.main_folder)
        end

        def handle_file
          Result::Text.new(context.presets.config_file)
        end

        def handle_email_test
          context.mailer.send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
          Result::Nothing.new
        end

        def handle_smtp_settings
          Result::SingleObject.new(context.mailer.email_settings)
        end

        def handle_proxy_check(server_url)
          options.get_option(:fpac, mandatory: true)
          Result::ValueList.new(@pac_exec.get_proxies(server_url), name: 'proxy')
        end

        def handle_check_update
          Result::SingleObject.new(check_gem_version)
        end

        def handle_initdemo
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

        def handle_vault
          execute_vault
        end

        def handle_test_throw(exception_class_name, exception_text)
          type = Object.const_get(exception_class_name)
          Aspera.assert(type <= Exception){"#{type} is not an exception: #{type.class}"}
          raise type, exception_text
        end

        def handle_test_web
          # placeholder for web test
        end

        def handle_platform
          Result::Text.new(Environment.instance.architecture)
        end

        def handle_completion_bash(words = nil)
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
        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
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
          :DEFAULT_CHECK_NEW_VERSION_DAYS,
          :COFFEE_IMAGE_URL
      end
    end
  end
end
