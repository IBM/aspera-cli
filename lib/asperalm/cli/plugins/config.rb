require 'asperalm/cli/basic_auth_plugin'
require 'asperalm/fasp/installation'
require 'singleton'
require 'xmlsimple'

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
        @@OLD_PROGRAM_NAME = 'aslmcli'
        # new plugin name for AoC
        @@ASPERA_PLUGIN_S=:aspera.to_s
        @@DEFAULT_REDIRECT='http://localhost:12345'
        def initialize
          @program_version=nil
          @config_folder=nil
          @option_config_file=nil
          @use_plugin_defaults=true
          @config_presets=nil
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
        attr_accessor :option_override
        attr_accessor :option_config_file

        def preset_by_name(config_name)
          raise CliError,"no such config preset: #{config_name}" unless @config_presets.has_key?(config_name)
          return @config_presets[config_name]
        end
        
        def set_program_info(tool_name,gem_name,version)
          @program_version=version
          @gem_name=gem_name
          @tool_name=tool_name
          @config_folder=File.join(Dir.home,@@ASPERA_HOME_FOLDER_NAME,tool_name)
          @old_config_folder=File.join(Dir.home,@@ASPERA_HOME_FOLDER_NAME,@@OLD_PROGRAM_NAME)
          if Dir.exist?(@old_config_folder) and ! Dir.exist?(@config_folder)
            Log.log.warn("Detected former configuration folder, renaming: #{@old_config_folder} -> #{@config_folder}")
            FileUtils.mv(@old_config_folder, @config_folder)
          end
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
              new_plugin_name=@@ASPERA_PLUGIN_S
              if @config_presets[@@CONFIG_PRESET_DEFAULT].is_a?(Hash) and @config_presets[@@CONFIG_PRESET_DEFAULT].has_key?(old_plugin_name)
                @config_presets[@@CONFIG_PRESET_DEFAULT][new_plugin_name]=@config_presets[@@CONFIG_PRESET_DEFAULT][old_plugin_name]
                @config_presets[@@CONFIG_PRESET_DEFAULT].delete(old_plugin_name)
                Log.log.warn("Converted plugin default: #{old_plugin_name} -> #{new_plugin_name}")
                save_required=true
              end
            end
            config_tested_version='0.8.10'
            if Gem::Version.new(version) <= Gem::Version.new(config_tested_version)
              old_subpath=File.join('',@@ASPERA_HOME_FOLDER_NAME,@@OLD_PROGRAM_NAME,'')
              new_subpath=File.join('',@@ASPERA_HOME_FOLDER_NAME,@tool_name,'')
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
          action=Main.instance.options.get_next_command([:genkey,:plugins,:flush_tokens,:list,:overview,:open,:echo,:id,:documentation,:wizard,:export_to_cli,:detect])
          case action
          when :id
            config_name=Main.instance.options.get_next_argument('config name')
            action=Main.instance.options.get_next_command([:show,:delete,:set,:unset,:initialize,:update,:ask])
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
            instance_url=Main.instance.options.get_option(:url,:mandatory)
            appli=discover_product(instance_url)
            case appli[:product]
            when :aoc
              Main.instance.display_status("Detected: Aspera on Cloud")
              require 'asperalm/cli/plugins/aspera'
              files_plugin=Plugins::Aspera.instance
              files_plugin.declare_options
              Main.instance.options.parse_options!
              Main.instance.options.set_option(:auth,:web)
              Main.instance.options.set_option(:redirect_uri,@@DEFAULT_REDIRECT)
              organization,instance_domain=FilesApi.parse_url(instance_url)
              aspera_preset_name='aoc_'+organization
              Main.instance.display_status("Creating preset: #{aspera_preset_name}")
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
              puts "- name: #{Main.instance.program_name}"
              puts "- redirect uri: #{@@DEFAULT_REDIRECT}"
              puts "- origin: localhost"
              puts "Once created please enter the following any required parameter:"
              OpenApplication.instance.uri(instance_url+"/admin/org/integrations")
              Main.instance.options.get_option(:client_id)
              Main.instance.options.get_option(:client_secret)
              @config_presets[@@CONFIG_PRESET_DEFAULT]||=Hash.new
              raise CliError,"a default configuration already exists (use --override=yes)" if @config_presets[@@CONFIG_PRESET_DEFAULT].has_key?(@@ASPERA_PLUGIN_S) and !option_override
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
              puts "setting config preset as default for #{@@ASPERA_PLUGIN_S}"
              @config_presets[@@CONFIG_PRESET_DEFAULT][@@ASPERA_PLUGIN_S]=aspera_preset_name
              puts "saving config file"
              save_presets_to_config_file
              return Main.result_status("Done. You can test with:\n#{Main.instance.program_name} aspera user info show")
            else
              raise CliBadArgument,"supports only: aoc, detected: #{appli}"
            end
          when :export_to_cli
            Main.instance.display_status("Exporting: Aspera on Cloud")
            require 'asperalm/cli/plugins/aspera'
            # need url / username
            Plugins::Aspera.instance.declare_options
            Main.instance.options.parse_options!
            url=Main.instance.options.get_option(:url,:mandatory)
            cli_conf_file=Fasp::Installation.instance.cli_conf_file
            data=JSON.parse(File.read(cli_conf_file))
            organization,instance_domain=FilesApi.parse_url(url)
            key_basename='org_'+organization+'.pem'
            key_file=File.join(File.dirname(File.dirname(cli_conf_file)),'etc',key_basename)
            File.write(key_file,Main.instance.options.get_option(:private_key,:mandatory))
            new_conf={
              'organization'       => organization,
              'hostname'           => [organization,instance_domain].join('.'),
              'clientId'           => Main.instance.options.get_option(:client_id,:mandatory),
              'clientSecret'       => Main.instance.options.get_option(:client_secret,:mandatory),
              'privateKeyFilename' => key_basename,
              'username'           => Main.instance.options.get_option(:username,:mandatory)
            }
            entry=data['AoCAccounts'].select{|i|i['organization'].eql?(organization)}.first
            if entry.nil?
              data['AoCAccounts'].push(new_conf)
              Main.instance.display_status("Creating new aoc entry: #{organization}")
            else
              Main.instance.display_status("Updating existing aoc entry: #{organization}")
              entry.merge!(new_conf)
            end
            File.write(cli_conf_file,JSON.pretty_generate(data))
            return Main.result_status("updated: #{cli_conf_file}")
          when :detect
            # need url / username
            BasicAuthPlugin.new.declare_options
            Main.instance.options.parse_options!
            return Main.result_status("found: #{discover_product(Main.instance.options.get_option(:url,:mandatory))}")
          else raise "error"
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
              Log.log.error("Default config name [#{default_config_name}] specified for plugin [#{plugin_sym.to_s}], but it does not exist in config file.\nPlease fix the issue: either create preset with one parameter (#{Main.instance.program_name} config id #{default_config_name} init @json:'{}') or remove default (#{Main.instance.program_name} config id default remove #{plugin_sym.to_s}).")
            end
            raise CliError,"Config name [#{default_config_name}] must be a hash, check config file." if !@config_presets[default_config_name].is_a?(Hash)
            return default_config_name
          end
          return nil
        end

        def discover_product(url)
          uri=URI.parse(url)
          api=Rest.new({:base_url=>url})
          begin
            result=api.call({:operation=>'GET',:subpath=>'',:headers=>{'Accept'=>'text/html'}})
            if result[:http].body.include?('<meta name="apple-mobile-web-app-title" content="AoC">')
              return {:product=>:aoc,:version=>'unknown'}
            end
          rescue e
            Log.log.debug("not aoc")
          end
          begin
            result=api.call({:operation=>'POST',:subpath=>'aspera/faspex',:headers=>{'Accept'=>'application/xrds+xml'},:text_body_params=>''})
            if result[:http].body.start_with?('<?xml')
              res_s=XmlSimple.xml_in(result[:http].body, {"ForceArray" => false})
              version=res_s['XRD']['application']['version']
              #return JSON.pretty_generate(res_s)
            end
            return {:product=>:faspex,:version=>version}
          rescue
            Log.log.debug("not faspex")
          end
          begin
            result=api.read('node_api/app')
            Log.log.warn("not supposed to work")
          rescue RestCallError => e
            if e.response.code.to_s.eql?('401') and e.response.body.eql?('{"error":{"user_message":"API user authentication failed"}}')
              return {:product=>:shares,:version=>'unknown'}
            end
            Log.log.warn("not shares: #{e.response.code} #{e.response.body}")
          rescue
          end
          return {:product=>:unknown,:version=>'unknown'}
        end

      end
    end
  end
end
