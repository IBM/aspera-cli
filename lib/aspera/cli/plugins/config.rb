# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/extended_value'
require 'aspera/cli/version'
require 'aspera/cli/formatter'
require 'aspera/cli/info'
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
require 'aspera/aoc'
require 'aspera/rest'
require 'xmlsimple'
require 'base64'
require 'net/smtp'
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
        CONF_PLUGIN_SYM = :config # Plugins::Config.name.split('::').last.downcase.to_sym
        CONF_GLOBAL_SYM = :config
        # default redirect for AoC web auth
        DEFAULT_REDIRECT = 'http://localhost:12345'
        # folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME = 'plugins'
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
        EXTV_INCLUDE_PRESETS = :incps
        EXTV_PRESET = :preset
        EXTV_VAULT = :vault
        PRESET_DIG_SEPARATOR = '.'
        DEFAULT_CHECK_NEW_VERSION_DAYS = 7
        DEFAULT_PRIV_KEY_FILENAME = 'aspera_aoc_key' # pragma: allowlist secret
        DEFAULT_PRIVKEY_LENGTH = 4096
        COFFEE_IMAGE = 'https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg'
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
          :EXTV_INCLUDE_PRESETS,
          :EXTV_PRESET,
          :EXTV_VAULT,
          :DEFAULT_CHECK_NEW_VERSION_DAYS,
          :DEFAULT_PRIV_KEY_FILENAME,
          :SERVER_COMMAND,
          :PRESET_DIG_SEPARATOR,
          :COFFEE_IMAGE
        def initialize(env, params)
          raise 'env and params must be Hash' unless env.is_a?(Hash) && params.is_a?(Hash)
          raise 'missing param' unless %i[name help version gem].sort.eql?(params.keys.sort)
          super(env)
          @info = params
          @main_folder = default_app_main_folder
          @plugins = {}
          @plugin_lookup_folders = []
          @use_plugin_defaults = true
          @config_presets = nil
          @connect_versions = nil
          @vault = nil
          @conf_file_default = File.join(@main_folder, DEFAULT_CONFIG_FILENAME)
          @option_config_file = @conf_file_default
          @pac_exec = nil
          @sdk_default_location = false
          Log.log.debug{"#{@info[:name]} folder: #{@main_folder}"}
          # set folder for FASP SDK
          add_plugin_lookup_folder(self.class.gem_plugins_folder)
          add_plugin_lookup_folder(File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME))
          # do file parameter first
          options.declare(:config_file, "Read parameters from file in YAML format, current=#{@option_config_file}", handler: {o: self, m: :option_config_file})
          options.parse_options!
          # read correct file (set @config_presets)
          read_config_file
          # add preset handler (needed for smtp)
          ExtendedValue.instance.set_handler(EXTV_PRESET, lambda{|v|preset_by_name(v)})
          ExtendedValue.instance.set_handler(EXTV_INCLUDE_PRESETS, lambda{|v|expanded_with_preset_includes(v)})
          ExtendedValue.instance.set_handler(EXTV_VAULT, lambda{|v|vault_value(v)})
          # load defaults before it can be overridden
          add_plugin_default_preset(CONF_GLOBAL_SYM)
          options.parse_options!
          options.declare(:no_default, 'Do not load default configuration for plugin', values: :none, short: 'N') { @use_plugin_defaults = false }
          options.declare(:override, 'Wizard: override existing value', values: :bool, default: :no)
          options.declare(:use_generic_client, 'Wizard: AoC: use global or org specific jwt client id', values: :bool, default: true)
          options.declare(:default, 'Wizard: set as default configuration for specified plugin (also: update)', values: :bool, default: true)
          options.declare(:test_mode, 'Wizard: skip private key check step', values: :bool, default: false)
          options.declare(:preset, 'Load the named option preset from current config file', short: 'P', handler: {o: self, m: :option_preset})
          options.declare(:pkeypath, 'Wizard: path to private key for JWT')
          options.declare(:ascp_path, 'Path to ascp', handler: {o: Fasp::Installation.instance, m: :ascp_path})
          options.declare(:use_product, 'Use ascp from specified product', handler: {o: self, m: :option_use_product})
          options.declare(:smtp, 'SMTP configuration', types: Hash)
          options.declare(:fpac, 'Proxy auto configuration script')
          options.declare(:proxy_credentials, 'HTTP proxy credentials (Array with user and password)')
          options.declare(:secret, 'Secret for access keys')
          options.declare(:vault, 'Vault for secrets')
          options.declare(:vault_password, 'Vault password')
          options.declare(:sdk_url, 'URL to get SDK', default: TRANSFER_SDK_ARCHIVE_URL)
          options.declare(:sdk_folder, 'SDK folder path', handler: {o: Fasp::Installation.instance, m: :sdk_folder})
          options.declare(:notif_to, 'Email recipient for notification of transfers')
          options.declare(:notif_template, 'Email ERB template for notification of transfers')
          options.declare(:version_check_days, 'Period in days to check new version (zero to disable)', coerce: Integer, default: DEFAULT_CHECK_NEW_VERSION_DAYS)
          options.declare(:plugin_folder, 'Folder where to find additional plugins', handler: {o: self, m: :option_plugin_folder})
          options.parse_options!
          # Check SDK folder is set or not, for compatibility, we check in two places
          sdk_folder = Fasp::Installation.instance.sdk_folder rescue nil
          if sdk_folder.nil?
            @sdk_default_location = true
            Log.log.debug('SDK folder is not set, checking default')
            # new location
            sdk_folder = default_app_main_folder(app_name: APP_NAME_SDK)
            Log.log.debug{"checking: #{sdk_folder}"}
            if !Dir.exist?(sdk_folder)
              Log.log.debug{"not exists: #{sdk_folder}"}
              # former location
              former_sdk_folder = File.join(default_app_main_folder, APP_NAME_SDK)
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
            raise CliBadArgument, 'proxy credentials shall be an array (#{proxy_creds.class})' unless proxy_creds.is_a?(Array)
            raise CliBadArgument, 'proxy credentials shall have two elements (#{proxy_creds.length})' unless proxy_creds.length.eql?(2)
            @pac_exec.proxy_user = Rest.proxy_user = proxy_creds[0]
            @pac_exec.proxy_pass = Rest.proxy_pass = proxy_creds[1]
          end
        end

        # env var name to override the app's main folder
        # default main folder is $HOME/<vendor main app folder>/<program name>
        def conf_dir_env_var
          return "#{@info[:name]}_home".upcase
        end

        # return product family folder (~/.aspera)
        def module_family_folder
          user_home_folder = Dir.home
          raise CliError, "Home folder does not exist: #{user_home_folder}. Check your user environment." unless Dir.exist?(user_home_folder)
          return File.join(user_home_folder, ASPERA_HOME_FOLDER_NAME)
        end

        # return product config folder (~/.aspera/<name>)
        def default_app_main_folder(app_name: nil)
          app_name = @info[:name] if app_name.nil?
          # find out application main folder
          app_folder = ENV[conf_dir_env_var]
          # if env var undefined or empty
          app_folder = File.join(module_family_folder, app_name) if app_folder.nil? || app_folder.empty?
          return app_folder
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
          Log.log.info{"check days: #{delay_days}"}
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
          last_check_days =
            begin
              current_date - Date.strptime(last_check_array.first, '%Y/%m/%d')
            rescue StandardError
              # negative value will force check
              -1
            end
          Log.log.debug{"days elapsed: #{last_check_days}"}
          return if last_check_days < delay_days
          # generate timestamp
          last_check_array[0] = current_date.strftime('%Y/%m/%d')
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

        private

        class << self
          def generate_rsa_private_key(path:, length: DEFAULT_PRIVKEY_LENGTH)
            require 'openssl'
            priv_key = OpenSSL::PKey::RSA.new(length)
            File.write(path, priv_key.to_s)
            File.write(path + '.pub', priv_key.public_key.to_s)
            Environment.restrict_file_access(path)
            Environment.restrict_file_access(path + '.pub')
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
        end

        # set parameter and value in global config
        # creates one if none already created
        # @return preset name that contains global default
        def set_global_default(key, value)
          # get default preset if it exists
          global_default_preset_name = get_plugin_default_config_name(CONF_GLOBAL_SYM)
          if global_default_preset_name.nil?
            global_default_preset_name = CONF_PRESET_GLOBAL
            @config_presets[CONF_PRESET_DEFAULT] ||= {}
            @config_presets[CONF_PRESET_DEFAULT][CONF_GLOBAL_SYM.to_s] = global_default_preset_name
          end
          @config_presets[global_default_preset_name] ||= {}
          @config_presets[global_default_preset_name][key.to_s] = value
          formatter.display_status("Updated: #{global_default_preset_name}: #{key} <- #{value}")
          save_presets_to_config_file
          return global_default_preset_name
        end

        public

        # $HOME/.aspera/`program_name`
        attr_reader :main_folder
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
          case current
          when Hash then return expanded_with_preset_includes(current, include_path)
          when String then return ExtendedValue.instance.evaluate(current)
          else return current
          end
        end

        # @return the hash value with 'incps' keys expanded to include other presets
        # @param hash_val
        # @param include_path to avoid inclusion loop
        def expanded_with_preset_includes(hash_val, include_path=[])
          raise CliError, "#{EXTV_INCLUDE_PRESETS} requires a Hash, have #{hash_val.class}" unless hash_val.is_a?(Hash)
          if hash_val.key?(EXTV_INCLUDE_PRESETS)
            memory = hash_val.clone
            includes = memory[EXTV_INCLUDE_PRESETS]
            memory.delete(EXTV_INCLUDE_PRESETS)
            hash_val = {}
            raise "#{EXTV_INCLUDE_PRESETS} must be an Array" unless includes.is_a?(Array)
            raise "#{EXTV_INCLUDE_PRESETS} must contain names" unless includes.map(&:class).uniq.eql?([String])
            includes.each do |preset_name|
              hash_val.merge!(preset_by_name(preset_name, include_path))
            end
            hash_val.merge!(memory)
          end
          return hash_val
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

        # read config file and validate format
        def read_config_file
          Log.log.debug{"config file is: #{@option_config_file}".red}
          # files search for configuration, by default the one given by user
          search_files = [@option_config_file]
          # find first existing file (or nil)
          conf_file_to_load = search_files.find{|f| File.exist?(f)}
          # require save if old version of file
          save_required = false
          # if no file found, create default config
          if conf_file_to_load.nil?
            Log.log.warn{"No config file found. Creating empty configuration file: #{@option_config_file}"}
            @config_presets = {CONF_PRESET_CONFIG => {CONF_PRESET_VERSION => @info[:version]}}
          else
            Log.log.debug{"loading #{@option_config_file}"}
            @config_presets = YAML.load_file(conf_file_to_load)
          end
          files_to_copy = []
          Log.log.debug{"Available_presets: #{@config_presets}"}
          raise 'Expecting YAML Hash' unless @config_presets.is_a?(Hash)
          # check there is at least the config section
          if !@config_presets.key?(CONF_PRESET_CONFIG)
            raise "Cannot find key: #{CONF_PRESET_CONFIG}"
          end
          version = @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]
          if version.nil?
            raise 'No version found in config section.'
          end
          Log.log.debug{"conf version: #{version}"}
          # if there are any conversion needed, those happen here.
          # Place new compatibility code here
          if save_required
            Log.log.warn('Saving automatic conversion.')
            @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION] = @info[:version]
            save_presets_to_config_file
            Log.log.warn('Copying referenced files')
            files_to_copy.each do |file|
              FileUtils.cp(file, @main_folder)
              Log.log.warn{"..#{file} -> #{@main_folder}"}
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
        def identify_plugin_for_url(url, check_only: nil)
          check_only = check_only.to_sym unless check_only.nil?
          plugins.each do |plugin_name_sym, plugin_info|
            # no detection for internal plugin
            next if plugin_name_sym.eql?(CONF_PLUGIN_SYM)
            next if check_only && !check_only.eql?(plugin_name_sym)
            # load plugin class
            require plugin_info[:require_stanza]
            c = self.class.plugin_class(plugin_name_sym)
            # requires detection method
            next unless c.respond_to?(:detect)
            current_url = url
            detection_info = nil
            # first try : direct
            begin
              detection_info = c.detect(current_url)
            rescue OpenSSL::SSL::SSLError => e
              Log.log.warn(e.message)
              Log.log.warn('Use option --insecure=yes to allow unchecked certificate') if e.message.include?('cert')
            rescue StandardError => e
              Log.log.debug{"Cannot detect #{plugin_name_sym} : #{e.class}/#{e.message}"}
            end
            # second try : is there a redirect ?
            if detection_info.nil?
              begin
                # TODO: check if redirect ?
                new_url = Rest.new(base_url: url).call(operation: 'GET', subpath: '', redirect_max: 1)[:http].uri.to_s
                unless url.eql?(new_url)
                  detection_info = c.detect(new_url)
                  current_url = new_url
                end
              rescue StandardError => e
                Log.log.debug{"Cannot detect #{plugin_name_sym} : #{e.message}"}
              end
            end
            # if there is a redirect, then the detector can override the url.
            return {product: plugin_name_sym, url: current_url}.merge(detection_info) unless detection_info.nil?
          end # loop
          raise "No known application found at #{url}"
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
            preset_name = set_global_default(:ascp_path, ascp_path)
            return Main.result_status("Saved to default global preset #{preset_name}")
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
              preset_name = set_global_default(:ascp_path, Fasp::Installation.instance.path(:ascp))
              return Main.result_status("Saved to default global preset #{preset_name}")
            end
          when :install
            # reset to default location, if older default was used
            Fasp::Installation.instance.sdk_folder = default_app_main_folder(app_name: APP_NAME_SDK) if @sdk_default_location
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
          # those operations require existing option
          raise "no such preset: #{name}" if PRESET_EXIST_ACTIONS.include?(action) && !@config_presets.key?(name)
          selected_preset = @config_presets[name]
          case action
          when :list
            return {type: :value_list, data: @config_presets.keys, name: 'name'}
          when :overview
            return {type: :object_list, data: Formatter.flatten_config_overview(@config_presets)}
          when :show
            raise "no such config: #{name}" if selected_preset.nil?
            return {type: :single_object, data: selected_preset}
          when :delete
            @config_presets.delete(name)
            save_presets_to_config_file
            return Main.result_status("Deleted: #{name}")
          when :get
            param_name = options.get_next_argument('parameter name')
            value = selected_preset[param_name]
            raise "no such option in preset #{name} : #{param_name}" if value.nil?
            case value
            when Numeric, String then return {type: :text, data: ExtendedValue.instance.evaluate(value.to_s)}
            end
            return {type: :single_object, data: value}
          when :unset
            param_name = options.get_next_argument('parameter name')
            selected_preset.delete(param_name)
            save_presets_to_config_file
            return Main.result_status("Removed: #{name}: #{param_name}")
          when :set
            param_name = options.get_next_argument('parameter name')
            param_value = options.get_next_argument('parameter value')
            param_name = Manager.option_line_to_name(param_name)
            if !@config_presets.key?(name)
              Log.log.debug{"no such config name: #{name}, initializing"}
              selected_preset = @config_presets[name] = {}
            end
            if selected_preset.key?(param_name)
              Log.log.warn{"overwriting value: #{selected_preset[param_name]}"}
            end
            selected_preset[param_name] = param_value
            save_presets_to_config_file
            return Main.result_status("Updated: #{name}: #{param_name} <- #{param_value}")
          when :initialize
            config_value = options.get_next_argument('extended value', type: Hash)
            if @config_presets.key?(name)
              Log.log.warn{"configuration already exists: #{name}, overwriting"}
            end
            @config_presets[name] = config_value
            save_presets_to_config_file
            return Main.result_status("Modified: #{@option_config_file}")
          when :update
            #  get unprocessed options
            unprocessed_options = options.get_options_table
            Log.log.debug{"opts=#{unprocessed_options}"}
            @config_presets[name] ||= {}
            @config_presets[name].merge!(unprocessed_options)
            # fix bug in 4.4 (creating key "true" in "default" preset)
            @config_presets[CONF_PRESET_DEFAULT].delete(true) if @config_presets[CONF_PRESET_DEFAULT].is_a?(Hash)
            save_presets_to_config_file
            return Main.result_status("Updated: #{name}")
          when :ask
            options.ask_missing_mandatory = :yes
            @config_presets[name] ||= {}
            options.get_next_argument('option names', expected: :multiple).each do |option_name|
              option_value = options.get_interactive(:option, option_name)
              @config_presets[name][option_name] = option_value
            end
            save_presets_to_config_file
            return Main.result_status("Updated: #{name}")
          when :lookup
            BasicAuthPlugin.register_options(@agents)
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
          gem
          plugin
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
          vault].freeze

        # "config" plugin
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
            section = '#' + section unless section.nil?
            OpenApplication.instance.uri("#{@info[:help]}#{section}")
            return Main.result_nothing
          when :genkey # generate new rsa key
            private_key_path = options.get_next_argument('private key file path')
            private_key_length = options.get_next_argument('size in bits', mandatory: false) || DEFAULT_PRIVKEY_LENGTH
            self.class.generate_rsa_private_key(path: private_key_path, length: private_key_length)
            return Main.result_status('Generated key: ' + private_key_path)
          when :echo # display the content of a value given on command line
            result = {type: :other_struct, data: options.get_next_argument('value')}
            # special for csv
            result[:type] = :object_list if result[:data].is_a?(Array) && result[:data].first.is_a?(Hash)
            result[:type] = :single_object if result[:data].is_a?(Hash)
            return result
          when :flush_tokens
            deleted_files = Oauth.flush_tokens
            return {type: :value_list, data: deleted_files, name: 'file'}
          when :plugin
            case options.get_next_command(%i[list create])
            when :list
              return {type: :object_list, data: @plugins.keys.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } }, fields: %w[plugin path]}
            when :create
              plugin_name = options.get_next_argument('name', expected: :single).downcase
              plugin_folder = options.get_next_argument('folder', expected: :single, mandatory: false) || File.join(@main_folder, ASPERA_PLUGINS_FOLDERNAME)
              plugin_file = File.join(plugin_folder, "#{plugin_name}.rb")
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
          when :wizard
            # interactive mode
            options.ask_missing_mandatory = true
            # register url option
            BasicAuthPlugin.register_options(@agents)
            params = {}
            # get from option, or ask
            params[:instance_url] = options.get_option(:url, mandatory: true)
            # check it is a well formatted url: starts with scheme
            if !params[:instance_url].match?(%r{^[a-z]{1,6}://})
              new_url = "https://#{params[:instance_url]}"
              Log.log.warn("URL #{params[:instance_url]} does not start with a scheme, using #{new_url}")
              params[:instance_url] = new_url
            end
            # allow user to tell the preset name
            params[:preset_name] = options.get_option(:id)
            # allow user to specify type of application (symbol)
            identification = identify_plugin_for_url(params[:instance_url], check_only: value_or_query(allowed_types: String))
            Log.log.debug{"Detected: #{identification}"}
            formatter.display_status("Detected: #{identification[:name]} at #{identification[:url]}".bold)
            # we detected application (not set by user)
            params[:plugin_sym] = identification[:product]
            # update the url option
            params[:instance_url] = identification[:url]
            options.set_option(:url, params[:instance_url])
            # instantiate plugin: command line options are known and wizard can be called
            plugin_instance = self.class.plugin_class(params[:plugin_sym]).new(@agents.merge({skip_basic_auth_options: true}))
            raise CliBadArgument, "Detected: #{params[:plugin_sym]}, no wizard available for this application" unless plugin_instance.respond_to?(:wizard)
            # get default preset name if not set by user
            params[:prepare] = true
            plugin_instance.send(:wizard, params)
            params[:prepare] = false

            if params[:need_private_key]
              # lets see if path to priv key is provided
              private_key_path = options.get_option(:pkeypath)
              # give a chance to provide
              if private_key_path.nil?
                formatter.display_status('Please provide path to your private RSA key, or empty to generate one:')
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
              params[:pub_key_pem] = OpenSSL::PKey::RSA.new(File.read(private_key_path)).public_key.to_s
              params[:private_key_path] = private_key_path
            end

            formatter.display_status("Preparing preset: #{params[:preset_name]}")
            # init defaults if necessary
            @config_presets[CONF_PRESET_DEFAULT] ||= {}
            option_override = options.get_option(:override, mandatory: true)
            raise CliError, "A default configuration already exists for plugin '#{params[:plugin_sym]}' (use --override=yes or --default=no)" \
              if !option_override && options.get_option(:default, mandatory: true) && @config_presets[CONF_PRESET_DEFAULT].key?(params[:plugin_sym])
            raise CliError, "Preset already exists: #{params[:preset_name]}  (use --override=yes or --id=<name>)" \
              if !option_override && @config_presets.key?(params[:preset_name])
            wizard_result = plugin_instance.send(:wizard, params)
            Log.log.debug{"wizard result: #{wizard_result}"}
            raise "Internal error: missing keys in wizard result: #{wizard_result.keys}" unless %i[preset_value test_args].eql?(wizard_result.keys.sort)
            @config_presets[params[:preset_name]] = wizard_result[:preset_value].stringify_keys
            params[:test_args] = wizard_result[:test_args]
            if options.get_option(:default, mandatory: true)
              formatter.display_status("Setting config preset as default for #{params[:plugin_sym]}")
              @config_presets[CONF_PRESET_DEFAULT][params[:plugin_sym].to_s] = params[:preset_name]
            else
              params[:test_args] = "-P#{params[:preset_name]} #{params[:test_args]}"
            end
            formatter.display_status('Saving config file.')
            save_presets_to_config_file
            return Main.result_status("Done.\nYou can test with:\n#{@info[:name]} #{params[:test_args]}")
          when :detect
            # need url / username
            BasicAuthPlugin.register_options(@agents)
            return {type: :single_object, data: identify_plugin_for_url(options.get_option(:url, mandatory: true))}
          when :coffee
            if OpenApplication.instance.url_method.eql?(:text)
              require 'aspera/preview/terminal'
              return Main.result_status(Preview::Terminal.build(Rest.new(base_url: COFFEE_IMAGE).read('')[:http].body, reserved_lines: 3))
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
                'url'                                    => 'ssh://' + DEMO + '.asperasoft.com:33001',
                'username'                               => ASPERA,
                'ssAP'.downcase.reverse + 'drow'.reverse => DEMO + ASPERA
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
            save_presets_to_config_file
            return Main.result_status('Done')
          when :vault then execute_vault
          else raise 'INTERNAL ERROR: wrong case'
          end
        end

        # @return email server setting with defaults if not defined
        def email_settings
          smtp = options.get_option(:smtp, mandatory: true, allowed_types: [Hash])
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

        # create a clean binding (ruby variable environment)
        def empty_binding
          Kernel.binding
        end

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
          template_binding = empty_binding
          # add variables to binding
          values.each do |k, v|
            raise "key (#{k.class}) must be Symbol" unless k.is_a?(Symbol)
            template_binding.local_variable_set(k, v)
          end
          # execute template
          msg_with_headers = ERB.new(notif_template).result(template_binding)
          Log.dump(:msg_with_headers, msg_with_headers)
          smtp = Net::SMTP.new(mail_conf[:server], mail_conf[:port])
          smtp.enable_starttls if mail_conf[:tls]
          smtp.enable_tls if mail_conf[:ssl]
          smtp.start(*start_options) do |smtp_session|
            smtp_session.send_message(msg_with_headers, values[:from_email], values[:to])
          end
        end

        def save_presets_to_config_file
          raise 'no configuration loaded' if @config_presets.nil?
          FileUtils.mkdir_p(@main_folder) unless Dir.exist?(@main_folder)
          Log.log.debug{"Writing #{@option_config_file}"}
          File.write(@option_config_file, @config_presets.to_yaml)
          Environment.restrict_file_access(@main_folder)
          Environment.restrict_file_access(@option_config_file)
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

        ALLOWED_KEYS = %i[password username description].freeze
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

        def vault_value(name)
          m = name.match(/^(.+)\.(.+)$/)
          raise 'vault name shall match <name>.<param>' if m.nil?
          info = vault.get(label: m[1])
          # raise "no such vault entry: #{m[1]}" if info.nil?
          value = info[m[2].to_sym]
          raise "no such entry value: #{m[2]}" if value.nil?
          return value
        end

        def vault
          if @vault.nil?
            vault_info = options.get_option(:vault) || {'type' => 'file', 'name' => 'vault.bin'}
            vault_password = options.get_option(:vault_password, mandatory: true)
            raise 'vault must be Hash' unless vault_info.is_a?(Hash)
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
              when Environment::OS_WINDOWS, Environment::OS_LINUX, Environment::OS_AIX
                raise 'not implemented'
              else raise 'Error, OS not supported'
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
            return v if conf_url.eql?(url) && v['username'].eql?(username)
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
