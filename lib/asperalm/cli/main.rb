require 'yaml'
require 'logger'
require 'syslog/logger'
require 'aspera/cli/files'
require 'aspera/cli/faspex'
require 'aspera/cli/shares'
require 'aspera/cli/node'
require 'aspera/rest'
require 'aspera/fasp_manager'
require 'aspera/opt_parser'

# listener for FASP transfers (debug)
class FaspListenerLogger < FileTransferListener
  def initialize(logger)
    @logger=logger
  end

  def event(data)
    @logger.debug "#{data}"
  end
end

class AsCli
  def opt_names
    [:logtype,:loglevel,:config_name,:config_file]
  end

  def get_logtypes
    [:syslog,:stdout]
  end

  def get_loglevels
    [:debug,:info,:warn,:error,:fatal,:unknown]
  end

  def set_logtype(logtype)
    case logtype
    when :stdout
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

  def initialize(defaults)
    @logger=Logger.new(STDERR)
    @logger.level=get_loglevels.index(:warn)
    @opt_parser = AsperaOptParser.new(self)
    @logger.debug("setting defaults")
    @opt_parser.set_defaults(defaults)
  end

  @@COMANDS=[:files,:faspex,:shares,:node]

  #################################
  # MAIN
  #--------------------------------
  def go(argv)

    # parse script arguments
    @opt_parser.banner = "NAME\n\t#{$0} -- a command line tool for Aspera Applications\n\n"
    @opt_parser.separator "SYNOPSIS"
    @opt_parser.separator "\t#{$0} [OPTIONS] COMMAND [ARGS]..."
    @opt_parser.separator ""
    @opt_parser.separator "DESCRIPTION"
    @opt_parser.separator "\tUse Aspera application to perform operations on command line."
    @opt_parser.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
    @opt_parser.separator ""
    @opt_parser.separator "EXAMPLES"
    @opt_parser.separator "\t#{$0} --log-level=debug --param-file=data/conf_testeng.qa.jwt.json send 200KB.1"
    @opt_parser.separator "\t#{$0} --log-level=debug files events"
    @opt_parser.separator "\t#{$0} -ntj files set_client_key LA-8RrEjw @file:data/myid"
    @opt_parser.separator "\nSPECIAL OPTION VALUES\n\tif an option begins with @env: or @file:, value is taken from env var or file"
    @opt_parser.separator ""
    @opt_parser.separator "COMMANDS"
    @opt_parser.separator "\tSupported commands: #{@@COMANDS.join(', ')}"
    @opt_parser.separator ""
    @opt_parser.separator "OPTIONS"
    @opt_parser.add_opt_list(:loglevel,"Log level",'-lTYPE','--log-level=TYPE')
    @opt_parser.add_opt_list(:logtype,"log method",'-qTYPE','--logger=TYPE')
    @opt_parser.add_opt_simple(:config_file,"-cSTRING", "--config-file=STRING","read parameters from file in JSON format")
    @opt_parser.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
    @opt_parser.on("-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true,@logger) }
    @opt_parser.on_tail("-h", "--help", "Show this message") { @opt_parser.exit_with_usage }

    begin
      @opt_parser.parse_ex!(argv)
      app_name=AsperaOptParser.get_next_arg_from_list(argv,'application',@@COMANDS)
      default_config=@loaded_config[app_name][@opt_parser.get_option_mandatory(:config_name)] if !@loaded_config.nil? and @loaded_config.has_key?(app_name)
      application=case app_name
      when :files; CliFiles.new(@logger)
      when :faspex; CliFaspex.new(@logger)
      when :shares; CliShares.new(@logger)
      when :node; CliNode.new(@logger)
      end

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
