require 'asperalm/cli/manager'
require 'asperalm/cli/plugin'
require 'asperalm/cli/plugins/config'
require 'asperalm/cli/extended_value'
require 'asperalm/cli/listener/logger'
require 'asperalm/cli/listener/progress_multi'
require 'asperalm/fasp/local'
require 'asperalm/fasp/connect'
require 'asperalm/fasp/node'
require 'asperalm/open_application'
require 'asperalm/temp_file_manager'
require 'asperalm/log'
require 'asperalm/rest'
require 'asperalm/files_api'
require 'text-table'
require 'fileutils'
require 'singleton'
require 'yaml'
require 'pp'

module Asperalm
  module Cli
    # The main CLI class
    class Main
      include Singleton
      # "tool" class method is an alias to "instance" of singleton
      singleton_class.send(:alias_method, :tool, :instance)
      def self.gem_version
        File.read(File.join(gem_root,@@GEM_NAME,'VERSION')).chomp
      end

      private
      # first level command for the main tool
      @@CONFIG_PLUGIN_NAME_SYM=:config
      # name of application, also foldername where config is stored
      @@PROGRAM_NAME = 'aslmcli'
      @@GEM_NAME = 'asperalm'
      # folder containing custom plugins in `config_folder`
      @@ASPERA_PLUGINS_FOLDERNAME='plugins'
      # folder containing plugins in the gem's main folder
      @@GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
      # Container module of current class : Asperalm::Cli
      @@CLI_MODULE=Module.nesting[1].to_s
      # Path to Plugin classes: Asperalm::Cli::Plugins
      @@PLUGINS_MODULE=@@CLI_MODULE+'::Plugins'
      RUBY_FILE_EXT='.rb'
      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'

      # find the root folder of gem where this class is
      def self.gem_root
        File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'),File.dirname(__FILE__))
      end

      # =============================================================
      # Parameter handlers
      #

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
        raise CliError,"no such preset defined: #{value}" unless config_presets.has_key?(value)
        @opt_mgr.add_option_preset(config_presets[value])
      end

      # returns the list of plugins from plugin folder
      #def plugin_sym_list
      #  return @plugins.keys
      #end

      #delete : def action_list; @plugins.keys; end

      def config_presets
        Plugins::Config.instance.config_presets
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

      # transfer agent singleton
      def transfer_manager
        if @transfer_manager_singleton.nil?
          # by default use local ascp
          case @opt_mgr.get_option(:transfer,:mandatory)
          when :direct
            @transfer_manager_singleton=Fasp::Local.instance
            if !@opt_mgr.get_option(:fasp_proxy,:optional).nil?
              @transfer_spec_default['EX_fasp_proxy_url']=@opt_mgr.get_option(:fasp_proxy,:optional)
            end
            if !@opt_mgr.get_option(:http_proxy,:optional).nil?
              @transfer_spec_default['EX_http_proxy_url']=@opt_mgr.get_option(:http_proxy,:optional)
            end
            # TODO: option to choose progress format
            # here we disable native stdout progress
            @transfer_manager_singleton.quiet=true
            Log.log.debug(">>>>#{@transfer_spec_default}".red)
          when :connect
            @transfer_manager_singleton=Fasp::Connect.instance
          when :node
            # support: @param:<name>
            # support extended values
            transfer_node_spec=@opt_mgr.get_option(:transfer_node,:optional)
            # of not specified, use default node
            case transfer_node_spec
            when nil
              param_set_name=Plugins::Config.instance.get_plugin_default_config_name(:node)
              raise CliBadArgument,"No default node configured, Please specify --transfer-node" if param_set_name.nil?
              node_config=config_presets[param_set_name]
            when /^@param:/
              param_set_name=transfer_node_spec.gsub!(/^@param:/,'')
              Log.log.debug("param_set_name=#{param_set_name}")
              raise CliBadArgument,"no such parameter set: [#{param_set_name}] in config file" if !config_presets.has_key?(param_set_name)
              node_config=config_presets[param_set_name]
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
            @transfer_manager_singleton=Fasp::Node.instance
            Fasp::Node.instance.node_api=Rest.new({:base_url=>sym_config[:url],:auth_type=>:basic,:basic_username=>sym_config[:username], :basic_password=>sym_config[:password]})
          else raise "ERROR"
          end
          @transfer_manager_singleton.add_listener(Listener::Logger.new)
          @transfer_manager_singleton.add_listener(Listener::ProgressMulti.new)
        end
        return @transfer_manager_singleton
      end

      attr_accessor :option_flat_hash
      attr_accessor :option_table_style

      # minimum initialization
      def initialize
        # overriding parameters on transfer spec
        @transfer_spec_default={}
        @option_help=false
        @option_show_config=false
        @option_flat_hash=true
        config_presets=nil
        @transfer_manager_singleton=nil
        @plugins={@@CONFIG_PLUGIN_NAME_SYM=>{:source=>__FILE__,:require_stanza=>nil}}
        @plugin_lookup_folders=[]
        @option_table_style=':.:'
        # define program name, sets default config folder
        Plugins::Config.instance.set_program_info(@@PROGRAM_NAME,@@GEM_NAME,self.class.gem_version)
        # set folders for temp files
        Fasp::Parameters.file_list_folder=File.join(config_folder,'filelists')
        Oauth.persistency_folder=config_folder
        #
        @opt_mgr=Manager.new(@@PROGRAM_NAME)
        add_plugin_lookup_folder(File.join(self.class.gem_root,@@GEM_PLUGINS_FOLDER))
        add_plugin_lookup_folder(File.join(config_folder,@@ASPERA_PLUGINS_FOLDERNAME))
      end

      # local options
      def init_options
        @opt_mgr.parser.banner = "NAME\n\t#{@@PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{self.class.gem_version})\n\n"
        @opt_mgr.parser.separator "SYNOPSIS"
        @opt_mgr.parser.separator "\t#{@@PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "DESCRIPTION"
        @opt_mgr.parser.separator "\tUse Aspera application to perform operations on command line."
        @opt_mgr.parser.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        @opt_mgr.parser.separator "\tDocumentation and examples: #{Plugins::Config.instance.gem_url}"
        @opt_mgr.parser.separator "\texecute: #{@@PROGRAM_NAME} conf doc"
        @opt_mgr.parser.separator ""
        @opt_mgr.parser.separator "COMMANDS"
        @opt_mgr.parser.separator "\tFirst level commands: #{@plugins.keys.map {|x| x.to_s}.join(', ')}"
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
        @opt_mgr.set_obj_attr(:table_style,self,:option_table_style)
        @opt_mgr.add_opt_simple(:table_style,"table display style, current=#{@option_table_style}")
        @opt_mgr.add_opt_switch(:help,"Show this message.","-h") { @option_help=true }
        @opt_mgr.add_opt_switch(:show_config, "Display parameters used for the provided action.") { @option_show_config=true }
        @opt_mgr.add_opt_switch(:rest_debug,"-r","more debug for HTTP calls") { Rest.debug=true }
        @opt_mgr.add_opt_switch(:version,"-v","display version") { puts self.class.gem_version;Process.exit(0) }
      end

      def declare_global_options
        # handler must be set before declaration
        @opt_mgr.set_obj_attr(:log_level,Log.instance,:level)
        @opt_mgr.set_obj_attr(:insecure,self,:option_insecure,:no)
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
        @opt_mgr.add_opt_simple(:query,"additional filter for API calls (extended value)")
        @opt_mgr.add_opt_boolean(:insecure,"do not validate HTTPS certificate")
        @opt_mgr.add_opt_boolean(:flat_hash,"display hash values as additional keys")
        @opt_mgr.add_opt_boolean(:override,"override existing value")

        @opt_mgr.set_option(:ui,OpenApplication.default_gui_mode)
        @opt_mgr.set_option(:fields,FIELDS_DEFAULT)
        @opt_mgr.set_option(:transfer,:direct)
        @opt_mgr.set_option(:format,:table)
      end

      # returns default parameters for a plugin from loaded config file
      # try to find: conffile[conffile["default"][plugin_str]]
      def add_plugin_default_preset(plugin_sym)
        default_config_name=Plugins::Config.instance.get_plugin_default_config_name(plugin_sym)
        Log.log.debug("add_plugin_default_preset:#{plugin_sym}:#{default_config_name}")
        return if default_config_name.nil?
        @opt_mgr.add_option_preset(config_presets[default_config_name],:unshift)
      end

      # plugin_name_sym is symbol
      # loads default parameters if no -P parameter
      def get_plugin_instance(plugin_name_sym)
        Log.log.debug("get_plugin_instance -> #{plugin_name_sym}")
        require @plugins[plugin_name_sym][:require_stanza]
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).instance
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

      # expect some list, but nothing to display
      def self.result_empty
        return {:type => :empty, :data => :nil }
      end

      # nothing expected
      def self.result_nothing
        return {:type => :nothing, :data => :nil }
      end

      def self.result_status(status)
        return {:type => :status, :data => status }
      end

      def self.result_success
        return result_status('complete')
      end

      # supported output formats
      def self.display_formats; [:table,:ruby,:json,:jsonpp,:yaml,:csv]; end

      CSV_RECORD_SEPARATOR="\n"
      CSV_FIELD_SEPARATOR=","

      # this method displays the results, especially the table format
      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash (got: #{results.class}: #{results})" unless results.is_a?(Hash)
        raise "INTERNAL ERROR, result must have type" unless results.has_key?(:type)
        raise "INTERNAL ERROR, result must have data" unless results.has_key?(:data) or [:empty,:nothing].include?(results[:type])

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
          when :nothing # no result expected
            Log.log.debug("no result expected")
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
          @plugins.keys.select { |s| !@plugins[s][:require_stanza].nil? }.each do |plugin_name_sym|
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

      protected

      def generate_new_key(key_filepath)
        require 'net/ssh'
        priv_key = OpenSSL::PKey::RSA.new(2048)
        File.write(key_filepath,priv_key.to_s)
        File.write(key_filepath+".pub",priv_key.public_key.to_s)
        nil
      end

      DEFAULT_REDIRECT='http://localhost:12345'

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
        STDOUT.puts(status) if @opt_mgr.get_option(:format,:mandatory).eql?(:table)
      end

      def preset_by_name(config_name)
        raise "no such config: #{config_name}" unless config_presets.has_key?(config_name)
        return config_presets[config_name]
      end

      # public method
      # $HOME/.aspera/aslmcli
      def config_folder
        Plugins::Config.instance.config_folder
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
      # @param: ts_source specifies how destination_root is set (how transfer spec was generated)
      # and not the default one
      def start_transfer_wait_result(transfer_spec,ts_source)
        # initialize transfert agent, to set default transfer spec options before merge
        transfer_manager
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
        Log.log.debug("mgr is a #{transfer_manager.class}")
        transfer_manager.start_transfer(transfer_spec)
        return self.class.result_nothing
      end

      # this is the main function called by initial script just after constructor
      def process_command_line(argv)
        exception_info=nil
        begin
          # first thing : manage debug level (allows debugging or option parser)
          early_debug_setup(argv)
          # give command line arguments to option manager (no parsing)
          @opt_mgr.add_cmd_line_options(argv)
          # declare initial options
          init_options
          # declare options for config file location
          Plugins::Config.instance.declare_options
          # parse declared options
          @opt_mgr.parse_options!
          # load default config if it was not overriden on command line
          Plugins::Config.instance.read_config_file
          # declare general options
          declare_global_options
          @opt_mgr.parse_options!
          # find plugins, shall be after parse! ?
          add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help and @opt_mgr.command_or_arg_empty?
          # load global default options and process
          add_plugin_default_preset(@@CONFIG_PLUGIN_NAME_SYM)
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
            command_sym=@@CONFIG_PLUGIN_NAME_SYM
          else
            command_sym=@opt_mgr.get_next_argument('command',@plugins.keys.dup.unshift(:help))
          end
          # main plugin is not dynamically instanciated
          case command_sym
          when :help
            exit_with_usage(true)
          when @@CONFIG_PLUGIN_NAME_SYM
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
          # execute and display
          display_results(command_plugin.execute_action)
          # wait for session termination
          transfer_manager.shutdown(true)
          @opt_mgr.fail_if_unprocessed
        rescue CliBadArgument => e;          exception_info=[e,'Argument',:usage]
        rescue CliNoSuchId => e;             exception_info=[e,'Identifier']
        rescue CliError => e;                exception_info=[e,'Tool',:usage]
        rescue Fasp::Error => e;             exception_info=[e,"FASP(ascp]"]
        rescue Asperalm::RestCallError => e; exception_info=[e,"Rest"]
        rescue SocketError => e;             exception_info=[e,"Network"]
        rescue StandardError => e;           exception_info=[e,"Other",:debug]
        rescue Interrupt => e;               exception_info=[e,"Interruption",:debug]
        end
        # cleanup file list files
        TempFileManager.instance.cleanup
        # processing of error condition
        unless exception_info.nil?
          STDERR.puts "ERROR:".bg_red().gray().blink()+" "+exception_info[1]+": "+exception_info[0].message
          STDERR.puts "Use '-h' option to get help." if exception_info[2].eql?(:usage)
          if Log.instance.level.eql?(:debug)
            # will force to show stack trace
            raise exception_info[0]
          else
            STDERR.puts "Use '--log-level=debug' to get more details." if exception_info[2].eql?(:debug)
            Process.exit(1)
          end
        end
        return nil
      end # process_command_line
    end # Main
  end # Cli
end # Asperalm
