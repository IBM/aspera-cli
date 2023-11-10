# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/extended_value'
require 'aspera/cli/version'
require 'aspera/cli/formatter'
require 'aspera/cli/info'
require 'aspera/cli/transfer_progress'
require 'aspera/fasp/installation'
require 'aspera/fasp/parameters'
require 'aspera/fasp/transfer_spec'
require 'aspera/fasp/error_info'
require 'aspera/proxy_auto_config'
require 'aspera/open_application'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/keychain/encrypted_hash'
require 'aspera/keychain/macos_security'
require 'aspera/persistency_folder'
require 'aspera/aoc'
require 'aspera/rest'
require 'xmlsimple'
require 'base64'
require 'open3'
require 'date'
require 'erb'

module Aspera
  module Cli
    module Plugins
      # manage the CLI config file
      class Config < Aspera::Cli::Plugin
        # folder in $HOME for application files (config, cache)
        ASPERA_HOME_FOLDER_NAME = '.aspera'
        # default config file
        DEFAULT_CONFIG_FILENAME = 'config.yaml'
        # reserved preset names
        CONF_PRESET_CONFIG = 'config'
        CONF_PRESET_VERSION = 'version'
        CONF_PRESET_DEFAULT = 'default'
        CONF_PRESET_GLOBAL = 'global_common_defaults'
        GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
        CONF_PLUGIN_SYM = :config # Plugins::Config.name.split('::').last.downcase.to_sym
        CONF_GLOBAL_SYM = :config
        # default redirect for AoC web auth
        DEFAULT_REDIRECT = 'http://localhost:12345'
        # folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME = 'plugins'
        PERSISTENCY_FOLDER = 'persist_store'
        RUBY_FILE_EXT = '.rb'
        ASPERA = 'aspera'
        AOC_COMMAND = 'aoc'
        SERVER_COMMAND = 'server'
        APP_NAME_SDK = 'sdk'
        CONNECT_WEB_URL = 'https://d3gcli72yxqn2z.cloudfront.net/connect'
        CONNECT_VERSIONS = 'connectversions.js'
        TRANSFER_SDK_ARCHIVE_URL = 'https://ibm.biz/aspera_transfer_sdk'
        DEMO = 'demo'
        DEMO_SERVER_PRESET = 'demoserver'
        AOC_PATH_API_CLIENTS = 'admin/api-clients'
        EMAIL_TEST_TEMPLATE = <<~END_OF_TEMPLATE
          From: <%=from_name%> <<%=from_email%>>
          To: <<%=to%>>
          Subject: #{GEM_NAME} email test

          This email was sent to test #{PROGRAM_NAME}.
        END_OF_TEMPLATE
        # special extended values
        EXTV_PRESET = :preset
        EXTV_VAULT = :vault
        PRESET_DIG_SEPARATOR = '.'
        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
        DEFAULT_PRIV_KEY_FILENAME = 'aspera_aoc_key' # pragma: allowlist secret
        DEFAULT_PRIVKEY_LENGTH = 4096
        COFFEE_IMAGE = 'https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg'
        WIZARD_RESULT_KEYS = %i[preset_value test_args].freeze
        GEM_CHECK_DATE_FMT = '%Y/%m/%d'
        # for testing only
        SELF_SIGNED_CERT = OpenSSL::SSL.const_get(:enon_yfirev.to_s.upcase.reverse) # cspell: disable-line
        private_constant :DEFAULT_CONFIG_FILENAME,
          :CONF_PRESET_CONFIG,
          :CONF_PRESET_VERSION,
          :CONF_PRESET_DEFAULT,
          :CONF_PRESET_GLOBAL,
          :DEFAULT_REDIRECT,
          :ASPERA_PLUGINS_FOLDERNAME,
          :RUBY_FILE_EXT,
          :ASPERA,
          :AOC_COMMAND,
          :DEMO,
          :TRANSFER_SDK_ARCHIVE_URL,
          :AOC_PATH_API_CLIENTS,
          :DEMO_SERVER_PRESET,
          :EMAIL_TEST_TEMPLATE,
          :EXTV_PRESET,
          :EXTV_VAULT,
          :DEFAULT_CHECK_NEW_VERSION_DAYS,
          :DEFAULT_PRIV_KEY_FILENAME,
          :SERVER_COMMAND,
          :PRESET_DIG_SEPARATOR,
          :COFFEE_IMAGE,
          :WIZARD_RESULT_KEYS,
          :SELF_SIGNED_CERT,
          :PERSISTENCY_FOLDER

        class << self
          def generate_rsa_private_key(path:, length: DEFAULT_PRIVKEY_LENGTH)
            require 'openssl'
            priv_key = OpenSSL::PKey::RSA.new(length)
            File.write(path, priv_key.to_s)
            File.write("#{path}.pub", priv_key.public_key.to_s)
            Environment.restrict_file_access(path)
            Environment.restrict_file_access("#{path}.pub")
            nil
          end

          # folder containing plugins in the gem's main folder
          def gem_plugins_folder
            File.dirname(File.expand_path(__FILE__))
          end

          # name of englobing module
          # @return "Aspera::Cli::Plugins"
          def module_full_name
            return Module.nesting[2].to_s
          end

          # @return main folder where code is, i.e. .../lib
          # go up as many times as englobing modules (not counting class, as it is a file)
          def gem_src_root
            File.expand_path(module_full_name.gsub('::', '/').gsub(%r{[^/]+}, '..'), gem_plugins_folder)
          end

          # instantiate a plugin
          # plugins must be Capitalized
          def plugin_class(plugin_name_sym)
            # Module.nesting[2] is Aspera::Cli::Plugins
            return Object.const_get("#{module_full_name}::#{plugin_name_sym.to_s.capitalize}")
          end

          # deep clone hash so that it does not get modified in case of display and secret hide
          def protect_presets(val)
            return JSON.parse(JSON.generate(val))
          end

          # return product family folder (~/.aspera)
          def module_family_folder
            user_home_folder = Dir.home
            raise CliError, "Home folder does not exist: #{user_home_folder}. Check your user environment." unless Dir.exist?(user_home_folder)
            return File.join(user_home_folder, ASPERA_HOME_FOLDER_NAME)
          end

          # return product config folder (~/.aspera/<name>)
          def default_app_main_folder(app_name:)
            raise 'app_name must be a non-empty String' unless app_name.is_a?(String) && !app_name.empty?
            return File.join(module_family_folder, app_name)
          end
        end # self

        def initialize(env, params)
          raise 'Internal Error: env and params must be Hash' unless env.is_a?(Hash) && params.is_a?(Hash)
          raise 'Internal Error: missing param' unless %i[gem help name version].eql?(params.keys.sort)
          # we need to defer parsing of options until we have the config file, so we can use @extend with @preset
          super(env)
          @info = params
          @plugins = {}
          @plugin_lookup_folders = []
          @use_plugin_defaults = true
          @config_presets = nil
          @config_checksum_on_disk = nil
          @connect_versions = nil
          @vault = nil
          @pac_exec = nil
          @sdk_default_location = false
          @option_insecure = false
          @option_ignore_cert_host_port = []
          @option_http_options = {}
          @ssl_warned_urls = []
          @option_rest_debug = false
          @option_cache_tokens = true
          @proxy_credentials = nil
          @main_folder = nil
          @option_config_file = nil
          @certificate_store = nil
          @certificate_paths = nil
        @progressbar = nil
          # option to set main folder
          options.declare(
            :home, 'Home folder for tool',
            handler: {o: self, m: :main_folder},
            types: String,
            default: self.class.default_app_main_folder(app_name: @info[:name]))
          options.parse_options!
          Log.log.debug{"#{@info[:name]} folder: #{@main_folder}"}
          # data persistency manager
          env[:persistency] = PersistencyFolder.new(File.join(@main_folder, PERSISTENCY_FOLDER))
          # set folders for plugin lookup
          add_plugin_lookup_folder(self.class.gem_plugins_folder)
          add_plugin_lookup_folder(File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME))
          # option to set config file
          options.declare(
            :config_file, 'Path to YAML file with preset configuration',
            handler: {o: self, m: :option_config_file},
            default: File.join(@main_folder, DEFAULT_CONFIG_FILENAME))
          options.parse_options!
          # read config file (set @config_presets)
          read_config_file
          # add preset handler (needed for smtp)
          ExtendedValue.instance.set_handler(EXTV_PRESET, lambda{|v|preset_by_name(v)})
          ExtendedValue.instance.set_handler(EXTV_VAULT, lambda{|v|vault_value(v)})
          # load defaults before it can be overridden
          add_plugin_default_preset(CONF_GLOBAL_SYM)
          options.parse_options!
          # declare generic plugin options only after handlers are declared
          Plugin.declare_generic_options(options)
          options.declare(:no_default, 'Do not load default configuration for plugin', values: :none, short: 'N') { @use_plugin_defaults = false }
          options.declare(:override, 'Wizard: override existing value', values: :bool, default: :no)
          options.declare(:use_generic_client, 'Wizard: AoC: use global or org specific jwt client id', values: :bool, default: true)
          options.declare(:default, 'Wizard: set as default configuration for specified plugin (also: update)', values: :bool, default: true)
          options.declare(:test_mode, 'Wizard: skip private key check step', values: :bool, default: false)
          options.declare(:pkeypath, 'Wizard: path to private key for JWT')
          options.declare(:preset, 'Load the named option preset from current config file', short: 'P', handler: {o: self, m: :option_preset})
          options.declare(:ascp_path, 'Path to ascp', handler: {o: Fasp::Installation.instance, m: :ascp_path})
          options.declare(:use_product, 'Use ascp from specified product', handler: {o: self, m: :option_use_product})
          options.declare(:smtp, 'SMTP configuration', types: Hash)
          options.declare(:fpac, 'Proxy auto configuration script')
          options.declare(:proxy_credentials, 'HTTP proxy credentials (user and password)', types: Array)
          options.declare(:secret, 'Secret for access keys')
          options.declare(:vault, 'Vault for secrets', types: Hash)
          options.declare(:vault_password, 'Vault password')
          options.declare(:sdk_url, 'URL to get SDK', default: TRANSFER_SDK_ARCHIVE_URL)
          options.declare(:sdk_folder, 'SDK folder path', handler: {o: Fasp::Installation.instance, m: :sdk_folder})
          options.declare(:notif_to, 'Email recipient for notification of transfers')
          options.declare(:notif_template, 'Email ERB template for notification of transfers')
          options.declare(:version_check_days, 'Period in days to check new version (zero to disable)', coerce: Integer, default: DEFAULT_CHECK_NEW_VERSION_DAYS)
          options.declare(:plugin_folder, 'Folder where to find additional plugins', handler: {o: self, m: :option_plugin_folder})
          options.declare(:insecure, 'Do not validate any HTTPS certificate', values: :bool, handler: {o: self, m: :option_insecure}, default: :no)
          options.declare(:ignore_certificate, 'List of HTTPS url where to no validate certificate', types: Array, handler: {o: self, m: :option_ignore_cert_host_port})
          options.declare(:cert_stores, 'List of folder with trusted certificates', types: [Array, String], handler: {o: self, m: :trusted_cert_locations})
          options.declare(:http_options, 'Options for HTTP/S socket', types: Hash, handler: {o: self, m: :option_http_options}, default: {})
          options.declare(:rest_debug, 'More debug for HTTP calls (REST)', values: :none, short: 'r') { @option_rest_debug = true }
          options.declare(:cache_tokens, 'Save and reuse Oauth tokens', values: :bool, handler: {o: self, m: :option_cache_tokens})
          options.declare(:progressbar, 'Display progress bar', values: :bool, default: Environment.terminal?)
          options.parse_options!
          @progressbar = TransferProgress.new if options.get_option(:progressbar)
          # Check SDK folder is set or not, for compatibility, we check in two places
          sdk_folder = Fasp::Installation.instance.sdk_folder rescue nil
          if sdk_folder.nil?
            @sdk_default_location = true
            Log.log.debug('SDK folder is not set, checking default')
            # new location
            sdk_folder = self.class.default_app_main_folder(app_name: APP_NAME_SDK)
            Log.log.debug{"checking: #{sdk_folder}"}
            if !Dir.exist?(sdk_folder)
              Log.log.debug{"not exists: #{sdk_folder}"}
              # former location
              former_sdk_folder = File.join(self.class.default_app_main_folder(app_name: @info[:name]), APP_NAME_SDK)
              Log.log.debug{"checking: #{former_sdk_folder}"}
              sdk_folder = former_sdk_folder if Dir.exist?(former_sdk_folder)
            end
            Log.log.debug{"using: #{sdk_folder}"}
            Fasp::Installation.instance.sdk_folder = sdk_folder
          end
          pac_script = options.get_option(:fpac)
          # create PAC executor
          @pac_exec = Aspera::ProxyAutoConfig.new(pac_script).register_uri_generic unless pac_script.nil?
          proxy_creds = options.get_option(:proxy_credentials)
          if !proxy_creds.nil?
            raise CliBadArgument, "proxy_credentials shall have two elements (#{proxy_creds.length})" unless proxy_creds.length.eql?(2)
            @proxy_credentials = {user: proxy_creds[0], pass: proxy_creds[1]}
            @pac_exec.proxy_user = @proxy_credentials[:user]
            @pac_exec.proxy_pass = @proxy_credentials[:pass]
          end
          Rest.set_parameters(user_agent: PROGRAM_NAME, session_cb: lambda{|http_session|update_http_session(http_session)})
          Oauth.persist_mgr = persistency if @option_cache_tokens
          Fasp::Parameters.file_list_folder = File.join(@main_folder, 'filelists')
          Aspera::RestErrorAnalyzer.instance.log_file = File.join(@main_folder, 'rest_exceptions.log')
          # register aspera REST call error handlers
          Aspera::RestErrorsAspera.register_handlers
        end

        attr_accessor :main_folder, :option_cache_tokens, :option_insecure, :option_http_options
        attr_reader :option_ignore_cert_host_port, :progressbar

        def trusted_cert_locations=(path_list)
          path_list = [path_list] unless path_list.is_a?(Array)
          if @certificate_store.nil?
            Log.log.debug('Creating SSL Cert store')
            @certificate_store = OpenSSL::X509::Store.new
            @certificate_store.set_default_paths
            @certificate_paths = []
          end

          path_list.each do |path|
            raise 'Expecting a String for cert location' unless path.is_a?(String)
            Log.log.debug("Adding cert location: #{path}")
            if path.eql?(ExtendedValue::DEF)
              path = OpenSSL::X509::DEFAULT_CERT_DIR
              @certificate_store.add_path(path)
              @certificate_paths.push(path)
              path = OpenSSL::X509::DEFAULT_CERT_FILE
              @certificate_store.add_file(path)
            elsif File.file?(path)
              @certificate_store.add_file(path)
            elsif File.directory?(path)
              @certificate_store.add_path(path)
            else
              raise "No such file or folder: #{path}"
            end
            @certificate_paths.push(path)
          end
        end

        def trusted_cert_locations(files_only: false)
          locations = if @certificate_paths.nil?
            [OpenSSL::X509::DEFAULT_CERT_DIR, OpenSSL::X509::DEFAULT_CERT_FILE]
          else
            @certificate_paths
          end
          locations = locations.select{|f|File.file?(f)} if files_only
          return locations
        end

        def option_ignore_cert_host_port=(url_list)
          url_list.each do |url|
            uri = URI.parse(url)
            @option_ignore_cert_host_port.push([uri.host, uri.port].freeze)
          end
        end

        def ignore_cert?(address, port)
          endpoint = [address, port].freeze
          Log.log.debug{"ignore cert? #{endpoint}"}
          return false unless @option_insecure || @option_ignore_cert_host_port.any?(endpoint)
          base_url = "https://#{address}:#{port}"
          if !@ssl_warned_urls.include?(base_url)
            formatter.display_message(
              :error,
              "#{Formatter::WARNING_FLASH} Ignoring certificate for: #{base_url}. Do not deactivate certificate verification in production.")
            @ssl_warned_urls.push(base_url)
          end
          return true
        end

        # called every time a new REST HTTP session is opened to set user-provided options
        # @param http_session [Net::HTTP] the newly created HTTP/S session object
        def update_http_session(http_session)
          http_session.set_debug_output($stdout) if @option_rest_debug
          # Rest.io_http_session(http_session).debug_output = Log.log
          http_session.verify_mode = SELF_SIGNED_CERT if http_session.use_ssl? && ignore_cert?(http_session.address, http_session.port)
          http_session.cert_store = @certificate_store if @certificate_store
          Log.log.debug{"using cert store #{http_session.cert_store} (#{@certificate_store})"} unless http_session.cert_store.nil?
          if @proxy_credentials
            http_session.proxy_user = @proxy_credentials[:user]
            http_session.proxy_pass = @proxy_credentials[:pass]
          end
          @option_http_options.each do |k, v|
            method = "#{k}=".to_sym
            # check if accessor is a method of Net::HTTP
            # continue_timeout= read_timeout= write_timeout=
            if http_session.respond_to?(method)
              http_session.send(method, v)
            else
              Log.log.error{"no such HTTP session attribute: #{k}"}
            end
          end
        end

        def check_gem_version
          latest_version =
            begin
              Rest.new(base_url: 'https://rubygems.org/api/v1').read("versions/#{@info[:gem]}/latest.json")[:data]['version']
            rescue StandardError
              Log.log.warn('Could not retrieve latest gem version on rubygems.')
              '0'
            end
          if Gem::Version.new(Environment.ruby_version) < Gem::Version.new(RUBY_FUTURE_MINIMUM_VERSION)
            Log.log.warn do
              "Note that a future version will require Ruby version #{RUBY_FUTURE_MINIMUM_VERSION} at minimum, "\
                "you are using #{Environment.ruby_version}"
            end
          end
          return {
            name:        @info[:gem],
            current:     Aspera::Cli::VERSION,
            latest:      latest_version,
            need_update: Gem::Version.new(Aspera::Cli::VERSION) < Gem::Version.new(latest_version)
          }
        end

        def periodic_check_newer_gem_version
          # get verification period
          delay_days = options.get_option(:version_check_days, mandatory: true)
          # check only if not zero day
          return if delay_days.eql?(0)
          # get last date from persistency
          last_check_array = []
          check_date_persist = PersistencyActionOnce.new(
            manager: persistency,
            data:    last_check_array,
            id:      'version_last_check')
          # get persisted date or nil
          current_date = Date.today
          last_check_days = (current_date - Date.strptime(last_check_array.first, GEM_CHECK_DATE_FMT)) rescue nil
          Log.log.debug{"gem check new version: #{delay_days}, #{last_check_days}, #{current_date}, #{last_check_array}"}
          return if !last_check_days.nil? && last_check_days < delay_days
          # generate timestamp
          last_check_array[0] = current_date.strftime(GEM_CHECK_DATE_FMT)
          check_date_persist.save
          # compare this version and the one on internet
          check_data = check_gem_version
          Log.log.warn do
            "A new version is available: #{check_data[:latest]}. You have #{check_data[:current]}. Upgrade with: gem update #{check_data[:name]}"
          end if check_data[:need_update]
        end

        # retrieve structure from cloud (CDN) with all versions available
        def connect_versions
          if @connect_versions.nil?
            api_connect_cdn = Rest.new({base_url: CONNECT_WEB_URL})
            javascript = api_connect_cdn.call({operation: 'GET', subpath: CONNECT_VERSIONS})
            # get result on one line
            connect_versions_javascript = javascript[:http].body.gsub(/\r?\n\s*/, '')
            Log.log.debug{"javascript=[\n#{connect_versions_javascript}\n]"}
            # get javascript object only
            found = connect_versions_javascript.match(/^.*? = (.*);/)
            raise CliError, 'Problem when getting connect versions from internet' if found.nil?
            all_data = JSON.parse(found[1])
            @connect_versions = all_data['entries']
          end
          return @connect_versions
        end

        # loads default parameters of plugin if no -P parameter
        # and if there is a section defined for the plugin in the "default" section
        # try to find: conf[conf["default"][plugin_str]]
        # @param plugin_name_sym : symbol for plugin name
        def add_plugin_default_preset(plugin_name_sym)
          default_config_name = get_plugin_default_config_name(plugin_name_sym)
          Log.log.debug{"add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}"}
          options.add_option_preset(preset_by_name(default_config_name), op: :unshift) unless default_config_name.nil?
          return nil
        end

        # get the default global preset, or init a new one
        def global_default_preset
          global_default_preset_name = get_plugin_default_config_name(CONF_GLOBAL_SYM)
          if global_default_preset_name.nil?
            global_default_preset_name = CONF_PRESET_GLOBAL.to_s
            set_preset_key(CONF_PRESET_DEFAULT, CONF_GLOBAL_SYM, global_default_preset_name)
          end
          return global_default_preset_name
        end

        def set_preset_key(preset, param_name, param_value)
          raise "Parameter name must be a String or Symbol, not #{param_name.class}" unless [String, Symbol].include?(param_name.class)
          param_name = param_name.to_s
          selected_preset = @config_presets[preset]
          if selected_preset.nil?
            Log.log.debug{"No such preset name: #{preset}, initializing"}
            selected_preset = @config_presets[preset] = {}
          end
          raise "expecting Hash for #{preset}.#{param_name}" unless selected_preset.is_a?(Hash)
          if selected_preset.key?(param_name)
            if selected_preset[param_name].eql?(param_value)
              Log.log.warn{"keeping same value for #{preset}: #{param_name}: #{param_value}"}
              return
            end
            Log.log.warn{"overwriting value: #{selected_preset[param_name]}"}
          end
          selected_preset[param_name] = param_value
          formatter.display_status("Updated: #{preset}: #{param_name} <- #{param_value}")
          nil
        end

        # set parameter and value in global config
        # creates one if none already created
        # @return preset name that contains global default
        def set_global_default(key, value)
          set_preset_key(global_default_preset, key, value)
        end

        # $HOME/.aspera/`program_name`
        attr_reader :gem_url, :plugins
        attr_accessor :option_config_file

        # @return the hash from name (also expands possible includes)
        # @param config_name name of the preset in config file
        # @param include_path used to detect and avoid include loops
        def preset_by_name(config_name, include_path=[])
          raise CliError, 'loop in include' if include_path.include?(config_name)
          include_path = include_path.clone # avoid messing up if there are multiple branches
          current = @config_presets
          config_name.split(PRESET_DIG_SEPARATOR).each do |name|
            raise CliError, "Expecting Hash for sub key: #{include_path} (#{current.class})" unless current.is_a?(Hash)
            include_path.push(name)
            current = current[name]
            raise CliError, "No such config preset: #{include_path}" if current.nil?
          end
          current = self.class.protect_presets(current) unless current.is_a?(String)
          return ExtendedValue.instance.evaluate(current)
        end

        def option_use_product=(value)
          Fasp::Installation.instance.use_ascp_from_product(value)
        end

        def option_use_product
          'write-only option, see value of ascp_path'
        end

        def option_plugin_folder=(value)
          case value
          when String then add_plugin_lookup_folder(value)
          when Array then value.each{|f|add_plugin_lookup_folder(f)}
          else raise "folder shall be Array or String, not #{value.class}"
          end
        end

        def option_plugin_folder
          return @plugin_lookup_folders
        end

        def option_preset; 'write-only option'; end

        def option_preset=(value)
          case value
          when String
            options.add_option_preset(preset_by_name(value))
          when Hash
            options.add_option_preset(value)
          else
            raise 'Preset definition must be a String for name, or Hash for value'
          end
        end

        def config_checksum
          JSON.generate(@config_presets).hash
        end

        # read config file and validate format
        def read_config_file
          Log.log.debug{"config file is: #{@option_config_file}".red}
          # files search for configuration, by default the one given by user
          search_files = [@option_config_file]
          # find first existing file (or nil)
          conf_file_to_load = search_files.find{|f| File.exist?(f)}
          # if no file found, create default config
          if conf_file_to_load.nil?
            Log.log.warn{"No config file found. New configuration file: #{@option_config_file}"}
            @config_presets = {CONF_PRESET_CONFIG => {CONF_PRESET_VERSION => 'new file'}}
            # @config_checksum_on_disk is nil
          else
            Log.log.debug{"loading #{@option_config_file}"}
            @config_presets = YAML.load_file(conf_file_to_load)
            @config_checksum_on_disk = config_checksum
          end
          files_to_copy = []
          Log.dump('Available_presets', @config_presets)
          raise 'Expecting YAML Hash' unless @config_presets.is_a?(Hash)
          # check there is at least the config section
          raise "Cannot find key: #{CONF_PRESET_CONFIG}" unless @config_presets.key?(CONF_PRESET_CONFIG)
          version = @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]
          raise 'No version found in config section.' if version.nil?
          Log.log.debug{"conf version: #{version}"}
          # VVV if there are any conversion needed, those happen here.
          # fix bug in 4.4 (creating key "true" in "default" preset)
          @config_presets[CONF_PRESET_DEFAULT].delete(true) if @config_presets[CONF_PRESET_DEFAULT].is_a?(Hash)
          # ^^^ Place new compatibility code before this line
          # set version to current
          @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION] = @info[:version]
          unless files_to_copy.empty?
            Log.log.warn('Copying referenced files')
            files_to_copy.each do |file|
              FileUtils.cp(file, @main_folder)
              Log.log.warn{"#{file} -> #{@main_folder}"}
            end
          end
        rescue Psych::SyntaxError => e
          Log.log.error('YAML error in config file')
          raise e
        rescue StandardError => e
          Log.log.debug{"-> #{e.class.name} : #{e}"}
          if File.exist?(@option_config_file)
            # then there is a problem with that file.
            new_name = "#{@option_config_file}.pre#{@info[:version]}.manual_conversion_needed"
            File.rename(@option_config_file, new_name)
            Log.log.warn{"Renamed config file to #{new_name}."}
            Log.log.warn('Manual Conversion is required. Next time, a new empty file will be created.')
          end
          raise CliError, e.to_s
        end

        # find plugins in defined paths
        def add_plugins_from_lookup_folders
          @plugin_lookup_folders.each do |folder|
            next unless File.directory?(folder)
            # TODO: add gem root to load path ? and require short folder ?
            # $LOAD_PATH.push(folder) if i[:add_path]
            Dir.entries(folder).select{|file|file.end_with?(RUBY_FILE_EXT)}.each do |source|
              add_plugin_info(File.join(folder, source))
            end
          end
        end

        def add_plugin_lookup_folder(folder)
          @plugin_lookup_folders.unshift(folder)
        end

        def add_plugin_info(path)
          raise "ERROR: plugin path must end with #{RUBY_FILE_EXT}" if !path.end_with?(RUBY_FILE_EXT)
          plugin_symbol = File.basename(path, RUBY_FILE_EXT).to_sym
          req = path.gsub(/#{RUBY_FILE_EXT}$/o, '')
          if @plugins.key?(plugin_symbol)
            Log.log.warn{"skipping plugin already registered: #{plugin_symbol}"}
            return
          end
          @plugins[plugin_symbol] = {source: path, require_stanza: req}
        end

        # Find a plugin, and issue the "require"
        # @return [Hash] plugin info: { product: , url:, version: }
        def identify_plugins_for_url
          app_url = options.get_next_argument('url', mandatory: true)
          check_only = options.get_next_argument('plugin name', mandatory: false)
          check_only = check_only.to_sym unless check_only.nil?
          found_apps = []
          plugins.each do |plugin_name_sym, plugin_info|
            # no detection for internal plugin
            next if plugin_name_sym.eql?(CONF_PLUGIN_SYM)
            next if check_only && !check_only.eql?(plugin_name_sym)
            # load plugin class
            require plugin_info[:require_stanza]
            detect_plugin_class = self.class.plugin_class(plugin_name_sym)
            # requires detection method
            next unless detect_plugin_class.respond_to?(:detect)
            detection_info = nil
            begin
              detection_info = detect_plugin_class.detect(app_url)
            rescue OpenSSL::SSL::SSLError => e
              Log.log.warn(e.message)
              Log.log.warn('Use option --insecure=yes to allow unchecked certificate') if e.message.include?('cert')
            rescue StandardError => e
              Log.log.debug{"detect error: #{e}"}
              next
            end
            next if detection_info.nil?
            raise 'internal error' if detection_info.key?(:url) && !detection_info[:url].is_a?(String)
            app_name = detect_plugin_class.respond_to?(:application_name) ? detect_plugin_class.application_name : detect_plugin_class.name.split('::').last
            # if there is a redirect, then the detector can override the url.
            found_apps.push({product: plugin_name_sym, name: app_name, url: app_url, version: 'unknown'}.merge(detection_info))
          end # loop
          raise "No known application found at #{app_url}" if found_apps.empty?
          raise 'Internal error' unless found_apps.all?{|a|a.keys.all?(Symbol)}
          return found_apps
        end

        def execute_connect_action
          command = options.get_next_command(%i[list info version])
          if %i[info version].include?(command)
            connect_id = options.get_next_argument('id or title')
            one_res = connect_versions.find{|i|i['id'].eql?(connect_id) || i['title'].eql?(connect_id)}
            raise CliNoSuchId.new(:connect, connect_id) if one_res.nil?
          end
          case command
          when :list
            return {type: :object_list, data: connect_versions, fields: %w[id title version]}
          when :info # shows files used
            one_res.delete('links')
            return {type: :single_object, data: one_res}
          when :version # shows files used
            all_links = one_res['links']
            command = options.get_next_command(%i[list download open])
            if %i[download open].include?(command)
              link_title = options.get_next_argument('title or rel')
              one_link = all_links.find {|i| i['title'].eql?(link_title) || i['rel'].eql?(link_title)}
              raise 'no such value' if one_link.nil?
            end
            case command
            when :list # shows files used
              return {type: :object_list, data: all_links}
            when :download
              folder_dest = transfer.destination_folder(Fasp::TransferSpec::DIRECTION_RECEIVE)
              # folder_dest=self.options.get_next_argument('destination folder')
              api_connect_cdn = Rest.new({base_url: CONNECT_WEB_URL})
              file_url = one_link['href']
              filename = file_url.gsub(%r{.*/}, '')
              api_connect_cdn.call({operation: 'GET', subpath: file_url, save_to_file: File.join(folder_dest, filename)})
              return Main.result_status("Downloaded: #{filename}")
            when :open
              OpenApplication.instance.uri(one_link['href'])
              return Main.result_status("Opened: #{one_link['href']}")
            end
          end
        end

        def execute_action_ascp
          command = options.get_next_command(%i[connect use show products info install spec errors])
          case command
          when :connect
            return execute_connect_action
          when :use
            ascp_path = options.get_next_argument('path to ascp')
            ascp_version = Fasp::Installation.instance.get_ascp_version(ascp_path)
            formatter.display_status("ascp version: #{ascp_version}")
            set_global_default(:ascp_path, ascp_path)
            return Main.result_nothing
          when :show # shows files used
            return {type: :status, data: Fasp::Installation.instance.path(:ascp)}
          when :info # shows files used
            data = Fasp::Installation::FILES.each_with_object({}) do |v, m|
              m[v.to_s] =
                begin
                  Fasp::Installation.instance.path(v)
                rescue => e
                  e.message
                end
            end
            # read PATHs from ascp directly, and pvcl modules as well
            Open3.popen3(Fasp::Installation.instance.path(:ascp), '-DDL-') do |_stdin, _stdout, stderr, thread|
              last_line = ''
              while (line = stderr.gets)
                line.chomp!
                last_line = line
                case line
                when /^DBG Path ([^ ]+) (dir|file) +: (.*)$/
                  data[Regexp.last_match(1)] = Regexp.last_match(3)
                when /^DBG Added module group:"([^"]+)" name:"([^"]+)", version:"([^"]+)" interface:"([^"]+)"$/
                  data[Regexp.last_match(2)] = "#{Regexp.last_match(4)} #{Regexp.last_match(1)} v#{Regexp.last_match(3)}"
                when %r{^DBG License result \(/license/(\S+)\): (.+)$}
                  data[Regexp.last_match(1)] = Regexp.last_match(2)
                when /^LOG (.+) version ([0-9.]+)$/
                  data['product_name'] = Regexp.last_match(1)
                  data['product_version'] = Regexp.last_match(2)
                when /^LOG Initializing FASP version ([^,]+),/
                  data['ascp_version'] = Regexp.last_match(1)
                end
              end
              if !thread.value.exitstatus.eql?(1) && !data.key?('root')
                raise last_line
              end
            end
            # ascp's openssl directory
            ascp_file = Fasp::Installation.instance.path(:ascp)
            File.binread(ascp_file).scan(/[\x20-\x7E]{4,}/) do |match|
              if (m = match.match(/OPENSSLDIR.*"(.*)"/))
                data['openssldir'] = m[1]
              end
            end if File.file?(ascp_file)
            data['keypass'] = Fasp::Installation.instance.bypass_pass
            # log is "-" no need to display
            data.delete('log')
            # show command line transfer spec
            data['ts'] = transfer.updated_ts
            return {type: :single_object, data: data}
          when :products
            command = options.get_next_command(%i[list use])
            case command
            when :list
              return {type: :object_list, data: Fasp::Installation.instance.installed_products, fields: %w[name app_root]}
            when :use
              default_product = options.get_next_argument('product name')
              Fasp::Installation.instance.use_ascp_from_product(default_product)
              set_global_default(:ascp_path, Fasp::Installation.instance.path(:ascp))
              return Main.result_nothing
            end
          when :install
            # reset to default location, if older default was used
            Fasp::Installation.instance.sdk_folder = self.class.default_app_main_folder(app_name: APP_NAME_SDK) if @sdk_default_location
            v = Fasp::Installation.instance.install_sdk(options.get_option(:sdk_url, mandatory: true))
            return Main.result_status("Installed version #{v}")
          when :spec
            return {
              type:   :object_list,
              data:   Fasp::Parameters.man_table,
              fields: [%w[name type], Fasp::Parameters::SUPPORTED_AGENTS_SHORT.map(&:to_s), %w[description]].flatten.freeze
            }
          when :errors
            error_data = []
            Fasp::ERROR_INFO.each_pair do |code, prop|
              error_data.push(code: code, mnemonic: prop[:c], retry: prop[:r], info: prop[:a])
            end
            return {type: :object_list, data: error_data}
          end
          raise "unexpected case: #{command}"
        end

        # legacy actions available globally
        PRESET_GBL_ACTIONS = %i[list overview lookup secure].freeze
        # operations requiring that preset exists
        PRESET_EXIST_ACTIONS = %i[show delete get unset].freeze
        # require id
        PRESET_INSTANCE_ACTIONS = %i[initialize update ask set].concat(PRESET_EXIST_ACTIONS).freeze
        PRESET_ALL_ACTIONS = [PRESET_GBL_ACTIONS, PRESET_INSTANCE_ACTIONS].flatten.freeze

        def execute_preset(action: nil, name: nil)
          action = options.get_next_command(PRESET_ALL_ACTIONS) if action.nil?
          name = instance_identifier if name.nil? && PRESET_INSTANCE_ACTIONS.include?(action)
          name = global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
          # those operations require existing option
          raise "no such preset: #{name}" if PRESET_EXIST_ACTIONS.include?(action) && !@config_presets.key?(name)
          case action
          when :list
            return {type: :value_list, data: @config_presets.keys, name: 'name'}
          when :overview
            # display process modifies the value (hide secrets): we do not want to save removed secrets
            return {type: :config_over, data: self.class.protect_presets(@config_presets)}
          when :show
            return {type: :single_object, data: self.class.protect_presets(@config_presets[name])}
          when :delete
            @config_presets.delete(name)
            return Main.result_status("Deleted: #{name}")
          when :get
            param_name = options.get_next_argument('parameter name')
            value = @config_presets[name][param_name]
            raise "no such option in preset #{name} : #{param_name}" if value.nil?
            case value
            when Numeric, String then return {type: :text, data: ExtendedValue.instance.evaluate(value.to_s)}
            end
            return {type: :single_object, data: value}
          when :unset
            param_name = options.get_next_argument('parameter name')
            @config_presets[name].delete(param_name)
            return Main.result_status("Removed: #{name}: #{param_name}")
          when :set
            param_name = options.get_next_argument('parameter name')
            param_name = Manager.option_line_to_name(param_name)
            param_value = options.get_next_argument('parameter value')
            set_preset_key(name, param_name, param_value)
            return Main.result_nothing
          when :initialize
            config_value = options.get_next_argument('extended value', type: Hash)
            if @config_presets.key?(name)
              Log.log.warn{"configuration already exists: #{name}, overwriting"}
            end
            @config_presets[name] = config_value
            return Main.result_status("Modified: #{@option_config_file}")
          when :update
            #  get unprocessed options
            unprocessed_options = options.get_options_table
            Log.log.debug{"opts=#{unprocessed_options}"}
            @config_presets[name] ||= {}
            @config_presets[name].merge!(unprocessed_options)
            return Main.result_status("Updated: #{name}")
          when :ask
            options.ask_missing_mandatory = :yes
            @config_presets[name] ||= {}
            options.get_next_argument('option names', expected: :multiple).each do |option_name|
              option_value = options.get_interactive(:option, option_name)
              @config_presets[name][option_name] = option_value
            end
            return Main.result_status("Updated: #{name}")
          when :lookup
            BasicAuthPlugin.declare_options(options)
            url = options.get_option(:url, mandatory: true)
            user = options.get_option(:username, mandatory: true)
            result = lookup_preset(url: url, username: user)
            raise 'no such config found' if result.nil?
            return {type: :single_object, data: result}
          when :secure
            identifier = options.get_next_argument('config name', mandatory: false)
            preset_names = identifier.nil? ? @config_presets.keys : [identifier]
            secret_keywords = %w[password secret].freeze
            preset_names.each do |preset_name|
              preset = @config_presets[preset_name]
              next unless preset.is_a?(Hash)
              preset.each_key do |option_name|
                secret_keywords.each do |keyword|
                  next unless option_name.end_with?(keyword)
                  vault_label = preset_name
                  incr = 0
                  until vault.get(label: vault_label, exception: false).nil?
                    vault_label = "#{preset_name}#{incr}"
                    incr += 1
                  end
                  to_set = {label: vault_label, password: preset[option_name]}
                  puts "need to encode #{preset_name}.#{option_name} -> #{vault_label} -> #{to_set}"
                  # to_copy=%i[]
                  vault.set(to_set)
                  preset[option_name] = "@vault:#{vault_label}.password"
                end
              end
            end
            return Main.result_status('Secrets secured in vault: Make sure to save the vault password securely.')
          end
        end

        ACTIONS = %i[
          preset
          open
          documentation
          genkey
          remote_certificate
          gem
          plugins
          flush_tokens
          echo
          wizard
          detect
          coffee
          ascp
          email_test
          smtp_settings
          proxy_check
          folder
          file
          check_update
          initdemo
          vault
          throw].freeze

        # Main action procedure for plugin
        def execute_action
          action = options.get_next_command(ACTIONS)
          case action
          when :preset # newer syntax
            return execute_preset
          when :open
            OpenApplication.editor(@option_config_file.to_s)
            return Main.result_nothing
          when :documentation
            section = options.get_next_argument('private key file path', mandatory: false)
            section = "##{section}" unless section.nil?
            OpenApplication.instance.uri("#{@info[:help]}#{section}")
            return Main.result_nothing
          when :genkey # generate new rsa key
            private_key_path = options.get_next_argument('private key file path')
            private_key_length = options.get_next_argument('size in bits', mandatory: false, type: Integer, default: DEFAULT_PRIVKEY_LENGTH)
            self.class.generate_rsa_private_key(path: private_key_path, length: private_key_length)
            return Main.result_status("Generated #{private_key_length} bit RSA key: #{private_key_path}")
          when :remote_certificate
            remote_url = options.get_next_argument('remote URL')
            @option_insecure = true
            remote_certificate = Rest.start_http_session(remote_url).peer_cert
            remote_certificate.subject.to_a.find { |name, _, _| name == 'CN' }[1]
            formatter.display_status("CN=#{remote_certificate.subject.to_a.find { |name, _, _| name == 'CN' }[1] rescue ''}")
            return Main.result_status(remote_certificate.to_pem)
          when :echo # display the content of a value given on command line
            result = {type: :other_struct, data: options.get_next_argument('value')}
            # special for csv
            result[:type] = :object_list if result[:data].is_a?(Array) && result[:data].first.is_a?(Hash)
            result[:type] = :single_object if result[:data].is_a?(Hash)
            return result
          when :flush_tokens
            deleted_files = Oauth.flush_tokens
            return {type: :value_list, data: deleted_files, name: 'file'}
          when :plugins
            case options.get_next_command(%i[list create])
            when :list
              result = []
              @plugins.each do |name, info|
                require info[:require_stanza]
                plugin_class = self.class.plugin_class(name)
                result.push({
                  plugin: name,
                  detect: Formatter.tick(plugin_class.respond_to?(:detect)),
                  wizard: Formatter.tick(plugin_class.respond_to?(:wizard)),
                  path:   info[:source]
                })
              end
              return {type: :object_list, data: result, fields: %w[plugin detect wizard path]}
            when :create
              plugin_name = options.get_next_argument('name', expected: :single).downcase
              destination_folder = options.get_next_argument('folder', expected: :single, mandatory: false) || File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME)
              plugin_file = File.join(destination_folder, "#{plugin_name}.rb")
              content = <<~END_OF_PLUGIN_CODE
                require 'aspera/cli/plugin'
                module Aspera
                  module Cli
                    module Plugins
                      class #{plugin_name.capitalize} < Plugin
                        ACTIONS=[]
                        def execute_action; return Main.result_status('You called plugin #{plugin_name}'); end
                      end # #{plugin_name.capitalize}
                    end # Plugins
                  end # Cli
                end # Aspera
              END_OF_PLUGIN_CODE
              File.write(plugin_file, content)
              return Main.result_status("Created #{plugin_file}")
            end
          when :detect, :wizard
            # interactive mode
            options.ask_missing_mandatory = true
            # detect plugins by url and optional query
            apps = identify_plugins_for_url.freeze
            return {
              type: :object_list,
              data: apps
            } if action.eql?(:detect)
            return wizard_find(apps)
          when :coffee
            if OpenApplication.instance.url_method.eql?(:text)
              require 'aspera/preview/terminal'
              return Main.result_status(Preview::Terminal.build(Rest.new(base_url: COFFEE_IMAGE).read('')[:http].body))
            end
            OpenApplication.instance.uri(COFFEE_IMAGE)
            return Main.result_nothing
          when :ascp
            execute_action_ascp
          when :gem
            case options.get_next_command(%i[path version name])
            when :path then return Main.result_status(self.class.gem_src_root)
            when :version then return Main.result_status(Aspera::Cli::VERSION)
            when :name then return Main.result_status(@info[:gem])
            end
          when :folder
            return Main.result_status(@main_folder)
          when :file
            return Main.result_status(@option_config_file)
          when :email_test
            send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
            return Main.result_nothing
          when :smtp_settings
            return {type: :single_object, data: email_settings}
          when :proxy_check
            # ensure fpac was provided
            options.get_option(:fpac, mandatory: true)
            server_url = options.get_next_argument('server url')
            return Main.result_status(@pac_exec.find_proxy_for_url(server_url))
          when :check_update
            return {type: :single_object, data: check_gem_version}
          when :initdemo
            if @config_presets.key?(DEMO_SERVER_PRESET)
              Log.log.warn{"Demo server preset already present: #{DEMO_SERVER_PRESET}"}
            else
              Log.log.info{"Creating Demo server preset: #{DEMO_SERVER_PRESET}"}
              @config_presets[DEMO_SERVER_PRESET] = {
                'url'                                    => "ssh://#{DEMO}.asperasoft.com:33001",
                'username'                               => ASPERA,
                'ssAP'.downcase.reverse + 'drow'.reverse => DEMO + ASPERA # cspell:disable-line
              }
            end
            @config_presets[CONF_PRESET_DEFAULT] ||= {}
            if @config_presets[CONF_PRESET_DEFAULT].key?(SERVER_COMMAND)
              Log.log.warn{"Server default preset already set to: #{@config_presets[CONF_PRESET_DEFAULT][SERVER_COMMAND]}"}
              Log.log.warn{"Use #{DEMO_SERVER_PRESET} for demo: -P#{DEMO_SERVER_PRESET}"} unless
                DEMO_SERVER_PRESET.eql?(@config_presets[CONF_PRESET_DEFAULT][SERVER_COMMAND])
            else
              @config_presets[CONF_PRESET_DEFAULT][SERVER_COMMAND] = DEMO_SERVER_PRESET
              Log.log.info{"Setting server default preset to : #{DEMO_SERVER_PRESET}"}
            end
            return Main.result_status('Done')
          when :vault then execute_vault
          when :throw
            # :type [String]
            options
            exception_class_name = options.get_next_argument('exception class name', mandatory: true)
            exception_text = options.get_next_argument('exception text', mandatory: true)
            exception_class = Object.const_get(exception_class_name)
            raise "#{exception_class} is not an exception: #{exception_class.class}" unless exception_class <= Exception
            raise exception_class, exception_text
          else raise 'INTERNAL ERROR: wrong case'
          end
        end

        def wizard_find(apps)
          identification = if apps.length.eql?(1)
            Log.log.debug{"Detected: #{identification}"}
            apps.first
          else
            formatter.display_status('Multiple applications detected, please select from:')
            formatter.display_results({type: :object_list, data: apps, fields: %w[product url version]})
            answer = options.prompt_user_input_in_list('product', apps.map{|a|a[:product]})
            apps.find{|a|a[:product].eql?(answer)}
          end
          wiz_url = identification[:url]
          Log.dump(:identification, identification, :ruby)
          formatter.display_status("Using: #{identification[:name]} at #{wiz_url}".bold)
          # set url for instantiation of plugin
          options.add_option_preset({url: wiz_url})
          # instantiate plugin: command line options will be known and wizard can be called
          wiz_plugin_class = self.class.plugin_class(identification[:product])
          raise CliBadArgument, "Detected: #{identification[:product]}, but this application has no wizard" unless wiz_plugin_class.respond_to?(:wizard)
          # instantiate plugin: command line options will be known, e.g. private_key
          plugin_instance = wiz_plugin_class.new(@agents)
          wiz_params = {
            object: plugin_instance
          }
          # is private key needed ?
          if options.known_options.key?(:private_key) &&
              (!wiz_plugin_class.respond_to?(:private_key_required?) || wiz_plugin_class.private_key_required?(wiz_url))
            # lets see if path to priv key is provided
            private_key_path = options.get_option(:pkeypath)
            # give a chance to provide
            if private_key_path.nil?
              formatter.display_status('Please provide the path to your private RSA key, or nothing to generate one:')
              private_key_path = options.get_option(:pkeypath, mandatory: true).to_s
              # private_key_path = File.expand_path(private_key_path)
            end
            # else generate path
            if private_key_path.empty?
              private_key_path = File.join(@main_folder, DEFAULT_PRIV_KEY_FILENAME)
            end
            if File.exist?(private_key_path)
              formatter.display_status('Using existing key:')
            else
              formatter.display_status("Generating #{DEFAULT_PRIVKEY_LENGTH} bit RSA key...")
              Config.generate_rsa_private_key(path: private_key_path)
              formatter.display_status('Created key:')
            end
            formatter.display_status(private_key_path)
            private_key_pem = File.read(private_key_path)
            options.set_option(:private_key, private_key_pem)
            wiz_params[:private_key_path] = private_key_path
            wiz_params[:pub_key_pem] = OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s
          end
          Log.dump(:wiz_params, wiz_params)
          # finally, call the wizard
          wizard_result = wiz_plugin_class.wizard(**wiz_params)
          Log.log.debug{"wizard result: #{wizard_result}"}
          raise "Internal error: missing or extra keys in wizard result: #{wizard_result.keys}" unless WIZARD_RESULT_KEYS.eql?(wizard_result.keys.sort)
          # get preset name from user or default
          wiz_preset_name = options.get_option(:id)
          if wiz_preset_name.nil?
            elements = [
              identification[:product],
              URI.parse(wiz_url).host
            ]
            elements.push(options.get_option(:username, mandatory: true)) unless wizard_result[:preset_value].key?(:link)
            wiz_preset_name = elements.join('_').strip.downcase.gsub(/[^a-z0-9]/, '_').squeeze('_')
          end
          # test mode does not change conf file
          return {type: :single_object, data: wizard_result} if options.get_option(:test_mode)
          # Write configuration file
          formatter.display_status("Preparing preset: #{wiz_preset_name}")
          # init defaults if necessary
          @config_presets[CONF_PRESET_DEFAULT] ||= {}
          option_override = options.get_option(:override, mandatory: true)
          raise CliError, "A default configuration already exists for plugin '#{identification[:product]}' (use --override=yes or --default=no)" \
            if !option_override && options.get_option(:default, mandatory: true) && @config_presets[CONF_PRESET_DEFAULT].key?(identification[:product])
          raise CliError, "Preset already exists: #{wiz_preset_name}  (use --override=yes or --id=<name>)" \
            if !option_override && @config_presets.key?(wiz_preset_name)
          @config_presets[wiz_preset_name] = wizard_result[:preset_value].stringify_keys
          test_args = wizard_result[:test_args]
          if options.get_option(:default, mandatory: true)
            formatter.display_status("Setting config preset as default for #{identification[:product]}")
            @config_presets[CONF_PRESET_DEFAULT][identification[:product].to_s] = wiz_preset_name
          else
            test_args = "-P#{wiz_preset_name} #{test_args}"
          end
          # TODO: actually test the command
          return Main.result_status("You can test with:\n#{@info[:name]} #{identification[:product]} #{test_args}")
        end

        # @return [Hash] email server setting with defaults if not defined
        def email_settings
          smtp = options.get_option(:smtp, mandatory: true)
          # change string keys into symbol keys
          smtp = smtp.symbolize_keys
          # defaults
          smtp[:tls] = !smtp[:ssl] unless smtp.key?(:tls)
          smtp[:port] ||= if smtp[:tls]
            587
          elsif smtp[:ssl]
            465
          else
            25
          end
          smtp[:from_email] ||= smtp[:username] if smtp.key?(:username)
          smtp[:from_name] ||= smtp[:from_email].gsub(/@.*$/, '').gsub(/[^a-zA-Z]/, ' ').capitalize if smtp.key?(:username)
          smtp[:domain] ||= smtp[:from_email].gsub(/^.*@/, '') if smtp.key?(:from_email)
          # check minimum required
          %i[server port domain].each do |n|
            raise "Missing mandatory smtp parameter: #{n}" unless smtp.key?(n)
          end
          Log.log.debug{"smtp=#{smtp}"}
          return smtp
        end

        # send email using ERB template
        def send_email_template(email_template_default: nil, values: {})
          values[:to] ||= options.get_option(:notif_to, mandatory: true)
          notif_template = options.get_option(:notif_template, mandatory: email_template_default.nil?) || email_template_default
          mail_conf = email_settings
          values[:from_name] ||= mail_conf[:from_name]
          values[:from_email] ||= mail_conf[:from_email]
          %i[from_name from_email].each do |n|
            raise "Missing email parameter: #{n}" unless values.key?(n)
          end
          start_options = [mail_conf[:domain]]
          start_options.push(mail_conf[:username], mail_conf[:password], :login) if mail_conf.key?(:username) && mail_conf.key?(:password)
          # create a binding with only variables defined in values
          template_binding = Environment.empty_binding
          # add variables to binding
          values.each do |k, v|
            raise "key (#{k.class}) must be Symbol" unless k.is_a?(Symbol)
            template_binding.local_variable_set(k, v)
          end
          # execute template
          msg_with_headers = ERB.new(notif_template).result(template_binding)
          Log.dump(:msg_with_headers, msg_with_headers)
          require 'net/smtp'
          smtp = Net::SMTP.new(mail_conf[:server], mail_conf[:port])
          smtp.enable_starttls if mail_conf[:tls]
          smtp.enable_tls if mail_conf[:ssl]
          smtp.start(*start_options) do |smtp_session|
            smtp_session.send_message(msg_with_headers, values[:from_email], values[:to])
          end
          nil
        end

        # Save current configuration to config file
        # return true if file was saved
        def save_config_file_if_needed
          raise 'no configuration loaded' if @config_presets.nil?
          current_checksum = config_checksum
          return false if @config_checksum_on_disk.eql?(current_checksum)
          FileUtils.mkdir_p(@main_folder) unless Dir.exist?(@main_folder)
          Environment.restrict_file_access(@main_folder)
          Log.log.info{"Writing #{@option_config_file}"}
          formatter.display_status('Saving config file.')
          Environment.write_file_restricted(@option_config_file, force: true) {@config_presets.to_yaml}
          @config_checksum_on_disk = current_checksum
          return true
        end

        # returns [String] name if config_presets has default
        # returns nil if there is no config or bypass default params
        def get_plugin_default_config_name(plugin_name_sym)
          raise 'internal error: config_presets shall be defined' if @config_presets.nil?
          if !@use_plugin_defaults
            Log.log.debug('skip default config')
            return nil
          end
          if @config_presets.key?(CONF_PRESET_DEFAULT) &&
              @config_presets[CONF_PRESET_DEFAULT].key?(plugin_name_sym.to_s)
            default_config_name = @config_presets[CONF_PRESET_DEFAULT][plugin_name_sym.to_s]
            if !@config_presets.key?(default_config_name)
              Log.log.error do
                "Default config name [#{default_config_name}] specified for plugin [#{plugin_name_sym}], but it does not exist in config file.\n"\
                  'Please fix the issue: either create preset with one parameter: '\
                  "(#{@info[:name]} config id #{default_config_name} init @json:'{}') or remove default (#{@info[:name]} config id default remove #{plugin_name_sym})."
              end
            end
            raise CliError, "Config name [#{default_config_name}] must be a hash, check config file." if !@config_presets[default_config_name].is_a?(Hash)
            return default_config_name
          end
          return nil
        end # get_plugin_default_config_name

        # TODO: delete: ALLOWED_KEYS = %i[password username description].freeze
        # @return [Hash] result of execution of vault command
        def execute_vault
          command = options.get_next_command(%i[list show create delete password])
          case command
          when :list
            return {type: :object_list, data: vault.list}
          when :show
            return {type: :single_object, data: vault.get(label: options.get_next_argument('label'))}
          when :create
            label = options.get_next_argument('label')
            info = options.get_next_argument('info Hash')
            raise 'info must be Hash' unless info.is_a?(Hash)
            info = info.symbolize_keys
            info[:label] = label
            vault.set(info)
            return Main.result_status('Password added')
          when :delete
            vault.delete(label: options.get_next_argument('label'))
            return Main.result_status('Password deleted')
          when :password
            raise 'Vault does not support password change' unless vault.respond_to?(:password=)
            new_password = options.get_next_argument('new_password')
            vault.password = new_password
            vault.save
            return Main.result_status('Password updated')
          end
        end

        # @return [String] value from vault matching <name>.<param>
        def vault_value(name)
          m = name.match(/^(.+)\.(.+)$/)
          raise 'vault name shall match <name>.<param>' if m.nil?
          # this raise exception if label not found:
          info = vault.get(label: m[1])
          value = info[m[2].to_sym]
          raise "no such entry value: #{m[2]}" if value.nil?
          return value
        end

        # @return [Object] vault, from options or cache
        def vault
          if @vault.nil?
            vault_info = options.get_option(:vault) || {'type' => 'file', 'name' => 'vault.bin'}
            vault_password = options.get_option(:vault_password, mandatory: true)
            vault_type = vault_info['type'] || 'file'
            vault_name = vault_info['name'] || (vault_type.eql?('file') ? 'vault.bin' : PROGRAM_NAME)
            case vault_type
            when 'file'
              # absolute_path? introduced in ruby 2.7
              vault_path = vault_name.eql?(File.absolute_path(vault_name)) ? vault_name : File.join(@main_folder, vault_name)
              @vault = Keychain::EncryptedHash.new(vault_path, vault_password)
            when 'system'
              case Environment.os
              when Environment::OS_X
                @vault = Keychain::MacosSystem.new(vault_name, vault_password)
              else
                raise 'not implemented for this OS'
              end
            else
              raise CliBadArgument, "Unknown vault type: #{vault_type}"
            end
          end
          raise 'No vault defined' if @vault.nil?
          @vault
        end

        # version of URL without trailing "/" and removing default port
        def canonical_url(url)
          url.gsub(%r{/+$}, '').gsub(%r{^(https://[^/]+):443$}, '\1')
        end

        def lookup_preset(url:, username:)
          # remove extra info to maximize match
          url = canonical_url(url)
          Log.log.debug{"Lookup preset for #{username}@#{url}"}
          @config_presets.each do |_k, v|
            next unless v.is_a?(Hash)
            conf_url = v['url'].is_a?(String) ? canonical_url(v['url']) : nil
            return self.class.protect_presets(v) if conf_url.eql?(url) && v['username'].eql?(username)
          end
          nil
        end

        def lookup_secret(url:, username:, mandatory: false)
          secret = options.get_option(:secret)
          if secret.nil?
            conf = lookup_preset(url: url, username: username)
            if conf.is_a?(Hash)
              Log.log.debug{"Found preset #{conf} with URL and username"}
              secret = conf['password']
            end
            raise "Please provide secret for #{username} using option: secret or by setting a preset for #{username}@#{url}." if secret.nil? && mandatory
          end
          return secret
        end
      end
    end
  end
end
