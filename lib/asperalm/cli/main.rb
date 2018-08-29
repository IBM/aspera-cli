require 'asperalm/cli/manager'
require 'asperalm/cli/plugin'
require 'asperalm/cli/extended_value'
require 'asperalm/fasp/client/resumer'
require 'asperalm/fasp/client/connect'
require 'asperalm/fasp/client/node'
require 'asperalm/fasp/listener_logger'
require 'asperalm/fasp/listener_progress'
require 'asperalm/open_application'
require 'asperalm/temp_file_manager'
require 'asperalm/log'
require 'asperalm/oauth'
require 'asperalm/files_api'
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
      def self.gem_version
        File.read(File.join(gem_root,@@GEM_NAME,'VERSION')).chomp
      end

      private
      # first level command for the main tool
      @@MAIN_PLUGIN_NAME_SYM=:config
      # name of application, also foldername where config is stored
      @@PROGRAM_NAME = 'aslmcli'
      @@GEM_NAME = 'asperalm'
      # folder in $HOME for application files (config, cache)
      @@ASPERA_HOME_FOLDER_NAME='.aspera'
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
      @@HELP_URL='http://www.rubydoc.info/gems/'+@@GEM_NAME
      @@GEM_URL='https://rubygems.org/gems/'+@@GEM_NAME
      RUBY_FILE_EXT='.rb'
      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'
      ASPERA_PLUGIN_S=:aspera.to_s

      # find the root folder of gem where this class is
      def self.gem_root
        File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'),File.dirname(__FILE__))
      end

      def save_presets_to_config_file
        raise "no configuration loaded" if @available_presets.nil?
        FileUtils::mkdir_p(config_folder) unless Dir.exist?(config_folder)
        Log.log.debug "writing #{@option_config_file}"
        File.write(@option_config_file,@available_presets.to_yaml)
      end

      # returns name if @available_presets has default
      # returns nil if there is no config or bypass default params
      def get_plugin_default_config_name(plugin_sym)
        default_config_name=nil
        return nil if @available_presets.nil? or !@use_plugin_defaults
        if @available_presets.has_key?(@@CONFIG_FILE_KEY_DEFAULT) and
        @available_presets[@@CONFIG_FILE_KEY_DEFAULT].has_key?(plugin_sym.to_s)
          default_config_name=@available_presets[@@CONFIG_FILE_KEY_DEFAULT][plugin_sym.to_s]
          if !@available_presets.has_key?(default_config_name)
            Log.log.error("Default config name [#{default_config_name}] specified for plugin [#{plugin_sym.to_s}], but it does not exist in config file.\nPlease fix the issue: either create preset with one parameter (aslmcli config id #{default_config_name} init @json:'{}') or remove default (aslmcli config id default remove #{plugin_sym.to_s}).")
          end
          raise CliError,"Config name [#{default_config_name}] must be a hash, check config file." if !@available_presets[default_config_name].is_a?(Hash)
        end

        return default_config_name
      end

      # returns default parameters for a plugin from loaded config file
      # try to find: conffile[conffile["default"][plugin_str]]
      def add_plugin_default_preset(plugin_sym)
        default_config_name=get_plugin_default_config_name(plugin_sym)
        Log.log.debug("add_plugin_default_preset:#{plugin_sym}:#{default_config_name}")
        return if default_config_name.nil?
        @opt_mgr.add_option_preset(@available_presets[default_config_name],:unshift)
      end

      # =============================================================
      # Parameter handlers
      #
      attr_accessor :option_override

      def option_insecure; Rest.insecure ; end

      def option_insecure=(value); Rest.insecure = value; end

      def option_transfer_spec; @transfer_spec_default; end

      def option_transfer_spec=(value); @transfer_spec_default.merge!(value); end

      def option_to_folder; @transfer_spec_default['destination_root']; end

      def option_to_folder=(value); @transfer_spec_default.merge!({'destination_root'=>value}); end

      def option_ui; OpenApplication.instance.url_method; end

      def option_ui=(value); OpenApplication.instance.url_method=value; end

      def option_preset; nil; end

      def option_preset=(value)
        raise CliError,"no such preset defined: #{value}" unless @available_presets.has_key?(value)
        @opt_mgr.add_option_preset(@available_presets[value])
      end

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

      # transfer agent singleton
      def transfer_agent
        if @transfer_agent_singleton.nil?
          # by default use local ascp
          case @opt_mgr.get_option(:transfer,:mandatory)
          when :direct
            @transfer_agent_singleton=Fasp::Client::Resumer.new
            if !@opt_mgr.get_option(:fasp_proxy,:optional).nil?
              @transfer_spec_default['EX_fasp_proxy_url']=@opt_mgr.get_option(:fasp_proxy,:optional)
            end
            if !@opt_mgr.get_option(:http_proxy,:optional).nil?
              @transfer_spec_default['EX_http_proxy_url']=@opt_mgr.get_option(:http_proxy,:optional)
            end
            # TODO: option to choose progress format
            # here we disable native stdout progress
            @transfer_spec_default['EX_quiet']=true
            Log.log.debug(">>>>#{@transfer_spec_default}".red)
          when :connect
            @transfer_agent_singleton=Fasp::Client::Connect.new
          when :node
            # support: @param:<name>
            # support extended values
            transfer_node_spec=@opt_mgr.get_option(:transfer_node,:optional)
            # of not specified, use default node
            case transfer_node_spec
            when nil
              param_set_name=get_plugin_default_config_name(:node)
              raise CliBadArgument,"No default node configured, Please specify --transfer-node" if param_set_name.nil?
              node_config=@available_presets[param_set_name]
            when /^@param:/
              param_set_name=transfer_node_spec.gsub!(/^@param:/,'')
              Log.log.debug("param_set_name=#{param_set_name}")
              raise CliBadArgument,"no such parameter set: [#{param_set_name}] in config file" if !@available_presets.has_key?(param_set_name)
              node_config=@available_presets[param_set_name]
            else
              node_config=ExtendedValue.parse(:transfer_node,transfer_node_spec)
            end
            Log.log.debug("node=#{node_config}")
            raise CliBadArgument,"the node configuration shall be a hash, use either @json:<json> or @param:<parameter set name>" if !node_config.is_a?(Hash)
            # now check there are required parameters
            sym_config={}
            [:url,:username,:password].each do |param|
              raise CliBadArgument,"missing parameter [#{param}] in node specification: #{node_config}" if !node_config.has_key?(param.to_s)
              sym_config[param]=node_config[param.to_s]
            end
            @transfer_agent_singleton=Fasp::Client::Node.new(Rest.new({:base_url=>sym_config[:url],:auth_type=>:basic,:basic_username=>sym_config[:username], :basic_password=>sym_config[:password]}))
          else raise "ERROR"
          end
          @transfer_agent_singleton.add_listener(Fasp::ListenerLogger.new,:struct)
          @transfer_agent_singleton.add_listener(Fasp::ListenerProgress.new,:struct)
        end
        return @transfer_agent_singleton
      end

      attr_accessor :option_flat_hash
      attr_accessor :option_config_file
      attr_accessor :option_table_style

      # minimum initialization
      def initialize
        # overriding parameters on transfer spec
        @transfer_spec_default={}
        @option_help=false
        @option_show_config=false
        @option_flat_hash=true
        @available_presets=nil
        @transfer_agent_singleton=nil
        @use_plugin_defaults=true
        @plugins={@@MAIN_PLUGIN_NAME_SYM=>{:source=>__FILE__,:require_stanza=>nil}}
        @plugin_lookup_folders=[]
        @config_folder=File.join(Dir.home,@@ASPERA_HOME_FOLDER_NAME,@@PROGRAM_NAME)
        @option_config_file=File.join(@config_folder,@@DEFAULT_CONFIG_FILENAME)
        @option_table_style=':.:'
        # set folders for temp files
        Fasp::Parameters.file_list_folder=File.join(@config_folder,'filelists')
        Oauth.persistency_folder=@config_folder
        # option manager is created later
        @opt_mgr=nil
        add_plugin_lookup_folder(File.join(self.class.gem_root,@@GEM_PLUGINS_FOLDER))
        add_plugin_lookup_folder(File.join(config_folder,@@ASPERA_PLUGINS_FOLDERNAME))
      end

      # local options
      def create_opt_mgr
        @opt_mgr=Manager.new(@@PROGRAM_NAME)
        @opt_mgr.parser.banner = "NAME\n\t#{@@PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{self.class.gem_version})\n\n"
        @opt_mgr.parser.separator "SYNOPSIS"
        @opt_mgr.parser.separator "\t#{@@PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "DESCRIPTION"
        @opt_mgr.parser.separator "\tUse Aspera application to perform operations on command line."
        @opt_mgr.parser.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        @opt_mgr.parser.separator "\tDocumentation and examples: #{@@GEM_URL}"
        @opt_mgr.parser.separator "\texecute: #{@@PROGRAM_NAME} conf doc"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "COMMANDS"
        @opt_mgr.parser.separator "\tFirst level commands: #{action_list.map {|x| x.to_s}.join(', ')}"
        @opt_mgr.parser.separator "\tNote that commands can be written shortened (provided it is unique)."
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "OPTIONS"
        @opt_mgr.parser.separator "\tOptions begin with a '-' (minus), and value is provided on command line.\n"
        @opt_mgr.parser.separator "\tSpecial values are supported beginning with special prefix, like: #{ExtendedValue.readers.map {|m| "@#{m}:"}.join(' ')}.\n"
        @opt_mgr.parser.separator "\tDates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "ARGS"
        @opt_mgr.parser.separator "\tSome commands require mandatory arguments, e.g. a path.\n"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "OPTIONS: global"
        @opt_mgr.declare_options_scan_env
        @opt_mgr.set_obj_attr(:config_file,self,:option_config_file)
        @opt_mgr.set_obj_attr(:table_style,self,:option_table_style)
        @opt_mgr.add_opt_simple(:config_file,"read parameters from file in YAML format, current=#{@option_config_file}")
        @opt_mgr.add_opt_simple(:table_style,"table display style, current=#{@option_table_style}")
        @opt_mgr.add_opt_switch(:help,"Show this message.","-h") { @option_help=true }
        @opt_mgr.add_opt_switch(:show_config, "Display parameters used for the provided action.") { @option_show_config=true }
        @opt_mgr.add_opt_switch(:rest_debug,"-r","more debug for HTTP calls") { Rest.debug=true }
        @opt_mgr.add_opt_switch(:no_default,"-N","do not load default configuration for plugin") { @use_plugin_defaults=false }
        @opt_mgr.add_opt_switch(:version,"-v","display version") { puts self.class.gem_version;Process.exit(0) }
      end

      def declare_options
        # handler must be set before declaration
        @opt_mgr.set_obj_attr(:log_level,Log.instance,:level)
        @opt_mgr.set_obj_attr(:insecure,self,:option_insecure,:no)
        @opt_mgr.set_obj_attr(:override,self,:option_override,:no)
        @opt_mgr.set_obj_attr(:flat_hash,self,:option_flat_hash)
        @opt_mgr.set_obj_attr(:ts,self,:option_transfer_spec)
        @opt_mgr.set_obj_attr(:to_folder,self,:option_to_folder)
        @opt_mgr.set_obj_attr(:logger,Log.instance,:logger_type)
        @opt_mgr.set_obj_attr(:ui,self,:option_ui)
        @opt_mgr.set_obj_attr(:preset,self,:option_preset)
        @opt_mgr.set_obj_attr(:use_product,Fasp::Installation.instance,:activated)

        @opt_mgr.add_opt_list(:ui,OpenApplication.user_interfaces,'method to start browser')
        @opt_mgr.add_opt_list(:log_level,Log.levels,"Log level")
        @opt_mgr.add_opt_list(:logger,Log.logtypes,"log method")
        @opt_mgr.add_opt_list(:format,self.class.display_formats,"output format")
        @opt_mgr.add_opt_list(:transfer,[:direct,:connect,:node],"type of transfer")
        @opt_mgr.add_opt_simple(:preset,"-PVALUE","load the named option preset from current config file")
        @opt_mgr.add_opt_simple(:transfer_node,"name of configuration used to transfer when using --transfer=node")
        @opt_mgr.add_opt_simple(:fields,"comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        @opt_mgr.add_opt_simple(:select,"select only some items in lists, extended value: hash (colum, value)")
        @opt_mgr.add_opt_simple(:fasp_proxy,"URL of FASP proxy (dnat / dnats)")
        @opt_mgr.add_opt_simple(:http_proxy,"URL of HTTP proxy (for http fallback)")
        @opt_mgr.add_opt_simple(:ts,"override transfer spec values (Hash, use @json: prefix), current=#{@opt_mgr.get_option(:ts,:optional)}")
        @opt_mgr.add_opt_simple(:to_folder,"destination folder for downloaded files")
        @opt_mgr.add_opt_simple(:lock_port,"prevent dual execution of a command, e.g. in cron")
        @opt_mgr.add_opt_simple(:use_product,"which local product to use for ascp, current=#{Fasp::Installation.instance.activated}")
        @opt_mgr.add_opt_boolean(:insecure,"do not validate HTTPS certificate")
        @opt_mgr.add_opt_boolean(:flat_hash,"display hash values as additional keys")
        @opt_mgr.add_opt_boolean(:override,"override existing value")

        @opt_mgr.set_option(:ui,OpenApplication.default_gui_mode)
        @opt_mgr.set_option(:fields,FIELDS_DEFAULT)
        @opt_mgr.set_option(:transfer,:direct)
        @opt_mgr.set_option(:format,:table)
      end

      # plugin_name_sym is symbol
      # loads default parameters if no -P parameter
      def get_plugin_instance(plugin_name_sym)
        Log.log.debug("get_plugin_instance -> #{plugin_name_sym}")
        require @plugins[plugin_name_sym][:require_stanza]
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new()
        # TODO: check that ancestor is Plugin?
        @opt_mgr.parser.separator "COMMAND: #{plugin_name_sym}"
        @opt_mgr.parser.separator "SUBCOMMANDS: #{command_plugin.action_list.map{ |p| p.to_s}.join(', ')}"
        @opt_mgr.parser.separator "OPTIONS:"
        command_plugin.declare_options
        # load default params only if no param already loaded
        add_plugin_default_preset(plugin_name_sym)
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

      # @param source [Hash] hash to modify
      # @param keep_last [bool]
      def self.flatten_object(source,keep_last)
        newval={}
        flatten_sub_hash_rec(source,keep_last,'',newval)
        source.clear
        source.merge!(newval)
      end

      # recursive function to modify a hash
      # @param source [Hash] to be modified
      # @param keep_last [bool] truer if last level is not
      # @param prefix [String] true if last level is not
      # @param dest [Hash] new hash flattened
      def self.flatten_sub_hash_rec(source,keep_last,prefix,dest)
        #is_simple_hash=source.is_a?(Hash) and source.values.inject(true){|m,v| xxx=!v.respond_to?(:each) and m;puts("->#{xxx}>#{v.respond_to?(:each)} #{v}-");xxx}
        is_simple_hash=false
        Log.log.debug("(#{keep_last})[#{is_simple_hash}] -#{source.values}- \n-#{source}-")
        return source if keep_last and is_simple_hash
        source.each do |k,v|
          if v.is_a?(Hash) and ( !keep_last or !is_simple_hash )
            flatten_sub_hash_rec(v,keep_last,prefix+k.to_s+'.',dest)
          else
            dest[prefix+k.to_s]=v
          end
        end
        return nil
      end

      # special for Aspera on Cloud display node
      # {"param" => [{"name"=>"foo","value"=>"bar"}]} will be expanded to {"param.foo" : "bar"}
      def self.flatten_name_value_list(hash)
        hash.keys.each do |k|
          v=hash[k]
          if v.is_a?(Array) and v.map{|i|i.class}.uniq.eql?([Hash]) and v.map{|i|i.keys}.flatten.sort.uniq.eql?(["name", "value"])
            v.each do |pair|
              hash["#{k}.#{pair["name"]}"]=pair["value"]
            end
            hash.delete(k)
          end
        end
      end

      # supported output formats
      def self.display_formats; [:table,:ruby,:json,:jsonpp,:yaml,:csv]; end

      CSV_RECORD_SEPARATOR="\n"
      CSV_FIELD_SEPARATOR=","

      # this method displays the results, especially the table format
      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash (got: #{results.class}: #{results})" unless results.is_a?(Hash)
        raise "INTERNAL ERROR, result must have type" unless results.has_key?(:type)
        raise "INTERNAL ERROR, result must have data" unless results.has_key?(:data) or results[:type].eql?(:empty)

        # comma separated list in string format
        user_asked_fields_list_str=@opt_mgr.get_option(:fields,:mandatory)
        display_format=@opt_mgr.get_option(:format,:mandatory)
        case display_format
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
          when :object_list # goes to table display
            raise "internal error: unexpected type: #{results[:data].class}, expecting Array" unless results[:data].is_a?(Array)
            # :object_list is an array of hash tables, where key=colum name
            table_rows_hash_val = results[:data]
            final_table_columns=nil
            if @option_flat_hash
              new_table_rows_hash_val=[]
              table_rows_hash_val.each do |obj|
                self.class.flatten_object(obj,results[:option_expand_last])
              end
            end
            case user_asked_fields_list_str
            when FIELDS_DEFAULT
              if results.has_key?(:fields) and !results[:fields].nil?
                final_table_columns=results[:fields]
              else
                if !table_rows_hash_val.empty?
                  final_table_columns=table_rows_hash_val.first.keys
                else
                  final_table_columns=['empty']
                end
              end
            when FIELDS_ALL
              raise "empty" if table_rows_hash_val.empty?
              final_table_columns=table_rows_hash_val.first.keys if table_rows_hash_val.is_a?(Array)
            else
              final_table_columns=user_asked_fields_list_str.split(',')
            end
          when :single_object # goes to table display
            # :single_object is a simple hash table  (can be nested)
            raise "internal error: unexpected type: #{results[:data].class}, expecting Hash" unless results[:data].is_a?(Hash)
            final_table_columns = results[:columns] || ['key','value']
            asked_fields=results[:data].keys
            case user_asked_fields_list_str
            when FIELDS_DEFAULT;asked_fields=results[:fields] if results.has_key?(:fields)
            when FIELDS_ALL;# keep all
            else
              asked_fields=user_asked_fields_list_str.split(',')
            end
            if @option_flat_hash
              self.class.flatten_object(results[:data],results[:option_expand_last])
              self.class.flatten_name_value_list(results[:data])
              # first level keys are potentially changed
              asked_fields=results[:data].keys
            end
            table_rows_hash_val=asked_fields.map { |i| { final_table_columns.first => i, final_table_columns.last => results[:data][i] } }
          when :value_list  # goes to table display
            # :value_list is a simple array of values, name of column provided in the :name
            final_table_columns = [results[:name]]
            table_rows_hash_val=results[:data].map { |i| { results[:name] => i } }
          when :empty # no table
            puts "empty"
            return
          when :status # no table
            # :status displays a simple message
            puts results[:data]
            return
          when :other_struct # no table
            # :other_struct is any other type of structure
            puts PP.pp(results[:data],'')
            return
          else
            raise "unknown data type: #{results[:type]}"
          end
          # here we expect: table_rows_hash_val and final_table_columns
          raise "no field specified" if final_table_columns.nil?
          if table_rows_hash_val.empty?
            puts "empty".gray unless display_format.eql?(:csv)
            return
          end
          # convert to string with special function. here table_rows_hash_val is an array of hash
          table_rows_hash_val=results[:textify].call(table_rows_hash_val) if results.has_key?(:textify)
          filter=@opt_mgr.get_option(:select,:optional)
          unless filter.nil?
            raise CliBadArgument,"expecting hash for select" unless filter.is_a?(Hash)
            filter.each{|k,v|table_rows_hash_val.select!{|i|i[k].eql?(v)}}
          end

          # convert data to string, and keep only display fields
          final_table_rows=table_rows_hash_val.map { |r| final_table_columns.map { |c| r[c].to_s } }
          # here : final_table_columns : list of column names
          # here: final_table_rows : array of list of value
          case display_format
          when :table
            style=@option_table_style.split('')
            # display the table !
            puts Text::Table.new(
            :head => final_table_columns,
            :rows => final_table_rows,
            :horizontal_boundary   => style[0],
            :vertical_boundary     => style[1],
            :boundary_intersection => style[2])
          when :csv
            puts final_table_rows.map{|t| t.join(CSV_FIELD_SEPARATOR)}.join(CSV_RECORD_SEPARATOR)
          end
        end
      end

      def exit_with_usage(all_plugins)
        # display main plugin options
        STDERR.puts(@opt_mgr.parser)
        if all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          plugin_sym_list.select { |s| !@plugins[s][:require_stanza].nil? }.each do |plugin_name_sym|
            # override main option parser with a brand new
            @opt_mgr=Manager.new(@@PROGRAM_NAME)
            @opt_mgr.parser.banner = ""
            get_plugin_instance(plugin_name_sym)
            STDERR.puts(@opt_mgr.parser)
          end
        end
        #STDERR.puts(@opt_mgr.parser)
        STDERR.puts "\nDocumentation : #{@@HELP_URL}"
        Process.exit(0)
      end

      def process_exception_exit(e,reason,propose_help=:none)
        TempFileManager.instance.cleanup
        STDERR.puts "ERROR:".bg_red().gray().blink()+" "+reason+": "+e.message
        STDERR.puts "Use '-h' option to get help." if propose_help.eql?(:usage)
        if Log.instance.level.eql?(:debug)
          raise e
        else
          STDERR.puts "Use '--log-level=debug' to get more details." if propose_help.eql?(:debug)
          Process.exit(1)
        end
      end

      # read config file and validate format
      # tries to cnvert if possible and required
      def read_config_file
        # oldest compatible conf file format, update to latest version when an incompatible change is made
        if !File.exist?(@option_config_file)
          Log.log.warn("No config file found. Creating empty configuration file: #{@option_config_file}")
          @available_presets={@@MAIN_PLUGIN_NAME_SYM.to_s=>{@@CONFIG_FILE_KEY_VERSION=>self.class.gem_version}}
          save_presets_to_config_file
          return nil
        end
        begin
          Log.log.debug "loading #{@option_config_file}"
          @available_presets=YAML.load_file(@option_config_file)
          Log.log.debug "Available_presets: #{@available_presets}"
          raise "Expecting YAML Hash" unless @available_presets.is_a?(Hash)
          # check there is at least the config section
          if !@available_presets.has_key?(@@MAIN_PLUGIN_NAME_SYM.to_s)
            raise "Cannot find key: #{@@MAIN_PLUGIN_NAME_SYM.to_s}"
          end
          version=@available_presets[@@MAIN_PLUGIN_NAME_SYM.to_s][@@CONFIG_FILE_KEY_VERSION]
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
            if @available_presets[@@CONFIG_FILE_KEY_DEFAULT].is_a?(Hash) and @available_presets[@@CONFIG_FILE_KEY_DEFAULT].has_key?(old_plugin_name)
              @available_presets[@@CONFIG_FILE_KEY_DEFAULT][new_plugin_name]=@available_presets[@@CONFIG_FILE_KEY_DEFAULT][old_plugin_name]
              @available_presets[@@CONFIG_FILE_KEY_DEFAULT].delete(old_plugin_name)
              Log.log.warn("Converted plugin default: #{old_plugin_name} -> #{new_plugin_name}")
              save_required=true
            end
          end
          # Place new compatibility code here
          if save_required
            @available_presets[@@MAIN_PLUGIN_NAME_SYM.to_s][@@CONFIG_FILE_KEY_VERSION]=self.class.gem_version
            save_presets_to_config_file
            Log.log.warn("Saving automatic conversion.")
          end
        rescue => e
          new_name="#{@option_config_file}.pre#{self.class.version}.manual_conversion_needed"
          File.rename(@option_config_file,new_name)
          Log.log.warn("Renamed config file to #{new_name}.")
          Log.log.warn("Manual Conversion is required.")
          raise CliError,e.to_s
        end
      end

      protected

      def generate_new_key(key_filepath)
        require 'net/ssh'
        priv_key = OpenSSL::PKey::RSA.new(2048)
        File.write(key_filepath,priv_key.to_s)
        File.write(key_filepath+".pub",priv_key.public_key.to_s)
        nil
      end

      DEFAULT_REDIRECT='http://localhost:12345'

      # "config" plugin
      def execute_action
        action=@opt_mgr.get_next_argument('action',[:genkey,:plugins,:flush_tokens,:list,:overview,:open,:echo,:id,:documentation,:quickstart])
        case action
        when :id
          config_name=@opt_mgr.get_next_argument('config name')
          action=@opt_mgr.get_next_argument('action',[:show,:delete,:set,:unset,:initialize,:update,:ask])
          case action
          when :show
            raise "no such config: #{config_name}" unless @available_presets.has_key?(config_name)
            return {:type=>:single_object,:data=>@available_presets[config_name]}
          when :delete
            @available_presets.delete(config_name)
            save_presets_to_config_file
            return Main.result_status("deleted: #{config_name}")
          when :set
            param_name=@opt_mgr.get_next_argument('parameter name')
            param_value=@opt_mgr.get_next_argument('parameter value')
            if !@available_presets.has_key?(config_name)
              Log.log.debug("no such config name: #{config_name}, initializing")
              @available_presets[config_name]=Hash.new
            end
            if @available_presets[config_name].has_key?(param_name)
              Log.log.warn("overwriting value: #{@available_presets[config_name][param_name]}")
            end
            @available_presets[config_name][param_name]=param_value
            save_presets_to_config_file
            return Main.result_status("updated: #{config_name}: #{param_name} <- #{param_value}")
          when :unset
            param_name=@opt_mgr.get_next_argument('parameter name')
            if @available_presets.has_key?(config_name)
              @available_presets[config_name].delete(param_name)
              save_presets_to_config_file
            else
              Log.log.warn("no such parameter: #{param_name} (ignoring)")
            end
            return Main.result_status("removed: #{config_name}: #{param_name}")
          when :initialize
            config_value=@opt_mgr.get_next_argument('extended value (Hash)')
            if @available_presets.has_key?(config_name)
              Log.log.warn("configuration already exists: #{config_name}, overwriting")
            end
            @available_presets[config_name]=config_value
            save_presets_to_config_file
            return Main.result_status("modified: #{@option_config_file}")
          when :update
            #  TODO: when arguments are provided: --option=value, this creates an entry in the named configuration
            theopts=@opt_mgr.get_options_table
            Log.log.debug("opts=#{theopts}")
            @available_presets[config_name]={} if !@available_presets.has_key?(config_name)
            @available_presets[config_name].merge!(theopts)
            save_presets_to_config_file
            return Main.result_status("updated: #{config_name}")
          when :ask
            @opt_mgr.ask_missing_mandatory=:yes
            @available_presets[config_name]||={}
            @opt_mgr.get_next_argument('option names',:multiple).each do |optionname|
              option_value=@opt_mgr.get_interactive(:option,optionname)
              @available_presets[config_name][optionname]=option_value
            end
            save_presets_to_config_file
            return Main.result_status("updated: #{config_name}")
          end
        when :documentation
          OpenApplication.instance.uri(@@HELP_URL)
          return Main.result_none
        when :open
          OpenApplication.instance.uri("#{@option_config_file}") #file://
          return Main.result_none
        when :genkey # generate new rsa key
          key_filepath=@opt_mgr.get_next_argument('private key file path')
          generate_new_key(key_filepath)
          return Main.result_status('generated key: '+key_filepath)
        when :echo # display the content of a value given on command line
          result={:type=>:other_struct, :data=>@opt_mgr.get_next_argument("value")}
          # special for csv
          result[:type]=:object_list if result[:data].is_a?(Array) and result[:data].first.is_a?(Hash)
          return result
        when :flush_tokens
          deleted_files=Oauth.flush_tokens
          return {:type=>:value_list, :name=>'file',:data=>deleted_files}
        when :plugins
          return {:data => plugin_sym_list.map { |i| { 'plugin' => i.to_s, 'path' => @plugins[i][:source] } } , :fields => ['plugin','path'], :type => :object_list }
        when :list
          return {:data => @available_presets.keys, :type => :value_list, :name => 'name'}
        when :overview
          return {:type=>:object_list,:data=>self.class.flatten_all_config(@available_presets)}
        when :quickstart # TODO
          # only one value, so no test, no switch for the time being
          plugin_name=@opt_mgr.get_next_argument('plugin name',[:aspera])
          require 'asperalm/cli/plugins/aspera'
          files_plugin=Plugins::Aspera.new
          files_plugin.declare_options
          @opt_mgr.parse_options!
          @opt_mgr.set_option(:auth,:web)
          #@opt_mgr.set_option(:client_id,FilesApi.random.first)
          #@opt_mgr.set_option(:client_secret,FilesApi.random.last)
          #@opt_mgr.set_option(:redirect_uri,'https://asperafiles.com/token')
          @opt_mgr.set_option(:redirect_uri,DEFAULT_REDIRECT)
          instance_url=@opt_mgr.get_option(:url,:mandatory)
          organization,instance_domain=FilesApi.parse_url(instance_url)
          aspera_preset_name='aoc_'+organization
          @available_presets[@@CONFIG_FILE_KEY_DEFAULT]||=Hash.new
          raise CliError,"a default configuration already exists (use --override=yes)" if @available_presets[@@CONFIG_FILE_KEY_DEFAULT].has_key?(ASPERA_PLUGIN_S) and !option_override
          raise CliError,"preset already exists: #{aspera_preset_name}  (use --override=yes)" if @available_presets.has_key?(aspera_preset_name) and !option_override
          files_plugin.init_apis
          myself=files_plugin.api_files_user.read('self')[:data]
          if !myself['public_key'].empty?
            Log.log.warn("public key is already set, overriding")
          end
          key_filepath=File.join(@config_folder,'aspera_on_cloud_key')
          if File.exist?(key_filepath)
            puts "key file already exists: #{key_filepath}"
          else
            puts "generating: #{key_filepath}"
            generate_new_key(key_filepath)
          end
          puts "updating profile with new key"
          files_plugin.api_files_user.update("users/#{myself['id']}",{'public_key'=>File.read(key_filepath+'.pub')})
          puts "creating new config preset: #{aspera_preset_name}"
          @available_presets[aspera_preset_name]={
            :url.to_s           =>@opt_mgr.get_option(:url),
            :redirect_uri.to_s  =>@opt_mgr.get_option(:redirect_uri),
            :client_id.to_s     =>@opt_mgr.get_option(:client_id),
            :client_secret.to_s =>@opt_mgr.get_option(:client_secret),
            :auth.to_s          =>:jwt.to_s,
            :private_key.to_s   =>'@file:'+key_filepath,
            :username.to_s      =>myself['email'],
          }
          puts "setting config preset as default for #{ASPERA_PLUGIN_S}"
          @available_presets[@@CONFIG_FILE_KEY_DEFAULT][ASPERA_PLUGIN_S]=aspera_preset_name
          puts "saving config file"
          save_presets_to_config_file
          return Main.result_status("Done. You can test with:\naslmcli aspera user info show")
          # TODO: update documentation, enable JWT for the client_id
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
      # Note: does not accept shortcuts
      def early_debug_setup(argv)
        argv.each do |arg|
          case arg
          when '--'
            return
          when /^--log-level=(.*)/
            Log.instance.level = $1.to_sym
          when /^--logger=(.*)/
            Log.instance.logger_type=$1.to_sym
          end
        end
      end

      public

      def display_status(status)
        STDOUT.puts(status)
      end

      def preset_by_name(config_name)
        raise "no such config: #{config_name}" unless @available_presets.has_key?(config_name)
        return @available_presets[config_name]
      end
      # public method
      # $HOME/.aspera/aslmcli
      attr_reader :config_folder

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
      # @param: ts_source specifies how destination_root is set (how transfer spec was generated)
      # and not the default one
      def start_transfer(transfer_spec,ts_source)
        # initialize transfert agent, to set default transfer spec options before merge
        transfer_agent
        case transfer_spec['direction']
        when 'receive'
          # init default if required in any case
          destination_folder(transfer_spec['direction'])
        when 'send'
          case ts_source
          when :direct
            # init default if required
            destination_folder(transfer_spec['direction'])
          when :node_gen3
            # in that case, destination is set in return by application (API/upload_setup)
            # but to_folder was used in intial api call
            @transfer_spec_default.delete('destination_root')
          when :node_gen4
            @transfer_spec_default['destination_root']='/'
          else
            raise StandardError,"InternalError: unsupported value: #{ts_source}"
          end
        end

        transfer_spec.merge!(@transfer_spec_default)
        # add bypass keys if there is a token, also prevents connect plugin to ask password
        transfer_spec['authentication']='token' if transfer_spec.has_key?('token')
        transfer_agent.start_transfer(transfer_spec)
        return self.class.result_success
      end

      # this is the main function called by initial script just after constructor
      def process_command_line(argv)
        begin
          # first thing : manage debug level (allows debugging or option parser)
          early_debug_setup(argv)
          # declare and parse basic options (includes config file location)
          create_opt_mgr
          # give command line arguments to option manager
          @opt_mgr.add_cmd_line_options(argv)
          # parse declared options
          @opt_mgr.parse_options!
          # load default config if it was not overriden on command line
          read_config_file
          # declare general options
          declare_options
          @opt_mgr.parse_options!
          # find plugins, shall be after parse! ?
          add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help and @opt_mgr.command_or_arg_empty?
          # load global default options and process
          add_plugin_default_preset(@@MAIN_PLUGIN_NAME_SYM)
          @opt_mgr.parse_options!
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
          if @option_show_config and @opt_mgr.command_or_arg_empty?
            command_sym=@@MAIN_PLUGIN_NAME_SYM
          else
            command_sym=@opt_mgr.get_next_argument('command',plugin_sym_list.dup.unshift(:help))
          end
          # main plugin is not dynamically instanciated
          case command_sym
          when :help
            exit_with_usage(true)
          when @@MAIN_PLUGIN_NAME_SYM
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
            display_results({:type=>:single_object,:data=>@opt_mgr.declared_options(false)})
            Process.exit(0)
          end
          display_results(command_plugin.execute_action)
          @opt_mgr.fail_if_unprocessed
        rescue CliBadArgument => e;          process_exception_exit(e,'Argument',:usage)
        rescue CliNoSuchId => e;             process_exception_exit(e,'Identifier')
        rescue CliError => e;                process_exception_exit(e,'Tool',:usage)
        rescue Fasp::Error => e;             process_exception_exit(e,"FASP(ascp)")
        rescue Asperalm::RestCallError => e; process_exception_exit(e,"Rest")
        rescue SocketError => e;             process_exception_exit(e,"Network")
        rescue StandardError => e;           process_exception_exit(e,"Other",:debug)
        rescue Interrupt => e;               process_exception_exit(e,"Interruption",:debug)
        end
        TempFileManager.instance.cleanup
        return nil
      end
    end # Main
  end # Cli
end # Asperalm
