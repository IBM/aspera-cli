require "asperalm/cli/opt_parser"
require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require 'asperalm/operating_system'
require 'asperalm/oauth'
require 'yaml'
require 'text-table'
require 'pp'
require 'fileutils'

module Asperalm
  module Cli
    module Plugins
    end

    class Main < Plugin
      # first level command for the main tool
      @@MAIN_PLUGIN_NAME_SYM=:config
      # name of application, also foldername where config is stored
      $PROGRAM_NAME = 'aslmcli'
      # folder in $HOME for the application
      @@ASPERA_HOME_FOLDERNAME='.aspera'
      # folder containing custom plugins in `config_folder`
      @@ASPERA_PLUGINS_FOLDERNAME='plugins'
      # main config file
      @@DEFAULT_CONFIG_FILENAME = 'config.yaml'
      # the singleton of this tool
      @@singleton=nil
      # folder containing plugins in the gem's main folder
      @@GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
      # Path to module Cli : Asperalm::Cli
      @@CLI_MODULE=Module.nesting[1].to_s
      # Path to Plugin classes: Asperalm::Cli::Plugins
      @@PLUGINS_MODULE=@@CLI_MODULE+"::Plugins"
      # $HOME/.aspera/aslmcli
      def config_folder
        return File.join(Dir.home,@@ASPERA_HOME_FOLDERNAME,$PROGRAM_NAME)
      end

      # $HOME/.aspera/aslmcli/config.yaml
      def config_file
        return File.join(config_folder,@@DEFAULT_CONFIG_FILENAME)
      end

      # get default configuration for named application
      def get_plugin_default_config(plugin_sym,config_name)
        if @configs.nil?
          Log.log.debug("no default config")
          return nil
        end
        config_id=plugin_sym.to_s+'_'+config_name
        if !@configs.has_key?(config_id)
          Log.log.debug("no default config: #{config_id}")
          return nil
        end
        default_config=@configs[config_id]
        Log.log.debug("#{plugin_sym} default config=#{default_config}")
        return default_config
      end

      def self.no_result
        return {:data => :nil, :type => :empty }
      end

      def self.status_result(status)
        return {:data => status, :type => :status }
      end

      def self.result_success
        return status_result('complete')
      end

      def attr_logtype(operation,value)
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

      def attr_loglevel(operation,value)
        case operation
        when :set
          Log.level = value
        else
          return Log.level
        end
      end

      def attr_insecure(operation,value)
        case operation
        when :set
          Rest.insecure=value
        else
          return Rest.insecure
        end
      end

      def attr_config_file(operation,value)
        case operation
        when :set
          @config_file_path=value
          Log.log.debug "loading #{value}"
          @configs=YAML.load_file(value)
          Log.log.debug "loaded: #{@configs}"
          self.options.set_defaults(get_plugin_default_config(@@MAIN_PLUGIN_NAME_SYM,self.options.get_option(:config_name)))
        else
          return @config_file_path
        end
      end

      def attr_transfer_spec(operation,value)
        case operation
        when :set
          Log.log.debug "attr_transfer_spec: set: #{value}".red
          FaspManager.ts_override_json=value
        else
          return FaspManager.ts_override_json
        end
      end

      def attr_browser(operation,value)
        case operation
        when :set
          Log.log.debug "attr_browser: set: #{value}".red
          OperatingSystem.open_url_method=value
        else
          return OperatingSystem.open_url_method
        end
      end

      def attr_load_params(operation,value)
        case operation
        when :set
          Log.log.debug "attr_load_params: set: #{value} : #{@configs[value]}".red
          self.options.set_defaults(@configs[value])
        else
          return nil
        end
      end

      def attr_fasp_folder(operation,value)
        case operation
        when :set
          Log.log.debug "attr_fasp_folder: set: #{value}".red
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

      # returns the list of plugins from plugin folder
      def scan_plugins(plugin_folder,plugin_subfolder)
        plugin_folder=File.join(plugin_folder,plugin_subfolder) if !plugin_subfolder.nil?
        Dir.entries(plugin_folder).select { |file| file.end_with?('.rb')}.each do |source|
          name=source.gsub(/\.rb$/,'')
          @plugins[name.to_sym]={:source=>File.join(plugin_folder,source),:req=>File.join(plugin_folder,name)}
        end
      end

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
          case self.options.get_option_mandatory(:transfer)
          when :connect
            @faspmanager.use_connect_client=true
          when :node
            node_config=get_plugin_default_config(:node,self.options.get_option_mandatory(:transfer_node_config))
            raise CliBadArgument,"no such node configuration: #{self.options.get_option_mandatory(:transfer_node_config)}" if node_config.nil?
            @faspmanager.tr_node_api=Rest.new(node_config[:url],{:auth=>{:type=>:basic,:user=>node_config[:username], :password=>node_config[:password]}})
          end
          # may be nil:
          @faspmanager.fasp_proxy_url=self.options.get_option(:fasp_proxy)
          @faspmanager.http_proxy_url=self.options.get_option(:http_proxy)
        end
        return @faspmanager
      end

      def options; @options;end

      def initialize(option_parser)
        @help_requested=false
        @options=option_parser
        @configs=nil
        @faspmanager=nil
        scan_all_plugins
        self.options.program_name=$PROGRAM_NAME
        self.options.banner = "NAME\n\t#{$PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{VERSION})\n\n"
        self.options.separator "SYNOPSIS"
        self.options.separator "\t#{$PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
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
        self.options.separator "\t#{$PROGRAM_NAME} files repo browse /"
        self.options.separator "\t#{$PROGRAM_NAME} faspex send ./myfile --log-level=debug"
        self.options.separator "\t#{$PROGRAM_NAME} shares upload ~/myfile /myshare"
        self.options.separator ""
        # handler must be set before setting defaults
        self.options.set_handler(:loglevel) { |op,val| attr_loglevel(op,val) }
        self.options.set_handler(:logtype) { |op,val| attr_logtype(op,val) }
        self.options.set_handler(:config_file) { |op,val| attr_config_file(op,val) }
        self.options.set_handler(:insecure) { |op,val| attr_insecure(op,val) }
        self.options.set_handler(:transfer_spec) { |op,val| attr_transfer_spec(op,val) }
        self.options.set_handler(:browser) { |op,val| attr_browser(op,val) }
        self.options.set_handler(:load_params) { |op,val| attr_load_params(op,val) }
        self.options.set_handler(:fasp_folder) { |op,val| attr_fasp_folder(op,val) }
      end

      # plugin_name_sym is symbol
      # initialize if necessary
      def get_plugin_instance(plugin_name_sym)
        require @plugins[plugin_name_sym][:req]
        Log.log.debug("loaded config -> #{@configs}")
        # TODO: check that ancestor is Plugin?
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new
        self.options.set_defaults(get_plugin_default_config(plugin_name_sym,self.options.get_option_mandatory(:config_name)))
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
        self.options.set_option(:transfer_node_config,'default')
        self.options.set_option(:insecure,:no)
        self.options.set_option(:format,:table)
        self.options.set_option(:logtype,:stdout)
        self.options.set_option(:config_file,config_file) if File.exist?(config_file)
        self.options.on("-h", "--help", "Show this message. Try: #{@@MAIN_PLUGIN_NAME_SYM} help") { @help_requested=true }
        self.options.add_opt_list(:browser,OperatingSystem.open_url_methods,"method to start browser",'-gTYPE','--browser=TYPE')
        self.options.add_opt_list(:insecure,[:yes,:no],"do not validate cert",'--insecure=VALUE')
        self.options.add_opt_list(:loglevel,Log.levels,"Log level",'-lTYPE','--log-level=VALUE')
        self.options.add_opt_list(:logtype,Log.logtypes,"log method",'-qTYPE','--logger=VALUE')
        self.options.add_opt_list(:format,self.class.result_formats,"output format",'--format=VALUE')
        self.options.add_opt_list(:transfer,[:ascp,:connect,:node],"type of transfer",'--transfer=VALUE')
        self.options.add_opt_simple(:config_file,"-CSTRING", "--config=STRING","read parameters from file in YAML format, current=#{self.options.get_option(:config_file)}")
        self.options.add_opt_simple(:config_name,"-nSTRING", "--cname=STRING","name of configuration in config file")
        self.options.add_opt_simple(:load_params,"--load-params=NAME","load the named configuration from current config file")
        self.options.add_opt_simple(:fasp_folder,"--fasp-folder=NAME","specify where to find FASP (main folder), current=#{self.options.get_option(:fasp_folder)}")
        self.options.add_opt_simple(:transfer_node_config,"--transfer-node=STRING","name of configuration used to transfer when using --transfer=node")
        self.options.add_opt_simple(:fields,"--fields=STRING","comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        self.options.add_opt_simple(:fasp_proxy,"--fasp-proxy=STRING","URL of FASP proxy (dnat / dnats)")
        self.options.add_opt_simple(:http_proxy,"--http-proxy=STRING","URL of HTTP proxy (for http fallback)")
        self.options.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
        self.options.add_opt_simple(:transfer_spec,"--ts=JSON","override transfer spec values, current=#{self.options.get_option(:transfer_spec)}")
      end

      # "cli" plugin
      def execute_action
        action=self.options.get_next_arg_from_list('action',[:help,:plugins,:flush,:ls,:init,:cat,:open])
        case action
        when :flush
          deleted_files=Oauth.flush_tokens
          return {:type=>:value_list, :name=>'file',:data=>deleted_files}
          return Main.status_result('token cache flushed')
        when :help
          # display main plugin options
          STDERR.puts self.options
          # list plugins that have a "require" field, i.e. all but main plugin
          plugin_sym_list.select { |s| !@plugins[s][:req].nil? }.each do |plugin_name_sym|
            # override main option parser...
            @options=OptParser.new
            self.options.banner = ""
            self.options.program_name=$PROGRAM_NAME
            self.options.set_defaults({:config_name => 'default',:transfer=>:ascp})
            get_plugin_instance(plugin_name_sym)
            STDERR.puts(self.options)
          end
          Process.exit 1
        when :plugins
          return {:data => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :hash_array }
        when :init
          raise CliError,"Folder already exists: #{config_folder}" if Dir.exist?(config_folder)
          FileUtils::mkdir_p(config_folder)
          sample_config={
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
          File.write(config_file,sample_config.to_yaml)
          puts "initialized: #{config_folder}"
          return Main.no_result
        when :cat
          return {:data=>File.read(config_file),:type=>:other_struct}
        when :open
          OperatingSystem.open_system_uri(config_file)
          return Main.no_result
        when :ls
          sections=plugin_sym_list
          if self.options.command_or_arg_empty?
            # just list plugins
            return {:data => sections, :type => :value_list, :name => 'plugin'}
          else
            plugin=self.options.get_next_arg_from_list('plugin',sections)
            names=@configs[plugin].keys.map { |i| i.to_sym }
            if self.options.command_or_arg_empty?
              # list names for tool
              return {:data => names, :type => :value_list, :name => 'name'}
            else
              # list parameters
              configname=self.options.get_next_arg_from_list('config',names)
              defaults=get_plugin_default_config(plugin,configname.to_s)
              return Main.no_result if defaults.nil?
              return {:data => defaults.keys.map { |i| { 'param' => i.to_s, 'value' => defaults[i] } } , :fields => ['param','value'], :type => :hash_array }
            end
          end
        end
      end

      # TODO: csv
      def self.result_formats; [:table,:ruby,:json,:yaml]; end

      def display_results(results)
        raise "ERROR, result must be Hash" if !results.is_a?(Hash)
        raise "ERROR, result must have data" if !results.has_key?(:data)
        raise "ERROR, result must have type" if !results.has_key?(:type)

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
            raise "ERROR"
          end
          raise "ERROR" if display_fields.nil?
          # convert to string with special function
          table_data=results[:textify].call(table_data) if results.has_key?(:textify)
          # convert data to string
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

      def exit_with_usage
        STDERR.puts self.options
        Process.exit 1
      end

      def process_exception_exit(e,reason,propose_help=:none)
        STDERR.puts "ERROR:".bg_red().gray().blink()+" "+reason+": "+e.message
        STDERR.puts "Use '-h' option, or '#{@@MAIN_PLUGIN_NAME_SYM} help' command to get help." if propose_help.eql?(:usage)
        if Log.level == :debug
          raise e
        else
          STDERR.puts "Use '--log-level=debug' to get more details." if propose_help.eql?(:debug)
          Process.exit 1
        end
      end

      def process_command_line(argv)
        begin
          # init options
          self.options.set_argv(argv)
          self.options.set_defaults({:config_name => 'default'})
          # declare global options
          self.declare_options
          # parse general options always, before finding plugin
          self.options.parse_options!
          # help requested without command ?
          self.exit_with_usage if @help_requested and self.options.command_or_arg_empty?
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
          self.exit_with_usage if @help_requested
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
        return nil
      end

      # get the main tool singleton instance
      def self.tool
        if @@singleton.nil?
          # quick init of debug level
          Log.level = ARGV.include?('--log-level=debug') ? :debug : :warn
          # opt parser separates options (start with '-') from arguments
          @@singleton = self.new(OptParser.new)
        end
        return @@singleton
      end

    end
  end
end
