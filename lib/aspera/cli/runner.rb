# frozen_string_literal: true

require 'aspera/cli/command_spec'
require 'aspera/cli/context'
require 'aspera/cli/parser'
require 'aspera/cli/formatter'
require 'aspera/cli/plugins/factory'
require 'aspera/cli/bootstrapper'
require 'aspera/cli/plugins/config'
require 'aspera/cli/mailer'
require 'aspera/cli/secret_finder'
require 'aspera/cli/extended_value'
require 'aspera/cli/transfer_agent'
require 'aspera/cli/version'
require 'aspera/cli/info'
require 'aspera/cli/hints'
require 'aspera/cli/result'
require 'aspera/secret_hider'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/schema/documentation'
require 'aspera/schema/registry'
require 'net/ssh/errors'
require 'openssl'

module Aspera
  module Cli
    # The main CLI class
    class Runner
      # Plugins store transfer result using this key and use result_transfer_multiple()
      STATUS_FIELD = 'status'

      class << self
        # Process statuses of finished transfer sessions
        # @param statuses [Array] array of transfer session statuses
        # @raise [Symbol] exception if there is one error
        # @return [Result] empty status result if all transfers succeeded
        def result_transfer(statuses)
          worst = TransferAgent.session_status(statuses)
          raise worst unless worst.eql?(:success)
          return Result::Nothing.new
        end

        # Used when one command executes several transfer jobs (each job being possibly multi session)
        # @param status_table [Array] [{STATUS_FIELD=>[status array],...},...]
        # @return [Result] a status object suitable as command result
        # Each element has a key STATUS_FIELD which contains the result of possibly multiple sessions
        def result_transfer_multiple(status_table)
          global_status = :success
          # Transform status array into string and find if there was problem
          status_table.each do |item|
            worst = TransferAgent.session_status(item[STATUS_FIELD])
            global_status = worst unless worst.eql?(:success)
            item[STATUS_FIELD] = item[STATUS_FIELD].join(',')
          end
          raise global_status unless global_status.eql?(:success)
          return Result::ObjectList.new(status_table)
        end
      end

      # Minimum initialization, no exception raised
      # @param argv [Array<String>] command line arguments
      # @return [nil]
      def initialize(argv)
        @argv = argv
        Log.dump(:argv, @argv, level: :trace2)
        @option_help = false
        @option_show_config = false
        @context = Context.new
      end

      # Execute the command and return the raw `Result` object.
      # Pure computation: no display, no Process.exit - raises on any error.
      # @return [Result, nil] the result of the command, or nil if nothing to execute
      def run_with_result
        init_agents_and_options
        Plugins::Factory.instance.add_plugins_from_lookup_folders
        # Help requested without command? Show global options + plugin list
        return result_usage if @option_help && @context.options.command_or_arg_empty?
        @context.config.periodic_check_newer_gem_version
        command_sym =
          if @option_show_config && @context.options.command_or_arg_empty?
            COMMAND_CONFIG
          else
            @context.options.get_next_command(Plugins::Factory.instance.plugin_list.unshift(COMMAND_HELP))
          end
        @context.options.fail_on_missing_mandatory = false if @option_help || @option_show_config
        case command_sym
        when COMMAND_HELP
          return result_usage
        when COMMAND_CONFIG
          command_plugin = @context.config
        else
          command_plugin = get_plugin_instance_with_options(command_sym)
          @context.options.parse_options!
        end
        # --help after a plugin name: if no positional args remain, show plugin-level help now.
        # If args remain (e.g. `ascli aoc files -h`), let the dispatch consume them and
        # intercept --help at the right depth via Cli::HelpRequest.
        return result_usage(plugin: command_plugin) if @option_help && @context.options.command_or_arg_empty?
        if @option_show_config
          result = Result::SingleObject.new(@context.options.known_options(only_defined: true).stringify_keys)
          @context.presets.save_if_needed
          @context.transfer.shutdown
          TempFileManager.instance.cleanup
          return result
        end
        execute_command = true
        lock_port = @context.options.get_option(:lock_port)
        if !lock_port.nil?
          begin
            Log.log.debug{"Opening lock port #{lock_port}"}
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
        begin
          result = command_plugin.execute_action if execute_command
        rescue Cli::HelpRequest => e
          return result_usage(plugin: e.plugin)
        ensure
          @context.presets.save_if_needed
          @context.transfer.shutdown
          TempFileManager.instance.cleanup
        end
        return result
      end

      # Main entry point: execute the command, display results, exit on error.
      # @return [nil]
      def run
        exception_info = nil
        begin
          result = run_with_result
          @context.formatter.display_results(result) if result
        rescue Net::SSH::AuthenticationFailed => e; exception_info = {e: e, t: 'SSH', security: true}
        rescue OpenSSL::SSL::SSLError => e;         exception_info = {e: e, t: 'SSL'}
        rescue Cli::BadArgument => e;               exception_info = {e: e, t: 'Argument', usage: true}
        rescue Cli::MissingArgument => e;           exception_info = {e: e, t: 'Missing'}
        rescue Cli::BadIdentifier => e;             exception_info = {e: e, t: 'Identifier'}
        rescue Cli::SchemaRequest => e;             exception_info = {e: e, t: 'Schema'}
        rescue Cli::Error => e;                     exception_info = {e: e, t: 'Tool', usage: true}
        rescue Transfer::Error => e;                exception_info = {e: e, t: 'Transfer'}
        rescue RestCallError => e;                  exception_info = {e: e, t: 'Rest'}
        rescue SocketError => e;                    exception_info = {e: e, t: 'Network'}
        rescue StandardError => e;                  exception_info = {e: e, t: "Other(#{e.class.name})", debug: true}
        rescue Interrupt => e;                      exception_info = {e: e, t: 'Interruption', debug: true}
        end
        # 1- processing of error condition
        unless exception_info.nil?
          Log.log.warn(exception_info[:e].message) if Log.instance.logger_type.eql?(:syslog) && exception_info[:security]
          Log.log.error{"#{exception_info[:t]}: #{exception_info[:e].message}"} unless exception_info[:e].is_a?(Cli::SchemaRequest)
          Log.log.debug{(['Backtrace:'] + exception_info[:e].backtrace).join("\n")} if exception_info[:debug]
          @context.formatter.display_message(:error, 'Use option -h to get help.') if exception_info[:usage]
          Hints.hint_for(exception_info[:e], @context.formatter)
          if exception_info[:e].is_a?(Cli::SchemaRequest)
            Log.log.info{"#{exception_info[:t]}: #{exception_info[:e].message}"}
            schema_path = exception_info[:e].path
            if schema_path.nil?
              Log.log.warn{'Sorry, no schema provided yet. Please refer to the manual or API.'}
            else
              builder = Schema::Documentation.new(TerminalFormatter, Schema::Registry.instance.reader(schema_path)).build
              @context.formatter.display_results(Result::ObjectList.new(builder.rows, fields: builder.columns))
            end
          end
        end
        # 2- processing of unprocessed arguments (skip when help was displayed: sub-commands are not consumed)
        unless @option_help
          @context.options&.final_errors&.each do |msg|
            Log.log.error{"Argument: #{msg}"}
            exception_info = {e: Exception.new(msg), t: 'UnusedArg'} if exception_info.nil?
          end
        end
        # 3- exit on error
        unless exception_info.nil?
          raise exception_info[:e] if Log.log.debug?
          @context.formatter.display_message(:error, 'Use --log-level=debug to get more details.') if exception_info[:debug]
          Process.exit(1)
        end
        return
      end

      # Display usage information and exit (used by the interactive CLI).
      # @param plugin [Plugins::Base, nil] plugin instance to show subcommands for
      # @return [nil]
      def show_usage(plugin: nil)
        @context.formatter.display_message(:error, usage_text(plugin: plugin))
        Process.exit(0)
      end

      # Return usage as a Result::Text (used by run_with_result, no display, no exit).
      # @param plugin [Plugins::Base, nil] plugin instance to show subcommands for
      # @return [Result::Text]
      def result_usage(plugin: nil)
        Result::Text.new(usage_text(plugin: plugin))
      end

      # Composite option handler for the `log` option (dot-notation sub-properties).
      # Supported sub-properties: +level+, +type+, +format+
      # @param _option_sym [Symbol] Option name (unused, always :log)
      # @param operation   [Symbol] +:set+ or +:get+
      # @param value       [Hash,nil] Hash of sub-properties to set (only for +:set+)
      def option_log(_option_sym, operation, value = nil)
        Aspera.assert_values(operation, %i[set get])
        case operation
        when :set
          Aspera.assert_type(value, Hash)
          value.each do |k, v|
            case k.to_sym
            when :level   then Log.instance.level = v.to_sym
            when :type    then Log.instance.logger_type = v.to_sym
            when :format  then Log.instance.formatter = v
            when :secrets then SecretHider.instance.log_secrets = BoolValue.true?(v)
            else Aspera.error_unexpected_value(k){'log sub-option (level, type, format, secrets)'}
            end
          end
        when :get
          return {level: Log.instance.level, type: Log.instance.logger_type, format: Log.instance.formatter, secrets: SecretHider.instance.log_secrets}
        end
        nil
      end

      private

      # Build the usage/help text.
      #
      # - No plugin:   global options + list of top-level plugins
      # - With plugin: global options + plugin options + subcommands at the path
      #                 that was reached before --help was encountered
      #
      # @param plugin [Plugins::Base, nil] plugin instance (carries the current dispatch path)
      # @return [String] the full help text
      def usage_text(plugin: nil)
        lines = [@context.options.help_text(banner: app_banner)]
        if plugin.nil?
          # Top-level: list all available plugins
          plugin_names = Plugins::Factory.instance.plugin_list.reject{ |s| s.eql?(COMMAND_CONFIG)}.sort
          lines << "\nPLUGINS"
          col_w = plugin_names.map{ |n| n.to_s.length}.max + 2
          plugin_names.each do |name|
            app = Plugins::Factory.instance.plugin_class(name).application_name
            lines << "    #{name.to_s.ljust(col_w)}  #{app}"
          end
        else
          path     = plugin.help_path || []
          registry = plugin.class.command_registry
          cmds     = registry.children_of(path)
          label    = plugin.class.name.split('::').last.downcase
          label   += " #{path.join(' ')}" unless path.empty?
          if cmds.any?
            # Intermediate node: list subcommands
            lines << "\nCOMMANDS: #{label}"
            col_w = cmds.keys.map{ |k| k.to_s.length}.max + 2
            cmds.each do |id, spec|
              lines << "    #{id.to_s.ljust(col_w)}  #{spec.description}"
            end
          else
            # Leaf node: show description + arguments
            spec = registry[path]
            lines << "\nCOMMAND: #{label}"
            lines << "    #{spec.description}" if spec&.description
            display_args = spec&.arguments || []
            if display_args.any?
              lines << "\nARGUMENTS:"
              col_w = display_args.map{ |a| a.name.to_s.length}.max + 2
              display_args.each do |arg|
                flag  = arg.mandatory ? arg.name.to_s : "[#{arg.name}]"
                types = case arg.type
                when :identifier then 'identifier'
                when Array       then arg.type.map(&:name).join(', ')
                when nil         then ''
                else arg.type.name
                end
                hint  = arg.type.eql?(Hash) && arg.schema ? "  (use 'help' as value to see schema)" : ''
                lines << "    #{flag.ljust(col_w)}  #{arg.description || types}#{hint}"
              end
            end
          end
        end
        lines.join("\n")
      end

      # Initialize agents and options
      # This can throw exception if there is a problem with the environment, needs to be caught by execute method
      # @raise [StandardError] if there is a problem with the environment
      # @return [nil]
      def init_agents_and_options
        @context.man_header = true
        # Create formatter, in case there is an exception, it is used to display.
        @context.formatter = Formatter.new
        # Create command line manager with arguments
        @context.options = Parser.new(Info::CMD_NAME, @argv)
        ExtendedValue.instance.on(EXTEND_ARGS){ |v| @context.options.args_as_extended(v)}
        # Formatter: declare metadata (class method), then bind to the instance
        Formatter.declare_options(@context.options)
        @context.formatter.bind_options(@context.options)
        # Compare $0 with expected name
        current_prog_name = File.basename($PROGRAM_NAME)
        Aspera.assert(current_prog_name.eql?(Info::CMD_NAME), type: :warn){"Please use '#{Info::CMD_NAME}' instead of '#{current_prog_name}'"}
        # Declare and parse global options
        declare_global_options
        # Bootstrap: populate context services (main_folder, persistency, presets, http_config,
        # progress_bar) and configure global singletons before any plugin is instantiated.
        # The vault callback is lazy: @vault extended-values are only resolved after Config.new,
        # so @context.config is always set by the time it is called.
        @bootstrapper = Bootstrapper.new(@context)
        @bootstrapper.run(
          gem_plugins_folder: Plugins::Config.gem_plugins_folder,
          vault_value_cb:     ->(v){@context.config.vault_value(v)}
        )
        # Do not display config commands if help is asked
        @context.man_header = false
        # Config declares remaining plugin options on top of what Bootstrapper already parsed
        @context.config = Plugins::Config.new(context: @context)
        @context.man_header = true
        # Sync cache_tokens from Config into the OAuth persist_mgr (now that option is parsed)
        OAuth::Factory.instance.persist_mgr = @context.persistency if @context.config.option_cache_tokens
        # Email service: depends on options declared by Config
        @context.mailer = Mailer.new(@context.options, @context.main_folder)
        # Secret finder: depends on options (:secret) and presets, both set by Bootstrapper
        @context.secret_finder = SecretFinder.new(@context.options, @context.presets)
        # The TransferAgent plugin may use the @preset parser
        @context.transfer = TransferAgent.new(@context)
        # Add commands for config plugin after all options have been added
        @context.config.add_manual_header(false)
        @context.validate
        # Set banner when all environment is created so that additional extended value modifiers are known, e.g. @preset
      end

      # Generate the application banner for help display
      # @return [String] formatted banner text
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
          #{t}#{ExtendedValue.instance.modifiers.join(', ')}
          #{t}Dates format is 'DD-MM-YY HH:MM:SS', or 'now' or '-<num>h'

          ARGS
          #{t}Some commands require mandatory arguments, e.g. a path.
        END_OF_BANNER
      end

      # Define header for manual and declare all global options
      # @return [nil]
      def declare_global_options
        Log.log.debug('declare_global_options')
        @context.options.declare(:help, description: 'Show this message', allowed: Allowed::TYPES_NONE, short: 'h') do
          @option_help = true
          @context.options.help_requested = true
        end
        @context.options.declare(:show_config, description: 'Display parameters used for the provided action', allowed: Allowed::TYPES_NONE){@option_show_config = true}
        @context.options.declare(:version, description: 'Display version', allowed: Allowed::TYPES_NONE, short: 'v'){@context.formatter.display_message(:data, Cli::VERSION); Process.exit(0)} # rubocop:disable Style/Semicolon
        @context.options.declare(
          :ui, description: 'Method to start browser',
          allowed: USER_INTERFACES,
          handler: {o: Environment.instance, m: :url_method}
        )
        @context.options.declare(
          :invalid_characters, description: 'Replacement character and invalid filename characters',
          handler: {o: Environment.instance, m: :file_illegal_characters}
        )
        @context.options.declare(:log_level, description: 'Log level', allowed: Log::LEVELS, handler: {o: Log.instance, m: :level})
        @context.options.declare(:log_format, description: 'Log formatter', allowed: [Proc, Logger::Formatter, String], handler: {o: Log.instance, m: :formatter})
        @context.options.declare(:logger, description: 'Logging method', allowed: Log::LOG_TYPES, handler: {o: Log.instance, m: :logger_type})
        @context.options.declare(:log, description: 'Logging options (dot-notation: level, type, format, secrets)', handler: {o: self, m: :option_log}, schema: Schema::Registry::LOG_OPTIONS)
        @context.options.declare(:lock_port, description: 'Prevent dual execution of a command, e.g. in cron', allowed: Allowed::TYPES_INTEGER)
        @context.options.declare(:once_only, description: 'Process only new items (some commands)', allowed: Allowed::TYPES_BOOLEAN, default: false)
        @context.options.declare(:log_secrets, description: 'Show passwords in logs', allowed: Allowed::TYPES_BOOLEAN, handler: {o: SecretHider.instance, m: :log_secrets})
        @context.options.declare(:clean_temp, description: 'Cleanup temporary files on exit', allowed: Allowed::TYPES_BOOLEAN, handler: {o: TempFileManager.instance, m: :cleanup_on_exit})
        @context.options.declare(:temp_folder, description: 'Temporary folder', handler: {o: TempFileManager.instance, m: :global_temp})
        @context.options.declare(:pid_file, description: 'Write process identifier to file, delete on exit')
        @context.options.declare(
          :parser, description: 'Default parser for structured parameters and options',
          handler: {o: ExtendedValue.instance, m: :default_decoder},
          allowed: ExtendedValue::DEFAULT_DECODERS,
          default: ExtendedValue::DEFAULT_DECODERS.first
        )
        # Parse declared options
        @context.options.parse_options!
      end

      # Get the plugin instance based on name
      # Also loads the plugin options, and default values from conf file
      # @param plugin_name_sym [Symbol] symbol for plugin name
      # @return [Plugins::Base] the plugin instance
      def get_plugin_instance_with_options(plugin_name_sym)
        Log.log.debug{"get_plugin_instance_with_options(#{plugin_name_sym})"}
        # Load default preset options for this plugin from config file
        default_config_name = @context.presets.plugin_default_name(plugin_name_sym)
        Log.log.debug{"add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}"}
        @context.options.add_option_preset(@context.presets.by_name(default_config_name), 'default_plugin', override: false) unless default_config_name.nil?
        command_plugin = Plugins::Factory.instance.create(plugin_name_sym, context: @context)
        return command_plugin
      end
      COMMAND_CONFIG = :config
      COMMAND_HELP = :help
      # Types that go to result of type = text
      SCALAR_TYPES = [String, Integer, Symbol].freeze
      USER_INTERFACES = %i[text graphical].freeze
      EXTEND_ARGS = :''

      private_constant :COMMAND_CONFIG, :COMMAND_HELP, :SCALAR_TYPES, :USER_INTERFACES, :EXTEND_ARGS
    end
  end
end
