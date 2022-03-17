# frozen_string_literal: true
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/extended_value'
require 'aspera/cli/version'
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
      class Config < Plugin
        # folder in $HOME for application files (config, cache)
        ASPERA_HOME_FOLDER_NAME='.aspera'
        # default config file
        DEFAULT_CONFIG_FILENAME = 'config.yaml'
        # reserved preset names
        CONF_PRESET_CONFIG='config'
        CONF_PRESET_VERSION='version'
        CONF_PRESET_DEFAULT='default'
        CONF_PRESET_GLOBAL='global_common_defaults'
        CONF_PRESET_SECRETS='default_secrets' # pragma: allowlist secret
        CONF_PLUGIN_SYM = :config # Plugins::Config.name.split('::').last.downcase.to_sym
        CONF_GLOBAL_SYM = :config
        # old tool name
        PROGRAM_NAME_V1 = 'aslmcli'
        PROGRAM_NAME_V2 = 'mlia'
        # default redirect for AoC web auth
        DEFAULT_REDIRECT='http://localhost:12345'
        # folder containing custom plugins in user's config folder
        ASPERA_PLUGINS_FOLDERNAME='plugins'
        RUBY_FILE_EXT='.rb'
        AOC_COMMAND_V1='files'
        AOC_COMMAND_V2='aspera'
        AOC_COMMAND_V3='aoc'
        AOC_COMMAND_CURRENT=AOC_COMMAND_V3
        SERVER_COMMAND='server'
        CONNECT_WEB_URL = 'https://d3gcli72yxqn2z.cloudfront.net/connect'
        CONNECT_VERSIONS = 'connectversions.js'
        TRANSFER_SDK_ARCHIVE_URL = 'https://ibm.biz/aspera_transfer_sdk'
        DEMO='demo'
        DEMO_SERVER_PRESET='demoserver'
        AOC_PATH_API_CLIENTS='admin/api-clients'
        EMAIL_TEST_TEMPLATE=<<~END_OF_TEMPLATE
          From: <%=from_name%> <<%=from_email%>>
          To: <<%=to%>>
          Subject: Amelia email test

          It worked !
        END_OF_TEMPLATE
        # special extended values
        EXTV_INCLUDE_PRESETS=:incps
        EXTV_PRESET=:preset
        PRESET_DIG_SEPARATOR='.'
        DEFAULT_CHECK_NEW_VERSION_DAYS=7
        DEFAULT_PRIV_KEY_FILENAME='aspera_aoc_key' # pragma: allowlist secret
        DEFAULT_PRIVKEY_LENGTH=4096
        private_constant :DEFAULT_CONFIG_FILENAME,:CONF_PRESET_CONFIG,:CONF_PRESET_VERSION,:CONF_PRESET_DEFAULT,
        :CONF_PRESET_GLOBAL,:PROGRAM_NAME_V1,:PROGRAM_NAME_V2,:DEFAULT_REDIRECT,:ASPERA_PLUGINS_FOLDERNAME,
        :RUBY_FILE_EXT,:AOC_COMMAND_V1,:AOC_COMMAND_V2,:AOC_COMMAND_V3,:AOC_COMMAND_CURRENT,:DEMO,
        :TRANSFER_SDK_ARCHIVE_URL,:AOC_PATH_API_CLIENTS,:DEMO_SERVER_PRESET,:EMAIL_TEST_TEMPLATE,:EXTV_INCLUDE_PRESETS,
        :EXTV_PRESET,:DEFAULT_CHECK_NEW_VERSION_DAYS,:DEFAULT_PRIV_KEY_FILENAME,:SERVER_COMMAND,:CONF_PRESET_SECRETS,
        :PRESET_DIG_SEPARATOR
        def initialize(env,params)
          raise 'env and params must be Hash' unless env.is_a?(Hash) && params.is_a?(Hash)
          raise 'missing param' unless [:name,:help,:version,:gem].sort.eql?(params.keys.sort)
          super(env)
          @info=params
          @main_folder=default_app_main_folder
          @plugins={}
          @plugin_lookup_folders=[]
          @use_plugin_defaults=true
          @config_presets=nil
          @connect_versions=nil
          @vault=nil
          @conf_file_default=File.join(@main_folder,DEFAULT_CONFIG_FILENAME)
          @option_config_file=@conf_file_default
          @pac_exec=nil
          Log.log.debug("#{@info[:name]} folder: #{@main_folder}")
          # set folder for FASP SDK
          add_plugin_lookup_folder(self.class.gem_plugins_folder)
          add_plugin_lookup_folder(File.join(@main_folder,ASPERA_PLUGINS_FOLDERNAME))
          # do file parameter first
          options.set_obj_attr(:config_file,self,:option_config_file)
          options.add_opt_simple(:config_file,"read parameters from file in YAML format, current=#{@option_config_file}")
          options.parse_options!
          # read correct file
          read_config_file
          # add preset handler (needed for smtp)
          ExtendedValue.instance.set_handler(EXTV_PRESET,:reader,lambda{|v|preset_by_name(v)})
          ExtendedValue.instance.set_handler(EXTV_INCLUDE_PRESETS,:decoder,lambda{|v|expanded_with_preset_includes(v)})
          # load defaults before it can be overriden
          add_plugin_default_preset(CONF_GLOBAL_SYM)
          options.parse_options!
          options.set_obj_attr(:ascp_path,Fasp::Installation.instance,:ascp_path)
          options.set_obj_attr(:sdk_folder,Fasp::Installation.instance,:sdk_folder)
          options.set_obj_attr(:use_product,self,:option_use_product)
          options.set_obj_attr(:preset,self,:option_preset)
          options.set_obj_attr(:plugin_folder,self,:option_plugin_folder)
          options.add_opt_switch(:no_default,'-N','do not load default configuration for plugin') { @use_plugin_defaults=false }
          options.add_opt_boolean(:override,'Wizard: override existing value')
          options.add_opt_boolean(:use_generic_client,'Wizard: AoC: use global or org specific jwt client id')
          options.add_opt_boolean(:default,'Wizard: set as default configuration for specified plugin (also: update)')
          options.add_opt_boolean(:test_mode,'Wizard: skip private key check step')
          options.add_opt_simple(:preset,'-PVALUE','load the named option preset from current config file')
          options.add_opt_simple(:pkeypath,'Wizard: path to private key for JWT')
          options.add_opt_simple(:ascp_path,'path to ascp')
          options.add_opt_simple(:use_product,'use ascp from specified product')
          options.add_opt_simple(:smtp,'smtp configuration (extended value: hash)')
          options.add_opt_simple(:fpac,'proxy auto configuration script')
          options.add_opt_simple(:secret,'default secret')
          options.add_opt_simple(:secrets,'secret vault')
          options.add_opt_simple(:sdk_url,'URL to get SDK')
          options.add_opt_simple(:sdk_folder,'SDK folder path')
          options.add_opt_simple(:notif_to,'email recipient for notification of transfers')
          options.add_opt_simple(:notif_template,'email ERB template for notification of transfers')
          options.add_opt_simple(:version_check_days,Integer,'period in days to check new version (zero to disable)')
          options.add_opt_simple(:plugin_folder,'folder where to find additional plugins')
          options.set_option(:use_generic_client,true)
          options.set_option(:test_mode,false)
          options.set_option(:default,true)
          options.set_option(:version_check_days,DEFAULT_CHECK_NEW_VERSION_DAYS)
          options.set_option(:sdk_url,TRANSFER_SDK_ARCHIVE_URL)
          options.set_option(:sdk_folder,File.join(@main_folder,'sdk'))
          options.set_option(:override,:no)
          options.parse_options!
          pac_script=options.get_option(:fpac,:optional)
          # create PAC executor
          @pac_exec=Aspera::ProxyAutoConfig.new(pac_script).register_uri_generic unless pac_script.nil?
        end

        # env var name to override the app's main folder
        # default main folder is $HOME/<vendor main app folder>/<program name>
        def conf_dir_env_var
          return "#{@info[:name]}_home".upcase
        end

        def default_app_main_folder
          # find out application main folder
          app_folder=ENV[conf_dir_env_var]
          # if env var undefined or empty
          if app_folder.nil? || app_folder.empty?
            user_home_folder=Dir.home
            raise CliError,"Home folder does not exist: #{user_home_folder}. Check your user environment or use #{conf_dir_env_var}." unless Dir.exist?(user_home_folder)
            app_folder=File.join(user_home_folder,ASPERA_HOME_FOLDER_NAME,@info[:name])
          end
          return app_folder
        end

        def check_gem_version
          latest_version=begin
            Rest.new(base_url: 'https://rubygems.org/api/v1').read("versions/#{@info[:gem]}/latest.json")[:data]['version']
          rescue StandardError
            Log.log.warn('Could not retrieve latest gem version on rubygems.')
            '0'
          end
          if Gem::Version.new(Environment.ruby_version) < Gem::Version.new(RUBY_FUTURE_MINIMUM_VERSION)
            Log.log.warn("Note that a future version will require Ruby version #{RUBY_FUTURE_MINIMUM_VERSION} at minimum, you are using #{Environment.ruby_version}")
          end
          return {name: @info[:gem], current: Aspera::Cli::VERSION, latest: latest_version, need_update: Gem::Version.new(Aspera::Cli::VERSION) < Gem::Version.new(latest_version)}
        end

        def periodic_check_newer_gem_version
          # get verification period
          delay_days=options.get_option(:version_check_days,:mandatory)
          Log.log.info("check days: #{delay_days}")
          # check only if not zero day
          return if delay_days.eql?(0)
          # get last date from persistency
          last_check_array=[]
          check_date_persist=PersistencyActionOnce.new(
          manager: persistency,
          data:    last_check_array,
          id:      'version_last_check')
          # get persisted date or nil
          current_date=Date.today
          last_check_days = begin
            current_date-Date.strptime(last_check_array.first, '%Y/%m/%d')
          rescue StandardError
            # negative value will force check
            -1
          end
          Log.log.debug("days elapsed: #{last_check_days}")
          return if last_check_days < delay_days
          # generate timestamp
          last_check_array[0]=current_date.strftime('%Y/%m/%d')
          check_date_persist.save
          # compare this version and the one on internet
          check_data=check_gem_version
          Log.log.warn("A new version is available: #{check_data[:latest]}. You have #{check_data[:current]}. Upgrade with: gem update #{check_data[:name]}") if check_data[:need_update]
        end

        # retrieve structure from cloud (CDN) with all versions available
        def connect_versions
          if @connect_versions.nil?
            api_connect_cdn=Rest.new({base_url: CONNECT_WEB_URL})
            javascript=api_connect_cdn.call({operation: 'GET',subpath: CONNECT_VERSIONS})
            # get result on one line
            connect_versions_javascript=javascript[:http].body.gsub(/\r?\n\s*/,'')
            Log.log.debug("javascript=[\n#{connect_versions_javascript}\n]")
            # get javascript object only
            found=connect_versions_javascript.match(/^.*? = (.*);/)
            raise CliError,'Problen when getting connect versions from internet' if found.nil?
            alldata=JSON.parse(found[1])
            @connect_versions=alldata['entries']
          end
          return @connect_versions
        end

        # loads default parameters of plugin if no -P parameter
        # and if there is a section defined for the plugin in the "default" section
        # try to find: conffile[conffile["default"][plugin_str]]
        # @param plugin_name_sym : symbol for plugin name
        def add_plugin_default_preset(plugin_name_sym)
          default_config_name=get_plugin_default_config_name(plugin_name_sym)
          Log.log.debug("add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}")
          options.add_option_preset(preset_by_name(default_config_name),:unshift) unless default_config_name.nil?
          return nil
        end

        private

        def generate_rsa_private_key(private_key_path,length)
          require 'openssl'
          priv_key = OpenSSL::PKey::RSA.new(length)
          File.write(private_key_path,priv_key.to_s)
          File.write(private_key_path+'.pub',priv_key.public_key.to_s)
          nil
        end

        class << self
          # folder containing plugins in the gem's main folder
          def gem_plugins_folder
            File.dirname(File.expand_path(__FILE__))
          end

          # name of englobin module
          # @return "Aspera::Cli::Plugins"
          def module_full_name
            return Module.nesting[2].to_s
          end

          # @return main folder where code is, i.e. .../lib
          # go up as many times as englobing modules (not counting class, as it is a file)
          def gem_src_root
            File.expand_path(module_full_name.gsub('::','/').gsub(%r{[^/]+},'..'),gem_plugins_folder)
          end

          # instanciate a plugin
          # plugins must be Capitalized
          def plugin_class(plugin_name_sym)
            # Module.nesting[2] is Aspera::Cli::Plugins
            return Object.const_get("#{module_full_name}::#{plugin_name_sym.to_s.capitalize}")
          end

          def flatten_all_config(t)
            r=[]
            t.each do |k,v|
              v.each do |kk,vv|
                r.push({'config'=>k,'parameter'=>kk,'value'=>vv})
              end
            end
            return r
          end
        end

        # set parameter and value in global config
        # creates one if none already created
        # @return preset name that contains global default
        def set_global_default(key,value)
          # get default preset if it exists
          global_default_preset_name=get_plugin_default_config_name(CONF_GLOBAL_SYM)
          if global_default_preset_name.nil?
            global_default_preset_name=CONF_PRESET_GLOBAL
            @config_presets[CONF_PRESET_DEFAULT]||={}
            @config_presets[CONF_PRESET_DEFAULT][CONF_GLOBAL_SYM.to_s]=global_default_preset_name
          end
          @config_presets[global_default_preset_name]||={}
          @config_presets[global_default_preset_name][key.to_s]=value
          self.format.display_status("Updated: #{global_default_preset_name}: #{key} <- #{value}")
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
          raise CliError,'loop in include' if include_path.include?(config_name)
          include_path=include_path.clone # avoid messing up if there are multiple branches
          current=@config_presets
          config_name.split(PRESET_DIG_SEPARATOR).each do |name|
            raise CliError,"not a Hash: #{include_path} (#{current.class})" unless current.is_a?(Hash)
            include_path.push(name)
            current=current[name]
            raise CliError,"no such config preset: #{include_path}" if nil?
          end
          case current
          when Hash then return expanded_with_preset_includes(current,include_path)
          when String then return ExtendedValue.instance.evaluate(current)
          else return current
          end
        end

        # @return the hash value with 'incps' keys expanced to include other presets
        # @param hash_val
        # @param include_path to avoid inclusion loop
        def expanded_with_preset_includes(hash_val, include_path=[])
          raise CliError,"#{EXTV_INCLUDE_PRESETS} requires a Hash, have #{hash_val.class}" unless hash_val.is_a?(Hash)
          if hash_val.has_key?(EXTV_INCLUDE_PRESETS)
            memory=hash_val.clone
            includes=memory[EXTV_INCLUDE_PRESETS]
            memory.delete(EXTV_INCLUDE_PRESETS)
            hash_val={}
            raise "#{EXTV_INCLUDE_PRESETS} must be an Array" unless includes.is_a?(Array)
            raise "#{EXTV_INCLUDE_PRESETS} must contain names" unless includes.map(&:class).uniq.eql?([String])
            includes.each do |preset_name|
              hash_val.merge!(preset_by_name(preset_name,include_path))
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

        def convert_preset_path(old_name,new_name,files_to_copy)
          old_subpath=File.join('',ASPERA_HOME_FOLDER_NAME,old_name,'')
          new_subpath=File.join('',ASPERA_HOME_FOLDER_NAME,new_name,'')
          # convert possible keys located in config folder
          @config_presets.values.select{|p|p.is_a?(Hash)}.each do |preset|
            preset.values.select{|v|v.is_a?(String) and v.include?(old_subpath)}.each do |value|
              old_val=value.clone
              included_path=File.expand_path(old_val.gsub(/^@file:/,''))
              files_to_copy.push(included_path) unless files_to_copy.include?(included_path) || !File.exist?(included_path)
              value.gsub!(old_subpath,new_subpath)
              Log.log.warn("Converted config value: #{old_val} -> #{value}")
            end
          end
        end

        def convert_preset_plugin_name(old_name,new_name)
          default_preset=@config_presets[CONF_PRESET_DEFAULT]
          return unless default_preset.is_a?(Hash) && default_preset.has_key?(old_name)
          default_preset[new_name]=default_preset[old_name]
          default_preset.delete(old_name)
          Log.log.warn("Converted plugin default: #{old_name} -> #{new_name}")
        end

        # read config file and validate format
        # tries to convert from older version if possible and required
        def read_config_file
          begin
            Log.log.debug("config file is: #{@option_config_file}".red)
            conf_file_v1=File.join(Dir.home,ASPERA_HOME_FOLDER_NAME,PROGRAM_NAME_V1,DEFAULT_CONFIG_FILENAME)
            conf_file_v2=File.join(Dir.home,ASPERA_HOME_FOLDER_NAME,PROGRAM_NAME_V2,DEFAULT_CONFIG_FILENAME)
            # files search for configuration, by default the one given by user
            search_files=[@option_config_file]
            # if default file, then also look for older versions
            search_files.push(conf_file_v2,conf_file_v1) if @option_config_file.eql?(@conf_file_default)
            # find first existing file (or nil)
            conf_file_to_load=search_files.select{|f| File.exist?(f)}.first
            # require save if old version of file
            save_required= !@option_config_file.eql?(conf_file_to_load)
            # if no file found, create default config
            if conf_file_to_load.nil?
              Log.log.warn("No config file found. Creating empty configuration file: #{@option_config_file}")
              @config_presets={CONF_PRESET_CONFIG=>{CONF_PRESET_VERSION=>@info[:version]}}
            else
              Log.log.debug("loading #{@option_config_file}")
              @config_presets=YAML.load_file(conf_file_to_load)
            end
            files_to_copy=[]
            Log.log.debug("Available_presets: #{@config_presets}")
            raise 'Expecting YAML Hash' unless @config_presets.is_a?(Hash)
            # check there is at least the config section
            if !@config_presets.has_key?(CONF_PRESET_CONFIG)
              raise "Cannot find key: #{CONF_PRESET_CONFIG}"
            end
            version=@config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]
            if version.nil?
              raise 'No version found in config section.'
            end
            # oldest compatible conf file format, update to latest version when an incompatible change is made
            # check compatibility of version of conf file
            config_tested_version='0.4.5'
            if Gem::Version.new(version) < Gem::Version.new(config_tested_version)
              raise "Unsupported config file version #{version}. Expecting min version #{config_tested_version}"
            end
            config_tested_version='0.6.15'
            if Gem::Version.new(version) < Gem::Version.new(config_tested_version)
              convert_preset_plugin_name(AOC_COMMAND_V1,AOC_COMMAND_V2)
              version=@config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]=config_tested_version
              save_required=true
            end
            config_tested_version='0.8.10'
            if Gem::Version.new(version) <= Gem::Version.new(config_tested_version)
              convert_preset_path(PROGRAM_NAME_V1,PROGRAM_NAME_V2,files_to_copy)
              version=@config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]=config_tested_version
              save_required=true
            end
            config_tested_version='1.0'
            if Gem::Version.new(version) <= Gem::Version.new(config_tested_version)
              convert_preset_plugin_name(AOC_COMMAND_V2,AOC_COMMAND_V3)
              convert_preset_path(PROGRAM_NAME_V2,@info[:name],files_to_copy)
              version=@config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]=config_tested_version
              save_required=true
            end
            Log.log.debug("conf version: #{version}")
            # Place new compatibility code here
            if save_required
              Log.log.warn('Saving automatic conversion.')
              @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]=@info[:version]
              save_presets_to_config_file
              Log.log.warn('Copying referenced files')
              files_to_copy.each do |file|
                FileUtils.cp(file,@main_folder)
                Log.log.warn("..#{file} -> #{@main_folder}")
              end
            end
          rescue Psych::SyntaxError => e
            Log.log.error('YAML error in config file')
            raise e
          rescue StandardError => e
            Log.log.debug("-> #{e}")
            new_name="#{@option_config_file}.pre#{@info[:version]}.manual_conversion_needed"
            File.rename(@option_config_file,new_name)
            Log.log.warn("Renamed config file to #{new_name}.")
            Log.log.warn('Manual Conversion is required. Next time, a new empty file will be created.')
            raise CliError,e.to_s
          end
        end

        # find plugins in defined paths
        def add_plugins_from_lookup_folders
          @plugin_lookup_folders.each do |folder|
            next unless File.directory?(folder)
            #TODO: add gem root to load path ? and require short folder ?
            #$LOAD_PATH.push(folder) if i[:add_path]
            Dir.entries(folder).select{|file|file.end_with?(RUBY_FILE_EXT)}.each do |source|
              add_plugin_info(File.join(folder,source))
            end
          end
        end

        def add_plugin_lookup_folder(folder)
          @plugin_lookup_folders.unshift(folder)
        end

        def add_plugin_info(path)
          raise "ERROR: plugin path must end with #{RUBY_FILE_EXT}" if !path.end_with?(RUBY_FILE_EXT)
          plugin_symbol=File.basename(path,RUBY_FILE_EXT).to_sym
          req=path.gsub(/#{RUBY_FILE_EXT}$/,'')
          if @plugins.has_key?(plugin_symbol)
            Log.log.warn("skipping plugin already registered: #{plugin_symbol}")
            return
          end
          @plugins[plugin_symbol]={source: path,require_stanza: req}
        end

        def identify_plugin_for_url(url)
          plugins.each do |plugin_name_sym,plugin_info|
            # no detection for internal plugin
            next if plugin_name_sym.eql?(CONF_PLUGIN_SYM)
            # load plugin class
            require plugin_info[:require_stanza]
            c=self.class.plugin_class(plugin_name_sym)
            next unless c.respond_to?(:detect)
            current_url=url
            detection_info=nil
            # first try : direct
            begin
              detection_info=c.detect(current_url)
            rescue StandardError => e
              Log.log.debug("Cannot detect #{plugin_name_sym} : #{e.message}")
            end
            # second try : is there a redirect ?
            if detection_info.nil?
              begin
                # TODO: check if redirect ?
                new_url=Rest.new(base_url: url).call(operation: 'GET',subpath: '',redirect_max: 1)[:http].uri.to_s
                unless url.eql?(new_url)
                  detection_info=c.detect(new_url)
                  current_url=new_url
                end
              rescue StandardError => e
                Log.log.debug("Cannot detect #{plugin_name_sym} : #{e.message}")
              end
            end
            return detection_info.merge(product: plugin_name_sym, url: current_url) unless detection_info.nil?
          end # loop
          raise "No known application found at #{url}"
        end

        def execute_connect_action
          command=options.get_next_command([:list,:info,:version])
          if [:info,:version].include?(command)
            connect_id=options.get_next_argument('id or title')
            one_res=connect_versions.select{|i|i['id'].eql?(connect_id) || i['title'].eql?(connect_id)}.first
            raise CliNoSuchId.new(:connect,connect_id) if one_res.nil?
          end
          case command
          when :list
            return {type: :object_list, data: connect_versions, fields: ['id','title','version']}
          when :info # shows files used
            one_res.delete('links')
            return {type: :single_object, data: one_res}
          when :version # shows files used
            all_links=one_res['links']
            command=options.get_next_command([:list,:download,:open])
            if [:download,:open].include?(command)
              link_title=options.get_next_argument('title or rel')
              one_link=all_links.select {|i| i['title'].eql?(link_title) or i['rel'].eql?(link_title)}.first
              raise 'no such value' if one_link.nil?
            end
            case command
            when :list # shows files used
              return {type: :object_list, data: all_links}
            when :download
              folder_dest=transfer.destination_folder(Fasp::TransferSpec::DIRECTION_RECEIVE)
              #folder_dest=self.options.get_next_argument('destination folder')
              api_connect_cdn=Rest.new({base_url: CONNECT_WEB_URL})
              fileurl = one_link['href']
              filename=fileurl.gsub(%r{.*/},'')
              api_connect_cdn.call({operation: 'GET',subpath: fileurl,save_to_file: File.join(folder_dest,filename)})
              return Main.result_status("Downloaded: #{filename}")
            when :open
              OpenApplication.instance.uri(one_link['href'])
              return Main.result_status("Opened: #{one_link['href']}")
            end
          end
        end

        def execute_action_ascp
          command=options.get_next_command([:connect,:use,:show,:products,:info,:install,:spec,:errors])
          case command
          when :connect
            return execute_connect_action
          when :use
            ascp_path=options.get_next_argument('path to ascp')
            ascp_version=Fasp::Installation.instance.get_ascp_version(ascp_path)
            self.format.display_status("ascp version: #{ascp_version}")
            preset_name=set_global_default(:ascp_path,ascp_path)
            return Main.result_status("Saved to default global preset #{preset_name}")
          when :show # shows files used
            return {type: :status, data: Fasp::Installation.instance.path(:ascp)}
          when :info # shows files used
            data=Fasp::Installation::FILES.each_with_object({}) do |v,m|
              m[v.to_s]=Fasp::Installation.instance.path(v) rescue 'Not Found'
            end
            # read PATHs from ascp directly, and pvcl modules as well
            Open3.popen3(Fasp::Installation.instance.path(:ascp),'-DDL-') do |_stdin, _stdout, stderr, thread|
              last_line=''
              while (line=stderr.gets)
                line.chomp!
                last_line=line
                case line
                when %r{^DBG Path ([^ ]+) (dir|file) +: (.*)$} then data[Regexp.last_match(1)]=Regexp.last_match(3)
                when %r{^DBG Added module group:"([^"]+)" name:"([^"]+)", version:"([^"]+)" interface:"([^"]+)"$} then data[Regexp.last_match(2)]=Regexp.last_match(4)
                when %r{^DBG License result \(/license/(\S+)\): (.+)$} then data[Regexp.last_match(1)]=Regexp.last_match(2)
                when %r{^LOG (.+) version ([0-9.]+)$} then data['product_name']=Regexp.last_match(1);data['product_version']=Regexp.last_match(2)
                when %r{^LOG Initializing FASP version ([^,]+),} then data['ascp_version']=Regexp.last_match(1)
                end
              end
              if !thread.value.exitstatus.eql?(1) && !data.has_key?('root')
                raise last_line
              end
            end
            data['keypass']=Fasp::Installation.instance.bypass_pass
            return {type: :single_object, data: data}
          when :products
            command=options.get_next_command([:list,:use])
            case command
            when :list
              return {type: :object_list, data: Fasp::Installation.instance.installed_products, fields: ['name','app_root']}
            when :use
              default_product=options.get_next_argument('product name')
              Fasp::Installation.instance.use_ascp_from_product(default_product)
              preset_name=set_global_default(:ascp_path,Fasp::Installation.instance.path(:ascp))
              return Main.result_status("Saved to default global preset #{preset_name}")
            end
          when :install
            v=Fasp::Installation.instance.install_sdk(options.get_option(:sdk_url,:mandatory))
            return Main.result_status("Installed version #{v}")
          when :spec
            return {type: :object_list, data: Fasp::Parameters.man_table, fields: ['name','type',Fasp::Parameters::SUPPORTED_AGENTS_SHORT.map(&:to_s),'description'].flatten}
          when :errors
            error_data=[]
            Fasp::ERROR_INFO.each_pair do |code,prop|
              error_data.push(code: code, mnemonic: prop[:c], retry: prop[:r], info: prop[:a])
            end
            return {type: :object_list, data: error_data}
          end
          raise "unexpected case: #{command}"
        end

        # legacy actions available globally
        PRESET_GBL_ACTIONS=[:list,:overview].freeze
        # require existing preset
        PRESET_EXST_ACTIONS=[:show,:delete,:get,:unset].freeze
        # require id
        PRESET_INSTANCE_ACTIONS=[PRESET_EXST_ACTIONS,:initialize,:update,:ask,:set].flatten.freeze
        PRESET_ALL_ACTIONS=[PRESET_GBL_ACTIONS,PRESET_INSTANCE_ACTIONS].flatten.freeze

        def execute_file_action(action,config_name)
          action=options.get_next_command(PRESET_ALL_ACTIONS) if action.nil?
          config_name=instance_identifier() if config_name.nil? && PRESET_INSTANCE_ACTIONS.include?(action)
          # those operations require existing option
          raise "no such preset: #{config_name}" if PRESET_EXST_ACTIONS.include?(action) && !@config_presets.has_key?(config_name)
          selected_preset=@config_presets[config_name]
          case action
          when :list
            return {type: :value_list, data: @config_presets.keys, name: 'name'}
          when :overview
            return {type: :object_list, data: self.class.flatten_all_config(@config_presets)}
          when :show
            raise "no such config: #{config_name}" if selected_preset.nil?
            return {type: :single_object, data: selected_preset}
          when :delete
            @config_presets.delete(config_name)
            save_presets_to_config_file
            return Main.result_status("Deleted: #{config_name}")
          when :get
            param_name=options.get_next_argument('parameter name')
            value=selected_preset[param_name]
            raise "no such option in preset #{config_name} : #{param_name}" if value.nil?
            case value
            when Numeric,String then return {type: :text, data: ExtendedValue.instance.evaluate(value.to_s)}
            end
            return {type: :single_object, data: value}
          when :unset
            param_name=options.get_next_argument('parameter name')
            selected_preset.delete(param_name)
            save_presets_to_config_file
            return Main.result_status("Removed: #{config_name}: #{param_name}")
          when :set
            param_name=options.get_next_argument('parameter name')
            param_value=options.get_next_argument('parameter value')
            if !@config_presets.has_key?(config_name)
              Log.log.debug("no such config name: #{config_name}, initializing")
              selected_preset=@config_presets[config_name]={}
            end
            if selected_preset.has_key?(param_name)
              Log.log.warn("overwriting value: #{selected_preset[param_name]}")
            end
            selected_preset[param_name]=param_value
            save_presets_to_config_file
            return Main.result_status("Updated: #{config_name}: #{param_name} <- #{param_value}")
          when :initialize
            config_value=options.get_next_argument('extended value (Hash)')
            if @config_presets.has_key?(config_name)
              Log.log.warn("configuration already exists: #{config_name}, overwriting")
            end
            @config_presets[config_name]=config_value
            save_presets_to_config_file
            return Main.result_status("Modified: #{@option_config_file}")
          when :update
            #  get unprocessed options
            theopts=options.get_options_table
            Log.log.debug("opts=#{theopts}")
            @config_presets[config_name]||={}
            @config_presets[config_name].merge!(theopts)
            # fix bug in 4.4 (creating key "true" in "default" preset)
            @config_presets[CONF_PRESET_DEFAULT].delete(true) if @config_presets[CONF_PRESET_DEFAULT].is_a?(Hash)
            save_presets_to_config_file
            return Main.result_status("Updated: #{config_name}")
          when :ask
            options.ask_missing_mandatory=:yes
            @config_presets[config_name]||={}
            options.get_next_argument('option names',:multiple).each do |optionname|
              option_value=options.get_interactive(:option,optionname)
              @config_presets[config_name][optionname]=option_value
            end
            save_presets_to_config_file
            return Main.result_status("Updated: #{config_name}")
          end
        end

        ACTIONS=[PRESET_GBL_ACTIONS,:id,:preset,:open,:documentation,:genkey,:gem,:plugin,:flush_tokens,:echo,:wizard,:export_to_cli,:detect,:coffee,:ascp,:email_test,
                 :smtp_settings,:proxy_check,:folder,:file,:check_update,:initdemo,:vault].flatten.freeze

        # "config" plugin
        def execute_action
          action=options.get_next_command(ACTIONS)
          case action
          when *PRESET_GBL_ACTIONS # older syntax
            return execute_file_action(action,nil)
          when :id # older syntax
            return execute_file_action(nil,options.get_next_argument('config name'))
          when :preset # newer syntax
            return execute_file_action(nil,nil)
          when :open
            OpenApplication.instance.uri(@option_config_file.to_s) #file://
            return Main.result_nothing
          when :documentation
            section=options.get_next_argument('private key file path',:single,:optional)
            section='#'+section unless section.nil?
            OpenApplication.instance.uri("#{@info[:help]}#{section}")
            return Main.result_nothing
          when :genkey # generate new rsa key
            private_key_path=options.get_next_argument('private key file path')
            generate_rsa_private_key(private_key_path,DEFAULT_PRIVKEY_LENGTH)
            return Main.result_status('Generated key: '+private_key_path)
          when :echo # display the content of a value given on command line
            result={type: :other_struct, data: options.get_next_argument('value')}
            # special for csv
            result[:type]=:object_list if result[:data].is_a?(Array) && result[:data].first.is_a?(Hash)
            return result
          when :flush_tokens
            deleted_files=Oauth.flush_tokens
            return {type: :value_list, data: deleted_files, name: 'file'}
          when :plugin
            case options.get_next_command([:list,:create])
            when :list
              return {type: :object_list, data: @plugins.keys.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } }, fields: ['plugin','path']}
            when :create
              plugin_name=options.get_next_argument('name',:single,:mandatory).downcase
              plugin_folder=options.get_next_argument('folder',:single,:optional) || File.join(@main_folder,ASPERA_PLUGINS_FOLDERNAME)
              plugin_file=File.join(plugin_folder,"#{plugin_name}.rb")
              content=<<~END_OF_PLUGIN_CODE
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
              File.write(plugin_file,content)
              return Main.result_status("Created #{plugin_file}")
            end
          when :wizard
            # interactive mode
            options.ask_missing_mandatory=true
            # register url option
            BasicAuthPlugin.new(@agents.merge(skip_option_header: true))
            # get from option, or ask
            instance_url=options.get_option(:url,:mandatory)
            # allow user to tell the preset name
            preset_name=options.get_option(:id,:optional)
            appli=identify_plugin_for_url(instance_url)
            plugin_name='<replace per app>'
            test_args='<replace per app>'
            case appli[:product]
            when :aoc
              self.format.display_status('Detected: Aspera on Cloud'.bold)
              plugin_name=AOC_COMMAND_CURRENT
              organization=AoC.parse_url(instance_url).first
              # if not defined by user, generate name
              preset_name=[appli[:product],organization].join('_') if preset_name.nil?
              self.format.display_status("Preparing preset: #{preset_name}")
              # init defaults if necessary
              @config_presets[CONF_PRESET_DEFAULT]||={}
              option_override=options.get_option(:override,:mandatory)
              option_default=options.get_option(:default,:mandatory)
              Log.log.error("override=#{option_override} -> #{option_override.class}")
              raise CliError,"A default configuration already exists for plugin '#{plugin_name}' (use --override=yes or --default=no)" if !option_override && option_default && @config_presets[CONF_PRESET_DEFAULT].has_key?(plugin_name)
              raise CliError,"Preset already exists: #{preset_name}  (use --override=yes or --id=<name>)" if !option_override && @config_presets.has_key?(preset_name)
              # lets see if path to priv key is provided
              private_key_path=options.get_option(:pkeypath,:optional)
              # give a chance to provide
              if private_key_path.nil?
                self.format.display_status('Please provide path to your private RSA key, or empty to generate one:')
                private_key_path=options.get_option(:pkeypath,:mandatory).to_s
              end
              # else generate path
              if private_key_path.empty?
                private_key_path=File.join(@main_folder,DEFAULT_PRIV_KEY_FILENAME)
              end
              if File.exist?(private_key_path)
                self.format.display_status('Using existing key:')
              else
                self.format.display_status("Generating #{DEFAULT_PRIVKEY_LENGTH} bit RSA key...")
                generate_rsa_private_key(private_key_path,DEFAULT_PRIVKEY_LENGTH)
                self.format.display_status('Created:')
              end
              self.format.display_status(private_key_path)
              pub_key_pem=OpenSSL::PKey::RSA.new(File.read(private_key_path)).public_key.to_s
              # declare command line options for AoC
              require 'aspera/cli/plugins/aoc'
              # make username mandatory for jwt, this triggers interactive input
              options.get_option(:username,:mandatory)
              # instanciate AoC plugin, so that command line options are known
              aoc_api=self.class.plugin_class(plugin_name).new(@agents.merge({skip_basic_auth_options: true, private_key_path: private_key_path})).aoc_api
              auto_set_pub_key=false
              auto_set_jwt=false
              use_browser_authentication=false
              if options.get_option(:use_generic_client)
                self.format.display_status('Using global client_id.')
                self.format.display_status('Please Login to your Aspera on Cloud instance.'.red)
                self.format.display_status('Navigate to your "Account Settings"'.red)
                self.format.display_status('Check or update the value of "Public Key" to be:'.red.blink)
                self.format.display_status(pub_key_pem.to_s)
                if !options.get_option(:test_mode)
                  self.format.display_status('Once updated or validated, press enter.')
                  OpenApplication.instance.uri(instance_url)
                  $stdin.gets
                end
              else
                self.format.display_status('Using organization specific client_id.')
                if options.get_option(:client_id,:optional).nil? || options.get_option(:client_secret,:optional).nil?
                  self.format.display_status('Please login to your Aspera on Cloud instance.'.red)
                  self.format.display_status('Go to: Apps->Admin->Organization->Integrations')
                  self.format.display_status('Create or check if there is an existing integration named:')
                  self.format.display_status("- name: #{@info[:name]}")
                  self.format.display_status("- redirect uri: #{DEFAULT_REDIRECT}")
                  self.format.display_status('- origin: localhost')
                  self.format.display_status('Once created or identified,')
                  self.format.display_status('Please enter:'.red)
                end
                OpenApplication.instance.uri("#{instance_url}/#{AOC_PATH_API_CLIENTS}")
                options.get_option(:client_id,:mandatory)
                options.get_option(:client_secret,:mandatory)
                use_browser_authentication=true
              end
              if use_browser_authentication
                self.format.display_status('We will use web authentication to bootstrap.')
                auto_set_pub_key=true
                auto_set_jwt=true
                aoc_api.oauth.params[:crtype]=:web
                aoc_api.oauth.params[:web][:redirect_uri]=DEFAULT_REDIRECT
                aoc_api.oauth.params[:scope]=AoC::SCOPE_FILES_ADMIN
              end
              myself=aoc_api.read('self')[:data]
              if auto_set_pub_key
                raise CliError,'Public key is already set in profile (use --override=yes)' unless myself['public_key'].empty? || option_override
                self.format.display_status('Updating profile with new key')
                aoc_api.update("users/#{myself['id']}",{'public_key'=>pub_key_pem})
              end
              if auto_set_jwt
                self.format.display_status('Enabling JWT for client')
                aoc_api.update("clients/#{options.get_option(:client_id)}",{'jwt_grant_enabled'=>true,'explicit_authorization_required'=>false})
              end
              self.format.display_status("Creating new config preset: #{preset_name}")
              @config_presets[preset_name]={
                :url.to_s           =>options.get_option(:url),
                :username.to_s      =>myself['email'],
                :auth.to_s          =>:jwt.to_s,
                :private_key.to_s   =>'@file:'+private_key_path
              }
              # set only if non nil
              [:client_id,:client_secret].each do |s|
                o=options.get_option(s)
                @config_presets[preset_name][s.to_s] = o unless o.nil?
              end
              test_args="#{plugin_name} user profile show"
            else
              raise CliBadArgument,"Supports only: aoc. Detected: #{appli}"
            end # product
            if option_default
              self.format.display_status("Setting config preset as default for #{plugin_name}")
              @config_presets[CONF_PRESET_DEFAULT][plugin_name]=preset_name
            else
              test_args="-P#{preset_name} #{test_args}"
            end
            self.format.display_status('Saving config file.')
            save_presets_to_config_file
            return Main.result_status("Done.\nYou can test with:\n#{@info[:name]} #{test_args}")
          when :export_to_cli
            self.format.display_status('Exporting: Aspera on Cloud')
            require 'aspera/cli/plugins/aoc'
            # need url / username
            add_plugin_default_preset(AOC_COMMAND_V3.to_sym)
            # instanciate AoC plugin
            self.class.plugin_class(AOC_COMMAND_CURRENT).new(@agents) # TODO: is this line needed ? get options ?
            url=options.get_option(:url,:mandatory)
            cli_conf_file=Fasp::Installation.instance.cli_conf_file
            data=JSON.parse(File.read(cli_conf_file))
            organization,instance_domain=AoC.parse_url(url)
            key_basename='org_'+organization+'.pem'
            key_file=File.join(File.dirname(File.dirname(cli_conf_file)),'etc',key_basename)
            File.write(key_file,options.get_option(:private_key,:mandatory))
            new_conf={
              'organization'       => organization,
              'hostname'           => [organization,instance_domain].join('.'),
              'privateKeyFilename' => key_basename,
              'username'           => options.get_option(:username,:mandatory)
            }
            new_conf['clientId']=options.get_option(:client_id,:optional)
            new_conf['clientSecret']=options.get_option(:client_secret,:optional)
            if new_conf['clientId'].nil?
              new_conf['clientId'],new_conf['clientSecret']=AoC.get_client_info()
            end
            entry=data['AoCAccounts'].select{|i|i['organization'].eql?(organization)}.first
            if entry.nil?
              data['AoCAccounts'].push(new_conf)
              self.format.display_status("Creating new aoc entry: #{organization}")
            else
              self.format.display_status("Updating existing aoc entry: #{organization}")
              entry.merge!(new_conf)
            end
            File.write(cli_conf_file,JSON.pretty_generate(data))
            return Main.result_status("Updated: #{cli_conf_file}")
          when :detect
            # need url / username
            BasicAuthPlugin.new(@agents)
            return {type: :single_object, data: identify_plugin_for_url(options.get_option(:url,:mandatory))}
          when :coffee
            OpenApplication.instance.uri('https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg')
            return Main.result_nothing
          when :ascp
            execute_action_ascp
          when :gem
            case options.get_next_command([:path,:version,:name])
            when :path then return Main.result_status(self.class.gem_src_root)
            when :version then return Main.result_status(Aspera::Cli::VERSION)
            when :name then return Main.result_status(@info[:gem])
            end
          when :folder
            return Main.result_status(@main_folder)
          when :file
            return Main.result_status(@option_config_file)
          when :email_test
            send_email_template({},EMAIL_TEST_TEMPLATE)
            return Main.result_nothing
          when :smtp_settings
            return {type: :single_object, data: email_settings}
          when :proxy_check
            # ensure fpac was provided
            options.get_option(:fpac,:mandatory)
            server_url=options.get_next_argument('server url')
            return Main.result_status(@pac_exec.find_proxy_for_url(server_url))
          when :check_update
            return {type: :single_object, data: check_gem_version}
          when :initdemo
            if @config_presets.has_key?(DEMO_SERVER_PRESET)
              Log.log.warn("Demo server preset already present: #{DEMO_SERVER_PRESET}")
            else
              Log.log.info("Creating Demo server preset: #{DEMO_SERVER_PRESET}")
              @config_presets[DEMO_SERVER_PRESET]=
{'url'=>'ssh://'+DEMO+'.asperasoft.com:33001','username'=>AOC_COMMAND_V2,'ssAP'.downcase.reverse+'drow'.reverse=>DEMO+AOC_COMMAND_V2}
            end
            @config_presets[CONF_PRESET_DEFAULT]||={}
            if @config_presets[CONF_PRESET_DEFAULT].has_key?(SERVER_COMMAND)
              Log.log.warn("Server default preset already set to: #{@config_presets[CONF_PRESET_DEFAULT][SERVER_COMMAND]}")
              Log.log.warn("Use #{DEMO_SERVER_PRESET} for demo: -P#{DEMO_SERVER_PRESET}") unless DEMO_SERVER_PRESET.eql?(@config_presets[CONF_PRESET_DEFAULT][SERVER_COMMAND])
            else
              @config_presets[CONF_PRESET_DEFAULT][SERVER_COMMAND]=DEMO_SERVER_PRESET
              Log.log.info("Setting server default preset to : #{DEMO_SERVER_PRESET}")
            end
            save_presets_to_config_file
            return Main.result_status('Done')
          when :vault
            command=options.get_next_command([:init,:list,:get,:set,:delete])
            case command
            when :init
              type=options.get_option(:value,:optional)
              case type
              when 'config',NilClass
                raise 'default secrets already exists' if @config_presets.has_key?(CONF_PRESET_SECRETS)
                @config_presets[CONF_PRESET_SECRETS]={}
                set_global_default(:secrets,"@preset:#{CONF_PRESET_SECRETS}")
              else raise 'no such vault type'
              end
              return Main.result_status('Done')
            when :list
              return {type: :object_list, data: vault.list}
            when :set
              # register url option
              BasicAuthPlugin.new(@agents.merge(skip_option_header: true))
              username=options.get_option(:username,:mandatory)
              url=options.get_option(:url,:mandatory)
              description=options.get_option(:value,:optional)
              secret=options.get_next_argument('secret')
              vault.set(username: username, url: url, description: description, secret: secret)
              save_presets_to_config_file if vault.is_a?(Keychain::EncryptedHash)
              return Main.result_status('Done')
            when :get
              # register url option
              BasicAuthPlugin.new(@agents.merge(skip_option_header: true))
              username=options.get_option(:username,:mandatory)
              url=options.get_option(:url,:optional)
              result=vault.get(username: username, url: url)
              return {type: :single_object, data: result}
            when :delete
              # register url option
              BasicAuthPlugin.new(@agents.merge(skip_option_header: true))
              username=options.get_option(:username,:mandatory)
              url=options.get_option(:url,:optional)
              vault.delete(username: username, url: url)
              return Main.result_status('Done')
            end
          else raise 'INTERNAL ERROR: wrong case'
          end
        end

        # @return email server setting with defaults if not defined
        def email_settings
          smtp=options.get_option(:smtp,:mandatory)
          # change string keys into symbol keys
          smtp=smtp.keys.each_with_object({}){|v,m|m[v.to_sym]=smtp[v];}
          # defaults
          smtp[:tls]||=true
          smtp[:port]||=smtp[:tls]?587:25
          smtp[:from_email]||=smtp[:username] if smtp.has_key?(:username)
          smtp[:from_name]||=smtp[:from_email].gsub(/@.*$/,'').gsub(/[^a-zA-Z]/,' ').capitalize if smtp.has_key?(:username)
          smtp[:domain]||=smtp[:from_email].gsub(/^.*@/,'') if smtp.has_key?(:from_email)
          # check minimum required
          [:server,:port,:domain].each do |n|
            raise "Missing smtp parameter: #{n}" unless smtp.has_key?(n)
          end
          Log.log.debug("smtp=#{smtp}")
          return smtp
        end

        # create a clean binding (ruby variable environment)
        def empty_binding
          Kernel.binding
        end

        def send_email_template(vars,email_template_default=nil)
          vars[:to]||=options.get_option(:notif_to,:mandatory)
          notif_template=options.get_option(:notif_template,email_template_default.nil? ? :mandatory : :optional) || email_template_default
          mail_conf=email_settings
          vars[:from_name]||=mail_conf[:from_name]
          vars[:from_email]||=mail_conf[:from_email]
          [:from_name,:from_email].each do |n|
            raise "Missing email parameter: #{n}" unless vars.has_key?(n)
          end
          start_options=[mail_conf[:domain]]
          start_options.push(mail_conf[:username],mail_conf[:password],:login) if mail_conf.has_key?(:username) && mail_conf.has_key?(:password)
          # create a binding with only variables defined in vars
          template_binding=empty_binding
          # add variables to binding
          vars.each do |k,v|
            raise "key (#{k.class}) must be Symbol" unless k.is_a?(Symbol)
            template_binding.local_variable_set(k,v)
          end
          # execute template
          msg_with_headers=ERB.new(notif_template).result(template_binding)
          Log.dump(:msg_with_headers,msg_with_headers)
          smtp = Net::SMTP.new(mail_conf[:server], mail_conf[:port])
          smtp.enable_starttls if mail_conf[:tls]
          smtp.start(*start_options) do |smtp_session|
            smtp_session.send_message(msg_with_headers, vars[:from_email], vars[:to])
          end
        end

        def save_presets_to_config_file
          raise 'no configuration loaded' if @config_presets.nil?
          FileUtils.mkdir_p(@main_folder) unless Dir.exist?(@main_folder)
          Log.log.debug("Writing #{@option_config_file}")
          File.write(@option_config_file,@config_presets.to_yaml)
        end

        # returns [String] name if config_presets has default
        # returns nil if there is no config or bypass default params
        def get_plugin_default_config_name(plugin_sym)
          raise 'internal error: config_presets shall be defined' if @config_presets.nil?
          if !@use_plugin_defaults
            Log.log.debug('skip default config')
            return nil
          end
          if @config_presets.has_key?(CONF_PRESET_DEFAULT) &&
          @config_presets[CONF_PRESET_DEFAULT].has_key?(plugin_sym.to_s)
            default_config_name=@config_presets[CONF_PRESET_DEFAULT][plugin_sym.to_s]
            if !@config_presets.has_key?(default_config_name)
              Log.log.error("Default config name [#{default_config_name}] specified for plugin [#{plugin_sym}], but it does not exist in config file.\nPlease fix the issue: either create preset with one parameter (#{@info[:name]} config id #{default_config_name} init @json:'{}') or remove default (#{@info[:name]} config id default remove #{plugin_sym}).")
            end
            raise CliError,"Config name [#{default_config_name}] must be a hash, check config file." if !@config_presets[default_config_name].is_a?(Hash)
            return default_config_name
          end
          return nil
        end # get_plugin_default_config_name

        def vault
          if @vault.nil?
            vault_info=options.get_option(:secrets,:optional)
            case vault_info
            when Hash
              @vault=Keychain::EncryptedHash.new(vault_info)
            when /^system/
              name=vault_info.start_with?('system:') ? vault_info[7..-1] : nil
              case Environment.os
              when Environment::OS_X
                @vault=Keychain::MacosSecurity.new(name)
              when Environment::OS_WINDOWS,Environment::OS_LINUX,Environment::OS_AIX
                raise 'not implemented'
              else raise 'Error'
              end
            when NilClass
              # keep nil
            else
              raise CliBadArgument,'secrets shall be Hash'
            end
          end
          raise 'No vault defined' if @vault.nil?
          @vault
        end

        def get_secret(options)
          raise 'options shall be Hash' unless options.is_a?(Hash)
          raise 'options shall have username' unless options.has_key?(:username)
          secret=self.options.get_option(:secret,:optional)
          if secret.nil?
            secret=vault.get(options) rescue nil
            # mandatory by default
            raise "please provide secret for #{options[:username]}" if secret.nil? && (options[:mandatory].nil? || options[:mandatory])
          end
          return secret
        end
      end
    end
  end
end
