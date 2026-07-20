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
require 'aspera/cli/preset_manager'
require 'aspera/cli/http'
require 'aspera/ascp/installation'
require 'aspera/sync/operations'
require 'aspera/products/transferd'
require 'aspera/transfer/parameters'
require 'aspera/transfer/spec'
require 'aspera/schema/documentation'
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
require 'aspera/ssl'
require 'openssl'
require 'digest'
require 'open3'
require 'date'
require 'erb'
require 'net/http'

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
            Aspera.assert(!app_name.empty?, 'app_name must not be empty')
            return File.join(module_family_folder, app_name)
          end
        end

        def initialize(**_)
          # We need to defer parsing of options until we have the config file, so we can use @extend with @preset
          super
          @vault_instance = nil
          @pac_exec = nil
          @sdk_default_location = false
          @option_cache_tokens = true
          @main_folder = nil
          @option_config_file = nil
          @progress_bar = nil
          # Option to set main folder
          options.declare(
            :home, 'Home folder for tool',
            handler: {o: self, m: :main_folder},
            default: self.class.default_app_main_folder(app_name: Info::CMD_NAME)
          )
          options.parse_options!
          Log.log.debug{"#{Info::CMD_NAME} folder: #{@main_folder}"}
          setup_persistency_and_plugin_folders
          # Option to set config file
          options.declare(
            :config_file, 'Path to YAML file with preset configuration',
            handler: {o: self, m: :option_config_file},
            default: File.join(@main_folder, DEFAULT_CONFIG_FILENAME)
          )
          options.parse_options!
          # Instantiate PresetManager (reads config file) and inject into context
          context.presets = PresetManager.new(config_file: @option_config_file)
          # Instantiate Http and inject into context
          context.http_config = Http.new
          setup_extended_value_handlers
          # Vault options
          options.declare(:secret, 'Secret for access keys')
          options.declare(:vault, 'Vault for secrets', allowed: Hash)
          options.declare(:vault_password, 'Vault password')
          options.parse_options!
          # Declare generic plugin options only after handlers are declared
          Base.declare_options(options)
          # Configuration options
          options.declare(:no_default, 'Do not load default configuration for plugin', allowed: Allowed::TYPES_NONE, short: 'N'){presets.use_plugin_defaults = false}
          options.declare(:preset, 'Load the named option preset from current config file', short: 'P', handler: {o: self, m: :option_preset})
          options.declare(:version_check_days, 'Period in days to check new version (zero to disable)', allowed: Allowed::TYPES_INTEGER, default: DEFAULT_CHECK_NEW_VERSION_DAYS)
          options.declare(:plugin_folder, 'Folder where to find additional plugins', handler: {o: self, m: :option_plugin_folder})
          # Declare wizard options
          @wizard = Wizard.new(self, @main_folder)
          # Transfer SDK options
          options.declare(:sdk_url, 'Ascp: URL to get Aspera Transfer Executables', default: SpecialValues::DEF)
          options.parse_options!
          set_sdk_dir
          options.declare(:locations_url, 'Ascp: URL to get download locations of Aspera Transfer Daemon', handler: {o: Ascp::Installation.instance, m: :transferd_urls})
          options.declare(:sdk_folder, 'Ascp: Path to folder with ascp (or product with "product:")', handler: {o: Products::Transferd, m: :sdk_directory})
          options.declare(:progress_bar, 'Display progress bar', allowed: Allowed::TYPES_BOOLEAN, default: Environment.terminal?)
          # Email options
          options.declare(:smtp, 'Email: SMTP configuration', allowed: Hash)
          options.declare(:notify_to, 'Email: Recipient for notification of transfers')
          options.declare(:notify_template, 'Email: ERB template for notification of transfers')
          # HTTP options — declared by HttpConfig itself
          context.http_config.declare_options(options)
          options.declare(:cache_tokens, 'Save and reuse OAuth tokens', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :option_cache_tokens})
          options.declare(:fpac, 'Proxy auto configuration script')
          options.declare(:proxy_credentials, 'HTTP proxy credentials for fpac: user, password', allowed: [Array, NilClass])
          options.parse_options!
          @progress_bar = TransferProgress.new if options.get_option(:progress_bar)
          setup_pac_executor
          setup_rest_and_transfer_runtime
        end

        private

        def setup_persistency_and_plugin_folders
          context.persistency = PersistencyFolder.new(File.join(@main_folder, PERSISTENCY_FOLDER))
          Plugins::Factory.instance.add_lookup_folder(self.class.gem_plugins_folder)
          Plugins::Factory.instance.add_lookup_folder(File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME))
        end

        def setup_extended_value_handlers
          ExtendedValue.instance.on(EXTEND_PRESET){ |v| presets.by_name(v)}
          ExtendedValue.instance.on(EXTEND_VAULT){ |v| vault_value(v)}
          add_plugin_default_preset(CONF_GLOBAL_SYM)
        end

        def setup_pac_executor
          pac_script = options.get_option(:fpac)
          return unless pac_script

          @pac_exec = ProxyAutoConfig.new(pac_script).register_uri_generic
          proxy_user_pass = options.get_option(:proxy_credentials)
          if proxy_user_pass
            Aspera.assert(proxy_user_pass.length.eql?(2), type: Cli::BadArgument){"proxy_credentials shall have two elements (#{proxy_user_pass.length})"}
            @pac_exec.proxy_user = proxy_user_pass[0]
            @pac_exec.proxy_pass = proxy_user_pass[1]
          end
        end

        def setup_rest_and_transfer_runtime
          RestParameters.instance.user_agent = Info::CMD_NAME
          RestParameters.instance.progress_bar = @progress_bar
          RestParameters.instance.session_cb = ->(http_session){context.http_config.update_session(http_session)}
          RestParameters.instance.spinner_cb = ->(title = nil, action: :spin){formatter.long_operation(title, action: action)}
          # Promote http_options keys that target global singletons (RestParameters, SSL, OAuth)
          http_opts = context.http_config.http_options
          keys_to_delete = []
          http_opts.each do |k, v|
            method = "#{k}=".to_sym
            if RestParameters.instance.respond_to?(method)
              keys_to_delete.push(k)
              RestParameters.instance.send(method, v)
            elsif k.eql?('ssl_options')
              keys_to_delete.push(k)
              Aspera::SSL.option_list = v
            elsif OAuth::Factory.instance.parameters.key?(k.to_sym)
              keys_to_delete.push(k)
              OAuth::Factory.instance.parameters[k.to_sym] = v
            end
          end
          keys_to_delete.each{ |k| http_opts.delete(k)}
          OAuth::Factory.instance.persist_mgr = persistency if @option_cache_tokens
          OAuth::Web.additional_info = "#{Info::CMD_NAME} v#{Cli::VERSION}"
          Transfer::Parameters.file_list_folder = File.join(@main_folder, FILE_LIST_FOLDER_NAME)
          RestErrorAnalyzer.instance.log_file = File.join(@main_folder, REST_EXCEPTIONS_LOG_FILENAME)
          # Register aspera REST call error handlers
          RestErrorsAspera.register_handlers
        end

        public

        attr_accessor :main_folder, :option_cache_tokens
        attr_reader :progress_bar

        # Delegations to http_config kept for backward compatibility with transfer_agent and plugins
        def option_insecure;            context.http_config.insecure; end
        def option_insecure=(v);        context.http_config.insecure = v; end
        def option_warn_insecure_cert;  context.http_config.warn_insecure; end
        def option_warn_insecure_cert=(v); context.http_config.warn_insecure = v; end
        def option_http_options;        context.http_config.http_options; end
        def option_http_options=(v);    context.http_config.http_options = v; end
        def option_ignore_cert_host_port; context.http_config.ignore_cert_host_port; end
        def ignore_cert?(address, port); context.http_config.ignore_cert?(address, port); end
        def trusted_cert_locations;     context.http_config.trusted_cert_locations; end
        def trusted_cert_locations=(v); context.http_config.trusted_cert_locations = v; end

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

        # Delegation to PresetManager: loads default preset options for a plugin
        def add_plugin_default_preset(plugin_name_sym)
          default_config_name = presets.plugin_default_name(plugin_name_sym)
          Log.log.debug{"add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}"}
          options.add_option_preset(presets.by_name(default_config_name), 'default_plugin', override: false) unless default_config_name.nil?
        end

        # Delegations to PresetManager kept for backward compatibility
        def defaults_set(plugin_name, preset_name, preset_values, option_default, option_override)
          presets.defaults_set(plugin_name, preset_name, preset_values, option_default, option_override)
        end

        def set_preset_key(preset, param_name, param_value)
          presets.set_key(preset, param_name, param_value)
        end

        def set_global_default(key, value)
          presets.set_global_default(key, value)
        end

        def preset_by_name(config_name, include_path = [])
          presets.by_name(config_name, include_path)
        end

        def get_plugin_default_config_name(plugin_name_sym)
          presets.plugin_default_name(plugin_name_sym)
        end

        def save_config_file_if_needed
          presets.save_if_needed
        end

        def lookup_preset(url:, username:)
          presets.lookup_preset(url: url, username: username)
        end

        attr_reader :gem_url
        attr_accessor :option_config_file

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
            # Collect info from ascp executable
            data = Ascp::Installation.instance.ascp_info
            # Add command line transfer spec
            data['ts'] = transfer.user_transfer_spec
            # Add keys
            DataRepository::ELEMENTS.each_with_object(data){ |i, h| h[i.to_s] = DataRepository.instance.item(i)}
            # Declare those as secrets
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

        # Legacy actions available globally
        PRESET_GBL_ACTIONS = %i[list overview lookup secure].freeze
        # Operations requiring that preset exists
        PRESET_EXIST_ACTIONS = %i[show delete get unset].freeze
        # require id
        PRESET_INSTANCE_ACTIONS = %i[initialize update ask set].concat(PRESET_EXIST_ACTIONS).freeze
        PRESET_ALL_ACTIONS = (PRESET_GBL_ACTIONS + PRESET_INSTANCE_ACTIONS).freeze

        def execute_preset(action: nil, name: nil)
          cp = presets.config_presets
          action = options.get_next_command(PRESET_ALL_ACTIONS) if action.nil?
          name = options.instance_identifier if name.nil? && PRESET_INSTANCE_ACTIONS.include?(action)
          name = presets.global_default_preset if name.eql?(GLOBAL_DEFAULT_KEYWORD)
          # Those operations require existing option
          raise "no such preset: #{name}" if PRESET_EXIST_ACTIONS.include?(action) && !cp.key?(name)
          case action
          when :list
            return Result::ValueList.new(cp.keys, name: 'name')
          when :overview
            # Display process modifies the value (hide secrets): we do not want to save removed secrets
            data = PresetManager.deep_clone(cp)
            formatter.hide_secrets(data)
            result = []
            data.each do |config, preset|
              preset.each do |parameter, value|
                result.push(CONF_OVERVIEW_KEYS.zip([config, parameter, value]).to_h)
              end
            end
            return Result::ObjectList.new(result, fields: CONF_OVERVIEW_KEYS)
          when :show
            return Result::SingleObject.new(PresetManager.deep_clone(cp[name]))
          when :delete
            cp.delete(name)
            return Result::Status.new("Deleted: #{name}")
          when :get
            param_name = options.get_next_argument('parameter name')
            value = cp[name][param_name]
            raise "no such option in preset #{name} : #{param_name}" if value.nil?
            case value
            when Numeric, String then return Result::Text.new(ExtendedValue.instance.evaluate(value.to_s, context: 'preset'))
            end
            return Result::SingleObject.new(value)
          when :unset
            param_name = options.get_next_argument('parameter name')
            cp[name].delete(param_name)
            return Result::Status.new("Removed: #{name}: #{param_name}")
          when :set
            param_name = options.get_next_argument('parameter name')
            param_name = Manager.option_line_to_name(param_name)
            param_value = options.get_next_argument('parameter value', validation: nil)
            set_preset_key(name, param_name, param_value)
            return Result::Nothing.new
          when :initialize
            config_value = options.get_next_argument('extended value', validation: Hash)
            Log.log.warn{"configuration already exists: #{name}, overwriting"} if cp.key?(name)
            cp[name] = config_value
            return Result::Status.new("Modified: #{@option_config_file}")
          when :update
            unprocessed_options = options.unprocessed_options_with_value
            Log.log.debug{"opts=#{unprocessed_options}"}
            cp[name] ||= {}
            cp[name].merge!(unprocessed_options)
            return Result::Status.new("Updated: #{name}")
          when :ask
            options.ask_missing_mandatory = true
            cp[name] ||= {}
            options.get_next_argument('option names', multiple: true).each do |option_name|
              option_value = options.get_interactive(option_name, check_option: true)
              cp[name][option_name] = option_value
            end
            return Result::Status.new("Updated: #{name}")
          when :lookup
            BasicAuth.declare_options(options)
            url = options.get_option(:url, mandatory: true)
            user = options.get_option(:username, mandatory: true)
            result = lookup_preset(url: url, username: user)
            raise Error, 'no such config found' if result.nil?
            return Result::SingleObject.new(result)
          when :secure
            identifier = options.get_next_argument('config name', mandatory: false)
            preset_names = identifier.nil? ? cp.keys : [identifier]
            secret_keywords = %w[password secret].freeze
            preset_names.each do |preset_name|
              preset = cp[preset_name]
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
                  vault.set(to_set)
                  preset[option_name] = "@vault:#{vault_label}.password"
                end
              end
            end
            return Result::Status.new('Secrets secured in vault: Make sure to save the vault password securely.')
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
          completion
        ].freeze

        # Main action procedure for plugin
        def execute_action
          action = options.get_next_command(ACTIONS)
          case action
          when :preset # Newer syntax
            return execute_preset
          when :open
            Environment.instance.open_editor(@option_config_file.to_s)
            return Result::Nothing.new
          when :documentation
            section = options.get_next_argument('private key file path', mandatory: false)
            section = "##{section}" unless section.nil?
            Environment.instance.open_uri("#{Info::DOC_URL}#{section}")
            return Result::Nothing.new
          when :genkey # Generate new rsa key
            private_key_path = options.get_next_argument('private key file path')
            private_key_length = options.get_next_argument('size in bits', mandatory: false, validation: Integer, default: OAuth::Jwt::DEFAULT_PRIV_KEY_LENGTH)
            OAuth::Jwt.generate_rsa_private_key(path: private_key_path, length: private_key_length)
            return Result::Status.new("Generated #{private_key_length} bit RSA key: #{private_key_path}")
          when :pubkey # Get pub key
            private_key_pem = options.get_next_argument('private key PEM value')
            return Result::Text.new(OpenSSL::PKey::RSA.new(private_key_pem).public_key.to_s)
          when :remote_certificate
            cert_action = options.get_next_command(%i[chain only name])
            remote_url = options.get_next_argument('remote URL')
            remote_chain = Rest.remote_certificate_chain(remote_url, as_string: false)
            raise "No certificate found for #{remote_url}" unless remote_chain&.first
            case cert_action
            when :chain
              return Result::Text.new(remote_chain.map(&:to_pem).join("\n"))
            when :only
              return Result::Text.new(remote_chain.first.to_pem)
            when :name
              return Result::Text.new(remote_chain.first.subject.to_a.find{ |name, _, _| name == 'CN'}[1])
            end
          when :echo # Display the content of a value given on command line
            return Result.auto(options.get_next_argument('value', validation: nil))
          when :download
            file_url = options.get_next_argument('source URL').chomp
            file_dest = options.get_next_argument('file path', mandatory: false)
            file_dest = File.join(transfer.destination_folder(Transfer::Spec::DIRECTION_RECEIVE), file_url.gsub(%r{.*/}, '')) if file_dest.nil?
            Log.log.info("Downloading: #{file_url}")
            Rest.new(base_url: file_url).call(operation: 'GET', save_to_file: file_dest)
            return Result::Status.new("Saved to: #{file_dest}")
          when :tokens
            require 'aspera/api/node'
            case options.get_next_command(%i{flush list show})
            when :flush
              return Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
            when :list
              return Result::ObjectList.new(OAuth::Factory.instance.persisted_tokens)
            when :show
              data = OAuth::Factory.instance.get_token_info(options.instance_identifier)
              raise Cli::Error, 'Unknown identifier' if data.nil?
              return Result::SingleObject.new(data)
            end
          when :plugins
            case options.get_next_command(%i[list create])
            when :list
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
              return Result::ObjectList.new(result, fields: %w[plugin detect wizard path])
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
                          return Result::Status.new('You called plugin #{plugin_name}')
                        end
                      end
                    end
                  end
                end
              END_OF_PLUGIN_CODE
              File.write(plugin_file, content)
              return Result::Status.new("Created #{plugin_file}")
            end
          when :detect, :wizard
            # Interactive mode
            options.ask_missing_mandatory = true
            # Detect plugins by url and optional query
            apps = @wizard.identify_plugins_for_url.freeze
            return Result::ObjectList.new(apps) if action.eql?(:detect)
            return @wizard.find(apps)
          when :coffee
            return Result::Image.new(COFFEE_IMAGE_URL)
          when :image
            return Result::Image.new(options.get_next_argument('image URI or blob'))
          when :ascp
            execute_action_ascp
          when :sync
            SyncActions.declare_options(options)
            case options.get_next_command(%i[spec admin translate])
            when :spec
              builder = Schema::Documentation.new(TerminalFormatter, Sync::Operations::CONF_SCHEMA, include_option: true).build
              return Result::ObjectList.new(builder.rows, fields: builder.columns)
            when :admin
              return execute_sync_admin
            when :translate
              return Result::SingleObject.new(Sync::Operations.args_to_conf(options.get_next_argument('async arguments', multiple: true)))
            else Aspera.error_unreachable_line
            end
          when :transferd
            execute_action_transferd
          when :gem
            case options.get_next_command(%i[path version name])
            when :path then return Result::Text.new(self.class.gem_src_root)
            when :version then return Result::Text.new(Cli::VERSION)
            when :name then return Result::Text.new(Info::GEM_NAME)
            else Aspera.error_unreachable_line
            end
          when :folder
            return Result::Text.new(@main_folder)
          when :file
            return Result::Text.new(@option_config_file)
          when :email_test
            send_email_template(email_template_default: EMAIL_TEST_TEMPLATE)
            return Result::Nothing.new
          when :smtp_settings
            return Result::SingleObject.new(email_settings)
          when :proxy_check
            # Ensure fpac was provided
            options.get_option(:fpac, mandatory: true)
            server_url = options.get_next_argument('server url')
            return Result::ValueList.new(@pac_exec.get_proxies(server_url), name: 'proxy')
          when :check_update
            return Result::SingleObject.new(check_gem_version)
          when :initdemo
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
            return Result::Status.new('Done')
          when :vault then execute_vault
          when :test then return execute_test
          when :platform
            return Result::Text.new(Environment.instance.architecture)
          when :completion
            return execute_completion
          else Aspera.error_unreachable_line
          end
        end

        # Generate shell completion
        # @return [Result] completion result
        def execute_completion
          shell_type = options.get_next_command(%i[bash])
          case shell_type
          when :bash
            if options.get_next_argument('', multiple: true, mandatory: false).nil?
              Plugins::Factory.instance.plugin_list.each{ |p| puts p}
            else
              Log.log.warn('only first level completion so far')
            end
            Process.exit(0)
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

        # @return [Hash] result of execution of vault command
        def execute_vault
          command = options.get_next_command(%i[info list show create delete password])
          case command
          when :info
            return Result::SingleObject.new(vault.info)
          when :list
            # , fields: %w(label url username password description)
            return Result::ObjectList.new(vault.list)
          when :show
            return Result::SingleObject.new(vault.get(label: options.get_next_argument('label')))
          when :create
            vault.set(options.get_next_argument('info', validation: Hash).symbolize_keys)
            return Result::Status.new('Secret added')
          when :delete
            label_to_delete = options.get_next_argument('label')
            vault.delete(label: label_to_delete)
            return Result::Status.new("Secret deleted: #{label_to_delete}")
          when :password
            Aspera.assert(vault.respond_to?(:change_password), 'Vault does not support password change')
            vault.change_password(options.get_next_argument('new_password'))
            return Result::Status.new('Vault password updated')
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

        # Lookup the corresponding secret for the given URL and usernames
        # @param url      [String] Server URL
        # @param username [String] Username
        # @return [String, nil] Secret if found
        def lookup_secret(url:, username:)
          secret = options.get_option(:secret)
          if secret.eql?('PRESET')
            conf = presets.lookup_preset(url: url, username: username)
            if conf.is_a?(Hash)
              Log.log.debug{"Found preset #{conf} with URL and username"}
              secret = conf['password']
            end
          end
          return secret
        end
        # Folder in $HOME for application files (~/.aspera)
        ASPERA_HOME_FOLDER_NAME = '.aspera'
        # Default config file name
        DEFAULT_CONFIG_FILENAME = 'config.yaml'
        # Used in execute_preset / execute_action to identify the global default keyword
        GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
        CONF_GLOBAL_SYM = :config
        # Folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME = 'plugins'
        PERSISTENCY_FOLDER = 'persist_store'
        FILE_LIST_FOLDER_NAME = 'filelists'
        REST_EXCEPTIONS_LOG_FILENAME = 'rest_exceptions.log'
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
        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
        COFFEE_IMAGE_URL = 'https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg'
        GEM_CHECK_DATE_FMT = '%Y/%m/%d'
        CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze
        SMTP_CONF_PARAMS = %i[server tls ssl port domain username password from_name from_email].freeze
        private_constant :ASPERA_HOME_FOLDER_NAME,
          :DEFAULT_CONFIG_FILENAME,
          :GLOBAL_DEFAULT_KEYWORD,
          :CONF_GLOBAL_SYM,
          :ASPERA_PLUGINS_FOLDERNAME,
          :PERSISTENCY_FOLDER,
          :FILE_LIST_FOLDER_NAME,
          :REST_EXCEPTIONS_LOG_FILENAME,
          :ASPERA,
          :SERVER_COMMAND,
          :TRANSFERD_APP_NAME,
          :DEMO_SERVER,
          :DEMO_PRESET,
          :EMAIL_TEST_TEMPLATE,
          :EXTEND_PRESET,
          :EXTEND_VAULT,
          :DEFAULT_CHECK_NEW_VERSION_DAYS,
          :COFFEE_IMAGE_URL,
          :GEM_CHECK_DATE_FMT,
          :CONF_OVERVIEW_KEYS,
          :SMTP_CONF_PARAMS
      end
    end
  end
end
