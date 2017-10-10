require "asperalm/cli/opt_parser"
require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require "asperalm/connect"
require 'asperalm/operating_system'
require 'asperalm/oauth'
require 'asperalm/fasp_manager_switch'
require 'text-table'
require 'fileutils'
require 'singleton'
require 'yaml'
require 'pp'

module Asperalm
  module Cli
    module Plugins; end

    #
    class FaspListenerProgress < FileTransferListener
      def initialize
        @progress=nil
      end

      def event(data)
        case data['Type']
        when 'NOTIFICATION'
          if data.has_key?('PreTransferBytes') then
            require 'ruby-progressbar'
            @progress=ProgressBar.create(
            :format     => '%a %B %p%% %r KB/sec %e',
            :rate_scale => lambda{|rate|rate/1024},
            :title      => 'progress',
            :total      => data['PreTransferBytes'].to_i)
          end
        when 'STATS'
          if !@progress.nil? then
            @progress.progress=data['TransferBytes'].to_i
          else
            puts "."
          end
        when 'DONE'
          if !@progress.nil? then
            @progress.progress=@progress.total
            @progress=nil
          else
            # terminate progress by going to next line
            puts "\n"
          end
        end
      end
    end

    # listener for FASP transfers (debug)
    class FaspListenerLogger < FileTransferListener
      def event(data)
        Log.log.debug "#{data}"
      end
    end

    # The main CI class, singleton
    class Main < Plugin
      include Singleton
      # "tool" class method is an alias to "instance"
      singleton_class.send(:alias_method, :tool, :instance)

      # first level command for the main tool
      @@MAIN_PLUGIN_NAME_STR='config'
      # name of application, also foldername where config is stored
      @@PROGRAM_NAME = 'aslmcli'
      # folder in $HOME for the application
      @@ASPERA_HOME_FOLDERNAME='.aspera'
      # folder containing custom plugins in `config_folder`
      @@ASPERA_PLUGINS_FOLDERNAME='plugins'
      # main config file
      @@DEFAULT_CONFIG_FILENAME = 'config.yaml'
      # folder containing plugins in the gem's main folder
      @@GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
      # Path to module Cli : Asperalm::Cli
      @@CLI_MODULE=Module.nesting[1].to_s
      # Path to Plugin classes: Asperalm::Cli::Plugins
      @@PLUGINS_MODULE=@@CLI_MODULE+"::Plugins"
      @@CONFIG_FILE_KEY_VERSION='version'
      @@CONFIG_FILE_KEY_DEFAULT='default'
      # oldest compatible conf file format
      @@MIN_CONFIG_VERSION='0.4.5'
      @@NO_DEFAULT='none'
      # $HOME/.aspera/aslmcli
      def config_folder
        return File.join(Dir.home,@@ASPERA_HOME_FOLDERNAME,@@PROGRAM_NAME)
      end

      # $HOME/.aspera/aslmcli/config.yaml
      def default_config_file
        return File.join(config_folder,@@DEFAULT_CONFIG_FILENAME)
      end

      def current_config_file
        return self.options.get_option_mandatory(:config_file)
      end

      def read_config_file(config_file_path=current_config_file)
        if !File.exist?(config_file_path)
          Log.log.info("no config file, using empty configuration")
          return {@@MAIN_PLUGIN_NAME_STR=>{@@CONFIG_FILE_KEY_VERSION=>Asperalm::VERSION}}
        end
        Log.log.debug "loading #{config_file_path}"
        return YAML.load_file(config_file_path)
      end

      def write_config_file(config=@loaded_configs,config_file_path=current_config_file)
        raise "no configuration loaded" if config.nil?
        FileUtils::mkdir_p(config_folder) if !Dir.exist?(config_folder)
        Log.log.debug "writing #{config_file_path}"
        File.write(config_file_path,config.to_yaml)
      end

      # returns default parameters for a plugin from loaded config file
      # 1) try to find: conffile[conffile["config"][:default][plugin_sym]]
      # 2) if no such value, it takes the name plugin_name+"_default", and loads this config
      def get_plugin_default_parameters(plugin_sym)
        return nil if @loaded_configs.nil? or !@load_plugin_defaults
        default_config_name=plugin_sym.to_s+'_default'
        if @loaded_configs.has_key?(@@CONFIG_FILE_KEY_DEFAULT) and
        @loaded_configs[@@CONFIG_FILE_KEY_DEFAULT].has_key?(plugin_sym.to_s)
          default_config_name=@loaded_configs[@@CONFIG_FILE_KEY_DEFAULT][plugin_sym.to_s]
        end
        # can be nil
        return @loaded_configs[default_config_name]
      end

      def self.no_result
        return {:type => :empty, :data => :nil }
      end

      def self.status_result(status)
        return {:type => :status, :data => status }
      end

      def self.result_success
        return status_result('complete')
      end

      # =============================================================
      # Parameter handlers
      #
      def handler_logtype(operation,value)
        case operation
        when :set
          level=Log.level
          Log.setlogger(value)
          self.options.set_option(:log_level,level)
          @logtype_cache=value
        else
          return @logtype_cache
          Log.log.debug "TODO: get logtype ??"
        end
      end

      def handler_loglevel(operation,value)
        case operation
        when :set
          Log.level = value
        else
          return Log.level
        end
      end

      def handler_insecure(operation,value)
        case operation
        when :set
          Rest.insecure=value
        else
          return Rest.insecure
        end
      end

      def handler_transfer_spec(operation,value)
        case operation
        when :set
          Log.log.debug "handler_transfer_spec: set: #{value}".red
          faspmanager.transfer_spec_default.merge!(value)
        else
          return faspmanager.transfer_spec_default
        end
      end

      def handler_browser(operation,value)
        case operation
        when :set
          Log.log.debug "handler_browser: set: #{value}".red
          OperatingSystem.open_url_method=value
        else
          return OperatingSystem.open_url_method
        end
      end

      def handler_fasp_folder(operation,value)
        case operation
        when :set
          Log.log.debug "handler_fasp_folder: set: #{value}".red
          Connect.fasp_install_paths=value
        else
          return Connect.fasp_install_paths
        end
      end

      # returns the list of plugins from plugin folder
      def plugin_sym_list
        return @plugins.keys
      end

      def action_list; plugin_sym_list; end

      # adds plugins from given plugin folder
      def scan_plugins(plugin_folder,plugin_subfolder)
        plugin_folder=File.join(plugin_folder,plugin_subfolder) if !plugin_subfolder.nil?
        Dir.entries(plugin_folder).select { |file| file.end_with?('.rb')}.each do |source|
          name=source.gsub(/\.rb$/,'')
          @plugins[name.to_sym]={:source=>File.join(plugin_folder,source),:req=>File.join(plugin_folder,name)}
        end
      end

      # adds plugins from system and user
      def scan_all_plugins
        # find plugins
        # value=path to class
        @plugins={@@MAIN_PLUGIN_NAME_STR.to_sym=>{:source=>__FILE__,:req=>nil}}
        gem_root=File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'), File.dirname(__FILE__))
        scan_plugins(gem_root,@@GEM_PLUGINS_FOLDER)
        user_plugin_folder=File.join(config_folder,@@ASPERA_PLUGINS_FOLDERNAME)
        if File.directory?(user_plugin_folder)
          $:.push(user_plugin_folder)
          scan_plugins(user_plugin_folder,nil)
        end
      end

      def faspmanager
        if @faspmanager_switch.nil?
          # create the FASP manager for transfers
          faspmanager_basic=FaspManager.new(Log.log)
          faspmanager_basic.add_listener(FaspListenerLogger.new)
          faspmanager_basic.add_listener(FaspListenerProgress.new)
          faspmanager_basic.ascp_path=Connect.path(:ascp)
          faspmanager_resume=FaspManagerResume.new(faspmanager_basic)
          @faspmanager_switch=FaspManagerSwitch.new(faspmanager_resume)
          @faspmanager_switch.connect_app_id=@@PROGRAM_NAME
          if !self.options.get_option(:fasp_proxy).nil?
            @faspmanager_switch.transfer_spec_default.merge!({'EX_fasp_proxy_url'=>self.options.get_option(:fasp_proxy)})
          end
          if !self.options.get_option(:http_proxy).nil?
            @faspmanager_switch.transfer_spec_default.merge!({'EX_http_proxy_url'=>self.options.get_option(:http_proxy)})
          end
          case self.options.get_option_mandatory(:transfer)
          when :connect
            @faspmanager_switch.use_connect_client=true
          when :node
            config_name=self.options.get_option(:transfer_node)
            if config_name.nil?
              node_config=get_plugin_default_parameters(:node)
              raise CliBadArgument,"Please specify --transfer-node" if node_config.nil?
            else
              node_config=@loaded_configs[config_name]
              raise CliBadArgument,"no such node configuration: #{config_name}" if node_config.nil?
            end
            @faspmanager_switch.tr_node_api=Rest.new(node_config[:url],{:auth=>{:type=>:basic,:username=>node_config[:username], :password=>node_config[:password]}})
          end
        end
        return @faspmanager_switch
      end

      def start_transfer(transfer_spec)
        # TODO: option to choose progress format
        transfer_spec['EX_quiet']=true
        faspmanager.start_transfer(transfer_spec)
        return self.class.result_success
      end

      def options; @options;end

      def initialize
        @help_requested=false
        @options=OptParser.new
        @loaded_configs=nil
        @faspmanager_switch=nil
        @load_plugin_defaults=true
        scan_all_plugins
        self.options.program_name=@@PROGRAM_NAME
        self.options.banner = "NAME\n\t#{@@PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{Asperalm::VERSION})\n\n"
        self.options.separator "SYNOPSIS"
        self.options.separator "\t#{@@PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
        self.options.separator ""
        self.options.separator "DESCRIPTION"
        self.options.separator "\tUse Aspera application to perform operations on command line."
        self.options.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        self.options.separator "\tAdditional documentation here: https://rubygems.org/gems/asperalm"
        self.options.separator ""
        self.options.separator "COMMANDS"
        self.options.separator "\tFirst level commands: #{action_list.map {|x| x.to_s}.join(', ')}"
        self.options.separator "\tNote that commands can be written shortened (provided it is unique)."
        self.options.separator ""
        self.options.separator "OPTIONS"
        self.options.separator "\tOptions begin with a '-' (minus), and value is provided on command line.\n"
        self.options.separator "\tSpecial values are supported beginning with special prefix, like: #{OptParser.value_modifier.map {|m| "@#{m}:"}.join(' ')}.\n"
        self.options.separator "\tDates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'"
        self.options.separator ""
        self.options.separator "ARGS"
        self.options.separator "\tSome commands require mandatory arguments, e.g. a path.\n"
        self.options.separator ""
        self.options.separator "EXAMPLES"
        self.options.separator "\t#{@@PROGRAM_NAME} files repo browse /"
        self.options.separator "\t#{@@PROGRAM_NAME} faspex send ./myfile --log-level=debug"
        self.options.separator "\t#{@@PROGRAM_NAME} shares upload ~/myfile /myshare"
        self.options.separator ""
        # handler must be set before setting defaults
        self.options.set_handler(:log_level) { |op,val| handler_loglevel(op,val) }
        self.options.set_handler(:logger) { |op,val| handler_logtype(op,val) }
        self.options.set_handler(:insecure) { |op,val| handler_insecure(op,val) }
        self.options.set_handler(:ts) { |op,val| handler_transfer_spec(op,val) }
        self.options.set_handler(:gui_mode) { |op,val| handler_browser(op,val) }
        self.options.set_handler(:fasp_folder) { |op,val| handler_fasp_folder(op,val) }
      end

      # plugin_name_sym is symbol
      # loads default parameters if no -P parameter
      def get_plugin_instance(plugin_name_sym)
        require @plugins[plugin_name_sym][:req]
        Log.log.debug("loaded config -> #{@loaded_configs}")
        # TODO: check that ancestor is Plugin?
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new
        # load default params only if no param already loaded
        if self.options.get_option(:load_params).nil?
          defaults_for_plugin=get_plugin_default_parameters(plugin_name_sym)
          self.options.set_defaults(defaults_for_plugin) if !defaults_for_plugin.nil?
        end
        self.options.separator "COMMAND: #{plugin_name_sym}"
        self.options.separator "SUBCOMMANDS: #{command_plugin.action_list.map{ |p| p.to_s}.join(', ')}"
        self.options.separator "OPTIONS:"
        command_plugin.declare_options
        return command_plugin
      end

      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'

      def declare_options
        self.options.separator "OPTIONS: global"
        self.options.set_option(:gui_mode,OperatingSystem.default_gui_mode)
        self.options.set_option(:fields,FIELDS_DEFAULT)
        self.options.set_option(:transfer,:ascp)
        self.options.set_option(:insecure,:no)
        self.options.set_option(:format,:table)
        self.options.set_option(:logger,:stdout)
        self.options.set_option(:config_file,default_config_file)
        self.options.on("-h", "--help", "Show this message.") { @help_requested=true }
        self.options.add_opt_list(:gui_mode,OperatingSystem.gui_modes,"method to start browser",'-gTYPE','--gui-mode=TYPE')
        self.options.add_opt_list(:insecure,[:yes,:no],"do not validate cert",'--insecure=VALUE')
        self.options.add_opt_list(:log_level,Log.levels,"Log level",'-lTYPE','--log-level=VALUE')
        self.options.add_opt_list(:logger,Log.logtypes,"log method",'-qTYPE','--logger=VALUE')
        self.options.add_opt_list(:format,self.class.display_formats,"output format",'--format=VALUE')
        self.options.add_opt_list(:transfer,[:ascp,:connect,:node],"type of transfer",'--transfer=VALUE')
        self.options.add_opt_simple(:config_file,"-CSTRING", "--config-file=STRING","read parameters from file in YAML format, current=#{self.options.get_option(:config_file)}")
        self.options.add_opt_simple(:load_params,"-PNAME","--load-params=NAME","load the named configuration from current config file, use \"#{@@NO_DEFAULT}\" to avoid loading the default configuration")
        self.options.add_opt_simple(:fasp_folder,"--fasp-folder=NAME","specify where to find FASP (main folder), current=#{self.options.get_option(:fasp_folder)}")
        self.options.add_opt_simple(:transfer_node,"--transfer-node=STRING","name of configuration used to transfer when using --transfer=node")
        self.options.add_opt_simple(:fields,"--fields=STRING","comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        self.options.add_opt_simple(:fasp_proxy,"--fasp-proxy=STRING","URL of FASP proxy (dnat / dnats)")
        self.options.add_opt_simple(:http_proxy,"--http-proxy=STRING","URL of HTTP proxy (for http fallback)")
        self.options.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
        self.options.add_opt_on(:no_default,"-N", "--no-default","dont load default configuration") { @load_plugin_defaults=false }
        self.options.add_opt_on(:version,"-v","--version","display version") { puts Asperalm::VERSION;Process.exit(0) }
        self.options.add_opt_simple(:ts,"--ts=JSON","override transfer spec values for transfers (hash, use @json: prefix), current=#{self.options.get_option(:ts)}")
      end

      def self.flatten_config_show(t)
        r=[]
        t.each do |k,v|
          v.each do |kk,vv|
            r.push({"config"=>k,"parameter"=>kk,"value"=>vv})
          end
        end
        return r
      end

      # "config" plugin
      def execute_action
        action=self.options.get_next_arg_from_list('action',[:genkey,:plugins,:flush_tokens,:list,:overview,:open,:echo,:id])
        case action
        when :id
          config_name=self.options.get_next_arg_value('config name')
          action=self.options.get_next_arg_from_list('action',[:set,:delete,:initialize,:show])
          case action
          when :show
            raise "no such config: #{config_name}" if !@loaded_configs.has_key?(config_name)
            return {:type=>:key_val_list,:data=>@loaded_configs[config_name]}
          when :delete
            @loaded_configs.delete(config_name)
            write_config_file
            return Main.status_result("deleted: #{config_name}")
          when :set
            param_name=self.options.get_next_arg_value('parameter name')
            param_value=self.options.get_next_arg_value('parameter value')
            if !@loaded_configs.has_key?(config_name)
              Log.log.debug("no such config name: #{config_name}, initializing")
              @loaded_configs[config_name]=Hash.new
            end
            if @loaded_configs[config_name].has_key?(param_name)
              Log.log.warn("overwriting value: #{@loaded_configs[config_name][param_name]}")
            end
            @loaded_configs[config_name][param_name]=param_value
            write_config_file
            return Main.status_result("updated: #{config_name}->#{param_name} to #{param_value}")
          when :initialize
            config_value=self.options.get_next_arg_value('config value')
            if @loaded_configs.has_key?(config_name)
              Log.log.warn("configuration already exists: #{config_name}, overwriting")
            end
            @loaded_configs[config_name]=config_value
            write_config_file
            return Main.status_result("modified: #{current_config_file}")
          end
        when :open
          OperatingSystem.open_uri(current_config_file)
          return Main.no_result
        when :genkey # generate new rsa key
          key_filepath=self.options.get_next_arg_value('private key file path')
          require 'net/ssh'
          priv_key = OpenSSL::PKey::RSA.new(2048)
          File.write(key_filepath,priv_key.to_s)
          File.write(key_filepath+".pub",priv_key.public_key.to_s)
          return Main.status_result('generated key: '+key_filepath)
        when :echo # display the content of a value given on command line
          return {:type=>:other_struct, :data=>self.options.get_next_arg_value("value")}
        when :flush_tokens
          deleted_files=Oauth.flush_tokens(config_folder)
          return {:type=>:value_list, :name=>'file',:data=>deleted_files}
          return Main.status_result('token cache flushed')
        when :plugins
          return {:data => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :hash_array }
        when :list
          return {:data => @loaded_configs.keys, :type => :value_list, :name => 'name'}
        when :overview
          return {:type=>:hash_array,:data=>self.class.flatten_config_show(@loaded_configs)}
        end
      end

      # supported output formats
      def self.display_formats; [:table,:ruby,:json,:jsonpp,:yaml,:csv]; end

      RECORD_SEPARATOR="\n"
      FIELD_SEPARATOR=","

      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash (#{results.class}: #{results})" if !results.is_a?(Hash)
        raise "INTERNAL ERROR, result must have type" if !results.has_key?(:type)
        raise "INTERNAL ERROR, result must have data" if !results.has_key?(:data) and !results[:type].eql?(:empty)

        required_fields=self.options.get_option_mandatory(:fields)
        case self.options.get_option_mandatory(:format)
        when :ruby
          puts PP.pp(results[:data],'')
        when :json
          puts JSON.generate(results[:data])
        when :jsonpp
          puts JSON.pretty_generate(results[:data])
        when :yaml
          puts results[:data].to_yaml
        when :table,:csv
          case results[:type]
          when :hash_array
            raise "internal error: unexpected type: #{results[:data].class}, expecting Array" if !results[:data].is_a?(Array)
            # :hash_array is an array of hash tables, where key=colum name
            table_data = results[:data]
            display_fields=nil
            case required_fields
            when FIELDS_DEFAULT
              if results.has_key?(:fields) and !results[:fields].nil?
                display_fields=results[:fields]
              else
                if !table_data.empty?
                  display_fields=table_data.first.keys
                else
                  display_fields=['empty']
                end
              end
            when FIELDS_ALL
              raise "empty results" if table_data.empty?
              display_fields=table_data.first.keys if table_data.is_a?(Array)
            else
              display_fields=required_fields.split(',')
            end
          when :key_val_list
            raise "internal error: unexpected type: #{results[:data].class}, expecting Hash" if !results[:data].is_a?(Hash)
            # :key_val_list is a simple hash table
            case required_fields
            when FIELDS_DEFAULT,FIELDS_ALL; display_fields = ['key','value']
            else display_fields=required_fields.split(',')
            end
            table_data=results[:data].keys.map { |i| { 'key' => i, 'value' => results[:data][i] } }
          when :value_list
            # :value_list is a simple array of values, name of column provided in the :name
            display_fields = [results[:name]]
            table_data=results[:data].map { |i| { results[:name] => i } }
          when :empty
            puts "empty"
            return
          when :status
            # :status displays a simple message
            puts results[:data]
            return
          when :other_struct
            # :other_struct is any other type of structure
            puts PP.pp(results[:data],'')
            return
          else
            raise "unknown data type: #{results[:type]}"
          end
          raise "no field specified" if display_fields.nil?
          # convert to string with special function. here table_data is an array of hash
          table_data=results[:textify].call(table_data) if results.has_key?(:textify)
          # convert data to string, and keep only display fields
          table_data=table_data.map { |r| display_fields.map { |c| r[c].to_s } }
          case self.options.get_option_mandatory(:format)
          when :table
            # display the table !
            puts Text::Table.new(
            :head => display_fields,
            :rows => table_data,
            :vertical_boundary  => '.',
            :horizontal_boundary => ':',
            :boundary_intersection => ':')
          when :csv
            puts table_data.map{|t| t.join(FIELD_SEPARATOR)}.join(RECORD_SEPARATOR)
          end
        end
      end

      def exit_with_usage(all_plugins)
        # display main plugin options
        STDERR.puts self.options
        if all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          plugin_sym_list.select { |s| !@plugins[s][:req].nil? }.each do |plugin_name_sym|
            # override main option parser...
            @options=OptParser.new
            self.options.banner = ""
            self.options.program_name=@@PROGRAM_NAME
            get_plugin_instance(plugin_name_sym)
            STDERR.puts(self.options)
          end
        end
        Process.exit 1
      end

      def process_exception_exit(e,reason,propose_help=:none)
        STDERR.puts "ERROR:".bg_red().gray().blink()+" "+reason+": "+e.message
        STDERR.puts "Use '-h' option to get help." if propose_help.eql?(:usage)
        if Log.level == :debug
          raise e
        else
          STDERR.puts "Use '--log-level=debug' to get more details." if propose_help.eql?(:debug)
          Process.exit 1
        end
      end

      # load config file and optionally loads parameters in options
      def load_config_file
        @loaded_configs=read_config_file
        Log.log.debug "loaded: #{@loaded_configs}"
        # check there is at least the config section
        if !@loaded_configs.has_key?(@@MAIN_PLUGIN_NAME_STR)
          raise CliError,"Config File: Cannot find key #{@@MAIN_PLUGIN_NAME_STR} in #{current_config_file}. Please check documentation."
        end
        # check version
        version=@loaded_configs[@@MAIN_PLUGIN_NAME_STR][@@CONFIG_FILE_KEY_VERSION]
        raise CliError,"Config File: No version found. Please check documentation. Expecting min version #{@@MIN_CONFIG_VERSION}" if version.nil?
        if Gem::Version.new(version) < Gem::Version.new(@@MIN_CONFIG_VERSION)
          raise CliError,"Unsupported config file version #{version}. Please check documentation. Expecting min version #{@@MIN_CONFIG_VERSION}"
        end
        # did the user specify parameters to load ?
        config_name_list=self.options.get_option(:load_params)
        if !config_name_list.nil?
          config_name_list.split(/,/).each do |name|
            Log.log.debug "loading config: #{name} : #{@loaded_configs[name]}".red
            if @loaded_configs.has_key?(name)
              self.options.set_defaults(@loaded_configs[name])
            elsif name.eql?(@@NO_DEFAULT)
              Log.log.debug("dont use generic default")
            else
              raise CliBadArgument,"no such config name: #{name}\nList configs with: aslmcli config list"
            end
          end
        end
      end

      # this is the main function called by initial script
      def process_command_line(argv)
        begin
          # init options
          # opt parser separates options (start with '-') from arguments
          self.options.set_argv(argv)
          # declare global options and set defaults
          self.declare_options
          # read options from env vars
          self.options.read_env_vars
          # parse general options
          self.options.parse_options!
          # load default config if it was not overriden on command line
          load_config_file
          # help requested without command ?
          self.exit_with_usage(true) if @help_requested and self.options.command_or_arg_empty?
          # load global default options, main plugin is not dynamically instanciated
          plugins_defaults=get_plugin_default_parameters(@@MAIN_PLUGIN_NAME_STR.to_sym)
          self.options.set_defaults(plugins_defaults) if !plugins_defaults.nil?
          command_sym=self.options.get_next_arg_from_list('command',plugin_sym_list)
          case command_sym
          when @@MAIN_PLUGIN_NAME_STR.to_sym
            command_plugin=self
          else
            # get plugin, set options, etc
            command_plugin=self.get_plugin_instance(command_sym)
            # parse plugin specific options
            self.options.parse_options!
          end
          # help requested ?
          self.exit_with_usage(false) if @help_requested
          display_results(command_plugin.execute_action)
          # unprocessed values ?
          if !self.options.unprocessed_options.empty?
            raise CliBadArgument,"unprocessed options: #{self.options.unprocessed_options}"
          end
          if !self.options.command_or_arg_empty?
            raise CliBadArgument,"unprocessed values: #{self.options.get_remaining_arguments(nil)}"
          end
        rescue CliBadArgument => e;          process_exception_exit(e,'Argument',:usage)
        rescue CliError => e;                process_exception_exit(e,'Tool',:usage)
        rescue Asperalm::TransferError => e; process_exception_exit(e,"Transfer")
        rescue Asperalm::RestCallError => e; process_exception_exit(e,"Rest")
        rescue SocketError => e;             process_exception_exit(e,"Network")
        rescue StandardError => e;           process_exception_exit(e,"Other",:debug)
        end
        return self
      end
    end
  end
end
