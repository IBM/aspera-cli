require "asperalm/cli/opt_parser"
require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require 'asperalm/browser_interaction'
require 'yaml'
require 'text-table'
require 'pp'
require 'fileutils'

module Asperalm
  module Cli
    module Plugins
    end

    class Main < Plugin
      @@MAIN_PLUGIN_NAME_SYM=:cli
      @@global_config=nil
      # get default configuration for named application
      def self.get_config_defaults(plugin_sym,config_name)
        if @@global_config.nil?
          Log.log.debug("no default config")
          return nil
        end
        if !@@global_config.has_key?(plugin_sym)
          Log.log.debug("no default config for #{plugin_sym}")
          return nil
        end
        default_config=@@global_config[plugin_sym][config_name]
        Log.log.debug("#{plugin_sym} default config=#{default_config}")
        return default_config
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
          @@global_config=YAML.load_file(value)
          Log.log.debug "loaded: #{@@global_config}"
          self.options.set_defaults(Main.get_config_defaults(@@MAIN_PLUGIN_NAME_SYM,self.options.get_option(:config_name)))
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
          BrowserInteraction.open_url_method=value
        else
          return BrowserInteraction.open_url_method
        end
      end
      @@GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
      @@CLI_MODULE=Module.nesting[1].to_s
      @@PLUGINS_MODULE=@@CLI_MODULE+"::Plugins"

      # returns the list of plugins from plugin folder
      def plugin_sym_list
        return @plugins.keys
      end

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
        if File.directory?(@@USER_PLUGINS_FOLDER)
          $:.push(@@USER_PLUGINS_FOLDER)
          scan_plugins(@@USER_PLUGINS_FOLDER,nil)
        end
      end

      def initialize(option_parser)
        super(option_parser)
        scan_all_plugins
        self.options.program_name=$PROGRAM_NAME
        self.options.banner = "NAME\n\t#{$PROGRAM_NAME} -- a command line tool for Aspera Applications\n\n"
        self.options.separator "SYNOPSIS"
        self.options.separator "\t#{$PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
        self.options.separator ""
        self.options.separator "COMMANDS"
        self.options.separator "\tSupported commands: #{plugin_sym_list.map {|x| x.to_s}.join(', ')}"
        self.options.separator "\tNote that commands can be written shortened."
        self.options.separator ""
        self.options.separator "DESCRIPTION"
        self.options.separator "\tUse Aspera application to perform operations on command line."
        self.options.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        self.options.separator "\tAdditional documentation here: https://rubygems.org/gems/asperalm"
        self.options.separator ""
        self.options.separator "EXAMPLES"
        self.options.separator "\t#{$PROGRAM_NAME} files repo browse /"
        self.options.separator "\t#{$PROGRAM_NAME} faspex send ./myfile --log-level=debug"
        self.options.separator "\t#{$PROGRAM_NAME} shares upload ~/myfile /myshare"
        self.options.separator "\nSPECIAL OPTION VALUES\n\tif an option value begins with @env: or @file:, value is taken from env var or file\n\tdates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'"
        self.options.separator ""
        # handler must be set before setting defaults
        self.options.set_handler(:loglevel) { |op,val| attr_loglevel(op,val) }
        self.options.set_handler(:logtype) { |op,val| attr_logtype(op,val) }
        self.options.set_handler(:config_file) { |op,val| attr_config_file(op,val) }
        self.options.set_handler(:insecure) { |op,val| attr_insecure(op,val) }
        self.options.set_handler(:transfer_spec) { |op,val| attr_transfer_spec(op,val) }
        self.options.set_handler(:browser) { |op,val| attr_browser(op,val) }
      end

      # plugin_name_sym is symbol
      # initialize if necessary
      def get_plugin_instance(plugin_name_sym)
        require @plugins[plugin_name_sym][:req]
        Log.log.debug("loaded config -> #{@@global_config}")
        default_config=Main.get_config_defaults(plugin_name_sym,self.options.get_option_mandatory(:config_name))
        # TODO: check that ancestor is Plugin
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new(self.options)
        command_plugin.options.set_defaults(default_config)
        if command_plugin.respond_to?(:faspmanager=) then
          # create the FASP manager for transfers
          command_plugin.faspmanager=FaspManagerResume.new
          command_plugin.faspmanager.set_listener(FaspListenerLogger.new)
          case self.options.get_option_mandatory(:transfer)
          when :connect
            command_plugin.faspmanager.use_connect_client=true
          when :node
            node_config=Main.get_config_defaults(:node,self.options.get_option_mandatory(:transfer_node_config))
            raise CliBadArgument,"no such node configuration: #{self.options.get_option_mandatory(:transfer_node_config)}" if node_config.nil?
            command_plugin.faspmanager.tr_node_api=Rest.new(node_config[:url],{:basic_auth=>{:user=>node_config[:username], :password=>node_config[:password]}})
          end
          # may be nil:
          command_plugin.faspmanager.fasp_proxy_url=self.options.get_option(:fasp_proxy)
          command_plugin.faspmanager.http_proxy_url=self.options.get_option(:http_proxy)
        end
        self.options.separator "OPTIONS: #{plugin_name_sym}"
        command_plugin.set_options
        return command_plugin
      end

      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'

      def set_options
        self.options.separator "OPTIONS: global"
        self.options.set_option(:browser,:tty)
        self.options.set_option(:fields,FIELDS_DEFAULT)
        self.options.set_option(:transfer,:ascp)
        self.options.set_option(:transfer_node_config,'default')
        self.options.set_option(:insecure,:no)
        self.options.set_option(:format,:text_table)
        self.options.set_option(:logtype,:stdout)
        self.options.set_option(:config_file,@@DEFAULT_CONFIG_FILE) if File.exist?(@@DEFAULT_CONFIG_FILE)
        self.options.on("-h", "--help", "Show this message") { self.options.exit_with_usage(nil) }
        self.options.add_opt_list(:browser,BrowserInteraction.open_url_methods,"method to start browser",'-gTYPE','--browser=TYPE')
        self.options.add_opt_list(:insecure,[:yes,:no],"do not validate cert",'--insecure=VALUE')
        self.options.add_opt_list(:loglevel,Log.levels,"Log level",'-lTYPE','--log-level=VALUE')
        self.options.add_opt_list(:logtype,[:syslog,:stdout],"log method",'-qTYPE','--logger=VALUE')
        self.options.add_opt_list(:format,[:ruby,:text_table,:json,:text],"output format",'--format=VALUE')
        self.options.add_opt_list(:transfer,[:ascp,:connect,:node],"type of transfer",'--transfer=VALUE')
        self.options.add_opt_simple(:config_file,"-fSTRING", "--config-file=STRING","read parameters from file in YAML format, current=#{self.options.get_option(:config_file)}")
        self.options.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
        self.options.add_opt_simple(:transfer_node_config,"--transfer-node=STRING","name of configuration used to transfer when using --transfer=node")
        self.options.add_opt_simple(:fields,"--fields=STRING","comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        self.options.add_opt_simple(:fasp_proxy,"--fasp-proxy=STRING","URL of FASP proxy (dnat / dnats)")
        self.options.add_opt_simple(:http_proxy,"--http-proxy=STRING","URL of HTTP proxy (for http fallback)")
        self.options.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
        self.options.add_opt_simple(:transfer_spec,"--ts=JSON","override transfer spec values, current=#{self.options.get_option(:transfer_spec)}")
      end

      def self.result_simple_table(name,list)
        return {:values => list.map { |i| { name => i.to_s } }}
      end

      def self.result_hash_table(hash)
        return {:values => hash.keys.map { |i| { 'key' => i, 'value' => hash[i] } }}
      end

      # "cli" plugin
      def execute_action
        command=self.options.get_next_arg_from_list('command',[:help,:config,:plugins])
        case command
        when :help
          STDERR.puts self.options
          plugin_sym_list.select { |s| !@plugins[s][:req].nil? }.each do |plugin_name_sym|
            self.options=OptParser.new([])
            self.options.banner = ""
            self.options.program_name=$PROGRAM_NAME
            self.options.set_defaults({:config_name => 'default',:transfer=>:ascp})
            get_plugin_instance(plugin_name_sym)
            STDERR.puts self.options
          end
          Process.exit 1
        when :plugins
          return {:values => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'] }
        when :config
          action=self.options.get_next_arg_from_list('action',[:ls,:init,:cat,:open])
          case action
          when :init
            raise CliError,"Folder already exists: #{$PROGRAM_FOLDER}" if Dir.exist?($PROGRAM_FOLDER)
            FileUtils::mkdir_p($PROGRAM_FOLDER)
            sample_config={
              :cli=>{"default"=>{:loglevel=>:warn}},
              :files=>{
              "default"=>{:auth=>:jwt, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MyAccessKeySecret", :private_key=>"@file:~/.aspera/aslmcli/filesapikey", :username=>"user@example.com"},
              "web"=>{:auth=>:web, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MyAccessKeySecret", :redirect_uri=>"http://local.connectme.us:12345"}
              },:faspex=>{
                "default"=>{:url=>"https://myfaspex.mycompany.com/aspera/faspex", :username=>"admin", :password=>"MyP@ssw0rd",:storage=>{'Local Storage'=>{:node=>'default',:path=>'/subpath'}}},
              "app2"=>{:url=>"https://faspex.other.com/aspera/faspex", :username=>"john@example", :password=>"yM7FmjfGN$J4"}
              },:shares=>{"default"=>{:url=>"https://10.25.0.6", :username=>"admin", :password=>"MyP@ssw0rd"}
              },:node=>{"default"=>{:url=>"https://10.25.0.8:9092", :username=>"node_user", :password=>"MyP@ssw0rd", :transfer_filter=>"t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?('faspex')", :file_filter=>"f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?('send')"}
              },:console=>{"default"=>{:url=>"https://console.myorg.com/aspera/console", :username=>"admin", :password=>"xxxxx"}
              },:fasp=>{"default"=>{:transfer_spec=>'{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","password":"xxxxx"}'}
              }}
            File.write(@@DEFAULT_CONFIG_FILE,sample_config.to_yaml)
            puts "initialized: #{$PROGRAM_FOLDER}"
            return nil
          when :cat
            return {:values=>File.read(@@DEFAULT_CONFIG_FILE),:format=>:text}
          when :open
            BrowserInteraction.open_system_uri(@@DEFAULT_CONFIG_FILE)
            return nil
          when :ls
            sections=plugin_sym_list
            if self.options.command_or_arg_empty?
              # just list plugins
              return self.class.result_simple_table('plugin',sections)
            else
              plugin=self.options.get_next_arg_from_list('plugin',sections)
              names=@@global_config[plugin].keys.map { |i| i.to_sym }
              if self.options.command_or_arg_empty?
                # list names for tool
                return self.class.result_simple_table('name',names)
              else
                # list parameters
                configname=self.options.get_next_arg_from_list('config',names)
                defaults=Main.get_config_defaults(plugin,configname.to_s)
                return nil if defaults.nil?
                return {:values => defaults.keys.map { |i| { 'param' => i.to_s, 'value' => defaults[i] } } , :fields => ['param','value'] }
              end
            end
          end
        end
      end

      def display_results(results)
        if results.nil?
          Log.log.debug("result=nil")
        elsif results.is_a?(String)
          $stdout.write(results)
        elsif results.is_a?(Hash) and results.has_key?(:values) then
          if results.has_key?(:format)
            if results[:format].eql?(:hash_table)
              results[:format]=:text_table
              results[:values]=results[:values].keys.map { |i| { 'key' => i, 'value' => results[:values][i] } }
            end
            self.options.set_option(:format,results[:format])
          end
          if results[:values].is_a?(Array) and results[:values].empty?
            $stdout.write("no result")
          else
            display_fields=nil
            if ![:ruby,:text].include?(self.options.get_option_mandatory(:format))
              case self.options.get_option_mandatory(:fields)
              when FIELDS_DEFAULT
                if !results.has_key?(:fields) or results[:fields].nil?
                  raise "empty results" if results[:values].empty?
                  display_fields=results[:values].first.keys
                else
                  display_fields=results[:fields]
                end
              when FIELDS_ALL
                raise "empty results" if results[:values].empty?
                display_fields=results[:values].first.keys if results[:values].is_a?(Array)
              else
                display_fields=self.options.get_option_mandatory(:fields).split(',')
              end
            end
            case self.options.get_option_mandatory(:format)
            when :ruby
              puts PP.pp(results[:values],'')
            when :json
              puts JSON.generate(results[:values])
            when :text
              puts results[:values]
            when :text_table
              rows=results[:values]
              if results.has_key?(:textify)
                rows=results[:textify].call(rows)
              end
              rows=rows.map{ |r| display_fields.map { |c| r[c].to_s } }
              puts Text::Table.new(:head => display_fields, :rows => rows, :vertical_boundary  => '.', :horizontal_boundary => ':', :boundary_intersection => ':')
            end
          end
        else
          puts ">other result>#{PP.pp(results,'')}".red
        end
      end

      def process_command_line()
        self.set_options
        # parse general options always, before finding plugin
        self.options.parse_options!()
        command_sym=self.options.get_next_arg_from_list('command',plugin_sym_list)
        case command_sym
        when @@MAIN_PLUGIN_NAME_SYM
          command_plugin=self
        else
          # get plugin
          command_plugin=self.get_plugin_instance(command_sym)
          # parse plugin specific options
          self.options.parse_options!()
        end
        results=command_plugin.execute_action
        display_results(results)
        # parse for help
        self.options.parse_options!()
        # unprocessed values ?
        if !self.options.unprocessed_options.empty?
          raise CliBadArgument,"unprocessed options: #{self.options.unprocessed_options}"
        end
        if !self.options.command_or_arg_empty?
          raise CliBadArgument,"unprocessed values: #{self.options.get_remaining_arguments(nil)}"
        end
        return nil
      end

      #################################
      # MAIN
      #--------------------------------
      $PROGRAM_NAME = 'aslmcli'
      @@ASPERA_HOME_FOLDERNAME='.aspera'
      @@ASPERA_PLUGINS_FOLDERNAME='plugins'
      @@DEFAULT_CONFIG_FILENAME = 'config.yaml'
      @@ASPERA_HOME_FOLDERPATH=File.join(Dir.home,@@ASPERA_HOME_FOLDERNAME)
      $PROGRAM_FOLDER=File.join(@@ASPERA_HOME_FOLDERPATH,$PROGRAM_NAME)
      @@DEFAULT_CONFIG_FILE=File.join($PROGRAM_FOLDER,@@DEFAULT_CONFIG_FILENAME)
      @@USER_PLUGINS_FOLDER=File.join($PROGRAM_FOLDER,@@ASPERA_PLUGINS_FOLDERNAME)

      def self.start
        # quick init of debug level
        Log.level = ARGV.include?('--log-level=debug') ? :debug : :warn
        tool=self.new(OptParser.new(ARGV))
        begin
          # this separates options (start with '-') from arguments
          tool.options.set_defaults({:config_name => 'default'})
          tool.process_command_line()
        rescue CliBadArgument => e
          raise e if Log.level == :debug
          tool.options.exit_with_usage("CLI error: #{e.message}")
        rescue CliError => e
          raise e if Log.level == :debug
          tool.options.exit_with_usage("Processing error: #{e.message}")
        rescue Asperalm::TransferError => e
          raise e if Log.level == :debug
          tool.options.exit_with_usage("FASP error: #{e.message}",false)
        end
      end
    end
  end
end
