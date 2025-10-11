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
    # Global objects shared with plugins
    class Context
      MEMBERS = %i[options transfer config formatter persistency man_header].freeze
      attr_accessor(*MEMBERS)

      def initialize
        @man_header = true
      end

      def validate
        MEMBERS.each do |i|
          Aspera.assert(instance_variable_defined?(:"@#{i}"))
          Aspera.assert(!instance_variable_get(:"@#{i}").nil?)
        end
      end

      def only_manual?
        transfer.eql?(:only_manual)
      end

      def only_manual
        @transfer = :only_manual
      end
    end

    # The main CLI class
    class Main
      # Plugins store transfer result using this key and use result_transfer_multiple()
      STATUS_FIELD = 'status'
      COMMAND_CONFIG = :config
      COMMAND_HELP = :help
      # Types that go to result of type = text
      SCALAR_TYPES = [String, Integer, Symbol].freeze
      USER_INTERFACES = %i[text graphical].freeze

      private_constant :COMMAND_CONFIG, :COMMAND_HELP, :SCALAR_TYPES, :USER_INTERFACES

      class << self
        # Early debug for parser
        # Note: does not accept shortcuts
        def early_debug_setup(argv)
          Log.instance.program_name = Info::CMD_NAME
          argv.each do |arg|
            case arg
            when '--' then break
            when /^--log-level=(.*)/ then Log.instance.level = Regexp.last_match(1).to_sym
            when /^--logger=(.*)/ then Log.instance.logger_type = Regexp.last_match(1).to_sym
            end
          rescue => e
            $stderr.puts("Error: #{e}") # rubocop:disable Style/StderrPuts
            Process.exit(1)
          end
        end

        def result_special(how); {type: :special, data: how}; end

        # Expect some list, but nothing to display
        def result_empty; result_special(:empty); end

        # Nothing expected
        def result_nothing; result_special(:nothing); end

        # Result is some status, such as "complete", "deleted"...
        # @param status [String] The status
        def result_status(status); return {type: :status, data: status}; end

        # Text result coming from command result
        def result_text(data); return {type: :text, data: data}; end

        def result_success; return result_status('complete'); end

        # Process statuses of finished transfer sessions
        # @raise exception if there is one error
        # else returns an empty status
        def result_transfer(statuses)
          worst = TransferAgent.session_status(statuses)
          raise worst unless worst.eql?(:success)
          return Main.result_nothing
        end

        # Used when one command executes several transfer jobs (each job being possibly multi session)
        # @param status_table [Array] [{STATUS_FIELD=>[status array],...},...]
        # @return a status object suitable as command result
        # Each element has a key STATUS_FIELD which contains the result of possibly multiple sessions
        def result_transfer_multiple(status_table)
          global_status = :success
          # Transform status array into string and find if there was problem
          status_table.each do |item|
            worst = TransferAgent.session_status(item[STATUS_FIELD])
            global_status = worst unless worst.eql?(:success)
            item[STATUS_FIELD] = item[STATUS_FIELD].map(&:to_s).join(',')
          end
          raise global_status unless global_status.eql?(:success)
          return result_object_list(status_table)
        end

        # Display image for that URL or directly blob
        def result_image(url_or_blob)
          return {type: :image, data: url_or_blob}
        end

        # A single object, must be Hash
        def result_single_object(data, fields: nil)
          return {type: :single_object, data: data, fields: fields}
        end

        # An Array of Hash
        def result_object_list(data, fields: nil, total: nil)
          return {type: :object_list, data: data, fields: fields, total: total}
        end

        # A list of values
        def result_value_list(data, name: 'id')
          Aspera.assert_type(data, Array)
          Aspera.assert_type(name, String)
          return {type: :value_list, data: data, name: name}
        end

        # Determines type of result based on data
        def result_auto(data)
          case data
          when NilClass
            return result_special(:null)
          when Hash
            return result_single_object(data)
          when Array
            all_types = data.map(&:class).uniq
            return result_object_list(data) if all_types.eql?([Hash])
            unsupported_types = all_types - SCALAR_TYPES
            return result_value_list(data, name: 'list') if unsupported_types.empty?
            Aspera.error_unexpected_value(unsupported_types){'list item types'}
          when *SCALAR_TYPES
            return result_text(data)
          else Aspera.error_unexpected_value(data.class.name){'result type'}
          end
        end
      end

      # Minimum initialization, no exception raised
      def initialize(argv)
        @argv = argv
        Log.dump(:argv, @argv, level: :trace2)
        @option_help = false
        @option_show_config = false
        @bash_completion = false
        @context = Context.new
      end

      # This is the main function called by initial script just after constructor
      def process_command_line
        # Catch exception information , if any
        exception_info = nil
        # False if command shall not be executed (e.g. --show-config)
        execute_command = true
        # Catch exceptions
        begin
          init_agents_options_plugins
          # Help requested without command ? (plugins must be known here)
          show_usage if @option_help && @context.options.command_or_arg_empty?
          generate_bash_completion if @bash_completion
          @context.config.periodic_check_newer_gem_version
          command_sym =
            if @option_show_config && @context.options.command_or_arg_empty?
              COMMAND_CONFIG
            else
              @context.options.get_next_command(PluginFactory.instance.plugin_list.unshift(COMMAND_HELP))
            end
          # Command will not be executed, but we need manual
          @context.options.fail_on_missing_mandatory = false if @option_help || @option_show_config
          # Main plugin is not dynamically instantiated
          case command_sym
          when COMMAND_HELP
            show_usage
          when COMMAND_CONFIG
            command_plugin = @context.config
          else
            # Get plugin, set options, etc
            command_plugin = get_plugin_instance_with_options(command_sym)
            # Parse plugin specific options
            @context.options.parse_options!
          end
          # Help requested for current plugin
          show_usage(all: false) if @option_help
          if @option_show_config
            @context.formatter.display_results(type: :single_object, data: @context.options.known_options(only_defined: true).stringify_keys)
            execute_command = false
          end
          # Locking for single execution (only after "per plugin" option, in case lock port is there)
          lock_port = @context.options.get_option(:lock_port)
          if !lock_port.nil?
            begin
              # No need to close later, will be freed on process exit. must save in member else it is garbage collected
              Log.log.debug{"Opening lock port #{lock_port}"}
              # Loopback address, could also be 'localhost'
              @tcp_server = TCPServer.new('127.0.0.1', lock_port)
            rescue StandardError => e
              execute_command = false
              Log.log.warn{"Another instance is already running (#{e.message})."}
            end
          end
          pid_file = @context.options.get_option(:pid_file)
          if !pid_file.nil?
            File.write(pid_file, Process.pid)
            Log.log.debug{"Wrote pid #{Process.pid} to #{pid_file}"}
            at_exit{File.delete(pid_file)}
          end
          # Execute and display (if not exclusive execution)
          @context.formatter.display_results(**command_plugin.execute_action) if execute_command
          # Save config file if command modified it
          @context.config.save_config_file_if_needed
          # Finish
          @context.transfer.shutdown
        rescue Net::SSH::AuthenticationFailed => e; exception_info = {e: e, t: 'SSH', security: true}
        rescue OpenSSL::SSL::SSLError => e;         exception_info = {e: e, t: 'SSL'}
        rescue Cli::BadArgument => e;               exception_info = {e: e, t: 'Argument', usage: true}
        rescue Cli::BadIdentifier => e;             exception_info = {e: e, t: 'Identifier'}
        rescue Cli::Error => e;                     exception_info = {e: e, t: 'Tool', usage: true}
        rescue Transfer::Error => e;                exception_info = {e: e, t: 'Transfer'}
        rescue RestCallError => e;                  exception_info = {e: e, t: 'Rest'}
        rescue SocketError => e;                    exception_info = {e: e, t: 'Network'}
        rescue StandardError => e;                  exception_info = {e: e, t: "Other(#{e.class.name})", debug: true}
        rescue Interrupt => e;                      exception_info = {e: e, t: 'Interruption', debug: true}
        end
        # Cleanup file list files
        TempFileManager.instance.cleanup
        # 1- processing of error condition
        unless exception_info.nil?
          Log.log.warn(exception_info[:e].message) if Log.instance.logger_type.eql?(:syslog) && exception_info[:security]
          @context.formatter.display_message(:error, "#{Formatter::ERROR_FLASH} #{exception_info[:t]}: #{exception_info[:e].message}")
          @context.formatter.display_message(:error, 'Use option -h to get help.') if exception_info[:usage]
          # Is that a known error condition with proposal for remediation ?
          Hints.hint_for(exception_info[:e], @context.formatter)
        end
        # 2- processing of command not processed (due to exception or bad command line)
        if execute_command || @option_show_config
          @context.options.final_errors.each do |msg|
            @context.formatter.display_message(:error, "#{Formatter::ERROR_FLASH} Argument: #{msg}")
            # Add code as exception if there is not already an error
            exception_info = {e: Exception.new(msg), t: 'UnusedArg'} if exception_info.nil?
          end
        end
        # 3- in case of error, fail the process status
        unless exception_info.nil?
          # Show stack trace in debug mode
          raise exception_info[:e] if Log.log.debug?
          # Else give hint and exit
          @context.formatter.display_message(:error, 'Use --log-level=debug to get more details.') if exception_info[:debug]
          Process.exit(1)
        end
        return
      end

      def init_agents_options_plugins
        init_agents_and_options
        # Find plugins, shall be after parse! ?
        PluginFactory.instance.add_plugins_from_lookup_folders
      end

      def show_usage(all: true, exit: true)
        # Display main plugin options (+config)
        @context.formatter.display_message(:error, @context.options.parser)
        if all
          @context.only_manual
          # List plugins that have a "require" field, i.e. all but main plugin
          PluginFactory.instance.plugin_list.each do |plugin_name_sym|
            # Config was already included in the global options
            next if plugin_name_sym.eql?(COMMAND_CONFIG)
            # Override main option parser with a brand new, to avoid having global options
            @context.options = Manager.new(Info::CMD_NAME)
            @context.options.parser.banner = '' # Remove default banner
            get_plugin_instance_with_options(plugin_name_sym)
            # Display generated help for plugin options
            @context.formatter.display_message(:error, @context.options.parser.help)
          end
        end
        Process.exit(0) if exit
      end

      private

      # This can throw exception if there is a problem with the environment, needs to be caught by execute method
      def init_agents_and_options
        # Create formatter, in case there is an exception, it is used to display.
        @context.formatter = Formatter.new
        # Create command line manager with arguments
        @context.options = Manager.new(Info::CMD_NAME, @argv)
        # Formatter adds options
        @context.formatter.declare_options(@context.options)
        ExtendedValue.instance.default_decoder = @context.options.get_option(:struct_parser)
        # Compare $0 with expected name
        current_prog_name = File.basename($PROGRAM_NAME)
        @context.formatter.display_message(
          :error,
          "#{Formatter::WARNING_FLASH} Please use '#{Info::CMD_NAME}' instead of '#{current_prog_name}'"
        ) unless current_prog_name.eql?(Info::CMD_NAME)
        # Declare and parse global options
        declare_global_options
        # Do not display config commands if help is asked
        @context.man_header = false
        # The Config plugin adds the @preset parser, so declare before TransferAgent which may use it
        @context.config = Plugins::Config.new(context: @context)
        @context.man_header = true
        # Data persistency is set in config
        Aspera.assert(@context.persistency){'missing persistency object'}
        # The TransferAgent plugin may use the @preset parser
        @context.transfer = TransferAgent.new(@context.options, @context.config)
        # Add commands for config plugin after all options have been added
        @context.config.add_manual_header(false)
        @context.validate
        # Set banner when all environment is created so that additional extended value modifiers are known, e.g. @preset
        @context.options.parser.banner = app_banner
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

      # Define header for manual
      def declare_global_options
        Log.log.debug('declare_global_options')
        @context.options.declare(:help, 'Show this message', values: :none, short: 'h'){@option_help = true}
        @context.options.declare(:bash_comp, 'Generate bash completion for command', values: :none){@bash_completion = true}
        @context.options.declare(:show_config, 'Display parameters used for the provided action', values: :none){@option_show_config = true}
        @context.options.declare(:version, 'Display version', values: :none, short: 'v'){@context.formatter.display_message(:data, Cli::VERSION); Process.exit(0)} # rubocop:disable Style/Semicolon
        @context.options.declare(
          :ui, 'Method to start browser',
          values: USER_INTERFACES,
          handler: {o: Environment.instance, m: :url_method}
        )
        @context.options.declare(
          :invalid_characters, 'Replacement character and invalid filename characters',
          handler: {o: Environment.instance, m: :file_illegal_characters}
        )
        @context.options.declare(:log_level, 'Log level', values: Log::LEVELS, handler: {o: Log.instance, m: :level})
        @context.options.declare(:log_format, 'Log formatter', types: [Proc, Logger::Formatter, String], handler: {o: Log.instance, m: :formatter})
        @context.options.declare(:logger, 'Logging method', values: Log::LOG_TYPES, handler: {o: Log.instance, m: :logger_type})
        @context.options.declare(:lock_port, 'Prevent dual execution of a command, e.g. in cron', coerce: Integer, types: Integer)
        @context.options.declare(:once_only, 'Process only new items (some commands)', values: :bool, default: false)
        @context.options.declare(:log_secrets, 'Show passwords in logs', values: :bool, handler: {o: SecretHider.instance, m: :log_secrets})
        @context.options.declare(:clean_temp, 'Cleanup temporary files on exit', values: :bool, handler: {o: TempFileManager.instance, m: :cleanup_on_exit})
        @context.options.declare(:pid_file, 'Write process identifier to file, delete on exit', types: String)
        # Parse declared options
        @context.options.parse_options!
      end

      # @return the plugin instance, based on name
      # Also loads the plugin options, and default values from conf file
      # @param plugin_name_sym : symbol for plugin name
      def get_plugin_instance_with_options(plugin_name_sym)
        Log.log.debug{"get_plugin_instance_with_options(#{plugin_name_sym})"}
        # Load default params only if no param already loaded before plugin instantiation
        @context.config.add_plugin_default_preset(plugin_name_sym)
        command_plugin = PluginFactory.instance.create(plugin_name_sym, context: @context)
        return command_plugin
      end

      def generate_bash_completion
        if @context.options.get_next_argument('', multiple: true, mandatory: false).nil?
          PluginFactory.instance.plugin_list.each{ |p| puts p}
        else
          Log.log.warn('only first level completion so far')
        end
        Process.exit(0)
      end
    end
  end
end
