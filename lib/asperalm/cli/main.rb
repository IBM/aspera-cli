require 'asperalm/cli/manager'
require 'asperalm/cli/plugin'
require 'asperalm/fasp/agent'
require 'asperalm/fasp/manager'
require 'asperalm/fasp/listener_logger'
require 'asperalm/fasp/listener_progress'
require 'asperalm/open_application'
require 'asperalm/log'
require 'asperalm/oauth'
require 'text-table'
require 'fileutils'
require 'singleton'
require 'yaml'
require 'pp'

module Asperalm
  module Cli
    # The main CLI class
    class Main < Plugin
      include Singleton
      # "tool" class method is an alias to "instance" of singleton
      singleton_class.send(:alias_method, :tool, :instance)
      def self.version;return @@TOOL_VERSION;end
      private
      @@TOOL_VERSION='0.6.11'
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
      # Container module of current class : Asperalm::Cli
      @@CLI_MODULE=Module.nesting[1].to_s
      # Path to Plugin classes: Asperalm::Cli::Plugins
      @@PLUGINS_MODULE=@@CLI_MODULE+'::Plugins'
      @@CONFIG_FILE_KEY_VERSION='version'
      @@CONFIG_FILE_KEY_DEFAULT='default'
      # oldest compatible conf file format, update to latest version when an incompatible change is made
      @@MIN_CONFIG_VERSION='0.4.5'
      @@NO_DEFAULT='none'
      @@HELP_URL='http://www.rubydoc.info/gems/asperalm'
      RUBY_FILE_EXT='.rb'
      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'

      # $HOME/.aspera/aslmcli/config.yaml
      def default_config_file
        return File.join(config_folder,@@DEFAULT_CONFIG_FILENAME)
      end

      def current_config_file
        return @opt_mgr.get_option(:config_file,:mandatory)
      end

      # config file format: hash of hash, keys are string
      def read_config_file(config_file_path=current_config_file)
        if !File.exist?(config_file_path)
          Log.log.info("no config file, using empty configuration")
          return {@@MAIN_PLUGIN_NAME_STR=>{@@CONFIG_FILE_KEY_VERSION=>@@TOOL_VERSION}}
        end
        Log.log.debug "loading #{config_file_path}"
        config=YAML.load_file(config_file_path)

        return config
      end

      def write_config_file(config=@loaded_configs,config_file_path=current_config_file)
        raise "no configuration loaded" if config.nil?
        FileUtils::mkdir_p(config_folder) unless Dir.exist?(config_folder)
        Log.log.debug "writing #{config_file_path}"
        File.write(config_file_path,config.to_yaml)
      end

      # returns name if @loaded_configs has default
      # returns nil if there is no config or bypass default params
      def get_plugin_default_config_name(plugin_sym)
        default_config_name=nil
        return nil if @loaded_configs.nil? or !@use_plugin_defaults
        if @loaded_configs.has_key?(@@CONFIG_FILE_KEY_DEFAULT) and
        @loaded_configs[@@CONFIG_FILE_KEY_DEFAULT].has_key?(plugin_sym.to_s)
          default_config_name=@loaded_configs[@@CONFIG_FILE_KEY_DEFAULT][plugin_sym.to_s]
          raise CliError,"Default config name [#{default_config_name}] specified for plugin [#{plugin_sym.to_s}], but it does not exist in config file." if !@loaded_configs.has_key?(default_config_name)
          raise CliError,"Config name [#{default_config_name}] must be a hash, check config file." if !@loaded_configs[default_config_name].is_a?(Hash)
        end

        return default_config_name
      end

      # returns default parameters for a plugin from loaded config file
      # try to find: conffile[conffile["config"][:default][plugin_sym]]
      def load_plugin_default_parameters(plugin_sym)
        default_config_name=get_plugin_default_config_name(plugin_sym)
        return if default_config_name.nil?
        @opt_mgr.set_defaults(@loaded_configs[default_config_name])
      end

      def self.result_none
        return {:type => :empty, :data => :nil }
      end

      def self.result_status(status)
        return {:type => :status, :data => status }
      end

      def self.result_success
        return result_status('complete')
      end

      # =============================================================
      # Parameter handlers
      #
      def option_log_level; Log.level; end

      def option_log_level=(value); Log.level = value; end

      def option_insecure; Rest.insecure; end

      def option_insecure=(value); Rest.insecure = value; end

      def option_transfer_spec; @transfer_spec_default; end

      def option_transfer_spec=(value); @transfer_spec_default.merge!(value); end

      def option_to_folder; @transfer_spec_default['destination_root']; end

      def option_to_folder=(value); @transfer_spec_default.merge!({'destination_root'=>value}); end

      def option_logtype; Log.logger_type; end

      def option_logtype=(value); Log.logger_type=(value); end

      def option_ui; OpenApplication.instance.url_method; end

      def option_ui=(value); OpenApplication.instance.url_method=value; end

      #      def option_fasp_folder; Fasp::Installation.instance.paths; end
      #
      #      def option_fasp_folder=(value); Fasp::Installation.instance.paths=value; end

      # returns the list of plugins from plugin folder
      def plugin_sym_list
        return @plugins.keys
      end

      def action_list; plugin_sym_list; end

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

      def transfer_agent
        if @transfer_agent_singleton.nil?
          Fasp::Manager.instance.add_listener(Fasp::ListenerLogger.new)
          Fasp::Manager.instance.add_listener(Fasp::ListenerProgress.new)
          @transfer_agent_singleton=Fasp::Agent.new
          @transfer_agent_singleton.connect_app_id=@@PROGRAM_NAME
          if !@opt_mgr.get_option(:fasp_proxy,:optional).nil?
            @transfer_agent_singleton.transfer_spec_default.merge!({'EX_fasp_proxy_url'=>@opt_mgr.get_option(:fasp_proxy,:optional)})
          end
          if !@opt_mgr.get_option(:http_proxy,:optional).nil?
            @transfer_agent_singleton.transfer_spec_default.merge!({'EX_http_proxy_url'=>@opt_mgr.get_option(:http_proxy,:optional)})
          end
          # by default use local ascp
          case @opt_mgr.get_option(:transfer,:mandatory)
          when :connect
            @transfer_agent_singleton.use_connect_client=true
          when :node
            # support: @param:<name>
            # support extended values
            transfer_node_spec=@opt_mgr.get_option(:transfer_node,:optional)
            # of not specified, use default node
            case transfer_node_spec
            when nil
              param_set_name=get_plugin_default_config_name(:node)
              raise CliBadArgument,"No default node configured, Please specify --transfer-node" if node_config.nil?
              node_config=@loaded_configs[config_name]
            when /^@param:/
              param_set_name=transfer_node_spec.gsub!(/^@param:/,'')
              Log.log.debug("param_set_name=#{param_set_name}")
              raise CliBadArgument,"no such parameter set: [#{param_set_name}] in config file" if !@loaded_configs.has_key?(param_set_name)
              node_config=@loaded_configs[param_set_name]
            else
              node_config=Manager.get_extended_value(:transfer_node,transfer_node_spec)
            end
            Log.log.debug("node=#{node_config}")
            raise CliBadArgument,"the node configuration shall be a hash, use either @json:<json> or @param:<parameter set name>" if !node_config.is_a?(Hash)
            # now check there are required parameters
            sym_config={}
            [:url,:username,:password].each do |param|
              raise CliBadArgument,"missing parameter [#{param}] in node specification: #{node_config}" if !node_config.has_key?(param.to_s)
              sym_config[param]=node_config[param.to_s]
            end
            @transfer_agent_singleton.tr_node_api=Rest.new(sym_config[:url],{:auth=>{:type=>:basic,:username=>sym_config[:username], :password=>sym_config[:password]}})
          end
        end
        return @transfer_agent_singleton
      end

      attr_accessor :option_flat_hash

      def initialize
        # overriding parameters on transfer spec
        @transfer_spec_default={}
        @option_help=false
        @option_show_config=false
        @option_flat_hash=:yes
        @loaded_configs=nil
        @transfer_agent_singleton=nil
        @use_plugin_defaults=true
        @plugins={@@MAIN_PLUGIN_NAME_STR.to_sym=>{:source=>__FILE__,:require_stanza=>nil}}
        @plugin_lookup_folders=[]
        # find the root folder of gem where this class is
        gem_root=File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'),File.dirname(__FILE__))
        add_plugin_lookup_folder(File.join(gem_root,@@GEM_PLUGINS_FOLDER))
        add_plugin_lookup_folder(File.join(config_folder,@@ASPERA_PLUGINS_FOLDERNAME))
        @opt_mgr=Manager.new
        @opt_mgr.parser.program_name=@@PROGRAM_NAME
      end

      def declare_options
        @opt_mgr.parser.banner = "NAME\n\t#{@@PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{@@TOOL_VERSION})\n\n"
        @opt_mgr.parser.separator "SYNOPSIS"
        @opt_mgr.parser.separator "\t#{@@PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "DESCRIPTION"
        @opt_mgr.parser.separator "\tUse Aspera application to perform operations on command line."
        @opt_mgr.parser.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        @opt_mgr.parser.separator "\tDocumentation and examples: https://rubygems.org/gems/asperalm"
        @opt_mgr.parser.separator "\texecute: #{@@PROGRAM_NAME} conf doc"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "COMMANDS"
        @opt_mgr.parser.separator "\tFirst level commands: #{action_list.map {|x| x.to_s}.join(', ')}"
        @opt_mgr.parser.separator "\tNote that commands can be written shortened (provided it is unique)."
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "OPTIONS"
        @opt_mgr.parser.separator "\tOptions begin with a '-' (minus), and value is provided on command line.\n"
        @opt_mgr.parser.separator "\tSpecial values are supported beginning with special prefix, like: #{Manager.value_reader.map {|m| "@#{m}:"}.join(' ')}.\n"
        @opt_mgr.parser.separator "\tDates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "ARGS"
        @opt_mgr.parser.separator "\tSome commands require mandatory arguments, e.g. a path.\n"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "OPTIONS: global"
        @opt_mgr.parser.on("-h", "--help", "Show this message.") { @option_help=true }
        @opt_mgr.parser.on("--show-config", "Display parameters used for the provided action.") { @option_show_config=true }
        @opt_mgr.add_opt_list(:ui,OpenApplication.user_interfaces,"method to start browser",'-gTYPE')
        @opt_mgr.add_opt_list(:insecure,[:yes,:no],"do not validate HTTPS certificate")
        @opt_mgr.add_opt_list(:flat_hash,[:yes,:no],"display hash values as additional keys")
        @opt_mgr.add_opt_list(:log_level,Log.levels,"Log level")
        @opt_mgr.add_opt_list(:logger,Log.logtypes,"log method")
        @opt_mgr.add_opt_list(:format,self.class.display_formats,"output format")
        @opt_mgr.add_opt_list(:transfer,[:direct,:connect,:node],"type of transfer")
        @opt_mgr.add_opt_simple(:config_file,"read parameters from file in YAML format, current=#{@opt_mgr.get_option(:config_file,:optional)}")
        @opt_mgr.add_opt_simple(:load_params,"-PVALUE","load the named configuration from current config file, use \"#{@@NO_DEFAULT}\" to avoid loading the default configuration")
        @opt_mgr.add_opt_simple(:fasp_folder,"specify where to find FASP (main folder), current=#{@opt_mgr.get_option(:fasp_folder,:optional)}")
        @opt_mgr.add_opt_simple(:transfer_node,"name of configuration used to transfer when using --transfer=node")
        @opt_mgr.add_opt_simple(:fields,"comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        @opt_mgr.add_opt_simple(:fasp_proxy,"URL of FASP proxy (dnat / dnats)")
        @opt_mgr.add_opt_simple(:http_proxy,"URL of HTTP proxy (for http fallback)")
        @opt_mgr.add_opt_switch(:rest_debug,"-r","more debug for HTTP calls") { Rest.set_debug(true) }
        @opt_mgr.add_opt_switch(:no_default,"-N","do not load default configuration") { @use_plugin_defaults=false }
        @opt_mgr.add_opt_switch(:version,"-v","display version") { puts @@TOOL_VERSION;Process.exit(0) }
        @opt_mgr.add_opt_simple(:ts,"override transfer spec values (hash, use @json: prefix), current=#{@opt_mgr.get_option(:ts,:optional)}")
        @opt_mgr.add_opt_simple(:to_folder,"destination folder for downloaded files, current=#{@opt_mgr.get_option(:to_folder,:optional)}")
        @opt_mgr.add_opt_simple(:lock_port,"prevent dual execution of a command, e.g. in cron")
        @opt_mgr.add_opt_simple(:use_product,"which local product to use for ascp")

        # handler must be set before setting defaults
        @opt_mgr.set_obj_attr(:log_level,self,:option_log_level)
        @opt_mgr.set_obj_attr(:insecure,self,:option_insecure)
        @opt_mgr.set_obj_attr(:flat_hash,self,:option_flat_hash)
        @opt_mgr.set_obj_attr(:ts,self,:option_transfer_spec)
        @opt_mgr.set_obj_attr(:to_folder,self,:option_to_folder)
        @opt_mgr.set_obj_attr(:logger,self,:option_logtype)
        @opt_mgr.set_obj_attr(:ui,self,:option_ui)
        @opt_mgr.set_obj_attr(:use_product,Fasp::Installation.instance,:activated)
        #@opt_mgr.set_obj_attr(:fasp_folder,Fasp::Installation.instance,:paths)

        @opt_mgr.set_option(:ui,OpenApplication.default_gui_mode)
        @opt_mgr.set_option(:fields,FIELDS_DEFAULT)
        @opt_mgr.set_option(:transfer,:direct)
        @opt_mgr.set_option(:insecure,:no)
        @opt_mgr.set_option(:flat_hash,:yes)
        @opt_mgr.set_option(:format,:table)
        @opt_mgr.set_option(:config_file,default_config_file)
        #@opt_mgr.set_option(:to_folder,'.')
        #@opt_mgr.set_option(:logger,:stdout)
      end

      # plugin_name_sym is symbol
      # loads default parameters if no -P parameter
      def get_plugin_instance(plugin_name_sym)
        require @plugins[plugin_name_sym][:require_stanza]
        Log.log.debug("loaded config -> #{@loaded_configs}")
        # TODO: check that ancestor is Plugin?
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new
        @opt_mgr.parser.separator "COMMAND: #{plugin_name_sym}"
        @opt_mgr.parser.separator "SUBCOMMANDS: #{command_plugin.action_list.map{ |p| p.to_s}.join(', ')}"
        @opt_mgr.parser.separator "OPTIONS:"
        command_plugin.declare_options
        # load default params only if no param already loaded
        if @opt_mgr.get_option(:load_params,:optional).nil?
          load_plugin_default_parameters(plugin_name_sym)
        end
        return command_plugin
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

      def self.flatten_one_config(source,prefix='',dest=nil)
        dest={} if dest.nil?
        source.each do |k,v|
          unless v.is_a?(Hash)
            dest[prefix+k.to_s]=v
          else
            flatten_one_config(v,prefix+k.to_s+'.',dest)
          end
        end
        return dest
      end

      # supported output formats
      def self.display_formats; [:table,:ruby,:json,:jsonpp,:yaml,:csv]; end

      RECORD_SEPARATOR="\n"
      FIELD_SEPARATOR=","

      # this method displays the results, especially the table format
      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash (got: #{results.class}: #{results})" unless results.is_a?(Hash)
        raise "INTERNAL ERROR, result must have type" unless results.has_key?(:type)
        raise "INTERNAL ERROR, result must have data" unless results.has_key?(:data) or results[:type].eql?(:empty)

        # comma separated list in string format
        user_asked_fields_list_str=@opt_mgr.get_option(:fields,:mandatory)
        case @opt_mgr.get_option(:format,:mandatory)
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
            raise "internal error: unexpected type: #{results[:data].class}, expecting Array" unless results[:data].is_a?(Array)
            # :hash_array is an array of hash tables, where key=colum name
            table_data = results[:data]
            out_table_columns=nil
            case user_asked_fields_list_str
            when FIELDS_DEFAULT
              if results.has_key?(:fields) and !results[:fields].nil?
                out_table_columns=results[:fields]
              else
                if !table_data.empty?
                  out_table_columns=table_data.first.keys
                else
                  out_table_columns=['empty']
                end
              end
            when FIELDS_ALL
              raise "empty" if table_data.empty?
              out_table_columns=table_data.first.keys if table_data.is_a?(Array)
            else
              out_table_columns=user_asked_fields_list_str.split(',')
              out_table_columns=out_table_columns.map{|i|i.to_sym} if results[:symb_key]
            end
          when :key_val_list
            # :key_val_list is a simple hash table
            raise "internal error: unexpected type: #{results[:data].class}, expecting Hash" unless results[:data].is_a?(Hash)
            out_table_columns = results[:columns]
            out_table_columns = ['key','value'] if out_table_columns.nil?
            asked_fields=results[:data].keys
            case user_asked_fields_list_str
            when FIELDS_DEFAULT;asked_fields=results[:fields] if results.has_key?(:fields)
            when FIELDS_ALL;# keep all
            else
              asked_fields=user_asked_fields_list_str.split(',')
              asked_fields=asked_fields.map{|i|i.to_sym} if results[:symb_key]
            end
            if @option_flat_hash.eql?(:yes)
              results[:data]=self.class.flatten_one_config(results[:data])
              asked_fields=results[:data].keys
            end
            table_data=asked_fields.map { |i| { out_table_columns.first => i, out_table_columns.last => results[:data][i] } }
          when :value_list
            # :value_list is a simple array of values, name of column provided in the :name
            out_table_columns = [results[:name]]
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
          raise "no field specified" if out_table_columns.nil?
          if table_data.empty?
            puts "empty".gray
            return
          end
          # convert to string with special function. here table_data is an array of hash
          table_data=results[:textify].call(table_data) if results.has_key?(:textify)
          # convert data to string, and keep only display fields
          table_data=table_data.map { |r| out_table_columns.map { |c| r[c].to_s } }
          case @opt_mgr.get_option(:format,:mandatory)
          when :table
            # display the table !
            puts Text::Table.new(
            :head => out_table_columns,
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
        STDERR.puts(@opt_mgr.parser)
        if all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          plugin_sym_list.select { |s| !@plugins[s][:require_stanza].nil? }.each do |plugin_name_sym|
            # override main option parser...
            @opt_mgr=Manager.new
            @opt_mgr.parser.banner = ""
            @opt_mgr.parser.program_name=@@PROGRAM_NAME
            get_plugin_instance(plugin_name_sym)
            STDERR.puts(@opt_mgr.parser)
          end
        end
        #STDERR.puts(@opt_mgr.parser)
        STDERR.puts "\nDocumentation : #{@@HELP_URL}"
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
          raise CliError,"Config File: Cannot find key [#{@@MAIN_PLUGIN_NAME_STR}] in #{current_config_file}. Please check documentation."
        end
        # check presence of version of conf file
        version=@loaded_configs[@@MAIN_PLUGIN_NAME_STR][@@CONFIG_FILE_KEY_VERSION]
        raise CliError,"Config File: No version found. Please check documentation. Expecting min version #{@@MIN_CONFIG_VERSION}" if version.nil?
        # check compatibility of version of conf file
        if Gem::Version.new(version) < Gem::Version.new(@@MIN_CONFIG_VERSION)
          raise CliError,"Unsupported config file version #{version}. Please check documentation. Expecting min version #{@@MIN_CONFIG_VERSION}"
        end
        # did the user specify parameters to load ?
        config_name_list=@opt_mgr.get_option(:load_params,:optional)
        if !config_name_list.nil?
          config_name_list.split(/,/).each do |name|
            Log.log.debug "loading config: #{name} : #{@loaded_configs[name]}".red
            if @loaded_configs.has_key?(name)
              @opt_mgr.set_defaults(@loaded_configs[name])
            elsif name.eql?(@@NO_DEFAULT)
              Log.log.debug("dont use generic default")
            else
              raise CliBadArgument,"no such config name: #{name}\nList configs with: aslmcli config list"
            end
          end
        end
      end

      protected

      # "config" plugin
      def execute_action
        action=@opt_mgr.get_next_argument('action',[:genkey,:plugins,:flush_tokens,:list,:overview,:open,:echo,:id,:documentation])
        case action
        when :id
          config_name=@opt_mgr.get_next_argument('config name')
          action=@opt_mgr.get_next_argument('action',[:set,:delete,:initialize,:show,:update,:ask])
          case action
          when :show
            raise "no such config: #{config_name}" unless @loaded_configs.has_key?(config_name)
            return {:type=>:key_val_list,:data=>@loaded_configs[config_name]}
          when :delete
            @loaded_configs.delete(config_name)
            write_config_file
            return Main.result_status("deleted: #{config_name}")
          when :set
            param_name=@opt_mgr.get_next_argument('parameter name')
            param_value=@opt_mgr.get_next_argument('parameter value')
            if !@loaded_configs.has_key?(config_name)
              Log.log.debug("no such config name: #{config_name}, initializing")
              @loaded_configs[config_name]=Hash.new
            end
            if @loaded_configs[config_name].has_key?(param_name)
              Log.log.warn("overwriting value: #{@loaded_configs[config_name][param_name]}")
            end
            @loaded_configs[config_name][param_name]=param_value
            write_config_file
            return Main.result_status("updated: #{config_name}->#{param_name} to #{param_value}")
          when :initialize
            config_value=@opt_mgr.get_next_argument('extended value (Hash)')
            if @loaded_configs.has_key?(config_name)
              Log.log.warn("configuration already exists: #{config_name}, overwriting")
            end
            @loaded_configs[config_name]=config_value
            write_config_file
            return Main.result_status("modified: #{current_config_file}")
          when :update
            #  TODO: when arguments are provided: --option=value, this creates an entry in the named configuration
            theopts=@opt_mgr.get_options_table
            Log.log.debug("opts=#{theopts}")
            @loaded_configs[config_name]={} if !@loaded_configs.has_key?(config_name)
            @loaded_configs[config_name].merge!(theopts)
            write_config_file
            return Main.result_status("updated: #{config_name}")
          when :ask
            @opt_mgr.use_interactive=:yes
            @loaded_configs[config_name]||={}
            @opt_mgr.get_next_argument('option names',:multiple).each do |optionname|
              option_value=@opt_mgr.get_interactive(:option,optionname)
              @loaded_configs[config_name][optionname]=option_value
            end
            write_config_file
            return Main.result_status("updated: #{config_name}")
          end
        when :documentation
          OpenApplication.instance.uri(@@HELP_URL)
          return Main.result_none
        when :open
          OpenApplication.instance.uri(current_config_file)
          return Main.result_none
        when :genkey # generate new rsa key
          key_filepath=@opt_mgr.get_next_argument('private key file path')
          require 'net/ssh'
          priv_key = OpenSSL::PKey::RSA.new(2048)
          File.write(key_filepath,priv_key.to_s)
          File.write(key_filepath+".pub",priv_key.public_key.to_s)
          return Main.result_status('generated key: '+key_filepath)
        when :echo # display the content of a value given on command line
          result={:type=>:other_struct, :data=>@opt_mgr.get_next_argument("value")}
          # special for csv
          result[:type]=:hash_array if result[:data].is_a?(Array) and result[:data].first.is_a?(Hash)
          return result
        when :flush_tokens
          deleted_files=Oauth.flush_tokens(config_folder)
          return {:type=>:value_list, :name=>'file',:data=>deleted_files}
        when :plugins
          return {:data => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :hash_array }
        when :list
          return {:data => @loaded_configs.keys, :type => :value_list, :name => 'name'}
        when :overview
          return {:type=>:hash_array,:data=>self.class.flatten_all_config(@loaded_configs)}
        end
      end

      def add_plugin_lookup_folder(folder)
        @plugin_lookup_folders.push(folder)
      end

      def add_plugin_info(path)
        raise "ERROR: plugin path must end with #{RUBY_FILE_EXT}" if !path.end_with?(RUBY_FILE_EXT)
        name=File.basename(path,RUBY_FILE_EXT)
        req=path.gsub(/#{RUBY_FILE_EXT}$/,'')
        @plugins[name.to_sym]={:source=>path,:require_stanza=>req}
      end

      # early debug for parser
      def early_debug_setup(argv)
        argv.each do |arg|
          case arg
          when /^--log-level=(.*)/
            Log.level = $1.to_sym
          when /^--logger=(.*)/
            Log.logger_type=$1.to_sym
          end
        end
      end

      public

      # public method
      # $HOME/.aspera/aslmcli
      def config_folder
        return File.join(Dir.home,@@ASPERA_HOME_FOLDERNAME,@@PROGRAM_NAME)
      end

      def options;@opt_mgr;end

      # return destination folder for transfers
      # sets default if needed
      # param: 'send' or 'receive'
      def destination_folder(direction)
        # set default if needed
        if @transfer_spec_default['destination_root'].nil?
          # default: / on remote, . on local
          case direction
          when 'send'
            @transfer_spec_default['destination_root']='/'
          when 'receive'
            @transfer_spec_default['destination_root']='.'
          else
            raise "wrong direction: #{direction}"
          end
        end
        return @transfer_spec_default['destination_root']
      end

      # plugins shall use this method to start a transfer
      # set_default_destination if destination_root shall be used from the provided transfer spec
      # and not the default one
      def start_transfer(transfer_spec,set_default_destination=true)
        if set_default_destination
          destination_folder(transfer_spec['direction'])
        else
          # in that case, destination is set in return by application (API/upload_setup)
          # but to_folder was used in intial api call
          @transfer_spec_default.delete('destination_root')
        end

        transfer_spec.merge!(@transfer_spec_default)
        # TODO: option to choose progress format
        # here we disable native stdout progress
        transfer_spec['EX_quiet']=true
        # add bypass keys if there is a token, also prevents connect plugin to ask password
        transfer_spec['authentication']="token" if transfer_spec.has_key?('token')
        transfer_agent.start_transfer(transfer_spec)
        return self.class.result_success
      end

      # this is the main function called by initial script
      def process_command_line(argv)
        begin
          # first thing : manage debug level (allows debugging or option parser)
          early_debug_setup(argv)
          # init opt parser separates options (start with '-') from arguments
          @opt_mgr.add_cmd_line_options(argv)
          # declare global options and set defaults
          declare_options
          # parse general options
          @opt_mgr.parse_options!
          # load default config if it was not overriden on command line
          load_config_file
          # find plugins, shall be after parse! ?
          add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help and @opt_mgr.command_or_arg_empty?
          # load global default options
          load_plugin_default_parameters(@@MAIN_PLUGIN_NAME_STR.to_sym)
          # dual execution locking
          lock_port=@opt_mgr.get_option(:lock_port,:optional)
          if !lock_port.nil?
            begin
              # no need to close later, will be freed on process exit
              TCPServer.new('127.0.0.1',lock_port.to_i)
            rescue => e
              raise CliError,"Another instance is already running (lock port=#{lock_port})."
            end
          end
          command_sym=@opt_mgr.get_next_argument('command',plugin_sym_list.dup.unshift(:help))
          # main plugin is not dynamically instanciated
          case command_sym
          when :help
            exit_with_usage(true)
          when @@MAIN_PLUGIN_NAME_STR.to_sym
            command_plugin=self
          else
            # get plugin, set options, etc
            command_plugin=get_plugin_instance(command_sym)
            # parse plugin specific options
            @opt_mgr.parse_options!
          end
          # help requested ?
          exit_with_usage(false) if @option_help
          if @option_show_config
            display_results({:type=>:key_val_list,:data=>@opt_mgr.declared_options})
            Process.exit(0)
          end
          display_results(command_plugin.execute_action)
          @opt_mgr.fail_if_unprocessed
        rescue CliBadArgument => e;          process_exception_exit(e,'Argument',:usage)
        rescue CliError => e;                process_exception_exit(e,'Tool',:usage)
        rescue Fasp::Error => e;             process_exception_exit(e,"FASP(ascp)")
        rescue Asperalm::RestCallError => e; process_exception_exit(e,"Rest")
        rescue SocketError => e;             process_exception_exit(e,"Network")
        rescue StandardError => e;           process_exception_exit(e,"Other",:debug)
        rescue Interrupt => e;               process_exception_exit(e,"Interruption",:debug)
        end
        return self
      end
    end # Main
  end # Cli
end # Asperalm
