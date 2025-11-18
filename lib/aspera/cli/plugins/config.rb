# frozen_string_literal: true

# cspell:ignore initdemo genkey pubkey asperasoft filelists
require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/plugins/factory'
require 'aspera/cli/extended_value'
require 'aspera/cli/special_values'
require 'aspera/cli/version'
require 'aspera/cli/formatter'
require 'aspera/cli/info'
require 'aspera/cli/transfer_progress'
require 'aspera/cli/wizard'
require 'aspera/cli/sync_actions'
require 'aspera/ascp/installation'
require 'aspera/sync/operations'
require 'aspera/products/transferd'
require 'aspera/transfer/parameters'
require 'aspera/transfer/spec'
require 'aspera/transfer/spec_doc'
require 'aspera/keychain/macos_security'
require 'aspera/proxy_auto_config'
require 'aspera/environment'
require 'aspera/persistency_action_once'
require 'aspera/id_generator'
require 'aspera/persistency_folder'
require 'aspera/data_repository'
require 'aspera/line_logger'
require 'aspera/rest'
require 'aspera/oauth/jwt'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/oauth'
require 'openssl'
require 'open3'
require 'date'
require 'erb'

module Aspera
  module Cli
    module Plugins
      # Manage the CLI config file
      class Config < Base
        include SyncActions

        class << self
          # Folder containing plugins in the gem's main folder
          def gem_plugins_folder
            File.dirname(File.expand_path(__FILE__))
          end

          # @return main folder where code is, i.e. .../lib
          # Go up as many times as englobing modules (not counting class, as it is a file)
          def gem_src_root
            # Module.nesting[2] is Cli::Plugins
            File.expand_path(Module.nesting[2].to_s.gsub('::', '/').gsub(%r{[^/]+}, '..'), gem_plugins_folder)
          end

          # Deep clone hash so that it does not get modified in case of display and secret hide
          def deep_clone(val)
            return Marshal.load(Marshal.dump(val))
          end

          # @return product family folder (~/.aspera)
          def module_family_folder
            user_home_folder = Dir.home
            Aspera.assert(Dir.exist?(user_home_folder), type: Cli::Error){"Home folder does not exist: #{user_home_folder}. Check your user environment."}
            return File.join(user_home_folder, ASPERA_HOME_FOLDER_NAME)
          end

          # @return [String] Product config folder (~/.aspera/<name>)
          def default_app_main_folder(app_name:)
            Aspera.assert_type(app_name, String)
            Aspera.assert(!app_name.empty?)
            return File.join(module_family_folder, app_name)
          end
        end

        def initialize(**_)
          # We need to defer parsing of options until we have the config file, so we can use @extend with @preset
          super
          @use_plugin_defaults = true
          @config_presets = nil
          @config_checksum_on_disk = nil
          @vault_instance = nil
          @pac_exec = nil
          @sdk_default_location = false
          @option_insecure = false
          @option_warn_insecure_cert = true
          @option_ignore_cert_host_port = []
          @option_http_options = {}
          @ssl_warned_urls = []
          @option_cache_tokens = true
          @main_folder = nil
          @option_config_file = nil
          # Store is used for ruby https (OpenSSL::X509::Store)
          @certificate_store = nil
          # Paths are used for ascp
          @certificate_paths = nil
          @progress_bar = nil
          # Option to set main folder
          options.declare(
            :home, 'Home folder for tool',
            handler: {o: self, m: :main_folder},
            default: self.class.default_app_main_folder(app_name: Info::CMD_NAME)
          )
          options.parse_options!
          Log.log.debug{"#{Info::CMD_NAME} folder: #{@main_folder}"}
          # Data persistency manager, created by config plugin, set for global object
          context.persistency = PersistencyFolder.new(File.join(@main_folder, PERSISTENCY_FOLDER))
          # Set folders for plugin lookup
          Plugins::Factory.instance.add_lookup_folder(self.class.gem_plugins_folder)
          Plugins::Factory.instance.add_lookup_folder(File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME))
          # Option to set config file
          options.declare(
            :config_file, 'Path to YAML file with preset configuration',
            handler: {o: self, m: :option_config_file},
            default: File.join(@main_folder, DEFAULT_CONFIG_FILENAME)
          )
          options.parse_options!
          # Read config file (set @config_presets)
          read_config_file
          # Add preset handler (needed for smtp)
          ExtendedValue.instance.set_handler(EXTEND_PRESET, lambda{ |v| preset_by_name(v)})
          ExtendedValue.instance.set_handler(EXTEND_VAULT, lambda{ |v| vault_value(v)})
          # Load defaults before it can be overridden
          add_plugin_default_preset(CONF_GLOBAL_SYM)
          # Vault options
          options.declare(:secret, 'Secret for access keys')
          options.declare(:vault, 'Vault for secrets', allowed: Hash)
          options.declare(:vault_password, 'Vault password')
          options.parse_options!
          # Declare generic plugin options only after handlers are declared
          Base.declare_options(options)
          # Configuration options
          options.declare(:no_default, 'Do not load default configuration for plugin', allowed: Allowed::TYPES_NONE, short: 'N'){@use_plugin_defaults = false}
          options.declare(:preset, 'Load the named option preset from current config file', short: 'P', handler: {o: self, m: :option_preset})
          options.declare(:version_check_days, 'Period in days to check new version (zero to disable)', allowed: Allowed::TYPES_INTEGER, default: DEFAULT_CHECK_NEW_VERSION_DAYS)
          options.declare(:plugin_folder, 'Folder where to find additional plugins', handler: {o: self, m: :option_plugin_folder})
          # Declare wizard options
          @wizard = Wizard.new(self, @main_folder)
          # Transfer SDK options
          options.declare(:sdk_url, 'Ascp: URL to get Aspera Transfer Executables', default: SpecialValues::DEF)
          options.parse_options!
          set_sdk_dir
          options.declare(:ascp_path, 'Ascp: Path to ascp (or product with "product:")', handler: {o: Ascp::Installation.instance, m: :ascp_path}, default: "#{Ascp::Installation::USE_PRODUCT_PREFIX}#{Ascp::Installation::FIRST_FOUND}")
          options.declare(:locations_url, 'Ascp: URL to get download locations of Aspera Transfer Daemon', handler: {o: Ascp::Installation.instance, m: :transferd_urls})
          options.declare(:sdk_folder, 'Ascp: SDK installation folder path', handler: {o: Products::Transferd, m: :sdk_directory})
          options.declare(:progress_bar, 'Display progress bar', allowed: Allowed::TYPES_BOOLEAN, default: Environment.terminal?)
          # Email options
          options.declare(:smtp, 'Email: SMTP configuration', allowed: Hash)
          options.declare(:notify_to, 'Email: Recipient for notification of transfers')
          options.declare(:notify_template, 'Email: ERB template for notification of transfers')
          # HTTP options
          options.declare(:insecure, 'HTTP/S: Do not validate any certificate', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :option_insecure}, default: false)
          options.declare(:ignore_certificate, 'HTTP/S: Do not validate certificate for these URLs', allowed: [Array, NilClass], handler: {o: self, m: :option_ignore_cert_host_port})
          options.declare(:warn_insecure, 'HTTP/S: Issue a warning if certificate is ignored', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :option_warn_insecure_cert}, default: true)
          options.declare(:cert_stores, 'HTTP/S: List of folder with trusted certificates', allowed: Allowed::TYPES_STRING_ARRAY, handler: {o: self, m: :trusted_cert_locations})
          options.declare(:http_options, 'HTTP/S: Options for HTTP/S socket', allowed: Hash, handler: {o: self, m: :option_http_options}, default: {})
          options.declare(:http_proxy, 'HTTP/S: URL for proxy with optional credentials', handler: {o: self, m: :option_http_proxy})
          options.declare(:cache_tokens, 'Save and reuse OAuth tokens', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :option_cache_tokens})
          options.declare(:fpac, 'Proxy auto configuration script')
          options.declare(:proxy_credentials, 'HTTP proxy credentials for fpac: user, password', allowed: [Array, NilClass])
          options.parse_options!
          @progress_bar = TransferProgress.new if options.get_option(:progress_bar)
          pac_script = options.get_option(:fpac)
          # Create PAC executor
          if !pac_script.nil?
            @pac_exec = ProxyAutoConfig.new(pac_script).register_uri_generic
            proxy_user_pass = options.get_option(:proxy_credentials)
            if !proxy_user_pass.nil?
              Aspera.assert(proxy_user_pass.length.eql?(2), type: Cli::BadArgument){"proxy_credentials shall have two elements (#{proxy_user_pass.length})"}
              @pac_exec.proxy_user = proxy_user_pass[0]
              @pac_exec.proxy_pass = proxy_user_pass[1]
            end
          end
          RestParameters.instance.user_agent = Info::CMD_NAME
          RestParameters.instance.progress_bar = @progress_bar
          RestParameters.instance.session_cb = lambda{ |http_session| update_http_session(http_session)}
          # Check http options that are global
          keys_to_delete = []
          @option_http_options.each do |k, v|
            method = "#{k}=".to_sym
            if RestParameters.instance.respond_to?(method)
              keys_to_delete.push(k)
              RestParameters.instance.send(method, v)
            elsif k.eql?('ssl_options')
              keys_to_delete.push(k)
              # NOTE: here is a hack that allows setting SSLContext options
              Aspera.assert_type(v, Array){'ssl_options'}
              # Start with default options
              ssl_options = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options]
              v.each do |opt|
                case opt
                when Integer
                  ssl_options = opt
                when String
                  name = "OP_#{opt.start_with?('-') ? opt[1..] : opt}".upcase
                  raise Cli::BadArgument, "Unknown ssl_option: #{name}, use one of: #{OpenSSL::SSL.constants.grep(/^OP_/).map{ |c| c.to_s.sub(/^OP_/, '')}.join(', ')}" if !OpenSSL::SSL.const_defined?(name)
                  if opt.start_with?('-')
                    ssl_options &= ~OpenSSL::SSL.const_get(name)
                  else
                    ssl_options |= OpenSSL::SSL.const_get(name)
                  end
                else
                  Aspera.error_unexpected_value(opt.class.name){'Expected String or Integer in ssl_options'}
                end
              end
              OpenSSL::SSL::SSLContext::DEFAULT_PARAMS[:options] = ssl_options
            elsif OAuth::Factory.instance.parameters.key?(k.to_sym)
              keys_to_delete.push(k)
              OAuth::Factory.instance.parameters[k.to_sym] = v
            end
          end
          keys_to_delete.each{ |k| @option_http_options.delete(k)}
          OAuth::Factory.instance.persist_mgr = persistency if @option_cache_tokens
          OAuth::Web.additional_info = "#{Info::CMD_NAME} v#{Cli::VERSION}"
          Transfer::Parameters.file_list_folder = File.join(@main_folder, 'filelists')
          RestErrorAnalyzer.instance.log_file = File.join(@main_folder, 'rest_exceptions.log')
          # Register aspera REST call error handlers
          RestErrorsAspera.register_handlers
        end

        attr_accessor :main_folder, :option_cache_tokens, :option_insecure, :option_warn_insecure_cert, :option_http_options
        attr_reader :option_ignore_cert_host_port, :progress_bar

        def set_sdk_dir
          # Check SDK folder is set or not, for compatibility, we check in two places
          sdk_dir = Products::Transferd.sdk_directory rescue nil
          if sdk_dir.nil?
            @sdk_default_location = true
            Log.log.debug('SDK folder is not set, checking default')
            # New location
            sdk_dir = self.class.default_app_main_folder(app_name: TRANSFERD_APP_NAME)
            Log.log.debug{"Checking: #{sdk_dir}"}
            if !Dir.exist?(sdk_dir)
              Log.log.debug{"No such folder: #{sdk_dir}"}
              # Former location
              former_sdk_folder = File.join(self.class.default_app_main_folder(app_name: Info::CMD_NAME), TRANSFERD_APP_NAME)
              Log.log.debug{"Checking: #{former_sdk_folder}"}
              sdk_dir = former_sdk_folder if Dir.exist?(former_sdk_folder)
            end
            Log.log.debug{"Using: #{sdk_dir}"}
            Products::Transferd.sdk_directory = sdk_dir
          end
        end

        # Add files, folders or default locations to the certificate store
        # @param path_list [Array<String>] List of paths to add
        # @return the list of paths
        def trusted_cert_locations=(path_list)
          Aspera.assert_type(path_list, Array){'cert locations'}
          if @certificate_store.nil?
            Log.log.debug('Creating SSL Cert store')
            @certificate_store = OpenSSL::X509::Store.new
            @certificate_paths = []
          end

          path_list.each do |path|
            Aspera.assert_type(path, String){'Expecting a String for certificate location'}
            paths_to_add = [path]
            Log.log.debug{"Adding cert location: #{path}"}
            if path.eql?(SpecialValues::DEF)
              @certificate_store.set_default_paths
              paths_to_add = [OpenSSL::X509::DEFAULT_CERT_DIR]
              # JRuby cert file seems not to be PEM
              paths_to_add.push(OpenSSL::X509::DEFAULT_CERT_FILE) unless defined?(JRUBY_VERSION)
              paths_to_add.select!{ |f| File.exist?(f)}
            elsif File.file?(path)
              @certificate_store.add_file(path)
            elsif File.directory?(path)
              @certificate_store.add_path(path)
            else
              raise "No such file or folder: #{path}"
            end
            paths_to_add.each do |p|
              pp = [File.realpath(p)]
              if File.directory?(p)
                pp = Dir.entries(p)
                  .map{ |e| File.realpath(File.join(p, e))}
                  .select{ |entry| File.file?(entry)}
                  .select{ |entry| CERT_EXT.any?{ |ext| entry.end_with?(ext)}}
              end
              @certificate_paths.concat(pp)
            end
          end
          @certificate_paths.uniq!
        end

        # @return only files
        def trusted_cert_locations
          locations = @certificate_paths
          if locations.nil?
            # Compute default locations
            self.trusted_cert_locations = [SpecialValues::DEF]
            locations = @certificate_paths
            # Restore defaults
            @certificate_paths = @certificate_store = nil
          end
          return locations
        end

        def option_http_proxy
          return ENV['http_proxy']
        end

        def option_http_proxy=(value)
          URI.parse(value)
          ENV['http_proxy'] = value
        end

        def option_ignore_cert_host_port=(url_list)
          url_list.each do |url|
            uri = URI.parse(url)
            raise "Expecting https scheme: #{url}" unless uri.scheme.eql?('https')
            @option_ignore_cert_host_port.push([uri.host, uri.port].freeze)
          end
        end

        def ignore_cert?(address, port)
          endpoint = [address, port].freeze
          ignore_cert = false
          if @option_insecure || @option_ignore_cert_host_port.any?(endpoint)
            ignore_cert = true
            if @option_warn_insecure_cert
              base_url = "https://#{address}:#{port}"
              if !@ssl_warned_urls.include?(base_url)
                formatter.display_message(
                  :error,
                  "#{Formatter::WARNING_FLASH} Ignoring certificate for: #{base_url}. Do not deactivate certificate verification in production."
                )
                @ssl_warned_urls.push(base_url)
              end
            end
          end
          Log.log.debug{"ignore cert? #{endpoint} -> #{ignore_cert}"}
          return ignore_cert
        end

        # Called every time a new REST HTTP session is opened to set user-provided options
        # @param http_session [Net::HTTP] the newly created HTTP/S session object
        def update_http_session(http_session)
          http_session.set_debug_output(LineLogger.new(:trace2)) if Log.instance.logger.trace2?
          # Rest.io_http_session(http_session).debug_output = Log.log
          http_session.verify_mode = SELF_SIGNED_CERT if http_session.use_ssl? && ignore_cert?(http_session.address, http_session.port)
          http_session.cert_store = @certificate_store if @certificate_store
          Log.log.debug{"Using cert store #{http_session.cert_store} (#{@certificate_store})"} unless http_session.cert_store.nil?
          @option_http_options.each do |k, v|
            method = "#{k}=".to_sym
            # Check if accessor is a method of Net::HTTP
            # continue_timeout= read_timeout= write_timeout=
            if http_session.respond_to?(method)
              http_session.send(method, v)
            else
              Log.log.error{"Unknown HTTP session attribute: #{k}"}
            end
          end
        end

        def check_gem_version
          latest_version =
            begin
              Rest.new(base_url: 'https://rubygems.org/api/v1').read("versions/#{Info::GEM_NAME}/latest.json")['version']
            rescue StandardError
              Log.log.warn('Could not retrieve latest gem version on rubygems.')
              '0'
            end
          if Gem::Version.new(Environment.ruby_version) < Gem::Version.new(Info::RUBY_FUTURE_MINIMUM_VERSION)
            Log.log.warn do
              "Note that a future version will require Ruby version #{Info::RUBY_FUTURE_MINIMUM_VERSION} at minimum, " \
                "you are using #{Environment.ruby_version}"
            end
          end
          return {
            name:        Info::GEM_NAME,
            current:     Cli::VERSION,
            latest:      latest_version,
            need_update: Gem::Version.new(Cli::VERSION) < Gem::Version.new(latest_version)
          }
        end

        def periodic_check_newer_gem_version
          # Get verification period
          delay_days = options.get_option(:version_check_days, mandatory: true).to_i
          # Check only if not zero day
          return if delay_days.eql?(0)
          # Get last date from persistency
          last_check_array = []
          check_date_persist = PersistencyActionOnce.new(
            manager: persistency,
            data:    last_check_array,
            id:      'version_last_check'
          )
          # Get persisted date or nil
          current_date = Date.today
          last_check_days = (current_date - Date.strptime(last_check_array.first, GEM_CHECK_DATE_FMT)) rescue nil
          Log.log.debug{"gem check new version: #{delay_days}, #{last_check_days}, #{current_date}, #{last_check_array}"}
          return if !last_check_days.nil? && last_check_days < delay_days
          # Generate timestamp
          last_check_array[0] = current_date.strftime(GEM_CHECK_DATE_FMT)
          check_date_persist.save
          # Compare this version and the one on internet
          check_data = check_gem_version
          Log.log.warn do
            "A new version is available: #{check_data[:latest]}. You have #{check_data[:current]}. Upgrade with: gem update #{check_data[:name]}"
          end if check_data[:need_update]
        end

        # Loads default parameters of plugin if no -P parameter
        # and if there is a section defined for the plugin in the "default" section
        # Try to find: conf[conf["default"][plugin_str]]
        # @param plugin_name_sym : symbol for plugin name
        def add_plugin_default_preset(plugin_name_sym)
          default_config_name = get_plugin_default_config_name(plugin_name_sym)
          Log.log.debug{"add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}"}
          options.add_option_preset(preset_by_name(default_config_name), 'default_plugin', override: false) unless default_config_name.nil?
          return
        end

        # Get the default global preset, or set default one
        def global_default_preset
          result = get_plugin_default_config_name(CONF_GLOBAL_SYM)
          if result.nil?
            result = CONF_PRESET_GLOBAL
            set_preset_key(CONF_PRESET_DEFAULTS, CONF_GLOBAL_SYM, result)
          end
          return result
        end

        def defaults_set(plugin_name, preset_name, preset_values, option_default, option_override)
          @config_presets[CONF_PRESET_DEFAULTS] ||= {}
          raise Cli::Error, "A default configuration already exists for plugin '#{plugin_name}' (use --override=yes or --default=no)" \
            if !option_override && option_default && @config_presets[CONF_PRESET_DEFAULTS].key?(plugin_name)
          raise Cli::Error, "Preset already exists: #{preset_name}  (use --override=yes or provide alternate name on command line)" \
            if !option_override && @config_presets.key?(preset_name)
          if option_default
            formatter.display_status("Setting config preset as default for #{plugin_name}")
            @config_presets[CONF_PRESET_DEFAULTS][plugin_name.to_s] = preset_name
          end
          @config_presets[preset_name] = preset_values
        end

        def set_preset_key(preset, param_name, param_value)
          Aspera.assert_values(param_name.class, [String, Symbol]){'parameter'}
          param_name = param_name.to_s
          selected_preset = @config_presets[preset]
          if selected_preset.nil?
            Log.log.debug{"Unknown preset name: #{preset}, initializing"}
            selected_preset = @config_presets[preset] = {}
          end
          Aspera.assert_type(selected_preset, Hash){"#{preset}.#{param_name}"}
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

        # Set parameter and value in global config
        # Creates one if none already created
        # @return preset name that contains global default
        def set_global_default(key, value)
          set_preset_key(global_default_preset, key, value)
        end

        # $HOME/.aspera/`program_name`
        attr_reader :gem_url
        attr_accessor :option_config_file

        # @param config_name name of the preset in config file
        # @param include_path used to detect and avoid include loops
        # @return copy of the hash from name (also expands possible includes)
        def preset_by_name(config_name, include_path = [])
          raise Cli::Error, 'loop in include' if include_path.include?(config_name)
          include_path = include_path.clone # Avoid messing up if there are multiple branches
          current = @config_presets
          config_name.split(PRESET_DIG_SEPARATOR).each do |name|
            Aspera.assert_type(current, Hash, type: Cli::Error){"sub key: #{include_path}"}
            include_path.push(name)
            current = current[name]
            raise Cli::Error, "Unknown config preset: #{include_path}" if current.nil?
          end
          current = self.class.deep_clone(current) unless current.is_a?(String)
          return ExtendedValue.instance.evaluate(current, context: 'preset')
        end

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
            options.add_option_preset(preset_by_name(value), 'set_by_name')
          else
            raise BadArgument, 'Preset definition must be a String for preset name, or Hash for set of values'
          end
        end

        def config_checksum
          JSON.generate(@config_presets).hash
        end

        # Read config file and validate format
        def read_config_file
          Log.log.debug{"config file is: #{@option_config_file}".red}
          # Files search for configuration, by default the one given by user
          search_files = [@option_config_file]
          # Find first existing file (or nil)
          conf_file_to_load = search_files.find{ |f| File.exist?(f)}
          # If no file found, create default config
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
          Log.dump(:available_presets, @config_presets, level: :trace1)
          Aspera.assert_type(@config_presets, Hash){'config file YAML'}
          # Check there is at least the config section
          Aspera.assert(@config_presets.key?(CONF_PRESET_CONFIG)){"Cannot find key: #{CONF_PRESET_CONFIG}"}
          version = @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]
          raise Error, 'No version found in config section.' if version.nil?
          Log.log.debug{"conf version: #{version}"}
          # VVV if there are any conversion needed, those happen here.
          # Fix bug in 4.4 (creating key "true" in "default" preset)
          @config_presets[CONF_PRESET_DEFAULTS].delete(true) if @config_presets[CONF_PRESET_DEFAULTS].is_a?(Hash)
          # ^^^ Place new compatibility code before this line
          # Set version to current
          @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION] = Cli::VERSION
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
            # Then there is a problem with that file.
            new_name = "#{@option_config_file}.pre#{Cli::VERSION}.manual_conversion_needed"
            File.rename(@option_config_file, new_name)
            Log.log.warn{"Renamed config file to #{new_name}."}
            Log.log.warn('Manual Conversion is required. Next time, a new empty file will be created.')
          end
          raise Cli::Error, e.to_s
        end

        def execute_connect_action
          command = options.get_next_command(%i[list info version])
          if %i[info version].include?(command)
            connect_id = options.get_next_argument('id or title')
            one_res = Products::Connect.instance.versions.find{ |i| i['id'].eql?(connect_id) || i['title'].eql?(connect_id)}
            raise Cli::BadIdentifier.new(:connect, connect_id) if one_res.nil?
          end
          case command
          when :list
            return Main.result_object_list(Products::Connect.instance.versions, fields: %w[id title version])
          when :info
            one_res.delete('links')
            return Main.result_single_object(one_res)
          when :version
            all_links = one_res['links']
            command = options.get_next_command(%i[list download open])
            if %i[download open].include?(command)
              link_title = options.get_next_argument('title or rel')
              one_link = all_links.find{ |i| i['title'].eql?(link_title) || i['rel'].eql?(link_title)}
              raise "no such value: #{link_title}" if one_link.nil?
            end
            case command
            when :list
              return Main.result_object_list(all_links)
            when :download
              archive_path = one_link['href']
              save_to_path = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), archive_path.gsub(%r{.*/}, ''))
              Products::Connect.instance.cdn_api.call(operation: 'GET', subpath: archive_path, save_to_file: save_to_path)
              return Main.result_status("Downloaded: #{save_to_path}")
            when :open
              Environment.instance.open_uri(one_link['href'])
              return Main.result_status("Opened: #{one_link['href']}")
            end
          end
        end

        def execute_action_ascp
          command = options.get_next_command(%i[connect use show products info install spec schema errors])
          case command
          when :connect
            return execute_connect_action
          when :use
            ascp_path = options.get_next_argument('path to ascp')
            Ascp::Installation.instance.ascp_path = ascp_path
            formatter.display_status("ascp version: #{Ascp::Installation.instance.get_ascp_version(ascp_path)}")
            set_global_default(:ascp_path, ascp_path)
            return Main.result_nothing
          when :show
            return Main.result_text(Ascp::Installation.instance.path(:ascp))
          when :info
            # Collect info from ascp executable
            data = Ascp::Installation.instance.ascp_info
            # Add command line transfer spec
            data['ts'] = transfer.user_transfer_spec
            # Add keys
            DataRepository::ELEMENTS.each_with_object(data){ |i, h| h[i.to_s] = DataRepository.instance.item(i)}
            # Declare those as secrets
            SecretHider::ADDITIONAL_KEYS_TO_HIDE.concat(DataRepository::ELEMENTS.map(&:to_s))
            return Main.result_single_object(data)
          when :products
            command = options.get_next_command(%i[list use])
            case command
            when :list
              return Main.result_object_list(Ascp::Installation.instance.installed_products, fields: %w[name app_root])
            when :use
              default_product = options.get_next_argument('product name')
              Ascp::Installation.instance.use_ascp_from_product(default_product)
              set_global_default(:ascp_path, "#{Ascp::Installation::USE_PRODUCT_PREFIX}#{default_product}")
              return Main.result_nothing
            end
          when :install
            # Reset to default location, if older default was used
            Products::Transferd.sdk_directory = self.class.default_app_main_folder(app_name: TRANSFERD_APP_NAME) if @sdk_default_location
            version = options.get_next_argument('transferd version', mandatory: false)
            n, v = Ascp::Installation.instance.install_sdk(url: options.get_option(:sdk_url, mandatory: true), version: version)
            return Main.result_status("Installed #{n} version #{v}")
          when :spec
            fields, data = Transfer::SpecDoc.man_table(Formatter, include_option: true)
            return Main.result_object_list(data, fields: fields.map(&:to_s))
          when :schema
            schema = Transfer::Spec::SCHEMA.merge({'$comment'=>'DO NOT EDIT, this file was generated from the YAML.'})
            agent = options.get_next_argument('transfer agent name', mandatory: false)
            schema['properties'] = schema['properties'].select{ |_k, v| CommandLineBuilder.supported_by_agent(agent, v)} unless agent.nil?
            schema['properties'] = schema['properties'].sort.to_h
            return Main.result_single_object(schema)
          when :errors
            error_data = []
            Ascp::Management::ERRORS.each_pair do |code, prop|
              error_data.push(code: code, mnemonic: prop[:c], retry: prop[:r], info: prop[:a])
            end
            return Main.result_object_list(error_data)
          else Aspera.error_unexpected_value(command)
          end
          Aspera.error_unreachable_line
        end

        def execute_action_transferd
          command = options.get_next_command(%i[list install])
          case command
          when :install
            # Reset to default location, if older default was used
            Products::Transferd.sdk_directory = self.class.default_app_main_folder(app_name: TRANSFERD_APP_NAME) if @sdk_default_location
            version = options.get_next_argument('transferd version', mandatory: false)
            n, v = Ascp::Installation.instance.install_sdk(url: options.get_option(:sdk_url, mandatory: true), version: version)
            return Main.result_status("Installed #{n} version #{v}")
          when :list
            sdk_list = Ascp::Installation.instance.sdk_locations
            return Main.result_object_list(
              sdk_list,
              fields: sdk_list.first.keys - ['url']
            )
          else Aspera.error_unexpected_value(command)
          end
          Aspera.error_unreachable_line
        end

        # Legacy actions available globally
        PRESET_GBL_ACTIONS = %i[list overview lookup secure].freeze
        # Operations requiring that preset exists
        PRESET_EXIST_ACTIONS = %i[show delete get unset].freeze
        # require id
        PRESET_INSTANCE_ACTIONS = %i[initialize update ask set].concat(PRESET_EXIST_ACTIONS).freeze
        PRESET_ALL_ACTIONS = (PRESET_GBL_ACTIONS + PRESET_INSTANCE_ACTIONS).freeze

        def execute_preset(action: nil, name: nil)
          action = options.get_next_command(PRESET_ALL_ACTIONS) if action.nil?
          name = instance_identifier if name.nil? && PRESET_INSTANCE_ACTIONS.include?(action)
          name = global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
          # Those operations require existing option
          raise "no such preset: #{name}" if PRESET_EXIST_ACTIONS.include?(action) && !@config_presets.key?(name)
          case action
          when :list
            return Main.result_value_list(@config_presets.keys, name: 'name')
          when :overview
            # Display process modifies the value (hide secrets): we do not want to save removed secrets
            data = self.class.deep_clone(@config_presets)
            formatter.hide_secrets(data)
            result = []
            data.each do |config, preset|
              preset.each do |parameter, value|
                result.push(CONF_OVERVIEW_KEYS.zip([config, parameter, value]).to_h)
              end
            end
            return Main.result_object_list(result, fields: CONF_OVERVIEW_KEYS)
          when :show
            return Main.result_single_object(self.class.deep_clone(@config_presets[name]))
          when :delete
            @config_presets.delete(name)
            return Main.result_status("Deleted: #{name}")
          when :get
            param_name = options.get_next_argument('parameter name')
            value = @config_presets[name][param_name]
            raise "no such option in preset #{name} : #{param_name}" if value.nil?
            case value
            when Numeric, String then return Main.result_text(ExtendedValue.instance.evaluate(value.to_s, context: 'preset'))
            end
            return Main.result_single_object(value)
          when :unset
            param_name = options.get_next_argument('parameter name')
            @config_presets[name].delete(param_name)
            return Main.result_status("Removed: #{name}: #{param_name}")
          when :set
            param_name = options.get_next_argument('parameter name')
            param_name = Manager.option_line_to_name(param_name)
            param_value = options.get_next_argument('parameter value', validation: nil)
            set_preset_key(name, param_name, param_value)
            return Main.result_nothing
          when :initialize
            config_value = options.get_next_argument('extended value', validation: Hash)
            Log.log.warn{"configuration already exists: #{name}, overwriting"} if @config_presets.key?(name)
            @config_presets[name] = config_value
            return Main.result_status("Modified: #{@option_config_file}")
          when :update
            #  get unprocessed options
            unprocessed_options = options.unprocessed_options_with_value
            Log.log.debug{"opts=#{unprocessed_options}"}
            @config_presets[name] ||= {}
            @config_presets[name].merge!(unprocessed_options)
            return Main.result_status("Updated: #{name}")
          when :ask
            options.ask_missing_mandatory = true
            @config_presets[name] ||= {}
            options.get_next_argument('option names', multiple: true).each do |option_name|
              option_value = options.get_interactive(option_name, check_option: true)
              @config_presets[name][option_name] = option_value
            end
            return Main.result_status("Updated: #{name}")
          when :lookup
            BasicAuth.declare_options(options)
            url = options.get_option(:url, mandatory: true)
            user = options.get_option(:username, mandatory: true)
            result = lookup_preset(url: url, username: user)
            raise Error, 'no such config found' if result.nil?
            return Main.result_single_object(result)
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
          pubkey
          remote_certificate
          gem
          plugins
          tokens
          echo
          download
          wizard
          detect
          coffee
          image
          ascp
          sync
          transferd
          email_test
          smtp_settings
          proxy_check
          folder
          file
          check_update
          initdemo
          vault
          test
          platform
        ].freeze

        # Main action procedure for plugin
        def execute_action
          action = options.get_next_command(ACTIONS)
          case action
          when :preset # Newer syntax
            return execute_preset
          when :open
            Environment.instance.open_editor(@option_config_file.to_s)
            return Main.result_nothing
          when :documentation
            section = options.get_next_argument('private key file path', mandatory: false)
            section = "##{section}" unless section.nil?
            Environment.instance.open_uri("#{Info::DOC_URL}#{section}")
            return Main.result_nothing
          when :genkey # Generate new rsa key
            private_key_path = options.get_next_argument('private key file path')
            private_key_length = options.get_next_argument('size in bits', mandatory: false, validation: Integer, default: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH)
            OAuth::Jwt.generate_rsa_private_key(path: private_key_path, length: private_key_length)
            return Main.result_status("Generated #{private_key_length} bit RSA key: #{private_key_path}")
          when :pubkey # Get pub key
            private_key_pem = options.get_next_argument('private key PEM value')
            return Main.result_text(OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s)
          when :remote_certificate
            cert_action = options.get_next_command(%i[chain only name])
            remote_url = options.get_next_argument('remote URL')
            remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
            raise "No certificate found for #{remote_url}" unless remote_chain&.first
            case cert_action
            when :chain
              return Main.result_text(remote_chain.map(&:to_pem).join("\n"))
            when :only
              return Main.result_text(remote_chain.first.to_pem)
            when :name
              return Main.result_text(remote_chain.first.subject.to_a.find{ |name, _, _| name == 'CN'}[1])
            end
          when :echo # Display the content of a value given on command line
            return Main.result_auto(options.get_next_argument('value', validation: nil))
          when :download
            file_url = options.get_next_argument('source URL').chomp
            file_dest = options.get_next_argument('file path', mandatory: false)
            file_dest = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), file_url.gsub(%r{.*/}, '')) if file_dest.nil?
            formatter.display_status("Downloading: #{file_url}")
            Rest.new(base_url: file_url).call(operation: 'GET', save_to_file: file_dest)
            return Main.result_status("Saved to: #{file_dest}")
          when :tokens
            require 'aspera/api/node'
            case options.get_next_command(%i{flush list show})
            when :flush
              return Main.result_value_list(OAuth::Factory.instance.flush_tokens, name: 'file')
            when :list
              return Main.result_object_list(OAuth::Factory.instance.persisted_tokens)
            when :show
              data = OAuth::Factory.instance.get_token_info(instance_identifier)
              raise Cli::Error, 'Unknown identifier' if data.nil?
              return Main.result_single_object(data)
            end
          when :plugins
            case options.get_next_command(%i[list create])
            when :list
              result = []
              Plugins::Factory.instance.plugin_list.each do |name|
                plugin_class = Plugins::Factory.instance.plugin_class(name)
                result.push({
                  plugin: name,
                  detect: Formatter.tick(plugin_class.respond_to?(:detect)),
                  wizard: Formatter.tick(plugin_class.instance_methods.include?(:wizard)),
                  path:   Plugins::Factory.instance.plugin_source(name)
                })
              end
              return Main.result_object_list(result, fields: %w[plugin detect wizard path])
            when :create
              plugin_name = options.get_next_argument('name').downcase
              destination_folder = options.get_next_argument('folder', mandatory: false) || File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME)
              plugin_file = File.join(destination_folder, "#{plugin_name}.rb")
              content = <<~END_OF_PLUGIN_CODE
                require 'aspera/cli/plugins/base'
                module Aspera
                  module Cli
                    module Plugins
                      class #{plugin_name.snake_to_capital} < Base
                        ACTIONS=[]
                        def execute_action
                          return Main.result_status('You called plugin #{plugin_name}')
                        end
                      end
                    end
                  end
                end
              END_OF_PLUGIN_CODE
              File.write(plugin_file, content)
              return Main.result_status("Created #{plugin_file}")
            end
          when :detect, :wizard
            # Interactive mode
            options.ask_missing_mandatory = true
            # Detect plugins by url and optional query
            apps = @wizard.identify_plugins_for_url.freeze
            return Main.result_object_list(apps) if action.eql?(:detect)
            return @wizard.find(apps)
          when :coffee
            return Main.result_image(COFFEE_IMAGE_URL)
          when :image
            return Main.result_image(options.get_next_argument('image URI or blob'))
          when :ascp
            execute_action_ascp
          when :sync
            case options.get_next_command(%i[spec admin translate])
            when :spec
              fields, data = Transfer::SpecDoc.man_table(Formatter, include_option: true, agent_columns: false, schema: Sync::Operations::CONF_SCHEMA)
              return Main.result_object_list(data, fields: fields.map(&:to_s))
            when :admin
              return execute_sync_admin
            when :translate
              return Main.result_single_object(Sync::Operations.args_to_conf(options.get_next_argument('async arguments', multiple: true)))
            else Aspera.error_unreachable_line
            end
          when :transferd
            execute_action_transferd
          when :gem
            case options.get_next_command(%i[path version name])
            when :path then return Main.result_text(self.class.gem_src_root)
            when :version then return Main.result_text(Cli::VERSION)
            when :name then return Main.result_text(Info::GEM_NAME)
            else Aspera.error_unreachable_line
            end
          when :folder
            return Main.result_text(@main_folder)
          when :file
            return Main.result_text(@option_config_file)
          when :email_test
            send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
            return Main.result_nothing
          when :smtp_settings
            return Main.result_single_object(email_settings)
          when :proxy_check
            # Ensure fpac was provided
            options.get_option(:fpac, mandatory: true)
            server_url = options.get_next_argument('server url')
            return Main.result_text(@pac_exec.get_proxies(server_url))
          when :check_update
            return Main.result_single_object(check_gem_version)
          when :initdemo
            if @config_presets.key?(DEMO_PRESET)
              Log.log.warn{"Demo server preset already present: #{DEMO_PRESET}"}
            else
              Log.log.info{"Creating Demo server preset: #{DEMO_PRESET}"}
              @config_presets[DEMO_PRESET] = {
                'url'                                    => "ssh://#{DEMO_SERVER}.asperasoft.com:33001",
                'username'                               => ASPERA,
                'ssAP'.downcase.reverse + 'drow'.reverse => DEMO_SERVER + ASPERA # cspell:disable-line
              }
            end
            @config_presets[CONF_PRESET_DEFAULTS] ||= {}
            if @config_presets[CONF_PRESET_DEFAULTS].key?(SERVER_COMMAND)
              Log.log.warn{"Server default preset already set to: #{@config_presets[CONF_PRESET_DEFAULTS][SERVER_COMMAND]}"}
              Log.log.warn{"Use #{DEMO_PRESET} for demo: -P#{DEMO_PRESET}"} unless
                DEMO_PRESET.eql?(@config_presets[CONF_PRESET_DEFAULTS][SERVER_COMMAND])
            else
              @config_presets[CONF_PRESET_DEFAULTS][SERVER_COMMAND] = DEMO_PRESET
              Log.log.info{"Setting server default preset to : #{DEMO_PRESET}"}
            end
            return Main.result_status('Done')
          when :vault then execute_vault
          when :test then return execute_test
          when :platform
            return Main.result_text(Environment.instance.architecture)
          else Aspera.error_unreachable_line
          end
        end

        # @return [Hash] email server setting with defaults if not defined
        def email_settings
          smtp = options.get_option(:smtp, mandatory: true)
          # Change keys from string into symbol
          smtp = smtp.symbolize_keys
          unsupported = smtp.keys - SMTP_CONF_PARAMS
          raise Cli::Error, "Unsupported SMTP parameter: #{unsupported.join(', ')}, use: #{SMTP_CONF_PARAMS.join(', ')}" unless unsupported.empty?
          # Defaults
          # smtp[:ssl] = nil (false)
          smtp[:tls] = !smtp[:ssl] unless smtp.key?(:tls)
          smtp[:port] ||= if smtp[:tls]
            587
          elsif smtp[:ssl]
            465
          else
            25
          end
          smtp[:from_email] ||= smtp[:username] if smtp.key?(:username)
          smtp[:from_name] ||= smtp[:from_email].sub(/@.*$/, '').gsub(/[^a-zA-Z]/, ' ').capitalize if smtp.key?(:username)
          smtp[:domain] ||= smtp[:from_email].sub(/^.*@/, '') if smtp.key?(:from_email)
          # Check minimum required
          %i[server port domain].each do |n|
            Aspera.assert(smtp.key?(n)){"Missing mandatory smtp parameter: #{n}"}
          end
          Log.log.debug{"smtp=#{smtp}"}
          return smtp
        end

        # Send email using ERB template
        # @param email_template_default [String] default template, can be overridden by option
        # @param values [Hash] values to be used in template, keys with default: to, from_name, from_email
        def send_email_template(email_template_default: nil, values: {})
          values[:to] ||= options.get_option(:notify_to, mandatory: true)
          notify_template = options.get_option(:notify_template, mandatory: email_template_default.nil?) || email_template_default
          mail_conf = email_settings
          values[:from_name] ||= mail_conf[:from_name]
          values[:from_email] ||= mail_conf[:from_email]
          %i[to from_email].each do |n|
            Aspera.assert_type(values[n], String){"Missing email parameter: #{n} in config"}
          end
          start_options = [mail_conf[:domain]]
          start_options.push(mail_conf[:username], mail_conf[:password], :login) if mail_conf.key?(:username) && mail_conf.key?(:password)
          # Create a binding with only variables defined in values
          template_binding = Environment.empty_binding
          # Add variables to binding
          values.each do |k, v|
            Aspera.assert_type(k, Symbol)
            template_binding.local_variable_set(k, v)
          end
          # Execute template
          msg_with_headers = ERB.new(notify_template).result(template_binding)
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
        # @return true if file was saved
        def save_config_file_if_needed
          raise Error, 'no configuration loaded' if @config_presets.nil?
          current_checksum = config_checksum
          return false if @config_checksum_on_disk.eql?(current_checksum)
          FileUtils.mkdir_p(@main_folder)
          Environment.restrict_file_access(@main_folder)
          Log.log.info{"Writing #{@option_config_file}"}
          formatter.display_status('Saving config file.')
          Environment.write_file_restricted(@option_config_file, force: true){@config_presets.to_yaml}
          @config_checksum_on_disk = current_checksum
          return true
        end

        # @return [String] name if config_presets has default
        # @return nil if there is no config or bypass default params
        def get_plugin_default_config_name(plugin_name_sym)
          Aspera.assert(!@config_presets.nil?){'config_presets shall be defined'}
          if !@use_plugin_defaults
            Log.log.debug('skip default config')
            return
          end
          if !@config_presets.key?(CONF_PRESET_DEFAULTS)
            Log.log.debug('No default section')
            return
          end
          Aspera.assert_type(@config_presets[CONF_PRESET_DEFAULTS], Hash){'default section'}
          if !@config_presets[CONF_PRESET_DEFAULTS].key?(plugin_name_sym.to_s)
            Log.log.debug("No default for #{plugin_name_sym}")
            return
          end
          default_config_name = @config_presets[CONF_PRESET_DEFAULTS][plugin_name_sym.to_s]
          if !@config_presets.key?(default_config_name)
            Log.log.error do
              "Default config name [#{default_config_name}] specified for plugin [#{plugin_name_sym}], but it does not exist in config file.\n" \
                "Please fix the issue: either create preset with one parameter:\n" \
                "#{Info::CMD_NAME} config id #{default_config_name} init @json:'{}'\n" \
                "or remove default:\n#{Info::CMD_NAME} config id default remove #{plugin_name_sym}"
            end
            raise Cli::Error, "No such preset: #{default_config_name}"
          end
          Aspera.assert_type(@config_presets[default_config_name], Hash, type: Cli::Error){'preset type'}
          return default_config_name
        end

        # @return [Hash] result of execution of vault command
        def execute_vault
          command = options.get_next_command(%i[info list show create delete password])
          case command
          when :info
            return Main.result_single_object(vault.info)
          when :list
            # , fields: %w(label url username password description)
            return Main.result_object_list(vault.list)
          when :show
            return Main.result_single_object(vault.get(label: options.get_next_argument('label')))
          when :create
            vault.set(options.get_next_argument('info', validation: Hash).symbolize_keys)
            return Main.result_status('Secret added')
          when :delete
            label_to_delete = options.get_next_argument('label')
            vault.delete(label: label_to_delete)
            return Main.result_status("Secret deleted: #{label_to_delete}")
          when :password
            Aspera.assert(vault.respond_to?(:change_password)){'Vault does not support password change'}
            vault.change_password(options.get_next_argument('new_password'))
            return Main.result_status('Vault password updated')
          end
        end

        # @return [String] value from vault matching <name>.<param>
        def vault_value(name)
          m = name.split('.')
          raise BadArgument, 'vault name shall match <name>.<param>' unless m.length.eql?(2)
          # This raise exception if label not found:
          info = vault.get(label: m[0])
          value = info[m[1].to_sym]
          raise "no such entry value: #{m[1]}" if value.nil?
          return value
        end

        # @return [Object] vault, from options or cache
        def vault
          return @vault_instance unless @vault_instance.nil?
          info = options.get_option(:vault).symbolize_keys
          info[:type] ||= 'file'
          require 'aspera/keychain/factory'
          @vault_instance = Keychain::Factory.create(
            info,
            Info::CMD_NAME,
            @main_folder,
            options.get_option(:vault_password)
          )
        end

        # Artificially raise an exception for tests
        def execute_test
          case options.get_next_command(%i[throw web])
          when :throw
            # :type [String]
            # Options
            exception_class_name = options.get_next_argument('exception class name', mandatory: true)
            exception_text = options.get_next_argument('exception text', mandatory: true)
            type = Object.const_get(exception_class_name)
            Aspera.assert(type <= Exception){"#{type} is not an exception: #{type.class}"}
            raise type, exception_text
          when :web
          end
        end

        # Version of URL without trailing "/" and removing default port
        def canonical_url(url)
          url.chomp('/').sub(%r{^(https://[^/]+):443$}, '\1')
        end

        # Look for a preset that has the corresponding URL and username
        # @return the first one matching
        def lookup_preset(url:, username:)
          # Remove extra info to maximize match
          url = canonical_url(url)
          Log.log.debug{"Lookup preset for #{username}@#{url}"}
          @config_presets.each_value do |v|
            next unless v.is_a?(Hash)
            conf_url = v['url'].is_a?(String) ? canonical_url(v['url']) : nil
            return self.class.deep_clone(v) if conf_url.eql?(url) && v['username'].eql?(username)
          end
          nil
        end

        # Lookup the corresponding secret for the given URL and usernames
        # @raise Exception if mandatory and not found
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
        # Private
        # Folder in $HOME for application files (config, cache)
        ASPERA_HOME_FOLDER_NAME = '.aspera'
        # Default config file
        DEFAULT_CONFIG_FILENAME = 'config.yaml'
        # Reserved preset names
        CONF_PRESET_CONFIG = 'config'
        CONF_PRESET_VERSION = 'version'
        CONF_PRESET_DEFAULTS = 'default'
        CONF_PRESET_GLOBAL = 'global_common_defaults'
        # Special name to identify value of default
        GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
        CONF_GLOBAL_SYM = :config
        # Folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME = 'plugins'
        PERSISTENCY_FOLDER = 'persist_store'
        ASPERA = 'aspera'
        SERVER_COMMAND = 'server'
        TRANSFERD_APP_NAME = 'sdk'
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
        PRESET_DIG_SEPARATOR = '.'
        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
        COFFEE_IMAGE_URL = 'https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg'
        GEM_CHECK_DATE_FMT = '%Y/%m/%d'
        # For testing only
        SELF_SIGNED_CERT = OpenSSL::SSL.const_get(:enon_yfirev.to_s.upcase.reverse) # cspell: disable-line
        CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze
        SMTP_CONF_PARAMS = %i[server tls ssl port domain username password from_name from_email].freeze
        CERT_EXT = %w[crt cer pem der].freeze
        private_constant :ASPERA_HOME_FOLDER_NAME,
          :DEFAULT_CONFIG_FILENAME,
          :CONF_PRESET_CONFIG,
          :CONF_PRESET_VERSION,
          :CONF_PRESET_DEFAULTS,
          :CONF_PRESET_GLOBAL,
          :ASPERA_PLUGINS_FOLDERNAME,
          :ASPERA,
          :DEMO_SERVER,
          :DEMO_PRESET,
          :EMAIL_TEST_TEMPLATE,
          :EXTEND_PRESET,
          :EXTEND_VAULT,
          :DEFAULT_CHECK_NEW_VERSION_DAYS,
          :SERVER_COMMAND,
          :PRESET_DIG_SEPARATOR,
          :COFFEE_IMAGE_URL,
          :SELF_SIGNED_CERT,
          :PERSISTENCY_FOLDER,
          :CONF_OVERVIEW_KEYS,
          :SMTP_CONF_PARAMS,
          :TRANSFERD_APP_NAME,
          :GLOBAL_DEFAULT_KEYWORD,
          :CONF_GLOBAL_SYM,
          :GEM_CHECK_DATE_FMT,
          :CERT_EXT
      end
    end
  end
end
