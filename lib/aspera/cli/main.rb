# frozen_string_literal: true

require 'aspera/cli/manager'
require 'aspera/cli/formatter'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/version'
require 'aspera/cli/info'
require 'aspera/cli/hints'
require 'aspera/secret_hider'
require 'aspera/log'

module Aspera
  module Cli
    # The main CLI class
    class Main
      # Plugins store transfer result using this key and use result_transfer_multiple()
      STATUS_FIELD = 'status'

      class << self
        # expect some list, but nothing to display
        def result_empty; return {type: :empty, data: :nil}; end

        # nothing expected
        def result_nothing; return {type: :nothing, data: :nil}; end

        def result_status(status); return {type: :status, data: status}; end

        def result_success; return result_status('complete'); end

        # Process statuses of finished transfer sessions
        # raise exception if there is one error
        # else returns an empty status
        def result_transfer(statuses)
          worst = TransferAgent.session_status(statuses)
          raise worst unless worst.eql?(:success)
          return Main.result_nothing
        end

        # used when one command executes several transfer jobs (each job being possibly multi session)
        # @param status_table [Array] [{STATUS_FIELD=>[status array],...},...]
        # @return a status object suitable as command result
        # each element has a key STATUS_FIELD which contains the result of possibly multiple sessions
        def result_transfer_multiple(status_table)
          global_status = :success
          # transform status array into string and find if there was problem
          status_table.each do |item|
            worst = TransferAgent.session_status(item[STATUS_FIELD])
            global_status = worst unless worst.eql?(:success)
            item[STATUS_FIELD] = item[STATUS_FIELD].map(&:to_s).join(',')
          end
          raise global_status unless global_status.eql?(:success)
          return {type: :object_list, data: status_table}
        end

        def result_picture_in_terminal(options, blob)
          require 'aspera/preview/terminal'
          terminal_options = options.get_option(:query, default: {}).symbolize_keys
          allowed_options = Preview::Terminal.method(:build).parameters.select{|i|i[0].eql?(:key)}.map{|i|i[1]}
          unknown_options = terminal_options.keys - allowed_options
          raise "invalid options: #{unknown_options.join(', ')}, use #{allowed_options.join(', ')}" unless unknown_options.empty?
          return Main.result_status(Preview::Terminal.build(blob, **terminal_options))
        end
      end # self

      private

      # shortcuts helpers like in plugins
      %i[options transfer config formatter persistency].each do |name|
        define_method(name){@agents[name]}
      end

      # =============================================================
      # Parameter handlers
      #

      # minimum initialization, no exception raised
      def initialize(argv)
        @argv = argv
        # environment provided to plugin for various capabilities
        @agents = {}
        @option_help = false
        @option_show_config = false
        @bash_completion = false
      end

      # This can throw exception if there is a problem with the environment, needs to be caught by execute method
      def init_agents_and_options
        # create formatter, in case there is an exception, it is used to display.
        @agents[:formatter] = Formatter.new
        # second : manage debug level (allows debugging of option parser)
        early_debug_setup
        @agents[:options] = Manager.new(PROGRAM_NAME)
        # give command line arguments to option manager
        options.parse_command_line(@argv)
        # formatter adds options
        formatter.declare_options(options)
        # compare $0 with expected name
        current_prog_name = File.basename($PROGRAM_NAME)
        formatter.display_message(
          :error,
          "#{Formatter::WARNING_FLASH} Please use '#{PROGRAM_NAME}' instead of '#{current_prog_name}'") unless current_prog_name.eql?(PROGRAM_NAME)
        # declare and parse global options
        declare_global_options
        # the Config plugin adds the @preset parser, so declare before TransferAgent which may use it
        @agents[:config] = Plugins::Config.new(@agents, gem: GEM_NAME, name: PROGRAM_NAME, help: DOC_URL, version: Aspera::Cli::VERSION)
        # data persistency
        raise 'internal error: missing persistency object' unless @agents[:persistency]
        # the TransferAgent plugin may use the @preset parser
        @agents[:transfer] = TransferAgent.new(options, config)
        Log.log.debug('plugin env created'.red)
        # set banner when all environment is created so that additional extended value modifiers are known, e.g. @preset
        options.parser.banner = app_banner
      end

      def app_banner
        t = ' ' * 8
        return <<~END_OF_BANNER
          NAME
          #{t}#{PROGRAM_NAME} -- a command line tool for Aspera Applications (v#{Aspera::Cli::VERSION})

          SYNOPSIS
          #{t}#{PROGRAM_NAME} COMMANDS [OPTIONS] [ARGS]

          DESCRIPTION
          #{t}Use Aspera application to perform operations on command line.
          #{t}Documentation and examples: #{GEM_URL}
          #{t}execute: #{PROGRAM_NAME} conf doc
          #{t}or visit: #{DOC_URL}
          #{t}source repo: #{SRC_URL}

          ENVIRONMENT VARIABLES
          #{t}Any option can be set as an environment variable, refer to the manual

          COMMANDS
          #{t}To list first level commands, execute: #{PROGRAM_NAME}
          #{t}Note that commands can be written shortened (provided it is unique).

          OPTIONS
          #{t}Options begin with a '-' (minus), and value is provided on command line.
          #{t}Special values are supported beginning with special prefix @pfx:, where pfx is one of:
          #{t}#{ExtendedValue.instance.modifiers.map(&:to_s).join(', ')}
          #{t}Dates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'

          ARGS
          #{t}Some commands require mandatory arguments, e.g. a path.
        END_OF_BANNER
      end

      # define header for manual
      def declare_global_options
        Log.log.debug('declare_global_options')
        options.declare(:help, 'Show this message', values: :none, short: 'h') { @option_help = true }
        options.declare(:bash_comp, 'Generate bash completion for command', values: :none) { @bash_completion = true }
        options.declare(:show_config, 'Display parameters used for the provided action', values: :none) { @option_show_config = true }
        options.declare(:version, 'Display version', values: :none, short: 'v') { formatter.display_message(:data, Aspera::Cli::VERSION); Process.exit(0) } # rubocop:disable Style/Semicolon, Layout/LineLength
        options.declare(:warnings, 'Check for language warnings', values: :none, short: 'w') { $VERBOSE = true }
        options.declare(
          :ui, 'Method to start browser',
          values: OpenApplication.user_interfaces,
          handler: {o: OpenApplication.instance, m: :url_method},
          default: OpenApplication.default_gui_mode)
        options.declare(:log_level, 'Log level', values: Log.levels, handler: {o: Log.instance, m: :level})
        options.declare(:logger, 'Logging method', values: Log::LOG_TYPES, handler: {o: Log.instance, m: :logger_type})
        options.declare(:lock_port, 'Prevent dual execution of a command, e.g. in cron', coerce: Integer, types: Integer)
        options.declare(:once_only, 'Process only new items (some commands)', values: :bool, default: false)
        options.declare(:log_secrets, 'Show passwords in logs', values: :bool, handler: {o: SecretHider, m: :log_secrets})
        options.declare(:clean_temp, 'Cleanup temporary files on exit', values: :bool, handler: {o: TempFileManager.instance, m: :cleanup_on_exit})
        options.declare(:pid_file, 'Write process identifier to file, delete on exit', types: String)
        # parse declared options
        options.parse_options!
      end

      # @return the plugin instance, based on name
      # also loads the plugin options, and default values from conf file
      # @param plugin_name_sym : symbol for plugin name
      def get_plugin_instance_with_options(plugin_name_sym, env=nil)
        env ||= @agents
        Log.log.debug{"get_plugin_instance_with_options(#{plugin_name_sym})"}
        require config.plugins[plugin_name_sym][:require_stanza]
        # load default params only if no param already loaded before plugin instantiation
        env[:config].add_plugin_default_preset(plugin_name_sym)
        command_plugin = Plugins::Config.plugin_class(plugin_name_sym).new(env)
        Log.log.debug{"got #{command_plugin.class}"}
        # TODO: check that ancestor is Plugin?
        return command_plugin
      end

      def generate_bash_completion
        if options.get_next_argument('', expected: :multiple, mandatory: false).nil?
          config.plugins.each_key{|p|puts p.to_s}
        else
          Log.log.warn('only first level completion so far')
        end
        Process.exit(0)
      end

      def exit_with_usage(all_plugins)
        Log.log.debug('exit_with_usage'.bg_red)
        # display main plugin options
        formatter.display_message(:error, options.parser)
        if all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          config.plugins.each_key do |plugin_name_sym|
            next if plugin_name_sym.eql?(Plugins::Config::CONF_PLUGIN_SYM)
            # override main option parser with a brand new, to avoid having global options
            plugin_env = @agents.clone
            plugin_env[:all_manuals] = true # force declaration of all options
            plugin_env[:options] = Manager.new(PROGRAM_NAME)
            plugin_env[:options].parser.banner = '' # remove default banner
            get_plugin_instance_with_options(plugin_name_sym, plugin_env)
            # display generated help for plugin options
            formatter.display_message(:error, plugin_env[:options].parser.help)
          end
        end
        Process.exit(0)
      end

      protected

      # early debug for parser
      # Note: does not accept shortcuts
      def early_debug_setup
        Aspera::Log.instance.program_name = PROGRAM_NAME
        @argv.each do |arg|
          case arg
          when '--' then break
          when /^--log-level=(.*)/ then Aspera::Log.instance.level = Regexp.last_match(1).to_sym
          when /^--logger=(.*)/ then Aspera::Log.instance.logger_type = Regexp.last_match(1).to_sym
          end
        rescue => e
          $stderr.puts("Error: #{e}")
        end
      end

      public

      # this is the main function called by initial script just after constructor
      def process_command_line
        # catch exception information , if any
        exception_info = nil
        # false if command shall not be executed (e.g. --show-config)
        execute_command = true
        # catch exceptions
        begin
          init_agents_and_options
          # find plugins, shall be after parse! ?
          config.add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help && options.command_or_arg_empty?
          generate_bash_completion if @bash_completion
          config.periodic_check_newer_gem_version
          command_sym =
            if @option_show_config && options.command_or_arg_empty?
              Plugins::Config::CONF_PLUGIN_SYM
            else
              options.get_next_command(config.plugins.keys.dup.unshift(:help))
            end
          # command will not be executed, but we need manual
          options.fail_on_missing_mandatory = false if @option_help || @option_show_config
          # main plugin is not dynamically instantiated
          case command_sym
          when :help
            exit_with_usage(true)
          when Plugins::Config::CONF_PLUGIN_SYM
            command_plugin = config
          else
            # get plugin, set options, etc
            command_plugin = get_plugin_instance_with_options(command_sym)
            # parse plugin specific options
            options.parse_options!
          end
          # help requested for current plugin
          exit_with_usage(false) if @option_help
          if @option_show_config
            formatter.display_results({type: :single_object, data: options.known_options(only_defined: true).stringify_keys})
            execute_command = false
          end
          # locking for single execution (only after "per plugin" option, in case lock port is there)
          lock_port = options.get_option(:lock_port)
          if !lock_port.nil?
            begin
              # no need to close later, will be freed on process exit. must save in member else it is garbage collected
              Log.log.debug{"Opening lock port #{lock_port}"}
              @tcp_server = TCPServer.new('127.0.0.1', lock_port)
            rescue StandardError => e
              execute_command = false
              Log.log.warn{"Another instance is already running (#{e.message})."}
            end
          end
          pid_file = options.get_option(:pid_file)
          if !pid_file.nil?
            File.write(pid_file, Process.pid)
            Log.log.debug{"Wrote pid #{Process.pid} to #{pid_file}"}
            at_exit{File.delete(pid_file)}
          end
          # execute and display (if not exclusive execution)
          formatter.display_results(command_plugin.execute_action) if execute_command
          # save config file if command modified it
          config.save_config_file_if_needed
          # finish
          transfer.shutdown
        rescue Net::SSH::AuthenticationFailed => e; exception_info = {e: e, t: 'SSH', security: true}
        rescue OpenSSL::SSL::SSLError => e;         exception_info = {e: e, t: 'SSL'}
        rescue Cli::BadArgument => e;               exception_info = {e: e, t: 'Argument', usage: true}
        rescue Cli::NoSuchIdentifier => e;          exception_info = {e: e, t: 'Identifier'}
        rescue Cli::Error => e;                     exception_info = {e: e, t: 'Tool', usage: true}
        rescue Fasp::Error => e;                    exception_info = {e: e, t: 'Transfer'}
        rescue Aspera::RestCallError => e;          exception_info = {e: e, t: 'Rest'}
        rescue SocketError => e;                    exception_info = {e: e, t: 'Network'}
        rescue StandardError => e;                  exception_info = {e: e, t: "Other(#{e.class.name})", debug: true}
        rescue Interrupt => e;                      exception_info = {e: e, t: 'Interruption', debug: true}
        end
        # cleanup file list files
        TempFileManager.instance.cleanup
        # 1- processing of error condition
        unless exception_info.nil?
          Log.log.warn(exception_info[:e].message) if Aspera::Log.instance.logger_type.eql?(:syslog) && exception_info[:security]
          formatter.display_message(:error, "#{Formatter::ERROR_FLASH} #{exception_info[:t]}: #{exception_info[:e].message}")
          formatter.display_message(:error, 'Use option -h to get help.') if exception_info[:usage]
          # Is that a known error condition with proposal for remediation ?
          Hints.hint_for(exception_info[:e], formatter)
        end
        # 2- processing of command not processed (due to exception or bad command line)
        if execute_command || @option_show_config
          options.final_errors.each do |msg|
            formatter.display_message(:error, "#{Formatter::ERROR_FLASH} Argument: #{msg}")
            # add code as exception if there is not already an error
            exception_info = {e: Exception.new(msg), t: 'UnusedArg'} if exception_info.nil?
          end
        end
        # 3- in case of error, fail the process status
        unless exception_info.nil?
          # show stack trace in debug mode
          raise exception_info[:e] if Log.log.debug?
          # else give hint and exit
          formatter.display_message(:error, 'Use --log-level=debug to get more details.') if exception_info[:debug]
          Process.exit(1)
        end
        return nil
      end # process_command_line
    end # Main
  end # Cli
end # Aspera
