# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'argument'
require_relative 'context'
require_relative 'parser'
require_relative 'formatter'
require_relative 'table_fitter'
require_relative 'plugins/factory'
require_relative 'bootstrapper'
require_relative '../rest/aspera_errors' # registers error handlers of Aspera REST APIs
require_relative 'plugins/config'
require_relative 'mailer'
require_relative 'secret_finder'
require_relative 'extended_value'
require_relative 'security'
require_relative 'version'
require_relative 'info'
require_relative 'hints'
require_relative 'result'
require_relative '../units/duration'
require_relative '../secret/hider'
require_relative '../secret/reference'
require_relative '../ssh'
require_relative '../log'
require_relative '../assert'
require_relative '../schema/documentation'
require_relative '../schema/registry'
require 'net/ssh/errors'
require 'net/protocol'
require 'openssl'

module Aspera
  module Cli
    # The main CLI class
    class Runner
      # Minimum initialization, no exception raised
      # @param argv [Array<String>] command line arguments
      # @param main_folder [String, nil] main folder set by the program (not by the arguments), e.g. the one of the MCP server; `nil`: option `home`
      # @param config_file [String, nil] configuration file set by the program (not by the arguments), e.g. the one of the MCP server; `nil`: option `config_file`
      # @param vault [Hash, nil] option `vault` set by the program (not by the arguments), e.g. the one of the MCP server; `nil`: option `vault`
      # @param vault_password [String, nil] option `vault_password` set by the program (not by the arguments); `nil`: option `vault_password`
      # @return [nil]
      def initialize(argv, main_folder: nil, config_file: nil, vault: nil, vault_password: nil)
        @main_folder = main_folder
        @config_file = config_file
        @vault = vault
        @vault_password = vault_password
        # Dumped (trace2) with secrets hidden by `CommandLine`
        @argv = argv
        @option_help = false
        @option_show_config = false
        @context = Context.new
      end

      attr_reader :context

      # Execute the command and return the raw `Result` object.
      # Pure computation: no display, no Process.exit - raises on any error.
      # @return [Result, nil] the result of the command, or nil if nothing to execute
      def run_with_result
        init_agents_and_options
        @context.config.add_plugin_lookup_folders
        Plugins::Factory.instance.add_plugins_from_lookup_folders
        # Config is created before the plugin folders are added: modules mounted on config by their bundles, with their options
        Plugins::Config.include_mounts(Plugins::Factory.instance.registry)
        Plugins::Config.declare_options(@context.options, target: @context.config, parse: true)
        # The service `transfer` declares its options (after those of config), and parses option `transfer`: agents of the bundles of the plugin folders are known
        @context.transfer
        # Help requested without command? Show global options + plugin list
        return result_usage if @option_help && @context.options.command_or_arg_empty?
        # Shell completion is executed on each `Tab`: no network access
        @context.config.periodic_check_newer_gem_version unless @context.options.next_arguments?(COMPLETION_COMMAND)
        # A plugin that cannot be loaded is not in the list of commands: give the reason, not an unknown command
        Plugins::Factory.instance.unavailable_plugins.each do |name, reason|
          raise Cli::Error, reason if @context.options.next_arguments?([name.to_s])
        end
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
            Log.log.debug { "Opening lock port #{lock_port}" }
            @tcp_server = TCPServer.new('127.0.0.1', lock_port)
          rescue StandardError => e
            execute_command = false
            Log.log.warn { "Another instance is already running (#{e.message})." }
          end
        end
        pid_file = @context.options.get_option(:pid_file)
        if !pid_file.nil?
          File.write(pid_file, ::Process.pid)
          Log.log.debug { "Wrote pid #{::Process.pid} to #{pid_file}" }
          at_exit { File.delete(pid_file) }
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
        rescue Net::SSH::AuthenticationFailed => e;    exception_info = {e: e, t: 'SSH', security: true, exit: ExitCode::AUTH}
        rescue OpenSSL::SSL::SSLError => e;            exception_info = {e: e, t: 'SSL', exit: ExitCode::NETWORK}
        rescue Cli::BadArgument, ParameterError => e;  exception_info = {e: e, t: 'Argument', usage: true, exit: ExitCode::USAGE}
        rescue Cli::MissingArgument => e;              exception_info = {e: e, t: 'Missing', exit: ExitCode::USAGE}
        rescue Cli::BadIdentifier, EntityNotFound, Aspera::Secret::NotFound => e
          exception_info = {e: e, t: 'Identifier', exit: ExitCode::NOT_FOUND}
        rescue AuthenticationError, Aspera::Secret::AuthenticationError => e
          exception_info = {e: e, t: 'Authentication', exit: ExitCode::AUTH}
        rescue Cli::SchemaRequest => e;                exception_info = {e: e, t: 'Schema', exit: ExitCode::SUCCESS}
        rescue Cli::PollConditionNotMet => e;          exception_info = {e: e, t: 'Poll', exit: ExitCode::ERROR}
        rescue Cli::Error => e;                        exception_info = {e: e, t: 'Tool', usage: true, exit: ExitCode::ERROR}
        rescue EnvironmentError => e;                  exception_info = {e: e, t: 'Environment', exit: ExitCode::ERROR}
        # Label `Vault`, as the option: with `Secret`, the log would hide a message of one word, as a secret value
        rescue Aspera::Secret::Error => e;             exception_info = {e: e, t: 'Vault', exit: ExitCode::ERROR}
        rescue Aspera::Ssh::Error => e;                exception_info = {e: e, t: 'SSH', exit: ExitCode::ERROR}
        rescue Rest::CallError => e;                   exception_info = {e: e, t: 'Rest', exit: ExitCode.for_call_error(e)}
        rescue *NETWORK_ERRORS => e;                   exception_info = {e: e, t: 'Network', exit: ExitCode::NETWORK}
        rescue StandardError => e;                     exception_info = other_error_info(e)
        rescue Interrupt => e;                         exception_info = {e: e, t: 'Interruption', debug: true, exit: ExitCode::INTERRUPTED}
        end
        # 1- processing of error condition
        unless exception_info.nil?
          Log.log.warn(exception_info[:e].message) if Log.instance.logger_type.eql?(:syslog) && exception_info[:security]
          Log.log.error { "#{exception_info[:t]}: #{exception_info[:e].message}" } unless exception_info[:e].is_a?(Cli::SchemaRequest)
          Log.log.info { "Location: #{plugin_location(exception_info[:e])}" } if exception_info[:debug] && plugin_location(exception_info[:e])
          Log.log.debug { (['Backtrace:'] + exception_info[:e].backtrace).join("\n") } if exception_info[:debug]
          @context.formatter.display_message(:error, 'Use option -h to get help.') if exception_info[:usage]
          Hints.hint_for(exception_info[:e], @context.formatter)
          if exception_info[:e].is_a?(Cli::SchemaRequest)
            Log.log.info { "#{exception_info[:t]}: #{exception_info[:e].message}" }
            display_schema(exception_info[:e].path)
          end
        end
        # 2- processing of unprocessed arguments (skip when help was displayed: sub-commands are not consumed)
        # With `show_config`, the command is not executed: its arguments are not consumed, but unknown options are reported
        unless @option_help
          @context.options&.final_errors(after_error: !exception_info.nil? || @option_show_config)&.each do |msg|
            Log.log.error { "Argument: #{msg}" }
            exception_info = {e: Exception.new(msg), t: 'UnusedArg', exit: ExitCode::USAGE} if exception_info.nil?
          end
        end
        # 3- exit on error
        unless exception_info.nil?
          if Log.log.debug?
            # Same display as an uncaught exception, but keeps the exit code
            $stderr.puts(exception_info[:e].full_message) # rubocop:disable Style/StderrPuts
          elsif exception_info[:debug]
            @context.formatter.display_message(:error, 'Use --log-level=debug to get more details.')
          end
          exit_code = exception_info[:exit]
          # Nagios plugins report the failure of the check itself as UNKNOWN
          exit_code = Nagios::UNKNOWN if !exit_code.eql?(ExitCode::SUCCESS) && @context.formatter&.format_type.eql?(:nagios)
          ::Process.exit(exit_code)
        end
        return
      end

      # Display usage information and exit (used by the interactive CLI).
      # @param plugin [Plugins::Base, nil] plugin instance to show subcommands for
      # @return [nil]
      def show_usage(plugin: nil)
        @context.formatter.display_message(:error, usage_text(plugin: plugin))
        ::Process.exit(0)
      end

      # Return usage as a Result::Text (used by run_with_result, no display, no exit).
      # @param plugin [Plugins::Base, nil] plugin instance to show subcommands for
      # @return [Result::Text]
      def result_usage(plugin: nil)
        Result::Text.new(usage_text(plugin: plugin))
      end

      # `on_set` callback of the `ui` option (dot-notation sub-properties): `mode`, `web_auth`, `hidden_silent`, `command`
      # A plain value is the `mode`. Values are validated against schema `UiOptions`.
      # @param value [Hash] sub-properties to set
      def option_ui=(value)
        Aspera.assert_type(value, Hash)
        value.each do |k, v|
          case k.to_sym
          when :mode
            Environment.instance.url_method =
              case v.to_s
              when 'auto' then Environment.instance.default_gui_mode
              when 'terminal', 'text' then :text
              when 'browser', 'graphical' then :graphical
              else Aspera.error_unexpected_value(v, type: BadArgument) { 'ui.mode' }
              end
          when :web_auth
            Aspera.assert_values(v.to_s, %w[port paste], type: BadArgument) { 'ui.web_auth' }
            Environment.instance.web_auth = v.to_sym
          when :hidden_silent
            Environment.instance.hidden_silent = BoolValue.true?(Parser.get_from_list(v.to_s, 'ui hidden_silent', BoolValue::ALL))
          when :command
            Environment.instance.browser_command = v.nil? || v.empty? ? nil : v.map(&:to_s)
          else Aspera.error_unexpected_value(k, type: BadArgument) { 'ui sub-option (mode, web_auth, hidden_silent, command)' }
          end
        end
      end

      # `on_set` callback of the `log` option (dot-notation sub-properties): `level`, `type`, `format`, `secrets`
      # @param value [Hash] sub-properties to set
      def option_log=(value)
        Aspera.assert_type(value, Hash)
        value.each do |k, v|
          case k.to_sym
          when :level   then Log.instance.level = v.to_sym
          when :type    then Log.instance.logger_type = v.to_sym
          when :format  then Log.instance.formatter = v
          when :secrets then Secret::Hider.instance.log_secrets = Parser.get_from_list(v.to_s, 'log secrets', BoolValue::ALL)
          else Aspera.error_unexpected_value(k) { 'log sub-option (level, type, format, secrets)' }
          end
        end
      end

      # `on_set` callback of the `temp` option (dot-notation sub-properties): `folder`, `clean`, `expiry`
      # A plain value is the `folder`. Values are validated against schema `TempOptions`.
      # @param value [Hash] sub-properties to set
      def option_temp=(value)
        Aspera.assert_type(value, Hash)
        value.each do |k, v|
          case k.to_sym
          when :folder then TempFileManager.instance.global_temp = v
          when :clean  then TempFileManager.instance.cleanup_on_exit = Parser.get_from_list(v.to_s, 'temp clean', BoolValue::ALL)
          when :expiry
            TempFileManager.instance.expiry_sec =
              case v
              when nil, false then nil
              when Numeric then v
              else Units::Duration.new(v).to_unit('s')
              end
          else Aspera.error_unexpected_value(k) { 'temp sub-option (folder, clean, expiry)' }
          end
        end
      rescue ParameterError => e
        raise BadArgument, "Option temp: #{e.message}"
      end

      private

      # @param error [StandardError] Error that is neither of the CLI, nor of a REST call, nor of the network
      # @return [Hash] Information on the error: label and exit code of its category if a bundle added one (`ExitCode.add_error`),
      #   else `Error` for an error raised on purpose by the gem, else `Other` with location: a bug (`AssertError`, `InternalError`), or an error not of the gem
      def other_error_info(error)
        category = ExitCode.error_category(error)
        return {e: error, t: category[:label], exit: category[:code]} unless category.nil?
        return {e: error, t: 'Error', exit: ExitCode::ERROR} if error.is_a?(Aspera::Error) && !error.is_a?(AssertError) && !error.is_a?(InternalError)
        {e: error, t: "Other(#{error.class.name})", debug: true, exit: ExitCode::ERROR}
      end

      # Location of an unexpected error in the code of a plugin (built-in or from option `plugin_folder`)
      # @param error [Exception] Error
      # @return [String, nil] First line of the backtrace in a plugin folder, e.g. `<FOLDER>/my_plugin.rb:12:in 'action_list'`, `nil` if none
      def plugin_location(error)
        folders = Plugins::Factory.instance.lookup_folders.map { |folder| File.join(folder, '') }
        error.backtrace&.find { |line| folders.any? { |folder| line.start_with?(folder) } }
      end

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
          plugin_names = Plugins::Factory.instance.plugin_list.reject { |s| s.eql?(COMMAND_CONFIG) }.sort
          lines << "\nPLUGINS"
          col_w = plugin_names.map { |n| n.to_s.length }.max + 2
          plugin_names.each do |name|
            app =
              begin
                Plugins::Factory.instance.plugin_class(name).application_name
              rescue Cli::Error => e
                # A plugin that cannot be loaded does not prevent the help
                e.message
              end
            lines << "    #{name.to_s.ljust(col_w)}  #{app}"
          end
        else
          path     = plugin.help_path || []
          registry = plugin.class.command_registry
          cmds     = registry.children_of(path)
          label    = plugin.class.plugin_name
          # Build label with positional argument slots inserted after each command
          # e.g. [:access_keys, :do, :download] -> "node access_keys do <access_key_id> download"
          path.each_index do |i|
            label += " #{path[i]}"
            registry.arguments_at(path[0..i]).each { |arg_spec| label += " #{arg_spec.syntax}" }
          end
          if cmds.any?
            # Intermediate node: show current command + description, then list subcommands
            lines << "\nCOMMAND: #{label}"
            node_spec = path.empty? ? nil : registry[path]
            lines << "  #{node_spec.description}" if node_spec&.description
            lines << "\n  SUBCOMMANDS:"
            col_w = cmds.keys.map { |k| k.to_s.length }.max + 2
            cmds.each do |id, spec|
              lines << "    #{id.to_s.ljust(col_w)}  #{spec.description}"
            end
          else
            # Leaf node: show description + arguments.
            spec = registry[path]
            lines << "\nCOMMAND: #{label}"
            lines << "    #{spec.description}" if spec&.description
            display_args = registry.arguments_at(path)
            # The files of a command with `transfer_paths` are given as the service `transfer` reads them (e.g. positional arguments)
            display_args += [@context.transfer.paths_argument(spec.transfer_paths)] if spec&.transfer_paths
            if display_args.any?
              lines << "\nARGUMENTS:"
              col_w = display_args.map { |a| a.name.to_s.length }.max + 2
              display_args.each do |arg|
                flag  = arg.mandatory ? arg.name.to_s : "[#{arg.name}]"
                flag += '...' if arg.multiple
                types = case arg.type
                when :identifier then 'identifier'
                when Array       then arg.type.map(&:name).join(', ')
                when nil         then ''
                else arg.type.name
                end
                hint  = Array(arg.type).include?(Hash) && arg.schema ? '  (schema shown below)' : ''
                lines << "    #{flag.ljust(col_w)}  #{arg.description || types}#{hint}"
                lines.concat(schema_help_lines(arg)) if Array(arg.type).include?(Hash) && arg.schema
              end
            end
            lines << "\nTIP: use --query=help to list available query parameters" if spec&.query_schema
          end
        end
        lines.join("\n")
      end

      # Render the structure of a Hash argument's JSON schema in command help.
      # @param arg [Argument]
      # @return [Array<String>]
      def schema_help_lines(arg)
        description = free_form_description(arg.schema)
        return ["\n    SCHEMA: #{arg.name}", description.lines.map { |line| "    #{line.chomp}" }.join("\n")] unless description.nil?
        builder = schema_documentation(arg.schema)
        rows = builder.rows.map do |row|
          builder.columns.map { |column| Array(row[column]).join("\n") }
        end
        style = {}
        style[:border] = :unicode_round if Environment.terminal_supports_unicode?
        table = TableFitter.table(headings: builder.columns, rows: rows, style: style, width: Environment.terminal_columns&.-(4)).to_s
        ["\n    SCHEMA: #{arg.name}", table.lines.map { |line| "    #{line.chomp}" }.join("\n")]
      end

      # Display the documentation of a schema: value `help` given to an option or argument
      # @param schema_path [String, nil] Path of the schema in the registry, `nil` if none
      # @return [nil]
      def display_schema(schema_path)
        if schema_path.nil?
          Log.log.warn { 'Sorry, no schema provided yet. Please refer to the manual or API.' }
          return
        end
        description = free_form_description(schema_path)
        unless description.nil?
          @context.formatter.display_message(:data, description)
          return
        end
        builder = schema_documentation(schema_path)
        @context.formatter.display_results(Result::ObjectList.new(builder.rows, fields: builder.columns))
        nil
      end

      # A free-form structure (`additionalProperties`, no `properties`) has no property to list: its description is the help.
      # @param schema_path [String] Path of the schema in the registry
      # @return [String, nil] Description of the schema for the terminal, followed by its examples (JSON), `nil` if the schema has properties to list
      def free_form_description(schema_path)
        node = Schema::Registry.instance.reader(schema_path).current
        return if %w[properties allOf oneOf].any? { |key| node.key?(key) }
        # OpenAPI 3.1: `examples` array (3.0: `example`)
        examples = node.key?('examples') ? Array(node['examples']) : [node['example']].compact
        text = TerminalFormatter.markdown_text(node['description'])
        examples.each { |example| text += "\nExample: #{JSON.generate(example)}" }
        text
      end

      # @param schema_path [String] Path of the schema in the registry
      # @return [Schema::Documentation] Documentation of the schema, for the terminal, with the options given by the code that registered it
      def schema_documentation(schema_path)
        Schema::Documentation.new(TerminalFormatter, Schema::Registry.instance.reader(schema_path), **Schema::Registry.instance.doc_options(schema_path)).build
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
        ExtendedValue.instance.on(EXTEND_ARGS, description: 'Structure from next arguments: <path>=<value>..., then end marker') { |v| @context.options.args_as_extended(v) }
        @context.formatter.declare_options(@context.options)
        # Compare $0 with expected name
        current_prog_name = File.basename($PROGRAM_NAME)
        Aspera.assert(current_prog_name.eql?(Info::CMD_NAME), type: :warn) { "Please use '#{Info::CMD_NAME}' instead of '#{current_prog_name}'" }
        # Declare and parse global options
        declare_global_options
        # Bootstrap: populate context services (main_folder, persistency, presets, vault, http_config,
        # progress_bar) and configure global singletons before any plugin is instantiated.
        @bootstrapper = Bootstrapper.new(@context, main_folder: @main_folder, config_file: @config_file, vault: @vault, vault_password: @vault_password)
        @bootstrapper.run(gem_plugins_folder: Plugins::Config.gem_plugins_folder)
        # Do not display config commands if help is asked
        @context.man_header = false
        # Config declares remaining plugin options on top of what Bootstrapper already parsed
        @context.config = Plugins::Config.new(context: @context)
        @context.man_header = true
        # Sync cache_tokens from Config into the OAuth persist_mgr (now that option is parsed)
        OAuth::Factory.instance.persist_mgr = @context.persistency if @context.options.get_option(:cache_tokens)
        # Email service: depends on options declared by Config
        @context.mailer = Mailer.new(@context.options, @context.main_folder)
        # Secret finder: depends on options (:secret) and presets, both set by Bootstrapper
        @context.secret_finder = SecretFinder.new(@context.options, @context.presets)
        # The service `transfer` is created once the plugin folders are added (see `run_with_result`)
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
          #{t}#{Info::CMD_NAME} [GLOBAL_OPTIONS] <command> [OPTIONS] [ARGS]

          DESCRIPTION
          #{t}Use Aspera application to perform operations on command line.
          #{t}Documentation and examples: #{Info::GEM_URL}
          #{t}execute: #{Info::CMD_NAME} conf doc
          #{t}or visit: #{Info::DOC_URL}
          #{t}source repo: #{Info::SRC_URL}
          #{t}AI assistants: #{Info::CMD_NAME} config commands, #{Info::LLMS_URL}

          ENVIRONMENT VARIABLES
          #{t}Any option can be set as an environment variable, refer to the manual

          COMMANDS
          #{t}To list first level commands, execute: #{Info::CMD_NAME}
          #{t}Note that commands can be written shortened (provided it is unique).

          OPTIONS
          #{t}Options begin with a '-' (minus), and value is provided on command line.
          #{t}Special values are supported beginning with special prefix @pfx:, where pfx is one of:
          #{t}#{ExtendedValue.instance.modifiers.reject(&:empty?).join(', ')}
          #{t}Durations: a number of seconds, or with units w, d, h, m, s, ms, us (e.g. 1h30m), or 1d 02:00:00
          #{t}Dates: @date:<DATE> gives <DATE> in UTC, ISO 8601. <DATE> is a date (e.g. 2026-11-27 10:00:00),
          #{t}or now, today, yesterday, tomorrow, optionally followed by -<DURATION> or +<DURATION> (e.g. now-24h)

          ARGS
          #{t}Some commands require mandatory arguments, e.g. a path.

          EXIT STATUS
          #{ExitCode::DESCRIPTIONS.map { |code, description| "#{t}#{code.to_s.ljust(5)}#{description}" }.join("\n")}
        END_OF_BANNER
      end

      # Define header for manual and declare all global options
      # @return [nil]
      def declare_global_options
        Log.log.debug('declare_global_options')
        @context.options.declare(:help, description: 'Show this message', allowed: Option::Type::NONE, short: 'h') do
          @option_help = true
          @context.help_requested = true
        end
        @context.options.declare(:show_config, description: 'Display parameters used for the provided action', allowed: Option::Type::NONE) { @option_show_config = true }
        @context.options.declare(:version, description: 'Display version', allowed: Option::Type::NONE, short: 'v') { @context.formatter.display_message(:data, Cli::VERSION); ::Process.exit(0) } # rubocop:disable Style/Semicolon
        @context.options.declare(
          :ui, description: 'User interface (dot-notation: mode, web_auth, hidden_silent, command)',
          allowed: [Hash, String], shorthand: 'mode', schema: Schema::Registry::UI_OPTIONS,
          on_set: method(:option_ui=)
        )
        @context.options.declare(
          :invalid_characters, description: 'Replacement character and invalid filename characters',
          default: Environment.instance.file_illegal_characters,
          on_set: Environment.instance.method(:file_illegal_characters=)
        )
        @context.options.declare(:log_level, description: 'Log level', allowed: Log::LEVELS, default: Log.instance.level, on_set: Log.instance.method(:level=))
        @context.options.declare(:log_format, description: 'Log formatter', allowed: [Proc, Logger::Formatter, String], on_set: Log.instance.method(:formatter=))
        @context.options.declare(:logger, description: 'Logging method', allowed: Log::LOG_TYPES, on_set: Log.instance.method(:logger_type=))
        @context.options.declare(:log, description: 'Logging options (dot-notation: level, type, format, secrets)', on_set: method(:option_log=), schema: Schema::Registry::LOG_OPTIONS)
        @context.options.declare(:security, description: 'Security restrictions (dot-notation: level, allowed_paths)', on_set: Security.instance.method(:options=), schema: Schema::Registry::SECURITY_OPTIONS)
        @context.options.declare(:lock_port, description: 'Prevent dual execution of a command, e.g. in cron', allowed: Option::Type::INTEGER)
        @context.options.declare(:once_only, description: 'Process only new items (some commands)', allowed: Option::Type::BOOLEAN, default: false)
        @context.options.declare(:dry_run, description: 'Do not perform changes, only show what would be done', allowed: Option::Type::BOOLEAN, default: false)
        @context.options.declare(:log_secrets, description: 'Show passwords in logs', allowed: Option::Type::BOOLEAN, default: Secret::Hider.instance.log_secrets, on_set: Secret::Hider.instance.method(:log_secrets=))
        @context.options.declare(
          :temp, description: 'Temporary files (dot-notation: folder, clean, expiry)',
          allowed: [Hash, String], shorthand: 'folder', schema: Schema::Registry::TEMP_OPTIONS,
          on_set: method(:option_temp=)
        )
        @context.options.declare(:clean_temp, description: 'Cleanup temporary files on exit', allowed: Option::Type::BOOLEAN, on_set: TempFileManager.instance.method(:cleanup_on_exit=), deprecation: {last: '4.27.5', message: 'use --temp.clean'})
        @context.options.declare(:temp_folder, description: 'Temporary folder', on_set: TempFileManager.instance.method(:global_temp=), deprecation: {last: '4.27.5', message: 'use --temp.folder'}, complete: :folder, security: :low)
        @context.options.declare(:pid_file, description: 'Write process identifier to file, delete on exit', complete: :file, security: :low)
        @context.options.declare(
          :parser, description: 'Default parser for structured parameters and options',
          on_set: ExtendedValue.instance.method(:default_decoder=),
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
        Log.log.debug { "get_plugin_instance_with_options(#{plugin_name_sym})" }
        # Load default preset options for this plugin from config file
        default_config_name = @context.presets.plugin_default_name(plugin_name_sym)
        Log.log.debug { "add_plugin_default_preset:#{plugin_name_sym}:#{default_config_name}" }
        @context.options.add_option_preset(@context.presets.by_name(default_config_name), 'default_plugin', override: false, configured: true) unless default_config_name.nil?
        command_plugin = Plugins::Factory.instance.create(plugin_name_sym, context: @context)
        return command_plugin
      end
      COMMAND_CONFIG = :config
      COMMAND_HELP = :help
      # Shell completion commands (scripts and words)
      COMPLETION_COMMAND = %w[config completion].freeze
      # Types that go to result of type = text
      SCALAR_TYPES = [String, Integer, Symbol].freeze
      EXTEND_ARGS = :''
      # Errors of name resolution, connection and timeout
      NETWORK_ERRORS = [
        SocketError, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ETIMEDOUT
      ].freeze

      private_constant :COMMAND_CONFIG, :COMMAND_HELP, :COMPLETION_COMMAND, :SCALAR_TYPES, :EXTEND_ARGS, :NETWORK_ERRORS
    end
  end
end
