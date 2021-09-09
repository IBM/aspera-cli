require 'aspera/cli/manager'
require 'aspera/cli/formater'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/version'
require 'aspera/open_application'
require 'aspera/temp_file_manager'
require 'aspera/persistency_folder'
require 'aspera/log'
require 'aspera/rest'
require 'aspera/nagios'
require 'aspera/secrets'

module Aspera
  module Cli
    # The main CLI class
    class Main

      attr_reader :plugin_env
      private
      # name of application, also foldername where config is stored
      PROGRAM_NAME = 'ascli'
      GEM_NAME = 'aspera-cli'
      VERBOSE_LEVELS=[:normal,:minimal,:quiet]

      private_constant :PROGRAM_NAME,:GEM_NAME,:VERBOSE_LEVELS

      # =============================================================
      # Parameter handlers
      #

      def option_insecure; Rest.insecure ; end

      def option_insecure=(value); Rest.insecure = value; end

      def option_ui; OpenApplication.instance.url_method; end

      def option_ui=(value); OpenApplication.instance.url_method=value; end

      # minimum initialization
      def initialize(argv)
        # first thing : manage debug level (allows debugging or option parser)
        early_debug_setup(argv)
        current_prog_name=File.basename($PROGRAM_NAME)
        unless current_prog_name.eql?(PROGRAM_NAME)
          @plugin_env[:formater].display_message(:error,"#{"WARNING".bg_red.blink.gray} Please use '#{PROGRAM_NAME}' instead of '#{current_prog_name}', '#{current_prog_name}' will be removed in a future version")
        end
        # overriding parameters on transfer spec
        @option_help=false
        @bash_completion=false
        @option_show_config=false
        @plugin_env={}
        @help_url='http://www.rubydoc.info/gems/'+GEM_NAME
        @gem_url='https://rubygems.org/gems/'+GEM_NAME
        # give command line arguments to option manager (no parsing)
        app_main_folder=ENV[conf_dir_env_var]
        # if env var undefined or empty
        if app_main_folder.nil? or app_main_folder.empty?
          user_home_folder=Dir.home
          raise CliError,"Home folder does not exist: #{user_home_folder}. Check your user environment or use #{conf_dir_env_var}." unless Dir.exist?(user_home_folder)
          app_main_folder=File.join(user_home_folder,Plugins::Config::ASPERA_HOME_FOLDER_NAME,PROGRAM_NAME)
        end
        @plugin_env[:options]=@opt_mgr=Manager.new(PROGRAM_NAME,argv,app_banner())
        @plugin_env[:formater]=Formater.new(@plugin_env[:options])
        Rest.user_agent=PROGRAM_NAME
        # must override help methods before parser called (in other constructors)
        init_global_options()
        # secret manager
        @plugin_env[:secret]=Aspera::Secrets.new
        # the Config plugin adds the @preset parser
        @plugin_env[:config]=Plugins::Config.new(@plugin_env,PROGRAM_NAME,@help_url,Aspera::Cli::VERSION,app_main_folder)
        # the TransferAgent plugin may use the @preset parser
        @plugin_env[:transfer]=TransferAgent.new(@plugin_env)
        Log.log.debug('created plugin env'.red)
        # set application folder for modules
        @plugin_env[:persistency]=PersistencyFolder.new(File.join(@plugin_env[:config].main_folder,'persist_store'))
        Oauth.persist_mgr=@plugin_env[:persistency]
        Fasp::Parameters.file_list_folder=File.join(@plugin_env[:config].main_folder,'filelists')
        Aspera::RestErrorAnalyzer.instance.log_file=File.join(@plugin_env[:config].main_folder,'rest_exceptions.log')
        # register aspera REST call error handlers
        Aspera::RestErrorsAspera.registerHandlers
      end

      def app_banner
        banner = "NAME\n\t#{PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{Aspera::Cli::VERSION})\n\n"
        banner << "SYNOPSIS\n"
        banner << "\t#{PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]\n"
        banner << "\nDESCRIPTION\n"
        banner << "\tUse Aspera application to perform operations on command line.\n"
        banner << "\tDocumentation and examples: #{@gem_url}\n"
        banner << "\texecute: #{PROGRAM_NAME} conf doc\n"
        banner << "\tor visit: #{@help_url}\n"
        banner << "\nENVIRONMENT VARIABLES\n"
        banner << "\t#{conf_dir_env_var}  config folder, default: $HOME/#{Plugins::Config::ASPERA_HOME_FOLDER_NAME}/#{PROGRAM_NAME}\n"
        banner << "\t#any option can be set as an environment variable, refer to the manual\n"
        banner << "\nCOMMANDS\n"
        banner << "\tTo list first level commands, execute: #{PROGRAM_NAME}\n"
        banner << "\tNote that commands can be written shortened (provided it is unique).\n"
        banner << "\nOPTIONS\n"
        banner << "\tOptions begin with a '-' (minus), and value is provided on command line.\n"
        banner << "\tSpecial values are supported beginning with special prefix, like: #{ExtendedValue.instance.modifiers.map{|m|"@#{m}:"}.join(' ')}.\n"
        banner << "\tDates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'\n\n"
        banner << "ARGS\n"
        banner << "\tSome commands require mandatory arguments, e.g. a path.\n"
      end

      # define header for manual
      def init_global_options
        Log.log.debug("init_global_options")
        @opt_mgr.add_opt_switch(:help,"-h","Show this message.") { @option_help=true }
        @opt_mgr.add_opt_switch(:bash_comp,"generate bash completion for command") { @bash_completion=true }
        @opt_mgr.add_opt_switch(:show_config, "Display parameters used for the provided action.") { @option_show_config=true }
        @opt_mgr.add_opt_switch(:rest_debug,"-r","more debug for HTTP calls") { Rest.debug=true }
        @opt_mgr.add_opt_switch(:version,'-v','display version') { @plugin_env[:formater].display_message(:data,Aspera::Cli::VERSION);Process.exit(0) }
        @opt_mgr.add_opt_switch(:warnings,'-w','check for language warnings') { $VERBOSE=true }
        # handler must be set before declaration
        @opt_mgr.set_obj_attr(:log_level,Log.instance,:level)
        @opt_mgr.set_obj_attr(:logger,Log.instance,:logger_type)
        @opt_mgr.set_obj_attr(:insecure,self,:option_insecure,:no)
        @opt_mgr.set_obj_attr(:ui,self,:option_ui)
        @opt_mgr.add_opt_list(:ui,OpenApplication.user_interfaces,'method to start browser')
        @opt_mgr.add_opt_list(:log_level,Log.levels,"Log level")
        @opt_mgr.add_opt_list(:logger,Log.logtypes,"log method")
        @opt_mgr.add_opt_simple(:lock_port,"prevent dual execution of a command, e.g. in cron")
        @opt_mgr.add_opt_simple(:query,"additional filter for API calls (extended value) (some commands)")
        @opt_mgr.add_opt_boolean(:insecure,"do not validate HTTPS certificate")
        @opt_mgr.add_opt_boolean(:once_only,"process only new items (some commands)")
        @opt_mgr.set_option(:ui,OpenApplication.default_gui_mode)
        @opt_mgr.set_option(:once_only,:false)
        # parse declared options
        @opt_mgr.parse_options!
      end

      # @return the plugin instance, based on name
      # also loads the plugin options, and default values from conf file
      # @param plugin_name_sym : symbol for plugin name
      def get_plugin_instance_with_options(plugin_name_sym,env=nil)
        env||=@plugin_env
        Log.log.debug("get_plugin_instance_with_options(#{plugin_name_sym})")
        require @plugin_env[:config].plugins[plugin_name_sym][:require_stanza]
        # load default params only if no param already loaded before plugin instanciation
        env[:config].add_plugin_default_preset(plugin_name_sym)
        command_plugin=Plugins::Config.plugin_new(plugin_name_sym,env)
        Log.log.debug("got #{command_plugin.class}")
        # TODO: check that ancestor is Plugin?
        return command_plugin
      end

      def generate_bash_completion
        if @opt_mgr.get_next_argument("",:multiple,:optional).nil?
          @plugin_env[:config].plugins.keys.each{|p|puts p.to_s}
        else
          Log.log.warn("only first level completion so far")
        end
        Process.exit(0)
      end

      # expect some list, but nothing to display
      def self.result_empty; return {:type => :empty, :data => :nil }; end

      # nothing expected
      def self.result_nothing; return {:type => :nothing, :data => :nil }; end

      def self.result_status(status); return {:type => :status, :data => status }; end

      def self.result_success; return result_status('complete'); end

      def exit_with_usage(all_plugins)
        Log.log.debug("exit_with_usage".bg_red)
        # display main plugin options
        @plugin_env[:formater].display_message(:error,@opt_mgr.parser)
        if all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          @plugin_env[:config].plugins.keys.each do |plugin_name_sym|
            next if plugin_name_sym.eql?(Plugins::Config::CONF_PLUGIN_SYM)
            # override main option parser with a brand new, to avoid having global options
            plugin_env=@plugin_env.clone
            plugin_env[:man_only]=true
            plugin_env[:options]=Manager.new(PROGRAM_NAME,[],'')
            get_plugin_instance_with_options(plugin_name_sym,plugin_env)
            # display generated help for plugin options
            @plugin_env[:formater].display_message(:error,plugin_env[:options].parser.to_s)
          end
        end
        Process.exit(0)
      end

      protected

      def conf_dir_env_var
        return "#{PROGRAM_NAME}_home".upcase
      end

      # early debug for parser
      # Note: does not accept shortcuts
      def early_debug_setup(argv)
        Log.instance.program_name=PROGRAM_NAME
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

      # Process statuses of finished transfer sessions
      # raise exception if there is one error
      # else returns an empty status
      def self.result_transfer(statuses)
        worst=TransferAgent.session_status(statuses)
        raise worst unless worst.eql?(:success)
        return Main.result_nothing
      end

      # this is the main function called by initial script just after constructor
      def process_command_line
        Log.log.debug('process_command_line')
        exception_info=nil
        execute_command=true
        begin
          # find plugins, shall be after parse! ?
          @plugin_env[:config].add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help and @opt_mgr.command_or_arg_empty?
          generate_bash_completion if @bash_completion
          # load global default options and process
          @plugin_env[:config].add_plugin_default_preset(Plugins::Config::CONF_GLOBAL_SYM)
          @opt_mgr.parse_options!
          @plugin_env[:config].periodic_check_newer_gem_version
          if @option_show_config and @opt_mgr.command_or_arg_empty?
            command_sym=Plugins::Config::CONF_PLUGIN_SYM
          else
            command_sym=@opt_mgr.get_next_command(@plugin_env[:config].plugins.keys.dup.unshift(:help))
          end
          # main plugin is not dynamically instanciated
          case command_sym
          when :help
            exit_with_usage(true)
          when Plugins::Config::CONF_PLUGIN_SYM
            command_plugin=@plugin_env[:config]
          else
            # get plugin, set options, etc
            command_plugin=get_plugin_instance_with_options(command_sym)
            # parse plugin specific options
            @opt_mgr.parse_options!
          end
          # help requested for current plugin
          exit_with_usage(false) if @option_help
          if @option_show_config
            @plugin_env[:formater].display_results({:type=>:single_object,:data=>@opt_mgr.declared_options(false)})
            Process.exit(0)
          end
          # locking for single execution (only after "per plugin" option, in case lock port is there)
          lock_port=@opt_mgr.get_option(:lock_port,:optional)
          if !lock_port.nil?
            begin
              # no need to close later, will be freed on process exit. must save in member else it is garbage collected
              Log.log.debug("Opening lock port #{lock_port.to_i}")
              @tcp_server=TCPServer.new('127.0.0.1',lock_port.to_i)
            rescue => e
              execute_command=false
              Log.log.warn("Another instance is already running (#{e.message}).")
            end
          end
          # execute and display (if not exclusive execution)
          @plugin_env[:formater].display_results(command_plugin.execute_action) if execute_command
          # finish
          @plugin_env[:transfer].shutdown
        rescue CliBadArgument => e;          exception_info=[e,'Argument',:usage]
        rescue CliNoSuchId => e;             exception_info=[e,'Identifier']
        rescue CliError => e;                exception_info=[e,'Tool',:usage]
        rescue Fasp::Error => e;             exception_info=[e,'FASP(ascp)']
        rescue Aspera::RestCallError => e;   exception_info=[e,'Rest']
        rescue SocketError => e;             exception_info=[e,'Network']
        rescue StandardError => e;           exception_info=[e,'Other',:debug]
        rescue Interrupt => e;               exception_info=[e,'Interruption',:debug]
        end
        # cleanup file list files
        TempFileManager.instance.cleanup
        # 1- processing of error condition
        unless exception_info.nil?
          @plugin_env[:formater].display_message(:error,"ERROR:".bg_red.gray.blink+" "+exception_info[1]+": "+exception_info[0].message)
          @plugin_env[:formater].display_message(:error,"Use '-h' option to get help.") if exception_info[2].eql?(:usage)
        end
        # 2- processing of command not processed (due to exception or bad command line)
        if execute_command
          @opt_mgr.final_errors.each do |msg|
            @plugin_env[:formater].display_message(:error,"ERROR:".bg_red.gray.blink+" Argument: "+msg)
          end
        end
        # 3- in case of error, fail the process status
        unless exception_info.nil?
          if Log.instance.level.eql?(:debug)
            # will force to show stack trace
            raise exception_info[0]
          else
            @plugin_env[:formater].display_message(:error,"Use '--log-level=debug' to get more details.") if exception_info[2].eql?(:debug)
            Process.exit(1)
          end
        end
        return nil
      end # process_command_line
    end # Main
  end # Cli
end # Aspera
