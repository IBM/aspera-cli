require "asperalm/cli/opt_parser"
require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require 'yaml'
require 'text-table'
require 'pp'
require 'fileutils'

module Asperalm
  module Cli
    class Main < Plugin
      def plugin_list
        self.class.get_plugin_list.push(:config)
      end

      def attr_logtype(operation,value)
        case operation
        when :set
          Log.setlogger(value)
          @option_parser.set_option(:loglevel,:warn)
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

      def attr_config_file(operation,value)
        case operation
        when :set
          Log.log.debug "loading #{value}"
          @loaded_config=YAML.load_file(value)
          Log.log.debug "loaded: #{@loaded_config}"
          @option_parser.set_defaults(@loaded_config[:global][@option_parser.get_option(:config_name)])
        else
          Log.log.debug "TODO: get config_file ???"
        end
      end

      def initialize(option_parser,defaults)
        option_parser.set_handler(:loglevel) { |op,val| attr_loglevel(op,val) }
        option_parser.set_handler(:logtype) { |op,val| attr_logtype(op,val) }
        option_parser.set_handler(:config_file) { |op,val| attr_config_file(op,val) }
        super(option_parser,defaults)
      end

      @@GEM_PLUGINS_FOLDER='asperalm/cli/plugins'
      @@CLI_MODULE=Module.nesting[1].to_s
      @@PLUGINS_MODULE=@@CLI_MODULE+"::Plugins"

      def self.get_plugin_list
        gem_root=File.expand_path(@@CLI_MODULE.to_s.gsub('::','/').gsub(%r([^/]+),'..'), File.dirname(__FILE__))
        plugin_folder=File.join(gem_root,@@GEM_PLUGINS_FOLDER)
        return Dir.entries(plugin_folder).select { |i| i.end_with?('.rb')}.map { |i| i.gsub(/\.rb$/,'').to_sym}
      end

      # plugin_name_sym is symbol
      def new_plugin(plugin_name_sym)
        require File.join(@@GEM_PLUGINS_FOLDER,plugin_name_sym.to_s)
        Log.log.debug("#{@option_parser.get_option_mandatory(:config_name)} -> #{@loaded_config} ")
        if !@loaded_config.nil? and @loaded_config.has_key?(plugin_name_sym)
          default_config=@loaded_config[plugin_name_sym][@option_parser.get_option_mandatory(:config_name)]
          Log.log.debug("#{plugin_name_sym} default config=#{default_config}")
        else
          default_config=nil
          Log.log.debug("no default config")
        end
        # TODO: check that ancestor is Plugin
        command_plugin=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new(@option_parser,default_config)
        if command_plugin.respond_to?(:faspmanager=) then
          # create the FASP manager for transfers
          faspmanager=FaspManagerResume.new
          faspmanager.set_listener(FaspListenerLogger.new)
          command_plugin.faspmanager=faspmanager
        end
        return command_plugin
      end

      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'

      def set_options
        @option_parser.banner = "NAME\n\t#{$PROGRAM_NAME} -- a command line tool for Aspera Applications\n\n"
        @option_parser.separator "SYNOPSIS"
        @option_parser.separator "\t#{$PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]"
        @option_parser.separator ""
        @option_parser.separator "COMMANDS"
        @option_parser.separator "\tSupported commands: #{plugin_list.map {|x| x.to_s}.join(', ')}"
        @option_parser.separator ""
        @option_parser.separator "DESCRIPTION"
        @option_parser.separator "\tUse Aspera application to perform operations on command line."
        @option_parser.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        @option_parser.separator ""
        @option_parser.separator "EXAMPLES"
        @option_parser.separator "\t#{$PROGRAM_NAME} files browse /"
        @option_parser.separator "\t#{$PROGRAM_NAME} faspex send ./myfile --log-level=debug"
        @option_parser.separator "\t#{$PROGRAM_NAME} shares upload ~/myfile /myshare"
        @option_parser.separator "\nSPECIAL OPTION VALUES\n\tif an option value begins with @env: or @file:, value is taken from env var or file"
        @option_parser.separator ""
        @option_parser.separator "OPTIONS (global)"
        @option_parser.set_option(:fields,FIELDS_DEFAULT)
        @option_parser.set_option(:transfer,:ascp)
        @option_parser.set_option(:transfer_node_config,'default')
        @option_parser.on("-h", "--help", "Show this message") { @option_parser.exit_with_usage(nil) }
        @option_parser.add_opt_list(:loglevel,Log.levels,"Log level",'-lTYPE','--log-level=TYPE')
        @option_parser.add_opt_list(:logtype,[:syslog,:stdout],"log method",'-qTYPE','--logger=TYPE') { |op,val| attr_logtype(op,val) }
        @option_parser.add_opt_list(:format,[:ruby,:text_table],"output format",'--format=TYPE')
        @option_parser.add_opt_list(:transfer,[:ascp,:connect,:node],"type of transfer",'--transfer=TYPE')
        @option_parser.add_opt_simple(:config_file,"-fSTRING", "--config-file=STRING","read parameters from file in YAML format")
        @option_parser.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
        @option_parser.add_opt_simple(:transfer_node_config,"--node-config=STRING","name of configuration used to transfer when using --transfer=node")
        @option_parser.add_opt_simple(:fields,"--fields=STRING","comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        @option_parser.add_opt_simple(:fasp_proxy,"--fasp-proxy=STRING","URL of FASP proxy (dnat / dnats)")
        @option_parser.add_opt_simple(:http_proxy,"--http-proxy=STRING","URL of HTTP proxy (for http fallback)")
        @option_parser.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
      end

      def self.result_simple_table(name,list)
        return {:values => list.map { |i| { name => i.to_s } }}
      end

      def execute_action
        subcommand=@option_parser.get_next_arg_from_list('action',[:ls,:init])
        case subcommand
        when :init
          raise StandardError,"Folder already exists: #{$PROGRAM_FOLDER}" if Dir.exist?($PROGRAM_FOLDER)
          FileUtils::mkdir_p($PROGRAM_FOLDER)
          sample_config={
            :global=>{"default"=>{:loglevel=>:warn}},
            :files=>{
            "default"=>{:auth=>:jwt, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MyAccessKeySecret", :private_key=>"@file:~/.aspera/aslmcli/filesapikey", :username=>"user@example.com"},
            "web"=>{:auth=>:web, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MyAccessKeySecret", :redirect_uri=>"http://local.connectme.us:12345"}
            },:faspex=>{
            "default"=>{:url=>"https://myfaspex.mycompany.com/aspera/faspex", :username=>"admin", :password=>"MyP@ssw0rd"},
            "app2"=>{:url=>"https://faspex.other.com/aspera/faspex", :username=>"john@example", :password=>"yM7FmjfGN$J4"}
            },:shares=>{"default"=>{:url=>"https://10.25.0.6", :username=>"admin", :password=>"MyP@ssw0rd"}
            },:node=>{"default"=>{:url=>"https://10.25.0.8:9092", :username=>"node_user", :password=>"MyP@ssw0rd", :transfer_filter=>"t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?('faspex')", :file_filter=>"f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?('send')"}
            },:console=>{"default"=>{:url=>"https://console.myorg.com/aspera/console", :username=>"admin", :password=>"xxxxx"}}
          }
          File.write($DEFAULT_CONFIG_FILE,sample_config.to_yaml)
          puts "initialized: #{$PROGRAM_FOLDER}"
          return nil
        when :ls
          sections=self.class.get_plugin_list.unshift(:global)
          if @option_parser.command_or_arg_empty?
            # just list plugins
            return self.class.result_simple_table('plugin',sections)
          else
            plugin=@option_parser.get_next_arg_from_list('plugin',sections)
            names=@loaded_config[plugin].keys.map { |i| i.to_sym }
            if @option_parser.command_or_arg_empty?
              # list names for tool
              return self.class.result_simple_table('name',names)
            else
              # list parameters
              configname=@option_parser.get_next_arg_from_list('config',names)
              return {:values => @loaded_config[plugin][configname.to_s].keys.map { |i| { 'param' => i.to_s, 'value' => @loaded_config[plugin][configname.to_s][i] } } , :fields => ['param','value'] }
            end
          end
        end
      end

      def process_command()
        self.set_options
        command_sym=@option_parser.get_next_arg_from_list('command',plugin_list)
        case command_sym
        when :config
          command_plugin=self
        else
          # execute plugin
          command_plugin=self.new_plugin(command_sym)
          @option_parser.separator "OPTIONS (#{command_sym})"
          command_plugin.set_options
        end
        @option_parser.parse_options!()
        if command_plugin.respond_to?(:faspmanager)
          case @option_parser.get_option_mandatory(:transfer)
          when :connect
            command_plugin.faspmanager.use_connect_client=true
          when :node
            node_config=@loaded_config[:node][@option_parser.get_option_mandatory(:transfer_node_config)]
            command_plugin.faspmanager.tr_node_api=Rest.new(node_config[:url],{:basic_auth=>{:user=>node_config[:username], :password=>node_config[:password]}})
          end
          # may be nil:
          command_plugin.faspmanager.fasp_proxy_url=@option_parser.get_option(:fasp_proxy)
          command_plugin.faspmanager.http_proxy_url=@option_parser.get_option(:http_proxy)
        end
        results=command_plugin.execute_action
        if results.nil?
          Log.log.debug("result=nil")
        elsif results.is_a?(String)
          $stdout.write(results)
        elsif results.is_a?(Hash) and results.has_key?(:values) then
          if results[:values].empty?
            $stdout.write("no result")
          else
            display_fields=nil
            case @option_parser.get_option_mandatory(:fields)
            when FIELDS_DEFAULT
              if !results.has_key?(:fields)
                raise "empty results" if results[:values].empty?
                display_fields=results[:values].first.keys
              else
                display_fields=results[:fields]
              end
            when FIELDS_ALL
              raise "empty results" if results[:values].empty?
              display_fields=results[:values].first.keys
            else
              display_fields=@option_parser.get_option_mandatory(:fields).split(',')
            end
            case @option_parser.get_option_mandatory(:format)
            when :ruby
              puts PP.pp(results[:values],'')
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
        if !@option_parser.command_or_arg_empty?
          raise CliBadArgument,"unprocessed values: #{@option_parser.get_remaining_arguments(nil)}"
        end
        return ""
      end

      #################################
      # MAIN
      #--------------------------------
      $PROGRAM_NAME = 'aslmcli'
      $ASPERA_HOME_FOLDERNAME='.aspera'
      $ASPERA_HOME_FOLDERPATH=File.join(Dir.home,$ASPERA_HOME_FOLDERNAME)
      $PROGRAM_FOLDER=File.join($ASPERA_HOME_FOLDERPATH,$PROGRAM_NAME)
      $DEFAULT_CONFIG_FILE=File.join($PROGRAM_FOLDER,'config.yaml')

      def self.start
        defaults={
          :logtype => :stdout,
          :loglevel => :warn,
          :format => :text_table,
          :config_name => 'default'
        }
        Log.level = defaults[:loglevel]
        @option_parser=OptParser.new(ARGV)
        config_file=$DEFAULT_CONFIG_FILE
        Log.log.debug("config file=#{config_file}")
        defaults[:config_file]=config_file if File.exist?(config_file)
        tool=self.new(@option_parser,defaults)
        begin
          tool.process_command()
        rescue CliBadArgument => e
          @option_parser.exit_with_usage("CLI error: #{e}")
        rescue Asperalm::TransferError => e
          @option_parser.exit_with_usage("FASP error: #{e}",false)
        end
      end
    end
  end
end
