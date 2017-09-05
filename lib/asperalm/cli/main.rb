require "asperalm/cli/opt_parser"
require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require 'asperalm/operating_system'
require 'asperalm/oauth'
require 'text-table'
require 'fileutils'
require 'singleton'
require 'yaml'
require 'pp'

module Asperalm
  module Cli
    module Plugins; end

    # The main CI class, singleton
    class Main < Plugin
      include Singleton
      # "tool" class method is an alias to "instance"
      singleton_class.send(:alias_method, :tool, :instance)

      # first level command for the main tool
      @@MAIN_PLUGIN_NAME_SYM=:config
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
      @@CONFIG_FILE_KEY_VERSION=:version
      # oldest compatible conf file format
      @@MIN_CONFIG_VERSION='0.3.7'
      # $HOME/.aspera/aslmcli
      def config_folder
        return File.join(Dir.home,@@ASPERA_HOME_FOLDERNAME,@@PROGRAM_NAME)
      end

      # $HOME/.aspera/aslmcli/config.yaml
      def default_config_file
        return File.join(config_folder,@@DEFAULT_CONFIG_FILENAME)
      end

      # returns default parameters for a plugin from loaded config file
      def get_plugin_default_parameters(plugin_sym)
        return nil if @loaded_configs.nil?
        default_config_name=plugin_sym.to_s+'_default'
        if @loaded_configs.has_key?(@@MAIN_PLUGIN_NAME_SYM.to_s) and
        @loaded_configs[@@MAIN_PLUGIN_NAME_SYM.to_s].has_key?(:default) and
        @loaded_configs[@@MAIN_PLUGIN_NAME_SYM.to_s][:default].has_key?(plugin_sym)
          default_config_name=@loaded_configs[@@MAIN_PLUGIN_NAME_SYM.to_s][:default][plugin_sym]
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
          Log.setlogger(value)
          self.options.set_option(:loglevel,:warn)
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
          FaspManager.ts_override_json=value
        else
          return FaspManager.ts_override_json
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
        @plugins={@@MAIN_PLUGIN_NAME_SYM=>{:source=>__FILE__,:req=>nil}}
        gem_root=File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'), File.dirname(__FILE__))
        scan_plugins(gem_root,@@GEM_PLUGINS_FOLDER)
        user_plugin_folder=File.join(config_folder,@@ASPERA_PLUGINS_FOLDERNAME)
        if File.directory?(user_plugin_folder)
          $:.push(user_plugin_folder)
          scan_plugins(user_plugin_folder,nil)
        end
      end

      def faspmanager
        if @faspmanager.nil?
          # create the FASP manager for transfers
          @faspmanager=FaspManagerResume.new
          @faspmanager.set_listener(FaspListenerLogger.new)
          @faspmanager.connect_app_id=@@PROGRAM_NAME
          case self.options.get_option_mandatory(:transfer)
          when :connect
            @faspmanager.use_connect_client=true
          when :node
            config_name=self.options.get_option(:transfer_node_config)
            if config_name.nil?
              node_config=get_plugin_default_parameters(:node)
              raise CliBadArgument,"Please specify --transfer-node" if node_config.nil?
            else
              node_config=@loaded_configs[config_name]
              raise CliBadArgument,"no such node configuration: #{config_name}" if node_config.nil?
            end
            @faspmanager.tr_node_api=Rest.new(node_config[:url],{:auth=>{:type=>:basic,:user=>node_config[:username], :password=>node_config[:password]}})
          end
          # may be nil:
          @faspmanager.fasp_proxy_url=self.options.get_option(:fasp_proxy)
          @faspmanager.http_proxy_url=self.options.get_option(:http_proxy)
        end
        return @faspmanager
      end

      def start_transfer(transfer_spec)
        faspmanager.transfer_with_spec(transfer_spec)
        return self.class.result_success
      end

      def options; @options;end

      def initialize
        @help_requested=false
        @options=OptParser.new
        @loaded_configs=nil
        @faspmanager=nil
        scan_all_plugins
        self.options.program_name=@@PROGRAM_NAME
        self.options.banner = "NAME\n\t#{@@PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{VERSION})\n\n"
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
        self.options.set_handler(:loglevel) { |op,val| handler_loglevel(op,val) }
        self.options.set_handler(:logtype) { |op,val| handler_logtype(op,val) }
        self.options.set_handler(:insecure) { |op,val| handler_insecure(op,val) }
        self.options.set_handler(:transfer_spec) { |op,val| handler_transfer_spec(op,val) }
        self.options.set_handler(:browser) { |op,val| handler_browser(op,val) }
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
          self.options.set_defaults(get_plugin_default_parameters(plugin_name_sym))
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
        self.options.set_option(:browser,:tty)
        self.options.set_option(:fields,FIELDS_DEFAULT)
        self.options.set_option(:transfer,:ascp)
        #self.options.set_option(:transfer_node_config,'default')
        self.options.set_option(:insecure,:no)
        self.options.set_option(:format,:table)
        self.options.set_option(:logtype,:stdout)
        self.options.set_option(:config_file,default_config_file) if File.exist?(default_config_file)
        self.options.on("-h", "--help", "Show this message. Try: #{@@MAIN_PLUGIN_NAME_SYM} help") { @help_requested=true }
        self.options.add_opt_list(:browser,OperatingSystem.open_url_methods,"method to start browser",'-gTYPE','--browser=TYPE')
        self.options.add_opt_list(:insecure,[:yes,:no],"do not validate cert",'--insecure=VALUE')
        self.options.add_opt_list(:loglevel,Log.levels,"Log level",'-lTYPE','--log-level=VALUE')
        self.options.add_opt_list(:logtype,Log.logtypes,"log method",'-qTYPE','--logger=VALUE')
        self.options.add_opt_list(:format,self.class.result_formats,"output format",'--format=VALUE')
        self.options.add_opt_list(:transfer,[:ascp,:connect,:node],"type of transfer",'--transfer=VALUE')
        self.options.add_opt_simple(:config_file,"-CSTRING", "--config=STRING","read parameters from file in YAML format, current=#{self.options.get_option(:config_file)}")
        self.options.add_opt_simple(:load_params,"-PNAME","--load-params=NAME","load the named configuration from current config file")
        self.options.add_opt_simple(:fasp_folder,"--fasp-folder=NAME","specify where to find FASP (main folder), current=#{self.options.get_option(:fasp_folder)}")
        self.options.add_opt_simple(:transfer_node_config,"--transfer-node=STRING","name of configuration used to transfer when using --transfer=node")
        self.options.add_opt_simple(:fields,"--fields=STRING","comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        self.options.add_opt_simple(:fasp_proxy,"--fasp-proxy=STRING","URL of FASP proxy (dnat / dnats)")
        self.options.add_opt_simple(:http_proxy,"--http-proxy=STRING","URL of HTTP proxy (for http fallback)")
        self.options.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
        self.options.add_opt_simple(:transfer_spec,"--ts=JSON","override transfer spec values, current=#{self.options.get_option(:transfer_spec)}")
      end

      # "config" plugin
      def execute_action
        action=self.options.get_next_arg_from_list('action',[:plugins,:flush,:ls,:init,:cat,:open,:show])
        case action
        when :show # display the content of a value given on command line
          return {:type=>:other_struct, :data=>self.options.get_next_arg_value("value")}
        when :flush
          deleted_files=Oauth.flush_tokens(config_folder)
          return {:type=>:value_list, :name=>'file',:data=>deleted_files}
          return Main.status_result('token cache flushed')
        when :plugins
          return {:data => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :hash_array }
        when :init
          raise CliError,"Folder already exists: #{config_folder}" if Dir.exist?(config_folder)
          FileUtils::mkdir_p(config_folder)
          sample_config={
            "config" =>{@@CONFIG_FILE_KEY_VERSION=>Asperalm::VERSION},
            "cli_default"=>{:loglevel=>:warn},
            "files_default"=>{:auth=>:jwt, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MyAccessKeySecret", :private_key=>"@file:~/.aspera/aslmcli/filesapikey", :username=>"user@example.com"},
            "files_web"=>{:auth=>:web, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MyAccessKeySecret", :redirect_uri=>"http://local.connectme.us:12345"},
            "faspex_default"=>{:url=>"https://myfaspex.mycompany.com/aspera/faspex", :username=>"admin", :password=>"MyP@ssw0rd",:storage=>{'Local Storage'=>{:node=>'default',:path=>'/subpath'}}},
            "faspex_app2"=>{:url=>"https://faspex.other.com/aspera/faspex", :username=>"john@example", :password=>"yM7FmjfGN$J4"},
            "shares_default"=>{:url=>"https://10.25.0.6", :username=>"admin", :password=>"MyP@ssw0rd"},
            "node_default"=>{:url=>"https://10.25.0.8:9092", :username=>"node_user", :password=>"MyP@ssw0rd", :transfer_filter=>"t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?('faspex')", :file_filter=>"f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?('send')"},
            "console_default"=>{:url=>"https://console.myorg.com/aspera/console", :username=>"admin", :password=>"xxxxx"},
            "fasp_default"=>{:transfer_spec=>'{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","password":"xxxxx"}'}
          }
          File.write(default_config_file,sample_config.to_yaml)
          puts "initialized: #{config_folder}"
          return Main.no_result
        when :cat
          return {:data=>File.read(default_config_file),:type=>:other_struct}
        when :open
          OperatingSystem.open_system_uri(default_config_file)
          return Main.no_result
        when :ls
          config_names=@loaded_configs.keys
          if self.options.command_or_arg_empty?
            # just list config names
            return {:data => config_names, :type => :value_list, :name => 'name'}
          else
            config_name=self.options.get_next_arg_from_list('config name',config_names)
            parameters=@loaded_configs[config_name].keys.map { |i| i.to_sym }
            if self.options.command_or_arg_empty?
              return {:data => @loaded_configs[config_name], :type => :key_val_list }
            else
              # list parameters
              param_symb=self.options.get_next_arg_from_list('parameter name',parameters)
              return {:data => [ @loaded_configs[config_name][param_symb] ] , :type => :value_list, :name => param_symb.to_s  }
            end
          end
        end
      end

      # TODO: csv
      def self.result_formats; [:table,:ruby,:json,:yaml]; end

      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash" if !results.is_a?(Hash)
        raise "INTERNAL ERROR, result must have type" if !results.has_key?(:type)
        raise "INTERNAL ERROR, result must have data" if !results.has_key?(:data) and !results[:type].eql?(:empty)

        required_fields=self.options.get_option_mandatory(:fields)
        case self.options.get_option_mandatory(:format)
        when :ruby
          puts PP.pp(results[:data],'')
        when :json
          puts JSON.generate(results[:data])
        when :yaml
          puts results[:data].to_yaml
        when :table
          case results[:type]
          when :hash_array
            # :hash_array is an array of hash tables, where key=colum name
            table_data = results[:data]
            display_fields=nil
            case required_fields
            when FIELDS_DEFAULT
              if results.has_key?(:fields) and !results[:fields].nil?
                display_fields=results[:fields]
              else
                raise "empty results" if table_data.empty?
                display_fields=table_data.first.keys
              end
            when FIELDS_ALL
              raise "empty results" if table_data.empty?
              display_fields=table_data.first.keys if table_data.is_a?(Array)
            else
              display_fields=required_fields.split(',')
            end
          when :key_val_list
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
          raise "ERROR" if display_fields.nil?
          # convert to string with special function. here table_data is an array of hash
          table_data=results[:textify].call(table_data) if results.has_key?(:textify)
          # convert data to string, and keep only display fields
          table_data=table_data.map { |r| display_fields.map { |c| r[c].to_s } }
          # display the table !
          puts Text::Table.new(
          :head => display_fields,
          :rows => table_data,
          :vertical_boundary  => '.',
          :horizontal_boundary => ':',
          :boundary_intersection => ':')
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
        file_path=self.options.get_option(:config_file)
        if file_path.nil?
          Log.log.debug "nil config file"
          @loaded_configs={"config"=>{}}
          return
        end
        Log.log.debug "loading #{file_path}"
        @loaded_configs=YAML.load_file(file_path)
        Log.log.debug "loaded: #{@loaded_configs}"
        # check there is at least the config section
        if !@loaded_configs.has_key?(@@MAIN_PLUGIN_NAME_SYM.to_s)
          raise CliError,"Config File: Cannot find key #{@@MAIN_PLUGIN_NAME_SYM.to_s} in #{file_path}. Please check documentation."
        end
        # check version
        version=@loaded_configs[@@MAIN_PLUGIN_NAME_SYM.to_s][@@CONFIG_FILE_KEY_VERSION]
        raise CliError,"Config File: No version found. Please check documentation. Expecting min version #{@@MIN_CONFIG_VERSION}" if version.nil?
        if Gem::Version.new(version) < Gem::Version.new(@@MIN_CONFIG_VERSION)
          raise CliError,"Unsupported config file version #{version}. Please check documentation. Expecting min version #{@@MIN_CONFIG_VERSION}"
        end
        # did the user specify parameters to load ?
        config_name_list=self.options.get_option(:load_params)
        if !config_name_list.nil?
          config_name_list.split(/,/).each do |name|
            Log.log.debug "loading config: #{name} : #{@loaded_configs[name]}".red
            self.options.set_defaults(@loaded_configs[name])
          end
        end
      end

      # this is the main function called by initial script
      def process_command_line(argv)
        begin
          # init options
          # opt parser separates options (start with '-') from arguments
          self.options.set_argv(argv)
          # declare global options
          self.declare_options
          # parse general options
          self.options.parse_options!
          # load default config if it was not overriden on command line
          load_config_file
          # help requested without command ?
          self.exit_with_usage(true) if @help_requested and self.options.command_or_arg_empty?
          command_sym=self.options.get_next_arg_from_list('command',plugin_sym_list)
          case command_sym
          when @@MAIN_PLUGIN_NAME_SYM
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
        rescue SocketError => e;             process_exception_exit(e,"Network")
        rescue StandardError => e;           process_exception_exit(e,"Other",:debug)
        end
        return self
      end
    end
  end
end
