require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/fasp/installation'
require 'asperalm/api_detector'
require 'xmlsimple'
require 'base64'

module Asperalm
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
        # old tool name
        OLD_PROGRAM_NAME = 'aslmcli'
        # default redirect for AoC web auth
        DEFAULT_REDIRECT='http://localhost:12345'
        # folder containing custom plugins in `main_folder`
        ASPERA_PLUGINS_FOLDERNAME='plugins'
        # folder containing plugins in the gem's main folder
        GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
        RUBY_FILE_EXT='.rb'
        OLD_AOC_COMMAND='files'
        NEW_AOC_COMMAND='aspera'

        private_constant :ASPERA_HOME_FOLDER_NAME,:DEFAULT_CONFIG_FILENAME,:CONF_PRESET_CONFIG,:CONF_PRESET_VERSION,:CONF_PRESET_DEFAULT,:OLD_PROGRAM_NAME,:DEFAULT_REDIRECT,:ASPERA_PLUGINS_FOLDERNAME,:GEM_PLUGINS_FOLDER,:RUBY_FILE_EXT,:OLD_AOC_COMMAND,:NEW_AOC_COMMAND
        def initialize(env,tool_name,gem_name,version)
          super(env)
          @plugins={}
          @plugin_lookup_folders=[]
          @use_plugin_defaults=true
          @config_presets=nil
          @program_version=version
          @gem_name=gem_name
          @tool_name=tool_name
          @main_folder=File.join(Dir.home,ASPERA_HOME_FOLDER_NAME,tool_name)
          @old_main_folder=File.join(Dir.home,ASPERA_HOME_FOLDER_NAME,OLD_PROGRAM_NAME)
          if Dir.exist?(@old_main_folder) and ! Dir.exist?(@main_folder)
            Log.log.warn("Detected former configuration folder, renaming: #{@old_main_folder} -> #{@main_folder}")
            FileUtils.mv(@old_main_folder, @main_folder)
          end
          @option_config_file=File.join(@main_folder,DEFAULT_CONFIG_FILENAME)
          @help_url='http://www.rubydoc.info/gems/'+@gem_name
          @gem_url='https://rubygems.org/gems/'+@gem_name
          add_plugin_lookup_folder(File.join(@main_folder,ASPERA_PLUGINS_FOLDERNAME))
          add_plugin_lookup_folder(File.join(Main.gem_root,GEM_PLUGINS_FOLDER))
          self.options.set_obj_attr(:override,self,:option_override,:no)
          self.options.set_obj_attr(:config_file,self,:option_config_file)
          self.options.add_opt_boolean(:override,"override existing value")
          self.options.add_opt_simple(:config_file,"read parameters from file in YAML format, current=#{@option_config_file}")
          self.options.add_opt_switch(:no_default,"-N","do not load default configuration for plugin") { @use_plugin_defaults=false }
          self.options.add_opt_boolean(:use_generic_client,'wizard: AoC: use global or org specific jwt client id')
          self.options.add_opt_simple(:pkeypath,"path to private key")
          self.options.set_option(:use_generic_client,true)
          self.options.parse_options!
        end

        # loads default parameters of plugin if no -P parameter
        # and if there is a section defined for the plugin in the "default" section
        # try to find: conffile[conffile["default"][plugin_str]]
        # @param plugin_name_sym : symbol for plugin name
        def add_plugin_default_preset(plugin_name_sym)
          default_config_name=get_plugin_default_config_name(plugin_name_sym)
          Log.log.debug("add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}")
          self.options.add_option_preset(preset_by_name(default_config_name),:unshift) unless default_config_name.nil?
          return nil
        end
        private

        def generate_new_key(private_key_path)
          require 'openssl'
          priv_key = OpenSSL::PKey::RSA.new(4096)
          File.write(private_key_path,priv_key.to_s)
          File.write(private_key_path+".pub",priv_key.public_key.to_s)
          nil
        end

        def self.flatten_all_config(t)
          r=[]
          t.each do |k,v|
            v.each do |kk,vv|
              r.push({"config"=>k,"parameter"=>kk,"value"=>vv})
            end
          end
          return r
        end

        public

        # $HOME/.aspera/`program_name`
        attr_reader :main_folder
        attr_reader :gem_url
        attr_reader :help_url
        attr_reader :plugins
        attr_accessor :option_override
        attr_accessor :option_config_file

        def preset_by_name(config_name)
          raise CliError,"no such config preset: #{config_name}" unless @config_presets.has_key?(config_name)
          return @config_presets[config_name]
        end

        # read config file and validate format
        # tries to cnvert if possible and required
        def read_config_file
          Log.log.debug("config file is: #{@option_config_file}".red)
          # oldest compatible conf file format, update to latest version when an incompatible change is made
          if !File.exist?(@option_config_file)
            Log.log.warn("No config file found. Creating empty configuration file: #{@option_config_file}")
            @config_presets={CONF_PRESET_CONFIG=>{CONF_PRESET_VERSION=>@program_version}}
            save_presets_to_config_file
            return nil
          end
          begin
            Log.log.debug "loading #{@option_config_file}"
            @config_presets=YAML.load_file(@option_config_file)
            Log.log.debug "Available_presets: #{@config_presets}"
            raise "Expecting YAML Hash" unless @config_presets.is_a?(Hash)
            # check there is at least the config section
            if !@config_presets.has_key?(CONF_PRESET_CONFIG)
              raise "Cannot find key: #{CONF_PRESET_CONFIG}"
            end
            version=@config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]
            if version.nil?
              raise "No version found in config section."
            end
            # check compatibility of version of conf file
            config_tested_version='0.4.5'
            if Gem::Version.new(version) < Gem::Version.new(config_tested_version)
              raise "Unsupported config file version #{version}. Expecting min version #{config_tested_version}"
            end
            save_required=false
            config_tested_version='0.6.14'
            if Gem::Version.new(version) <= Gem::Version.new(config_tested_version)
              if @config_presets[CONF_PRESET_DEFAULT].is_a?(Hash) and @config_presets[CONF_PRESET_DEFAULT].has_key?(OLD_AOC_COMMAND)
                @config_presets[CONF_PRESET_DEFAULT][NEW_AOC_COMMAND]=@config_presets[CONF_PRESET_DEFAULT][OLD_AOC_COMMAND]
                @config_presets[CONF_PRESET_DEFAULT].delete(OLD_AOC_COMMAND)
                Log.log.warn("Converted plugin default: #{OLD_AOC_COMMAND} -> #{NEW_AOC_COMMAND}")
                save_required=true
              end
            end
            config_tested_version='0.8.10'
            if Gem::Version.new(version) <= Gem::Version.new(config_tested_version)
              old_subpath=File.join('',ASPERA_HOME_FOLDER_NAME,OLD_PROGRAM_NAME,'')
              new_subpath=File.join('',ASPERA_HOME_FOLDER_NAME,@tool_name,'')
              # convert possible keys located in config folder
              @config_presets.values.select{|p|p.is_a?(Hash)}.each do |preset|
                preset.values.select{|v|v.is_a?(String) and v.include?(old_subpath)}.each do |value|
                  old_val=value.clone
                  value.gsub!(old_subpath,new_subpath)
                  Log.log.warn("Converted copnfig value: #{old_val} -> #{value}")
                  save_required=true
                end
              end
            end
            # Place new compatibility code here
            if save_required
              @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]=@program_version
              save_presets_to_config_file
              Log.log.warn("Saving automatic conversion.")
            end
          rescue => e
            Log.log.debug("-> #{e}")
            new_name="#{@option_config_file}.pre#{@program_version}.manual_conversion_needed"
            File.rename(@option_config_file,new_name)
            Log.log.warn("Renamed config file to #{new_name}.")
            Log.log.warn("Manual Conversion is required. Next time, a new empty file will be created.")
            raise CliError,e.to_s
          end
        end

        # find plugins in defined paths
        def add_plugins_from_lookup_folders
          @plugin_lookup_folders.each do |folder|
            if File.directory?(folder)
              #TODO: add gem root to load path ? and require short folder ?
              #$LOAD_PATH.push(folder) if i[:add_path]
              Dir.entries(folder).select{|file|file.end_with?(RUBY_FILE_EXT)}.each do |source|
                add_plugin_info(File.join(folder,source))
              end
            end
          end
        end

        def add_plugin_lookup_folder(folder)
          @plugin_lookup_folders.push(folder)
        end

        def add_plugin_info(path)
          raise "ERROR: plugin path must end with #{RUBY_FILE_EXT}" if !path.end_with?(RUBY_FILE_EXT)
          plugin_symbol=File.basename(path,RUBY_FILE_EXT).to_sym
          req=path.gsub(/#{RUBY_FILE_EXT}$/,'')
          if @plugins.has_key?(plugin_symbol)
            Log.log.warn("skipping plugin already registered: #{plugin_symbol}")
            return
          end
          @plugins[plugin_symbol]={:source=>path,:require_stanza=>req}
        end

        ACTIONS=[:gem_path, :genkey,:plugins,:flush_tokens,:list,:overview,:open,:echo,:id,:documentation,:wizard,:export_to_cli,:detect,:coffee]

        # "config" plugin
        def execute_action
          action=self.options.get_next_command(ACTIONS)
          case action
          when :id
            config_name=self.options.get_next_argument('config name')
            action=self.options.get_next_command([:show,:delete,:set,:unset,:initialize,:update,:ask])
            case action
            when :show
              raise "no such config: #{config_name}" unless @config_presets.has_key?(config_name)
              return {:type=>:single_object,:data=>@config_presets[config_name]}
            when :delete
              @config_presets.delete(config_name)
              save_presets_to_config_file
              return Main.result_status("deleted: #{config_name}")
            when :set
              param_name=self.options.get_next_argument('parameter name')
              param_value=self.options.get_next_argument('parameter value')
              if !@config_presets.has_key?(config_name)
                Log.log.debug("no such config name: #{config_name}, initializing")
                @config_presets[config_name]=Hash.new
              end
              if @config_presets[config_name].has_key?(param_name)
                Log.log.warn("overwriting value: #{@config_presets[config_name][param_name]}")
              end
              @config_presets[config_name][param_name]=param_value
              save_presets_to_config_file
              return Main.result_status("updated: #{config_name}: #{param_name} <- #{param_value}")
            when :unset
              param_name=self.options.get_next_argument('parameter name')
              if @config_presets.has_key?(config_name)
                @config_presets[config_name].delete(param_name)
                save_presets_to_config_file
              else
                Log.log.warn("no such parameter: #{param_name} (ignoring)")
              end
              return Main.result_status("removed: #{config_name}: #{param_name}")
            when :initialize
              config_value=self.options.get_next_argument('extended value (Hash)')
              if @config_presets.has_key?(config_name)
                Log.log.warn("configuration already exists: #{config_name}, overwriting")
              end
              @config_presets[config_name]=config_value
              save_presets_to_config_file
              return Main.result_status("modified: #{@option_config_file}")
            when :update
              #  TODO: when arguments are provided: --option=value, this creates an entry in the named configuration
              theopts=self.options.get_options_table
              Log.log.debug("opts=#{theopts}")
              @config_presets[config_name]={} if !@config_presets.has_key?(config_name)
              @config_presets[config_name].merge!(theopts)
              save_presets_to_config_file
              return Main.result_status("updated: #{config_name}")
            when :ask
              self.options.ask_missing_mandatory=:yes
              @config_presets[config_name]||={}
              self.options.get_next_argument('option names',:multiple).each do |optionname|
                option_value=self.options.get_interactive(:option,optionname)
                @config_presets[config_name][optionname]=option_value
              end
              save_presets_to_config_file
              return Main.result_status("updated: #{config_name}")
            end
          when :documentation
            OpenApplication.instance.uri(@help_url)
            return Main.result_nothing
          when :open
            OpenApplication.instance.uri("#{@option_config_file}") #file://
            return Main.result_nothing
          when :genkey # generate new rsa key
            private_key_path=self.options.get_next_argument('private key file path')
            generate_new_key(private_key_path)
            return Main.result_status('generated key: '+private_key_path)
          when :echo # display the content of a value given on command line
            result={:type=>:other_struct, :data=>self.options.get_next_argument("value")}
            # special for csv
            result[:type]=:object_list if result[:data].is_a?(Array) and result[:data].first.is_a?(Hash)
            return result
          when :flush_tokens
            deleted_files=Oauth.flush_tokens
            return {:type=>:value_list, :name=>'file',:data=>deleted_files}
          when :plugins
            return {:data => @plugins.keys.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :object_list }
          when :list
            return {:data => @config_presets.keys, :type => :value_list, :name => 'name'}
          when :overview
            return {:type=>:object_list,:data=>self.class.flatten_all_config(@config_presets)}
          when :wizard
            self.options.ask_missing_mandatory=true
            #self.options.set_option(:interactive,:yes)
            # register url option
            BasicAuthPlugin.new(@agents.merge(skip_option_header: true))
            instance_url=self.options.get_option(:url,:mandatory)
            appli=ApiDetector.discover_product(instance_url)
            case appli[:product]
            when :aoc
              self.format.display_status("Detected: Aspera on Cloud")
              organization,instance_domain=FilesApi.parse_url(instance_url)
              aspera_preset_name='aoc_'+organization
              self.format.display_status("Preparing preset: #{aspera_preset_name}")
              # init defaults if necessary
              @config_presets[CONF_PRESET_DEFAULT]||=Hash.new
              if !option_override
                raise CliError,"a default configuration already exists for plugin '#{NEW_AOC_COMMAND}' (use --override=yes)" if @config_presets[CONF_PRESET_DEFAULT].has_key?(NEW_AOC_COMMAND)
                raise CliError,"preset already exists: #{aspera_preset_name}  (use --override=yes)" if @config_presets.has_key?(aspera_preset_name)
              end
              # lets see if path to priv key is provided
              private_key_path=self.options.get_option(:pkeypath,:optional)
              # give a chance to provide
              if private_key_path.nil?
                self.format.display_status("Please provide path to your private RSA key, or empty to generate one:")
                private_key_path=self.options.get_option(:pkeypath,:mandatory).to_s
              end
              # else generate path
              if private_key_path.empty?
                private_key_path=File.join(@main_folder,'aspera_on_cloud_key')
              end
              if File.exist?(private_key_path)
                self.format.display_status("Using existing key:")
              else
                self.format.display_status("Generating key...")
                generate_new_key(private_key_path)
                self.format.display_status("Created:")
              end
              self.format.display_status("#{private_key_path}")
              pub_key_pem=OpenSSL::PKey::RSA.new(File.read(private_key_path)).public_key.to_s
              # define options
              require 'asperalm/cli/plugins/aspera'

              files_plugin=Plugins::Aspera.new(@agents.merge({skip_basic_auth_options: true}))

              self.options.set_option(:private_key,'@file:'+private_key_path)

              require_admin=false
              auto_set_pub_key=false
              auto_set_jwt=false
              use_browser_authentication=false

              if self.options.get_option(:use_generic_client)
                self.format.display_status("Using global client_id.")
                self.format.display_status("Please Login to your Aspera on Cloud instance.".red)
                self.format.display_status("Navigate to your \"Account Settings\"".red)
                self.format.display_status("Check or update the value of \"Public Key\" to be:".red.blink)
                self.format.display_status("#{pub_key_pem}")
                self.format.display_status("Once updated or validated, press enter.")
                OpenApplication.instance.uri(instance_url)
                STDIN.gets
              else
                self.format.display_status("Using organization specific client_id.")
                # clear only if user did not specify it already
                if FilesApi.is_global_client_id?(self.options.get_option(:client_id,:optional))
                  self.options.set_option(:client_id,nil)
                  self.options.set_option(:client_secret,nil)
                end
                if self.options.get_option(:client_id,:optional).nil? or self.options.get_option(:client_secret,:optional).nil?
                  self.format.display_status("Please login to your Aspera on Cloud instance.".red)
                  self.format.display_status("Go to: Apps->Admin->Organization->Integrations")
                  self.format.display_status("Create or check if there is an existing integration named:")
                  self.format.display_status("- name: #{@tool_name}")
                  self.format.display_status("- redirect uri: #{DEFAULT_REDIRECT}")
                  self.format.display_status("- origin: localhost")
                  self.format.display_status("Once created or identified,")
                  self.format.display_status("Please enter:".red)
                end
                OpenApplication.instance.uri(instance_url+"/admin/org/integrations")
                self.options.get_option(:client_id,:mandatory)
                self.options.get_option(:client_secret,:mandatory)
                use_browser_authentication=true
              end
              if use_browser_authentication
                self.format.display_status("We will use web authentication to bootstrap.")
                self.options.set_option(:auth,:web)
                self.options.set_option(:redirect_uri,DEFAULT_REDIRECT)
                auto_set_pub_key=true
                auto_set_jwt=true
                require_admin=true
              end
              api_aoc=files_plugin.get_aoc_api(require_admin)
              myself=api_aoc.read('self')[:data]
              if auto_set_pub_key
                raise CliError,"public key is already set in profile (use --override=yes)"  unless myself['public_key'].empty? or option_override
                self.format.display_status("Updating profile with new key")
                api_aoc.update("users/#{myself['id']}",{'public_key'=>pub_key_pem})
              end
              if auto_set_jwt
                self.format.display_status("Enabling JWT for client")
                api_aoc.update("clients/#{self.options.get_option(:client_id)}",{'jwt_grant_enabled'=>true,'explicit_authorization_required'=>false})
              end
              self.format.display_status("creating new config preset: #{aspera_preset_name}")
              @config_presets[aspera_preset_name]={
                :url.to_s           =>self.options.get_option(:url),
                :redirect_uri.to_s  =>self.options.get_option(:redirect_uri),
                :client_id.to_s     =>self.options.get_option(:client_id),
                :client_secret.to_s =>self.options.get_option(:client_secret),
                :auth.to_s          =>:jwt.to_s,
                :private_key.to_s   =>'@file:'+private_key_path,
                :username.to_s      =>myself['email'],
              }
              self.format.display_status("Setting config preset as default for #{NEW_AOC_COMMAND}")
              @config_presets[CONF_PRESET_DEFAULT][NEW_AOC_COMMAND]=aspera_preset_name
              self.format.display_status("saving config file")
              save_presets_to_config_file
              return Main.result_status("Done.\nYou can test with:\n#{@tool_name} aspera user info show")
            else
              raise CliBadArgument,"Supports only: aoc. Detected: #{appli}"
            end
          when :export_to_cli
            self.format.display_status("Exporting: Aspera on Cloud")
            require 'asperalm/cli/plugins/aspera'
            # need url / username
            add_plugin_default_preset(NEW_AOC_COMMAND.to_sym)
            files_plugin=Plugins::Aspera.new(@agents)
            url=self.options.get_option(:url,:mandatory)
            cli_conf_file=Fasp::Installation.instance.cli_conf_file
            data=JSON.parse(File.read(cli_conf_file))
            organization,instance_domain=FilesApi.parse_url(url)
            key_basename='org_'+organization+'.pem'
            key_file=File.join(File.dirname(File.dirname(cli_conf_file)),'etc',key_basename)
            File.write(key_file,self.options.get_option(:private_key,:mandatory))
            new_conf={
              'organization'       => organization,
              'hostname'           => [organization,instance_domain].join('.'),
              'clientId'           => self.options.get_option(:client_id,:mandatory),
              'clientSecret'       => self.options.get_option(:client_secret,:mandatory),
              'privateKeyFilename' => key_basename,
              'username'           => self.options.get_option(:username,:mandatory)
            }
            entry=data['AoCAccounts'].select{|i|i['organization'].eql?(organization)}.first
            if entry.nil?
              data['AoCAccounts'].push(new_conf)
              self.format.display_status("Creating new aoc entry: #{organization}")
            else
              self.format.display_status("Updating existing aoc entry: #{organization}")
              entry.merge!(new_conf)
            end
            File.write(cli_conf_file,JSON.pretty_generate(data))
            return Main.result_status("updated: #{cli_conf_file}")
          when :detect
            # need url / username
            BasicAuthPlugin.new(@agents)
            return Main.result_status("found: #{ApiDetector.discover_product(self.options.get_option(:url,:mandatory))}")
          when :coffee
            OpenApplication.instance.uri('https://enjoyjava.com/wp-content/uploads/2018/01/How-to-make-strong-coffee.jpg')
            return Main.result_nothing
          when :gem_path
            return Main.result_status(Main.gem_root)
          else raise "error"
          end
        end

        def save_presets_to_config_file
          raise "no configuration loaded" if @config_presets.nil?
          FileUtils::mkdir_p(@main_folder) unless Dir.exist?(@main_folder)
          Log.log.debug "writing #{@option_config_file}"
          File.write(@option_config_file,@config_presets.to_yaml)
        end

        # returns name if config_presets has default
        # returns nil if there is no config or bypass default params
        def get_plugin_default_config_name(plugin_sym)
          raise "internal error: config_presets shall be defined" if @config_presets.nil?
          if !@use_plugin_defaults
            Log.log.debug("skip default config")
            return nil
          end
          if @config_presets.has_key?(CONF_PRESET_DEFAULT) and
          @config_presets[CONF_PRESET_DEFAULT].has_key?(plugin_sym.to_s)
            default_config_name=@config_presets[CONF_PRESET_DEFAULT][plugin_sym.to_s]
            if !@config_presets.has_key?(default_config_name)
              Log.log.error("Default config name [#{default_config_name}] specified for plugin [#{plugin_sym.to_s}], but it does not exist in config file.\nPlease fix the issue: either create preset with one parameter (#{@tool_name} config id #{default_config_name} init @json:'{}') or remove default (#{@tool_name} config id default remove #{plugin_sym.to_s}).")
            end
            raise CliError,"Config name [#{default_config_name}] must be a hash, check config file." if !@config_presets[default_config_name].is_a?(Hash)
            return default_config_name
          end
          return nil
        end

      end
    end
  end
end
