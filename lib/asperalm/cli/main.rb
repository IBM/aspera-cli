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
        application=Object::const_get(@@PLUGINS_MODULE+'::'+plugin_name_sym.to_s.capitalize).new(@option_parser,default_config)
        if application.respond_to?(:faspmanager=) then
          # create the FASP manager for transfers
          faspmanager=FaspManagerResume.new
          faspmanager.set_listener(FaspListenerLogger.new)
          application.faspmanager=faspmanager
        end
        return application
      end

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
        @option_parser.separator "\t#{$PROGRAM_NAME} files events"
        @option_parser.separator "\t#{$PROGRAM_NAME} --log-level=debug --config-name=myfaspex send 200KB.1"
        @option_parser.separator "\t#{$PROGRAM_NAME} -ntj files set_client_key LA-8RrEjw @file:data/myid"
        @option_parser.separator "\nSPECIAL OPTION VALUES\n\tif an option value begins with @env: or @file:, value is taken from env var or file"
        @option_parser.separator ""
        @option_parser.separator "OPTIONS (global)"
        @option_parser.on("-h", "--help", "Show this message") { @option_parser.exit_with_usage(nil) }
        @option_parser.add_opt_list(:loglevel,Log.levels,"Log level",'-lTYPE','--log-level=TYPE')
        @option_parser.add_opt_list(:logtype,[:syslog,:stdout],"log method",'-qTYPE','--logger=TYPE') { |op,val| attr_logtype(op,val) }
        @option_parser.add_opt_list(:format,[:ruby,:text],"output format",'--format=TYPE')
        @option_parser.add_opt_simple(:config_file,"-fSTRING", "--config-file=STRING","read parameters from file in JSON format")
        @option_parser.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
        @option_parser.add_opt_on(:rest_debug,"-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
      end

      def dojob
        subcommand=@option_parser.get_next_arg_from_list('action',[:ls,:init])
        case subcommand
        when :init
          raise StandardError,"Folder already exists: #{$PROGRAM_FOLDER}" if Dir.exist?($PROGRAM_FOLDER)
          FileUtils::mkdir_p($PROGRAM_FOLDER)
          sample_config={
            :global=>{"default"=>{:loglevel=>:warn}},
            :files=>{
            "default"=>{:auth=>:jwt, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecret", :private_key=>"@file:~/.aspera/aslmcli/filesapikey", :username=>"user@example.com"},
            "web"=>{:auth=>:web, :url=>"https://myorg.asperafiles.com", :client_id=>"MyClientId", :client_secret=>"MySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecretMySecret", :redirect_uri=>"http://local.connectme.us:12345"}
            },:faspex=>{
            "default"=>{:url=>"https://myfaspex.mycompany.com/aspera/faspex", :username=>"admin", :password=>"MyP@ssw0rd"},
            "app2"=>{:url=>"https://faspex.other.com/aspera/faspex", :username=>"john@example", :password=>"yM7FmjfGN$J4"}
            },:shares=>{"default"=>{:url=>"https://10.25.0.6", :username=>"admin", :password=>"MyP@ssw0rd"}
            },:node=>{"default"=>{:url=>"https://10.25.0.8:9092", :username=>"node_user", :password=>"MyP@ssw0rd", :transfer_filter=>"t['status'].eql?('completed') and t['start_spec']['remote_user'].eql?('faspex')", :file_filter=>"f['status'].eql?('completed') and 0 != f['size'] and t['start_spec']['direction'].eql?('send')"}
            }, :console=>{"default"=>{:url=>"https://console.myorg.com/aspera/console", :username=>"admin", :password=>"xxxxx"}}
          }
          File.write($DEFAULT_CONFIG_FILE,sample_config.to_yaml)
          return "initialized: #{$PROGRAM_FOLDER}"
        when :ls
          sections=self.class.get_plugin_list.unshift(:global)
          if @option_parser.command_or_arg_empty?
            # just list plugins
            results={ :fields => ['plugin'], :values=>sections.map { |i| { 'plugin' => i.to_s } } }
          else
            plugin=@option_parser.get_next_arg_from_list('plugin',sections)
            names=@loaded_config[plugin].keys.map { |i| i.to_sym }
            if @option_parser.command_or_arg_empty?
              # list names for tool
              results={ :fields => ['name'], :values=>names.map { |i| { 'name' => i.to_s } } }
            else
              # list parameters
              configname=@option_parser.get_next_arg_from_list('config',names)
              results={ :fields => ['param','value'], :values=>@loaded_config[plugin][configname.to_s].keys.map { |i| { 'param' => i.to_s, 'value' => @loaded_config[plugin][configname.to_s][i] } } }
            end
          end
        end
      end

      def go()
        self.set_options
        command_sym=@option_parser.get_next_arg_from_list('command',plugin_list)
        case command_sym
        when :config
          application=self
        else
          # execute plugin
          application=self.new_plugin(command_sym)
          @option_parser.separator "OPTIONS (#{command_sym})"
          application.set_options
        end
        @option_parser.parse_options!()
        results=application.dojob
        if results.is_a?(Hash) and results.has_key?(:values) and results.has_key?(:fields) then
          case @option_parser.get_option_mandatory(:format)
          when :ruby
            puts PP.pp(results[:values],'')
          when :text
            rows=results[:values].map{ |r| results[:fields].map { |c| r[c].to_s } }
            puts Text::Table.new(:head => results[:fields], :rows => rows, :vertical_boundary  => '.', :horizontal_boundary => ':', :boundary_intersection => ':')
          end
        else
          if results.is_a?(String)
            $stdout.write(results)
          elsif results.nil?
            Log.log.debug("result=nil")
          else
            puts ">result>#{PP.pp(results,'')}"
          end
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
          :format => :text,
          :config_name => 'default'
        }
        Log.level = defaults[:loglevel]
        @option_parser=OptParser.new(ARGV)
        config_file=$DEFAULT_CONFIG_FILE
        Log.log.debug("config file=#{config_file}")
        defaults[:config_file]=config_file if File.exist?(config_file)
        tool=self.new(@option_parser,defaults)
        begin
          tool.go()
        rescue CliBadArgument => e
          @option_parser.exit_with_usage(e)
        end
      end
    end
  end
end
