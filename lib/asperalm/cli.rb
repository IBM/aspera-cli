require 'yaml'
require 'logger'
require 'asperalm/rest'
require 'asperalm/fasp_manager'
require 'asperalm/opt_parser'
require "asperalm/version"

module Asperalm
  class Cli
    def opt_names; [:logtype,:loglevel,:config_name,:config_file]; end

    def get_logtypes; [:syslog,:stdout]; end

    def get_loglevels; [:debug,:info,:warn,:error,:fatal,:unknown]; end

    def set_logtype(logtype)
      case logtype
      when :stdout
        require 'syslog/logger'
        @logger = Logger.new(STDOUT)
      when :syslog
        @logger = Logger::Syslog.new("as_cli")
      else
        raise "unknown logger: #{logtype}"
      end
      set_loglevel :warn
    end

    def set_loglevel(loglevel)
      @logger.level = get_loglevels.index(loglevel)
    end

    def get_loglevel
      get_loglevels[@logger.level]
    end

    def set_config_file(v)
      @logger.debug "loading #{v}"
      @loaded_config=YAML.load_file(v)
      @opt_parser.set_defaults(@loaded_config)
    end

    def initialize()
      @logger=Logger.new(STDERR)
      @logger.level=get_loglevels.index(:warn)
      @logger.debug("setting defaults")
    end

    @plugin_list=[]

    @@CONFIG_FILE_HOME='.aspera/ascli/config.yaml'
    @@SYSTEM_PLUGINS_FOLDER='asperalm/cli_plugins'

    #################################
    # MAIN
    #--------------------------------
    def go(argv)
      $PROGRAM_NAME = 'ascli'
      $DEFAULT_CONFIG_FILE=File.join(Dir.home,@@CONFIG_FILE_HOME)
      defaults={
        :logtype => :stdout,
        :loglevel => :warn,
        :config_name => 'default'
      }
      defaults[:config_file]=$DEFAULT_CONFIG_FILE if File.exist?($DEFAULT_CONFIG_FILE)

      # get list of available plugins
      plugin_folder=File.join(File.dirname(File.dirname(__FILE__)),@@SYSTEM_PLUGINS_FOLDER)
      @plugin_list=Dir.entries(plugin_folder).select { |i| i.end_with?('.rb')}.map { |i| i.gsub(/\.rb$/,'').to_sym}

      # parse script arguments
      @opt_parser = OptParser.new(self)
      @opt_parser.set_defaults(defaults)
      @opt_parser.banner = "NAME\n\t#{$PROGRAM_NAME} -- a command line tool for Aspera Applications\n\n"
      @opt_parser.separator "SYNOPSIS"
      @opt_parser.separator "\t#{$PROGRAM_NAME} [OPTIONS] COMMAND [ARGS]..."
      @opt_parser.separator ""
      @opt_parser.separator "DESCRIPTION"
      @opt_parser.separator "\tUse Aspera application to perform operations on command line."
      @opt_parser.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
      @opt_parser.separator ""
      @opt_parser.separator "EXAMPLES"
      @opt_parser.separator "\t#{$PROGRAM_NAME} files events"
      @opt_parser.separator "\t#{$PROGRAM_NAME} --log-level=debug --config-name=myfaspex send 200KB.1"
      @opt_parser.separator "\t#{$PROGRAM_NAME} -ntj files set_client_key LA-8RrEjw @file:data/myid"
      @opt_parser.separator "\nSPECIAL OPTION VALUES\n\tif an option value begins with @env: or @file:, value is taken from env var or file"
      @opt_parser.separator ""
      @opt_parser.separator "COMMANDS"
      @opt_parser.separator "\tSupported commands: #{@plugin_list.join(', ')}"
      @opt_parser.separator ""
      @opt_parser.separator "OPTIONS"
      @opt_parser.add_opt_list(:loglevel,"Log level",'-lTYPE','--log-level=TYPE')
      @opt_parser.add_opt_list(:logtype,"log method",'-qTYPE','--logger=TYPE')
      @opt_parser.add_opt_simple(:config_file,"-fSTRING", "--config-file=STRING","read parameters from file in JSON format")
      @opt_parser.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
      @opt_parser.on("-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true,@logger) }
      @opt_parser.on_tail("-h", "--help", "Show this message") { @opt_parser.exit_with_usage }

      begin
        @opt_parser.parse_ex!(argv)
        app_name=OptParser.get_next_arg_from_list(argv,'application',@plugin_list)
        default_config=@loaded_config[app_name][@opt_parser.get_option_mandatory(:config_name)] if !@loaded_config.nil? and @loaded_config.has_key?(app_name)
        require File.join(@@SYSTEM_PLUGINS_FOLDER,app_name.to_s)
        application=Object::const_get('Asperalm::CliPlugins::'+app_name.to_s.capitalize).new(@logger)
        # create the FASP manager for transfers
        faspmanager=FaspManager.new(@logger)
        faspmanager.set_listener(FaspListenerLogger.new(@logger))
        application.faspmanager=faspmanager
        application.go(argv,default_config)
      rescue OptionParser::InvalidArgument => e
        STDERR.puts "ERROR:".bg_red().gray()+" #{e}\n\n"
        @opt_parser.exit_with_usage
      end
    end
  end
end
