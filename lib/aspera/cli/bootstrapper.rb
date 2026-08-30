# frozen_string_literal: true

require 'aspera/cli/plugins/factory'
require 'aspera/cli/extended_value'
require 'aspera/cli/special_values'
require 'aspera/cli/info'
require 'aspera/cli/transfer_progress'
require 'aspera/cli/preset_manager'
require 'aspera/cli/http'
require 'aspera/ascp/installation'
require 'aspera/products/transferd'
require 'aspera/transfer/parameters'
require 'aspera/proxy_auto_config'
require 'aspera/environment'
require 'aspera/persistency_folder'
require 'aspera/rest'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/oauth'
require 'aspera/ssl'
require 'aspera/schema/registry'

module Aspera
  module Cli
    # Performs one-time bootstrap of all shared services into Context.
    # Called by Runner before instantiating Plugins::Config, so that Config
    # acts only as a CLI plugin (option declaration + command handlers).
    #
    # Responsibilities:
    #   - resolve context.main_folder (option :home)
    #   - populate context.persistency, context.presets, context.http_config, context.progress_bar
    #   - register plugin lookup folders
    #   - register @preset / @vault extended-value handlers
    #   - configure global singletons: RestParameters, OAuth::Factory, SSL, Transfer::Parameters,
    #     RestErrorAnalyzer
    #   - set up the PAC proxy executor (option :fpac)
    class Bootstrapper
      # Folder name inside $HOME for all Aspera tool data (~/.aspera)
      ASPERA_HOME_FOLDER_NAME  = '.aspera'
      # Default name for the YAML config file
      DEFAULT_CONFIG_FILENAME  = 'config.yaml'
      # Sub-folder for user-installed plugins
      ASPERA_PLUGINS_FOLDERNAME = 'plugins'
      # Sub-folder for persistency data
      PERSISTENCY_FOLDER       = 'persist_store'
      # Sub-folder for file lists used by transfers
      FILE_LIST_FOLDER_NAME    = 'filelists'
      # Log file for REST call exceptions
      REST_EXCEPTIONS_LOG_FILENAME = 'rest_exceptions.log'
      # Extended-value prefix that resolves a named preset
      EXTEND_PRESET = :preset
      # Extended-value prefix that resolves a vault secret
      EXTEND_VAULT  = :vault
      # Default preset name for the global config section
      CONF_GLOBAL_SYM = :config

      private_constant :ASPERA_HOME_FOLDER_NAME,
        :DEFAULT_CONFIG_FILENAME,
        :ASPERA_PLUGINS_FOLDERNAME,
        :PERSISTENCY_FOLDER,
        :FILE_LIST_FOLDER_NAME,
        :REST_EXCEPTIONS_LOG_FILENAME,
        :EXTEND_PRESET,
        :EXTEND_VAULT,
        :CONF_GLOBAL_SYM

      # @param context [Context] the shared context to populate
      def initialize(context)
        Aspera.assert_type(context, Context){'context'}
        @context = context
        @pac_exec = nil
      end

      # Run the full bootstrap sequence.
      # Must be called after context.options and context.formatter are set.
      # On return, context.persistency, context.presets, context.http_config and
      # context.progress_bar are populated and all global singletons are configured.
      #
      # @param gem_plugins_folder [String]  folder of built-in plugins (from Plugins::Config)
      # @param vault_value_cb     [Proc]    block(name) → secret value (from VaultManager)
      def run(gem_plugins_folder:, vault_value_cb:)
        setup_main_folder
        setup_persistency_and_plugin_folders(gem_plugins_folder)
        setup_config_file
        setup_extended_value_handlers(vault_value_cb)
        setup_progress_bar
        setup_pac_executor
        setup_rest_and_transfer_runtime
      end

      # Public accessor used as option handler for :config_file
      attr_accessor :config_file_option

      private

      # Declare + parse :home option → context.main_folder
      def setup_main_folder
        @context.options.declare(
          :home, 'Home folder for tool',
          handler: {o: @context, m: :main_folder},
          default: default_app_main_folder(app_name: Info::CMD_NAME)
        )
        @context.options.parse_options!
        Log.log.debug{"#{Info::CMD_NAME} folder: #{@context.main_folder}"}
      end

      # context.persistency + plugin lookup folders
      def setup_persistency_and_plugin_folders(gem_plugins_folder)
        @context.persistency = PersistencyFolder.new(File.join(@context.main_folder, PERSISTENCY_FOLDER))
        Plugins::Factory.instance.add_lookup_folder(gem_plugins_folder)
        Plugins::Factory.instance.add_lookup_folder(File.join(@context.main_folder, ASPERA_PLUGINS_FOLDERNAME))
      end

      # Declare + parse :config_file option → context.presets + context.http_config
      def setup_config_file
        @context.options.declare(
          :config_file, 'Path to YAML file with preset configuration',
          handler: {o: self, m: :config_file_option},
          default: File.join(@context.main_folder, DEFAULT_CONFIG_FILENAME)
        )
        @context.options.parse_options!
        @context.presets = PresetManager.new(config_file: @config_file_option)
        @context.http_config = Http.new
      end

      # Register @preset and @vault extended-value handlers + global config default preset
      def setup_extended_value_handlers(vault_value_cb)
        @context.options.declare(:secret, 'Secret for access keys')
        @context.options.declare(:vault, allowed: Hash, schema: Schema::Registry::VAULT_OPTIONS)
        @context.options.declare(:vault_password, 'Vault password')
        # Register @preset and @vault handlers BEFORE parse_options! so that
        # values like --secret=@preset:name are correctly evaluated at parse time.
        ExtendedValue.instance.on(EXTEND_PRESET){ |v| @context.presets.by_name(v)}
        ExtendedValue.instance.on(EXTEND_VAULT, &vault_value_cb)
        @context.options.parse_options!
        # Load global config default preset (equivalent of add_plugin_default_preset(:config))
        default_config_name = @context.presets.plugin_default_name(CONF_GLOBAL_SYM)
        unless default_config_name.nil?
          Log.log.debug{"add_plugin_default_preset:#{CONF_GLOBAL_SYM}:#{default_config_name}"}
          @context.options.add_option_preset(@context.presets.by_name(default_config_name), 'default_plugin', override: false)
        end
      end

      # Declare + parse :progress_bar → context.progress_bar
      def setup_progress_bar
        @context.options.declare(:progress_bar, 'Display progress bar', allowed: Allowed::TYPES_BOOLEAN, default: Environment.terminal?)
        @context.options.parse_options!
        @context.progress_bar = TransferProgress.new if @context.options.get_option(:progress_bar)
      end

      # Declare + parse :fpac / :proxy_credentials → sets up PAC executor
      def setup_pac_executor
        @context.options.declare(:fpac, 'Proxy auto configuration script')
        @context.options.declare(:proxy_credentials, 'HTTP proxy credentials for fpac: user, password', allowed: [Array, NilClass])
        @context.options.parse_options!
        pac_script = @context.options.get_option(:fpac)
        return unless pac_script

        @context.pac_executor = ProxyAutoConfig.new(pac_script).register_uri_generic
        proxy_user_pass = @context.options.get_option(:proxy_credentials)
        if proxy_user_pass
          Aspera.assert(proxy_user_pass.length.eql?(2), type: Cli::BadArgument){"proxy_credentials shall have two elements (#{proxy_user_pass.length})"}
          @context.pac_executor.proxy_user = proxy_user_pass[0]
          @context.pac_executor.proxy_pass = proxy_user_pass[1]
        end
      end

      # Configure global singletons: RestParameters, SSL, Transfer, RestErrorAnalyzer.
      # OAuth persist_mgr is NOT set here: it depends on :cache_tokens which is parsed later
      # by Config#initialize. Runner sets it after Config.new.
      def setup_rest_and_transfer_runtime
        RestParameters.instance.user_agent    = Info::CMD_NAME
        RestParameters.instance.progress_bar  = @context.progress_bar
        RestParameters.instance.session_cb    = ->(http_session){@context.http_config.update_session(http_session)}
        RestParameters.instance.spinner_cb    = ->(title = nil, action: :spin){@context.formatter.long_operation(title, action: action)}
        OAuth::Web.additional_info = "#{Info::CMD_NAME} v#{Cli::VERSION}"
        Transfer::Parameters.file_list_folder = File.join(@context.main_folder, FILE_LIST_FOLDER_NAME)
        RestErrorAnalyzer.instance.log_file   = File.join(@context.main_folder, REST_EXCEPTIONS_LOG_FILENAME)
        RestErrorsAspera.register_handlers
      end

      # @return [String] ~/.aspera
      def module_family_folder
        user_home_folder = Dir.home
        Aspera.assert(Dir.exist?(user_home_folder), type: Cli::Error){"Home folder does not exist: #{user_home_folder}. Check your user environment."}
        File.join(user_home_folder, ASPERA_HOME_FOLDER_NAME)
      end

      # @return [String] ~/.aspera/<app_name>
      def default_app_main_folder(app_name:)
        Aspera.assert_type(app_name, String)
        Aspera.assert(!app_name.empty?, 'app_name must not be empty')
        File.join(module_family_folder, app_name)
      end
    end
  end
end
