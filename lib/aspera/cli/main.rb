# frozen_string_literal: true

require 'aspera/cli/manager'
require 'aspera/cli/formatter'
require 'aspera/cli/plugins/config'
require 'aspera/cli/extended_value'
require 'aspera/cli/plugin_factory'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/version'
require 'aspera/cli/info'
require 'aspera/cli/hints'
require 'aspera/secret_hider'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # The main CLI class
    class Main
      # Plugins store transfer result using this key and use result_transfer_multiple()
      STATUS_FIELD = 'status'
      COMMAND_CONFIG = :config
      COMMAND_HELP = :help

      private_constant :COMMAND_CONFIG, :COMMAND_HELP

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

        def result_image(blob, formatter:)
          return Main.result_status(formatter.status_image(blob))
        end

        def result_single_object(data, fields: nil)
          return {type: :single_object, data: data, fields: fields}
        end

        def result_object_list(data, fields: nil, total: nil)
          return {type: :object_list, data: data, fields: fields, total: nil}
        end

        def result_value_list(data, name)
          return {type: :value_list, data: data, name: name}
        end
      end

      private

      # shortcuts helpers like in plugins
      %i[options transfer config formatter persistency].each do |name|
        define_method(name){@plug_init[name]}
      end

      # =============================================================
      # Parameter handlers
      #

      # minimum initialization, no exception raised
      def initialize(argv)
        @argv = argv
        # environment provided to plugin for various capabilities
        @plug_init = Plugin::INIT_PARAMS.each_with_object({}) { |key, hash| hash[key] = nil }
        @option_help = false
        @option_show_config = false
        @bash_completion = false
        early_debug_setup
        Log.log.trace2{Log.dump(:argv, @argv)}
      end

      # This can throw exception if there is a problem with the environment, needs to be caught by execute method
      def init_agents_and_options
        @plug_init[:only_manual] = false
        # create formatter, in case there is an exception, it is used to display.
        @plug_init[:formatter] = Formatter.new
        # create command line manager with arguments
        @plug_init[:options] = Manager.new(Info::CMD_NAME, @argv)
        # formatter adds options
        @plug_init[:formatter].declare_options(options)
        ExtendedValue.instance.default_decoder = options.get_option(:struct_parser)
        # compare $0 with expected name
        current_prog_name = File.basename($PROGRAM_NAME)
        formatter.display_message(
          :error,
          "#{Formatter::WARNING_FLASH} Please use '#{Info::CMD_NAME}' instead of '#{current_prog_name}'") unless current_prog_name.eql?(Info::CMD_NAME)
        # declare and parse global options
        declare_global_options
        # the Config plugin adds the @preset parser, so declare before TransferAgent which may use it
        @plug_init[:config] = Plugins::Config.new(**@plug_init, man_header: false)
        @plug_init[:persistency] = @plug_init[:config].persistency
        # data persistency
        Aspera.assert(@plug_init[:persistency]){'missing persistency object'}
        # the TransferAgent plugin may use the @preset parser
        @plug_init[:config].transfer = @plug_init[:transfer] = TransferAgent.new(options, config)
        # add commands for config plugin after all options have been added
        @plug_init[:config].add_manual_header(false)
        nil_keys = @plug_init.select{|_, value|value.nil?}.keys
        Aspera.assert(nil_keys.empty?){"nil : #{nil_keys}"}
        Log.log.debug('plugin env created'.red)
        # set banner when all environment is created so that additional extended value modifiers are known, e.g. @preset
        options.parser.banner = app_banner
      end

      def app_banner
        t = ' ' * 8
        return <<~END_OF_BANNER
          NAME
          #{t}#{Info::CMD_NAME} -- a command line tool for Aspera Applications (v#{Cli::VERSION})

          SYNOPSIS
          #{t}#{Info::CMD_NAME} COMMANDS [OPTIONS] [ARGS]

          DESCRIPTION
          #{t}Use Aspera application to perform operations on command line.
          #{t}Documentation and examples: #{Info::GEM_URL}
          #{t}execute: #{Info::CMD_NAME} conf doc
          #{t}or visit: #{Info::DOC_URL}
          #{t}source repo: #{Info::SRC_URL}

          ENVIRONMENT VARIABLES
          #{t}Any option can be set as an environment variable, refer to the manual

          COMMANDS
          #{t}To list first level commands, execute: #{Info::CMD_NAME}
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
        options.declare(:version, 'Display version', values: :none, short: 'v') { formatter.display_message(:data, Cli::VERSION); Process.exit(0) } # rubocop:disable Style/Semicolon, Layout/LineLength
        options.declare(
          :ui, 'Method to start browser',
          values: Environment::USER_INTERFACES,
          handler: {o: Environment.instance, m: :url_method},
          default: Environment.default_gui_mode)
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
        env ||= @plug_init
        Log.log.debug{"get_plugin_instance_with_options(#{plugin_name_sym})"}
        # load default params only if no param already loaded before plugin instantiation
        env[:config].add_plugin_default_preset(plugin_name_sym)
        command_plugin = PluginFactory.instance.create(plugin_name_sym, **env)
        return command_plugin
      end

      def generate_bash_completion
        if options.get_next_argument('', multiple: true, mandatory: false).nil?
          PluginFactory.instance.plugin_list.each{|p|puts p}
        else
          Log.log.warn('only first level completion so far')
        end
        Process.exit(0)
      end

      def exit_with_usage(include_all_plugins)
        Log.log.debug{"exit_with_usage(#{include_all_plugins})".bg_red}
        # display main plugin options (+config)
        formatter.display_message(:error, options.parser)
        if include_all_plugins
          # list plugins that have a "require" field, i.e. all but main plugin
          PluginFactory.instance.plugin_list.each do |plugin_name_sym|
            # config was already included in the global options
            next if plugin_name_sym.eql?(COMMAND_CONFIG)
            # override main option parser with a brand new, to avoid having global options
            plugin_env = @plug_init.clone
            plugin_env[:only_manual] = true # force declaration of all options
            plugin_env[:options] = Manager.new(Info::CMD_NAME)
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
        Log.instance.program_name = Info::CMD_NAME
        @argv.each do |arg|
          case arg
          when '--' then break
          when /^--log-level=(.*)/ then Log.instance.level = Regexp.last_match(1).to_sym
          when /^--logger=(.*)/ then Log.instance.logger_type = Regexp.last_match(1).to_sym
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
          PluginFactory.instance.add_plugins_from_lookup_folders
          # help requested without command ? (plugins must be known here)
          exit_with_usage(true) if @option_help && options.command_or_arg_empty?
          generate_bash_completion if @bash_completion
          config.periodic_check_newer_gem_version
          command_sym =
            if @option_show_config && options.command_or_arg_empty?
              COMMAND_CONFIG
            else
              options.get_next_command(PluginFactory.instance.plugin_list.unshift(COMMAND_HELP))
            end
          # command will not be executed, but we need manual
          options.fail_on_missing_mandatory = false if @option_help || @option_show_config
          # main plugin is not dynamically instantiated
          case command_sym
          when COMMAND_HELP
            exit_with_usage(true)
          when COMMAND_CONFIG
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
            formatter.display_results(type: :single_object, data: options.known_options(only_defined: true).stringify_keys)
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
          formatter.display_results(**command_plugin.execute_action) if execute_command
          # save config file if command modified it
          config.save_config_file_if_needed
          # finish
          transfer.shutdown
        rescue Net::SSH::AuthenticationFailed => e; exception_info = {e: e, t: 'SSH', security: true}
        rescue OpenSSL::SSL::SSLError => e;         exception_info = {e: e, t: 'SSL'}
        rescue Cli::BadArgument => e;               exception_info = {e: e, t: 'Argument', usage: true}
        rescue Cli::NoSuchIdentifier => e;          exception_info = {e: e, t: 'Identifier'}
        rescue Cli::Error => e;                     exception_info = {e: e, t: 'Tool', usage: true}
        rescue Transfer::Error => e;                exception_info = {e: e, t: 'Transfer'}
        rescue RestCallError => e;                  exception_info = {e: e, t: 'Rest'}
        rescue SocketError => e;                    exception_info = {e: e, t: 'Network'}
        rescue StandardError => e;                  exception_info = {e: e, t: "Other(#{e.class.name})", debug: true}
        rescue Interrupt => e;                      exception_info = {e: e, t: 'Interruption', debug: true}
        end
        # cleanup file list files
        TempFileManager.instance.cleanup
        # 1- processing of error condition
        unless exception_info.nil?
          Log.log.warn(exception_info[:e].message) if Log.instance.logger_type.eql?(:syslog) && exception_info[:security]
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
      end
    end
  end
end
