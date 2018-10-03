require 'asperalm/cli/plugin'
require 'singleton'

module Asperalm
  module Cli
    module Plugins
      # manage the CLI config file
      class Config < Plugin
        include Singleton
        private

        # folder in $HOME for application files (config, cache)
        @@ASPERA_HOME_FOLDER_NAME='.aspera'
        # main config file
        @@DEFAULT_CONFIG_FILENAME = 'config.yaml'
        @@RESERVED_SECTION_TOOL=:config
        @@CONFIG_PRESET_VERSION='version'
        @@CONFIG_PRESET_DEFAULT='default'
        # new plugin name for AoC
        ASPERA_PLUGIN_S=:aspera.to_s
        def initialize
          @program_version=nil
          @config_folder=nil
          @option_config_file=nil
          @use_plugin_defaults=true
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

        def action_list; [ :todo];end

        def declare_options
          Main.instance.options.set_obj_attr(:override,self,:option_override,:no)
          Main.instance.options.set_obj_attr(:config_file,self,:option_config_file)
          Main.instance.options.add_opt_simple(:config_file,"read parameters from file in YAML format, current=#{@option_config_file}")
          Main.instance.options.add_opt_switch(:no_default,"-N","do not load default configuration for plugin") { @use_plugin_defaults=false }
        end

        attr_reader :config_folder
        attr_reader :gem_url
        attr_reader :help_url
        attr_reader :config_presets
        attr_accessor :option_override
        attr_accessor :option_config_file

        def set_program_info(tool_name,gem_name,version)
          @program_version=version
          @gem_name=gem_name
          @config_folder=File.join(Dir.home,@@ASPERA_HOME_FOLDER_NAME,tool_name)
          @option_config_file=File.join(@config_folder,@@DEFAULT_CONFIG_FILENAME)
          @help_url='http://www.rubydoc.info/gems/'+@gem_name
          @gem_url='https://rubygems.org/gems/'+@gem_name
        end

        # read config file and validate format
        # tries to cnvert if possible and required
        def read_config_file
          Log.log.debug("config file is: #{@option_config_file}".red)
          # oldest compatible conf file format, update to latest version when an incompatible change is made
          if !File.exist?(@option_config_file)
            Log.log.warn("No config file found. Creating empty configuration file: #{@option_config_file}")
            @config_presets={@@RESERVED_SECTION_TOOL.to_s=>{@@CONFIG_PRESET_VERSION=>@program_version}}
            save_presets_to_config_file
            return nil
          end
          begin
            Log.log.debug "loading #{@option_config_file}"
            @config_presets=YAML.load_file(@option_config_file)
            Log.log.debug "Available_presets: #{@config_presets}"
            raise "Expecting YAML Hash" unless @config_presets.is_a?(Hash)
            # check there is at least the config section
            if !@config_presets.has_key?(@@RESERVED_SECTION_TOOL.to_s)
              raise "Cannot find key: #{@@RESERVED_SECTION_TOOL.to_s}"
            end
            version=@config_presets[@@RESERVED_SECTION_TOOL.to_s][@@CONFIG_PRESET_VERSION]
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
              old_plugin_name='files'
              new_plugin_name=ASPERA_PLUGIN_S
              if @config_presets[@@CONFIG_PRESET_DEFAULT].is_a?(Hash) and @config_presets[@@CONFIG_PRESET_DEFAULT].has_key?(old_plugin_name)
                @config_presets[@@CONFIG_PRESET_DEFAULT][new_plugin_name]=@config_presets[@@CONFIG_PRESET_DEFAULT][old_plugin_name]
                @config_presets[@@CONFIG_PRESET_DEFAULT].delete(old_plugin_name)
                Log.log.warn("Converted plugin default: #{old_plugin_name} -> #{new_plugin_name}")
                save_required=true
              end
            end
            # Place new compatibility code here
            if save_required
              @config_presets[@@RESERVED_SECTION_TOOL.to_s][@@CONFIG_PRESET_VERSION]=@program_version
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

        # "config" plugin
        def execute_action
          action=Main.instance.options.get_next_argument('action',[:genkey,:plugins,:flush_tokens,:list,:overview,:open,:echo,:id,:documentation,:wizard])
          case action
          when :id
            config_name=Main.instance.options.get_next_argument('config name')
            action=Main.instance.options.get_next_argument('action',[:show,:delete,:set,:unset,:initialize,:update,:ask])
            case action
            when :show
              raise "no such config: #{config_name}" unless @config_presets.has_key?(config_name)
              return {:type=>:single_object,:data=>@config_presets[config_name]}
            when :delete
              @config_presets.delete(config_name)
              save_presets_to_config_file
              return Main.result_status("deleted: #{config_name}")
            when :set
              param_name=Main.instance.options.get_next_argument('parameter name')
              param_value=Main.instance.options.get_next_argument('parameter value')
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
              param_name=Main.instance.options.get_next_argument('parameter name')
              if @config_presets.has_key?(config_name)
                @config_presets[config_name].delete(param_name)
                save_presets_to_config_file
              else
                Log.log.warn("no such parameter: #{param_name} (ignoring)")
              end
              return Main.result_status("removed: #{config_name}: #{param_name}")
            when :initialize
              config_value=Main.instance.options.get_next_argument('extended value (Hash)')
              if @config_presets.has_key?(config_name)
                Log.log.warn("configuration already exists: #{config_name}, overwriting")
              end
              @config_presets[config_name]=config_value
              save_presets_to_config_file
              return Main.result_status("modified: #{@option_config_file}")
            when :update
              #  TODO: when arguments are provided: --option=value, this creates an entry in the named configuration
              theopts=Main.instance.options.get_options_table
              Log.log.debug("opts=#{theopts}")
              @config_presets[config_name]={} if !@config_presets.has_key?(config_name)
              @config_presets[config_name].merge!(theopts)
              save_presets_to_config_file
              return Main.result_status("updated: #{config_name}")
            when :ask
              Main.instance.options.ask_missing_mandatory=:yes
              @config_presets[config_name]||={}
              Main.instance.options.get_next_argument('option names',:multiple).each do |optionname|
                option_value=Main.instance.options.get_interactive(:option,optionname)
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
            key_filepath=Main.instance.options.get_next_argument('private key file path')
            generate_new_key(key_filepath)
            return Main.result_status('generated key: '+key_filepath)
          when :echo # display the content of a value given on command line
            result={:type=>:other_struct, :data=>Main.instance.options.get_next_argument("value")}
            # special for csv
            result[:type]=:object_list if result[:data].is_a?(Array) and result[:data].first.is_a?(Hash)
            return result
          when :flush_tokens
            deleted_files=Oauth.flush_tokens
            return {:type=>:value_list, :name=>'file',:data=>deleted_files}
          when :plugins
            return {:data => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :object_list }
          when :list
            return {:data => @config_presets.keys, :type => :value_list, :name => 'name'}
          when :overview
            return {:type=>:object_list,:data=>self.class.flatten_all_config(@config_presets)}
          when :wizard
            # only one value, so no test, no switch for the time being
            plugin_name=Main.instance.options.get_next_argument('plugin name',[:aspera])
            require 'asperalm/cli/plugins/aspera'
            files_plugin=Plugins::Aspera.new
            files_plugin.declare_options
            Main.instance.options.parse_options!
            Main.instance.options.set_option(:auth,:web)
            Main.instance.options.set_option(:redirect_uri,DEFAULT_REDIRECT)
            instance_url=Main.instance.options.get_option(:url,:mandatory)
            organization,instance_domain=FilesApi.parse_url(instance_url)
            aspera_preset_name='aoc_'+organization
            key_filepath=File.join(@config_folder,'aspera_on_cloud_key')
            if File.exist?(key_filepath)
              puts "key file already exists: #{key_filepath}"
            else
              puts "generating: #{key_filepath}"
              generate_new_key(key_filepath)
            end
            puts "Please login to your Aspera on Cloud instance as Administrator."
            puts "Go to: Admin->Organization->Integrations"
            puts "Create a new integration:"
            puts "- name: aslmcli"
            puts "- redirect uri: #{DEFAULT_REDIRECT}"
            puts "- origin: localhost"
            puts "Once created please enter the following any required parameter:"
            OpenApplication.instance.uri(instance_url+"/admin/org/integrations")
            Main.instance.options.get_option(:client_id)
            Main.instance.options.get_option(:client_secret)
            @config_presets[@@CONFIG_PRESET_DEFAULT]||=Hash.new
            raise CliError,"a default configuration already exists (use --override=yes)" if @config_presets[@@CONFIG_PRESET_DEFAULT].has_key?(ASPERA_PLUGIN_S) and !option_override
            raise CliError,"preset already exists: #{aspera_preset_name}  (use --override=yes)" if @config_presets.has_key?(aspera_preset_name) and !option_override
            # todo: check if key is identical
            files_plugin.init_apis
            myself=files_plugin.api_files_user.read('self')[:data]
            raise CliError,"public key is already set (use --override=yes)"  unless myself['public_key'].empty? or option_override
            puts "updating profile with new key"
            files_plugin.api_files_user.update("users/#{myself['id']}",{'public_key'=>File.read(key_filepath+'.pub')})
            puts "Enabling JWT"
            files_plugin.api_files_admn.update("clients/#{Main.instance.options.get_option(:client_id)}",{"jwt_grant_enabled"=>true,"explicit_authorization_required"=>false})
            puts "creating new config preset: #{aspera_preset_name}"
            @config_presets[aspera_preset_name]={
              :url.to_s           =>Main.instance.options.get_option(:url),
              :redirect_uri.to_s  =>Main.instance.options.get_option(:redirect_uri),
              :client_id.to_s     =>Main.instance.options.get_option(:client_id),
              :client_secret.to_s =>Main.instance.options.get_option(:client_secret),
              :auth.to_s          =>:jwt.to_s,
              :private_key.to_s   =>'@file:'+key_filepath,
              :username.to_s      =>myself['email'],
            }
            puts "setting config preset as default for #{ASPERA_PLUGIN_S}"
            @config_presets[@@CONFIG_PRESET_DEFAULT][ASPERA_PLUGIN_S]=aspera_preset_name
            puts "saving config file"
            save_presets_to_config_file
            return Main.result_status("Done. You can test with:\naslmcli aspera user info show")
            # TODO: update documentation
          end
        end

        def save_presets_to_config_file
          raise "no configuration loaded" if @config_presets.nil?
          FileUtils::mkdir_p(config_folder) unless Dir.exist?(config_folder)
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
          if @config_presets.has_key?(@@CONFIG_PRESET_DEFAULT) and
          @config_presets[@@CONFIG_PRESET_DEFAULT].has_key?(plugin_sym.to_s)
            default_config_name=@config_presets[@@CONFIG_PRESET_DEFAULT][plugin_sym.to_s]
            if !@config_presets.has_key?(default_config_name)
              Log.log.error("Default config name [#{default_config_name}] specified for plugin [#{plugin_sym.to_s}], but it does not exist in config file.\nPlease fix the issue: either create preset with one parameter (aslmcli config id #{default_config_name} init @json:'{}') or remove default (aslmcli config id default remove #{plugin_sym.to_s}).")
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
