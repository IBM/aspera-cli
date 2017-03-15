require "asperalm/cli/plugin"
require "asperalm/version"
require "asperalm/log"
require 'yaml'

module Asperalm
  module Cli
    class Main < Plugin
      def opt_names; [:logtype,:loglevel,:config_name,:config_file]; end

      def get_logtypes; [:syslog,:stdout]; end

      def get_loglevels; Log.levels; end

      def set_logtype(logtype)
        set_loglevel :warn
      end

      def set_loglevel(loglevel)
        Log.level = loglevel
      end

      def get_loglevel
        Log.log.level
      end

      def set_config_file(v)
        Log.log.debug "loading #{v}"
        @loaded_config=YAML.load_file(v)
        self.set_defaults(@loaded_config[:global])
      end

      def command_list
        Plugin.get_plugin_list
      end

      def set_options
        self.separator ""
        self.separator "DESCRIPTION"
        self.separator "\tUse Aspera application to perform operations on command line."
        self.separator "\tOAuth 2.0 is used for authentication in Files, Several authentication methods are provided."
        self.separator ""
        self.separator "EXAMPLES"
        self.separator "\t#{$PROGRAM_NAME} files events"
        self.separator "\t#{$PROGRAM_NAME} --log-level=debug --config-name=myfaspex send 200KB.1"
        self.separator "\t#{$PROGRAM_NAME} -ntj files set_client_key LA-8RrEjw @file:data/myid"
        self.separator "\nSPECIAL OPTION VALUES\n\tif an option value begins with @env: or @file:, value is taken from env var or file"
        self.separator ""
        self.add_opt_list(:loglevel,"Log level",'-lTYPE','--log-level=TYPE')
        self.add_opt_list(:logtype,"log method",'-qTYPE','--logger=TYPE')
        self.add_opt_simple(:config_file,"-fSTRING", "--config-file=STRING","read parameters from file in JSON format")
        self.add_opt_simple(:config_name,"-nSTRING", "--config-name=STRING","name of configuration in config file")
        self.on("-r", "--rest-debug","more debug for HTTP calls") { Rest.set_debug(true) }
      end

      def dojob(app_name,argv)
        default_config=@loaded_config[app_name][self.get_option_mandatory(:config_name)] if !@loaded_config.nil? and @loaded_config.has_key?(app_name)
        application=Plugin.new_plugin(app_name)
        application.go(argv,default_config)
      end

      #################################
      # MAIN
      #--------------------------------
      @@CONFIG_FILE_HOME='.aspera/ascli/config.yaml'

      def self.start
        $PROGRAM_NAME = 'ascli'
        $DEFAULT_CONFIG_FILE=File.join(Dir.home,@@CONFIG_FILE_HOME)
        defaults={
          :logtype => :stdout,
          :loglevel => :warn,
          :config_name => 'default'
        }
        defaults[:config_file]=$DEFAULT_CONFIG_FILE if File.exist?($DEFAULT_CONFIG_FILE)
        tool=self.new
        begin
          tool.go(ARGV,defaults)
        rescue OptionParser::InvalidArgument => e
          STDERR.puts "ERROR:".bg_red().gray()+" #{e}\n\n"
          tool.exit_with_usage
        end
      end
    end
  end
end
