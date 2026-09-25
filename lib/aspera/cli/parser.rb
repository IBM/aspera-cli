# frozen_string_literal: true

require 'aspera/cli/preset_manager'
require 'aspera/cli/extended_value'
require 'aspera/cli/error'
require 'aspera/cli/special_values'
require 'aspera/cli/terminal_formatter'
require 'aspera/cli/option_types'
require 'aspera/cli/option_registry'
require 'aspera/cli/command_line'
require 'aspera/cli/prompt'
require 'aspera/schema/validator'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/dot_container'
require 'terminal-table'
require 'aspera/rainbow'
using Rainbow

module Aspera
  module Cli
    # Parse command line options and positional arguments.
    #
    # Options are declared incrementally (global, then plugin options).
    # Command line options are applied when their option is declared: explicitly with `parse_options!`,
    # or automatically on next read of an option or argument. Unknown options are kept for later.
    #
    # Option values come from several sources, see `OptionSource`: highest priority wins, whatever the order.
    class Parser
      include Prompt

      class << self
        # Find shortened string value in allowed symbol list
        # @param short_value    [String] Value or prefix to find
        # @param descr          [String] Description for error messages
        # @param allowed_values [Array]  List of allowed values
        # @return [Symbol, Boolean] matched symbol or boolean value
        def get_from_list(short_value, descr, allowed_values)
          Aspera.assert_type(short_value, String)
          # we accept shortcuts
          matching = allowed_values.select { |i| i.to_s.eql?(short_value) }
          matching = allowed_values.select { |i| i.to_s.start_with?(short_value) } unless matching.length.eql?(1)
          raise BadArgument, "Identifier '#{short_value}' used where a #{descr} is expected: place the identifier after the command" if matching.empty? && short_value.match?(REGEX_LOOKUP_ID_BY_FIELD)
          Aspera.assert(!matching.empty?, multi_choice_assert_msg("unknown value for #{descr}: #{short_value}", allowed_values), type: BadArgument)
          Aspera.assert(matching.length.eql?(1), multi_choice_assert_msg("ambiguous shortcut for #{descr}: #{short_value}", matching), type: BadArgument)
          return BoolValue.true?(matching.first) if allowed_values.eql?(BoolValue::ALL)
          matching.first
        end

        # Generates error message with list of allowed values
        # @param error_msg   [String] Error message
        # @param accept_list [Array<Symbol>] List of allowed values
        # @param aliases     [Hash{Symbol=>Symbol}, nil] alias→id map; used to annotate entries with their aliases
        def multi_choice_assert_msg(error_msg, accept_list, aliases: nil)
          # Build reverse map: id → [alias, ...] for annotation
          reverse = aliases&.each_with_object({}) do |(ali, id), h|
            (h[id] ||= []) << ali
          end
          lines = accept_list.map do |choice|
            suffix = reverse&.key?(choice) ? " (alias: #{reverse[choice].join(', ')})" : ''
            "- #{choice}#{suffix}"
          end
          [error_msg, 'Use:', *lines.sort].join("\n")
        end

        # Change option name with dash to name with underscore
        # @param name [String] option name with dash separators
        # @return [String] option name with underscore separators
        def option_line_to_name(name)
          name.gsub(Option::NAME_SEP_LINE, Option::NAME_SEP_SYMBOL)
        end

        # Convert option symbol to CLI line flag format
        # @param name [Symbol, String] option name
        # @return [String] option flag (e.g. "--option-name")
        def option_name_to_line(name)
          "#{Option::PREFIX}#{name.to_s.gsub(Option::NAME_SEP_SYMBOL, Option::NAME_SEP_LINE)}"
        end

        # Parse percent-selector string into field name and value (extended value is parsed in value)
        # @param identifier [String] identifier to parse
        # @return [Hash{Symbol => String}, nil] `{field:,value:}` if identifier is a percent selector, else `nil`
        def percent_selector(identifier)
          Aspera.assert_type(identifier, String)
          if (m = identifier.match(REGEX_LOOKUP_ID_BY_FIELD))
            return {field: m[1], value: ExtendedValue.instance.evaluate(m[2], context: "percent selector: #{m[1]}")}
          end
          nil
        end

        # Using dotted hash notation, convert value to bool, int, float or extended value
        # `true` and `yes` are converted to `true`, `false` and `no` to `false`
        # @param value [String] The value to convert to appropriate type
        # @return [Boolean, Integer, Float, String, Array, Hash] the converted value
        def smart_convert(value)
          case value
          when 'true', BoolValue::YES_SYM.to_s then true
          when 'false', BoolValue::NO_SYM.to_s then false
          else
            Integer(value, exception: false) ||
              Float(value, exception: false) ||
              ExtendedValue.instance.evaluate(value, context: 'dotted expression')
          end
        end
      end

      attr_accessor :ask_missing_mandatory, :ask_missing_optional
      attr_writer :fail_on_missing_mandatory

      # @param program_name [String] Name of the program
      # @param argv [Array<String>, nil] Command line arguments to parse
      def initialize(program_name, argv = nil)
        @registry = OptionRegistry.new
        # do we ask missing options and arguments to user ?
        @ask_missing_mandatory = false # STDIN.isatty
        # ask optional options if not provided and in interactive
        @ask_missing_optional = false
        # get_option fails if a mandatory parameter is asked
        @fail_on_missing_mandatory = true
        # Values from presets and env vars, for options not declared yet: option symbol -> [{value:, source:}]
        @pending_values = {}
        # `true` when options were declared or presets added since last parse
        @parse_needed = true
        # options can also be provided by env vars : --param-name -> ASCLI_PARAM_NAME
        env_prefix = program_name.upcase + Option::NAME_SEP_SYMBOL
        ENV.each do |k, v|
          add_pending_value(k.delete_prefix(env_prefix).downcase.to_sym, v, :env, replace: true) if k.start_with?(env_prefix)
        end
        Log.dump(:env, @pending_values)
        @command_line = CommandLine.new(argv || [])
        declare(:interactive, description: 'Use interactive input of missing params', allowed: Type::BOOLEAN, default: false, on_set: method(:ask_missing_mandatory=))
        declare(:ask_options, description: 'Ask even optional options', allowed: Type::BOOLEAN, default: false, on_set: method(:ask_missing_optional=))
      end

      # Declare an option
      # @param option_symbol [Symbol] option name
      # @param description   [String, nil] description for help; if nil, derived from schema
      # @param short         [String] short option name
      # @param allowed       [Object] Allowed values, see `OptionValue`.
      #   When `schema:` is provided:
      #   - Omit `allowed:` when the schema has a single type (`type: object/array`): it is inferred automatically.
      #   - Omit `allowed:` when the schema uses `oneOf`/`anyOf` and all branches are `object`: `Hash` is inferred.
      #   - Use `allowed: [Hash, String]` when the option additionally accepts a plain String shorthand;
      #     the schema then documents the Hash form and `=help` still shows it.
      # @param default       [Object] default value
      # @param on_set       [#call]  Called with the new value each time the value is set (e.g. a `Method`, or a lambda).
      #   For a flag (`Type::NONE`): called without argument when the flag is found
      # @param shorthand     [String] For a `Hash` option: a `String` value is stored as `{shorthand => value}`
      # @param deprecation   [Hash, nil] deprecation: `{last:, message:}`, see `Deprecation`
      # @param schema        [String] schema path documenting the Hash form of this option
      # @param block [Proc] Block to execute when option is found
      def declare(option_symbol, description: nil, short: nil, allowed: nil, default: nil, on_set: nil, shorthand: nil, deprecation: nil, schema: nil, &block)
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(!@registry.declared?(option_symbol)) { "#{option_symbol} already declared" }
        if on_set && allowed.eql?(Type::NONE)
          Aspera.assert(block.nil?) { "#{option_symbol}: flag with both on_set and block" }
          block = on_set
          on_set = nil
        end
        # An abbreviation already used on command line must stay unambiguous
        @command_line.abbreviated_option_tokens.each do |tok|
          Aspera.assert(!option_symbol.to_s.start_with?(tok.name), type: BadArgument) do
            "Ambiguous option #{tok.raw}: used as #{self.class.option_name_to_line(tok.abbreviation_of)}, but also matches #{self.class.option_name_to_line(option_symbol)}"
          end
        end
        option = @registry.add(
          OptionValue.new(
            option:      option_symbol,
            description: description,
            allowed:     allowed,
            on_set:      on_set,
            shorthand:   shorthand,
            deprecation: deprecation,
            schema:      schema
          ),
          short: short
        )
        description = option.description
        Aspera.assert(!description.nil?) { "#{option_symbol}: no description and no schema to derive one from" }
        Aspera.assert(description[-1] != '.') { "#{option_symbol} ends with dot" }
        Aspera.assert(description[0] == description[0].upcase) { "#{option_symbol} description does not start with an uppercase" }
        Aspera.assert(!['hash', 'extended value'].any? { |s| description.downcase.include?(s) }) { "#{option_symbol} shall use :allowed instead of hash/extended value in option description" }
        set_option(option_symbol, default, source: :default, warn_deprecation: false) unless default.nil?
        if option.flag?
          Aspera.assert(block.respond_to?(:call)) { "missing execution block for #{option_symbol}" }
          option.block = block
        end
        @parse_needed = true
        Log.log.trace1 { "declare: #{option_symbol}, group: #{option.group}, short: #{short}" }
      end

      # Set the current help section group name for subsequent declarations
      # @param name [String] group name, shown as section header in help text
      def group(name)
        @registry.group = name
      end

      # Low-level positional argument reader.
      # Prefer `Base#resolve_argument` from action methods.
      # The only direct call from outside `Cli::Parser` and `Cli::Plugins::Base` is to retrieve the list of files.
      # @param descr       [String]  Description for help
      # @param mandatory   [Boolean] `true`: raise error no more argument
      # @param multiple    [Boolean] `true`: return all remaining arguments (Array). String: until marker
      # @param accept_list [Array<Symbol>, nil] list of allowed values
      # @param validation  [Class, Array, nil] Accepted value type(s) or list of Symbols
      # @param aliases     [Hash] map of aliases: key = alias, value = real value
      # @param default     [Object] default value
      # @return [Object, Array, nil] one value, list or nil (if optional and no default)
      def get_next_argument(descr, mandatory: true, multiple: false, accept_list: nil, validation: Type::STRING, aliases: nil, default: nil, schema: nil)
        ensure_parsed
        Aspera.assert_array_all(accept_list, Symbol) unless accept_list.nil?
        Aspera.assert_hash_all(aliases, Symbol, Symbol) unless aliases.nil?
        validation = Symbol unless accept_list.nil?
        validation = [validation] unless validation.is_a?(Array) || validation.nil?
        Aspera.assert_array_all(validation, Class) { 'validation' } unless validation.nil?
        descr = "#{descr}#{add_types_info(validation)}"
        result =
          if !@command_line.pending_arguments.empty? then read_arguments(descr, multiple: multiple, validation: validation, accept_list: accept_list, aliases: aliases)
          elsif !default.nil? then default
          elsif mandatory then get_interactive(descr, multiple: multiple, accept_list: accept_list, aliases: aliases, schema: schema)
          end
        Log.log.trace1 { "#{descr}=#{result}" }
        result = aliases[result] if aliases&.key?(result)
        result = convert_argument(result, validation)
        (multiple ? result : [result]).each { |value| validate_argument(value, validation: validation, descr: descr, schema: schema) } if validation && (mandatory || !result.nil?)
        result
      end

      # Resource identifier as positional parameter
      #
      # @param description [String] description of the identifier
      # @param block       [Proc] block to search for identifier based on attribute value
      # @return [String, Array<String>] identifier or list of IDs (if `bulk` option is set)
      # @yieldparam field [String] The field name from percent selector
      # @yieldparam value [String] The value from percent selector
      # @yieldreturn [String] Resolved identifier
      def instance_identifier(description: 'identifier', &block)
        res_id = get_next_argument(description, multiple: get_option(:bulk))
        # Can be an Array
        if res_id.is_a?(String) && (m = Parser.percent_selector(res_id))
          Aspera.assert(block_given?, type: Cli::BadArgument) { "Percent syntax for #{description} not supported in this context" }
          res_id = yield(m[:field], m[:value])
        end
        res_id
      end

      # Get next positional command argument from accepted list
      # @param command_list [Array<Symbol>] accepted command names
      # @param aliases      [Hash, nil] command aliases
      # @return [Symbol] selected command
      def get_next_command(command_list, aliases: nil); get_next_argument('command', accept_list: command_list, aliases: aliases); end

      # Check whether an option has already been declared in this manager
      # @param option_symbol [Symbol] name of the option
      # @return [Boolean]
      def option_declared?(option_symbol)
        @registry.declared?(option_symbol)
      end

      # @return [Hash{Symbol => OptionValue}] all declared options (read-only view)
      def declared_options = @registry.options

      # Get an option definition by name
      # @param option_symbol [Symbol] name of the option
      # @return [OptionValue] Option definition
      # @raise [Cli::BadArgument] if option not found
      def option_def(option_symbol)
        @registry.fetch(option_symbol)
      end

      # Get an option value by name, can return nil
      # ask interactively if requested/required
      # @param option_symbol [Symbol] name of the option to retrieve
      # @param mandatory [Boolean] if true, raise error if option not set
      # @param schema [String, nil] contextual schema path override; when set, raises SchemaRequest
      #   if the option value is 'help' (used for --query whose schema depends on the current command)
      def get_option(option_symbol, mandatory: false, schema: nil)
        Aspera.assert_type(option_symbol, Symbol)
        ensure_parsed
        option = option_def(option_symbol)
        result = option.value
        # Contextual schema: raise SchemaRequest when value is 'help'
        raise SchemaRequest.new(:option, option_symbol.to_s, schema) if schema && result.eql?(SchemaRequest::KEYWORD)
        # Do not fail for manual generation if option mandatory but not set
        return :skip_missing_mandatory if result.nil? && mandatory && !@fail_on_missing_mandatory
        if result.nil?
          if !@ask_missing_mandatory
            Aspera.assert(!mandatory, type: Cli::BadArgument) { "Missing mandatory option: #{option_symbol}" }
          elsif @ask_missing_optional || mandatory
            result = get_interactive(option_symbol.to_s, accept_list: option.values, schema: option.schema)
            set_option(option_symbol, result, source: :interactive)
          end
        end
        result
      end

      # Set an option value by name: store value and call the `on_set` callback
      # String is given to extended value
      # @param option_symbol [Symbol] option name
      # @param value  [String] Value to set
      # @param source [Symbol] `OptionSource` of value
      def set_option(option_symbol, value, source: :code, warn_deprecation: true)
        Aspera.assert_type(option_symbol, Symbol)
        option_def(option_symbol).assign_value(value, source: source, warn_deprecation: warn_deprecation)
      end

      # Set option to `nil`
      # @param option_symbol [Symbol] option name
      # @return [nil]
      def clear_option(option_symbol)
        Aspera.assert_type(option_symbol, Symbol)
        option_def(option_symbol).clear
      end

      # Bind (or re-bind) an `on_set` callback to an already-declared option, for a target object created after declaration.
      # The callback is called with the current value, if any.
      # @param option_symbol [Symbol] name of the already-declared option
      # @param callback      [#call]  called with the new value each time the value is set (e.g. a `Method`)
      # @return [nil]
      def on_set(option_symbol, callback)
        Aspera.assert_type(option_symbol, Symbol)
        option_def(option_symbol).bind_on_set(callback)
      end

      # Adds each of the keys of specified hash as an option.
      # Values are applied by the next parse, and never override a value from env or command line.
      # @param preset_hash [Hash]    Options to add
      # @param where       [String]  Where the value comes from (for logs)
      # @param override    [Boolean] `false` for plugin default presets: lower priority than other presets
      def add_option_preset(preset_hash, where, override: true)
        Aspera.assert_type(preset_hash, Hash)
        Log.log.debug { "add_option_preset: #{preset_hash}, #{where}, #{override}" }
        source = override ? :preset : :plugin_preset
        preset_hash.each do |k, v|
          # Ignore comment/meta keys (e.g. _comment, _description)
          next if k.to_s.start_with?(PresetManager::Key::META_PREFIX)
          add_pending_value(k.to_sym, v, source, replace: override)
        end
        @parse_needed = true
      end

      # Allows a plugin to add an argument as next argument to process
      # @param argument [String] argument value to prepend
      # @return [nil]
      def unshift_next_argument(argument)
        @command_line.unshift_argument(argument)
        nil
      end

      # Check if there are no pending positional arguments
      # @return [Boolean] true if no pending positional arguments
      def command_or_arg_empty?
        ensure_parsed
        @command_line.pending_arguments.empty?
      end

      # Check for unprocessed options or arguments error messages
      # @return [Array<String>] list of error messages for unprocessed tokens
      def final_errors
        begin
          ensure_parsed
        rescue StandardError => e
          # already in error processing: report only unprocessed tokens
          Log.log.debug { "final parse: #{e}" }
        end
        result = []
        result.push("unprocessed options: #{@command_line.pending_options}") unless @command_line.pending_options.empty?
        result.push("unprocessed values: #{@command_line.pending_arguments}") unless @command_line.pending_arguments.empty?
        result
      end

      # Get all long options with a value from command line, used to generate a config in config file.
      # They are marked as processed.
      # @return [Hash] options with value, dotted notation expanded
      def unprocessed_options_with_value
        ensure_parsed
        result = {}
        @command_line.each_long_option_with_value do |tok|
          path = [tok.name, *tok.dot_path]
          Log.log.debug { "option #{path.join(DotContainer::SEPARATOR)}=#{tok.value}" }
          DotContainer.dotted_to_container(path, Parser.smart_convert(tok.value), result)
        end
        result
      end

      # @param only_defined [Boolean] if true, only return options that were defined
      # @return [Hash] options as taken from config file and command line just before command execution
      def known_options(only_defined: false)
        result = {}
        @registry.options.each_key do |option_symbol|
          v = get_option(option_symbol)
          result[option_symbol] = v unless only_defined && v.nil?
        rescue => e
          result[option_symbol] = e.to_s
        end
        result
      end

      # Apply values of options declared so far: from presets, env vars and command line.
      # Can be called any number of times: tokens of options not declared yet are kept for a later call.
      # Called automatically on read of option or argument, but must be called explicitly
      # when values set by `on_set` callbacks are used.
      def parse_options!
        Log.log.trace1('parse_options!'.red)
        @parse_needed = false
        apply_pending_values
        @command_line.pending_option_tokens.each { |tok| apply_option_token(tok) }
        # Presets loaded by a command line option (e.g. `-P`)
        apply_pending_values
        Log.log.trace1 { "unprocessed options: #{@command_line.pending_options}" }
      end

      # Prompt user for missing option or argument, or raise if not interactive
      # @param descr        [String] option name, or argument description
      # @param multiple     [Boolean, String] `true` if multiple values expected
      # @param accept_list  [Array<Symbol>, nil] List of expected values
      # @param aliases      [Hash, nil] aliases of values, for error message
      # @param schema       [String, nil] schema of value, for error message
      # @return [String] user input
      def get_interactive(descr, multiple: false, accept_list: nil, aliases: nil, schema: nil)
        option = @registry.options[descr.to_sym]
        default_prompt = "#{option ? 'option' : 'argument'}: #{descr}"
        if !@ask_missing_mandatory
          message = "Missing #{default_prompt}"
          message = self.class.multi_choice_assert_msg(message, accept_list, aliases: aliases) if accept_list
          message += "\n#{TerminalFormatter.hint}Give `#{SchemaRequest::KEYWORD}` as argument to retrieve the schema of the missing argument." if schema
          raise Cli::MissingArgument, message
        end
        # Ask interactively
        result = []
        puts(' (one per line, end with empty line)') if multiple
        loop do
          prompt = default_prompt
          prompt = "#{accept_list.join(' ')}\n#{default_prompt}" if accept_list
          entry = prompt_user_input(prompt, sensitive: option&.sensitive)
          break if entry.empty? && multiple
          entry = ExtendedValue.instance.evaluate(entry, context: 'interactive input')
          entry = self.class.get_from_list(entry, descr, accept_list) if accept_list
          return entry unless multiple
          result.push(entry)
        end
        result
      end

      # Read remaining args and build an `Array` or `Hash`
      # When used in an option value, only positional arguments after the option are used.
      # @param end_marker [String] Argument to `@:` extended value
      # @return [Hash, Array] Object representing dot-path values
      def args_as_extended(end_marker)
        end_marker = SpecialValues::EOA if end_marker.empty?
        result = nil
        @command_line.with_arguments_after_current_option do
          get_next_argument('args', multiple: end_marker).each do |argument|
            Aspera.assert(argument.include?(Option::VALUE_SEP)) { "Positional argument: #{argument} does not include #{Option::VALUE_SEP}" }
            path, value = argument.split(Option::VALUE_SEP, 2)
            result = DotContainer.dotted_to_container(path.split(DotContainer::SEPARATOR), Parser.smart_convert(value), result)
          end
        end
        result
      end

      # Generate help text for all declared options, grouped by section.
      # @param banner [String, nil] Optional banner text to prepend
      # @return [String] Formatted help text
      def help_text(banner: nil)
        rows = []
        current_group = nil
        @registry.options.each do |sym, opt|
          if opt.group != current_group
            current_group = opt.group
            rows << [{value: "OPTIONS: #{current_group}", colspan: 2}]
          end
          short_part = opt.short ? "-#{opt.short}, " : '    '
          flag = "#{short_part}#{symbol_to_option(sym, option_display_value(opt))}"
          desc = opt.deprecation ? "#{opt.description} (#{opt.deprecation})" : opt.description
          rows << [flag, desc]
        end
        table = Terminal::Table.new(rows: rows, style: {border: HELP_BORDER, padding_left: 0, padding_right: 2})
        banner.nil? ? table.to_s : "#{banner}\n#{table}"
      end

      # ======================================================
      private

      # AsciiBorder with all visible characters removed - used by help_text
      HELP_BORDER = Terminal::Table::AsciiBorder.new.tap do |b|
        b.top = false
        b.bottom = false
        b.left = false
        b.right = false
        b.remove_verticals
        b.remove_horizontals
      end.freeze

      # Parse if options were declared or presets added since last parse
      def ensure_parsed
        parse_options! if @parse_needed
      end

      # Add a type to the message if not special types
      # @param types [Array<Class>] types to add
      # @return [String] Types if relevant
      def add_types_info(types)
        return '' if !types || types.empty? || types.eql?(Type::ENUM) || types.eql?(Type::BOOLEAN) || types.eql?(Type::STRING)
        " (#{types.map(&:name).join(', ')})"
      end

      # Consume and evaluate positional arguments
      # @return [Object, Array] one value, or list if `multiple`
      def read_arguments(descr, multiple:, validation:, accept_list:, aliases:)
        values = @command_line.shift_arguments(multiple)
        values = values.map { |v| ExtendedValue.instance.evaluate(v, context: "argument: #{descr}", allowed: validation) }
        # If expecting list and only one arg of type array : it is the list
        values = values.first if multiple && values.length.eql?(1) && values.first.is_a?(Array)
        if accept_list
          allowed_values = accept_list + (aliases&.keys || [])
          values = values.map { |v| self.class.get_from_list(v, descr, allowed_values) }
        end
        multiple ? values : values.first
      end

      # Convert argument to expected type, when unambiguous
      # @param value      [Object] argument value
      # @param validation [Array<Class>, nil] accepted types
      # @return [Object] converted value
      def convert_argument(value, validation)
        # if value comes from JSON/YAML, it may come as Integer
        return value.to_s if value.is_a?(Integer) && validation.eql?(Type::STRING)
        return value unless value.is_a?(String) && validation.eql?(Type::INTEGER)
        Integer(value, exception: false).tap { |i| raise Cli::BadArgument, "Invalid integer: #{value}" if i.nil? }
      end

      # Validate a single argument value.
      # @param value      [Object]        the value to validate
      # @param validation [Array<Class>]  accepted types
      # @param descr      [String]        argument description (for error messages)
      # @param schema     [String, nil]   schema path for SchemaRequest and validation
      # @raise [SchemaRequest] when the value is 'help' and validation includes Hash.
      # @raise [BadArgument] when the value's type is not in the validation list.
      # @raise [BadArgument] when the value does not match its schema.
      def validate_argument(value, validation:, descr:, schema:)
        raise SchemaRequest.new(:argument, descr, schema) if validation.include?(Hash) && value.eql?(SchemaRequest::KEYWORD)
        raise BadArgument,
          "Argument #{descr} is a #{value.class} but must be #{'one of: ' if validation.length > 1}#{validation.map(&:name).join(', ')}" \
          unless validation.any? { |t| value.is_a?(t) }
        errors = Schema::Validator.instance.errors(value, schema) if schema && (value.is_a?(Hash) || value.is_a?(Array))
        raise BadArgument, "Argument #{descr}: #{errors.join('; ')} (give `#{SchemaRequest::KEYWORD}` as argument for schema)" unless errors.nil? || errors.empty?
      end

      # @param opt [OptionValue] option descriptor
      # @return [String, nil] placeholder shown in flag column, or nil for flags
      def option_display_value(opt)
        case opt.kind
        when :flag    then nil
        when :boolean then 'yes|no'
        when :integer then 'INT'
        when :enum
          opt.values&.any? && opt.values.length <= 4 ? opt.values.join('|') : 'ENUM'
        else
          if opt.types&.include?(Hash) || !opt.schema.nil?
            'HASH'
          elsif opt.types&.include?(Array)
            'LIST'
          else
            'VALUE'
          end
        end
      end

      # Apply a command line option token if its option is declared, else keep it for later.
      # @param tok [Option] option token
      def apply_option_token(tok)
        return if tok.consumed
        option = tok.short_char ? @registry.by_short(tok.short_char) : resolve_long_name(tok)
        return if option.nil?
        if option.flag?
          flags = flag_options(tok, option)
          return if flags.nil?
          @command_line.consume(tok, takes_value: false)
          flags.each { |f| f.block.call }
        else
          value = @command_line.consume(tok, takes_value: true)
          @command_line.with_current_option(tok) do
            if tok.dot_path.nil?
              option.assign_value(value, source: :cmdline)
            else
              # Fill a copy of the current value: the current value is not modified in place (`on_set` callback already received it),
              # and the result is complete (e.g. `--opt.0=a --opt.1=b`): not merged again
              current = copy_containers(option.value(log: false))
              value = DotContainer.dotted_to_container(tok.dot_path, Parser.smart_convert(value), current)
              option.assign_value(value, source: :cmdline, merge: false)
            end
          end
        end
      end

      # Copy nested `Hash` and `Array` containers, keep other values as-is (e.g. a `Proc` cannot be marshalled)
      # @param value [Object] value to copy
      # @return [Object] copy
      def copy_containers(value)
        case value
        when Hash then value.transform_values { |v| copy_containers(v) }
        when Array then value.map { |v| copy_containers(v) }
        else value
        end
      end

      # Flags to execute for a flag token: `--help`, `-h`, or combined `-hN`
      # @param tok    [Option]      flag token
      # @param option [OptionValue] declared flag option
      # @return [Array<OptionValue>, nil] flags, or `nil` if combined flags are not all declared yet
      # @raise [BadArgument] if a value is given
      def flag_options(tok, option)
        if tok.short_char.nil?
          Aspera.assert(!tok.inline? && tok.dot_path.nil?, type: BadArgument) { "Option #{self.class.option_name_to_line(option.option)} does not take a value" }
          return [option]
        end
        flags = [option, *tok.inline_value.to_s.chars.map { |c| @registry.by_short(c) }]
        return if flags.any?(&:nil?)
        Aspera.assert(flags.all?(&:flag?), type: BadArgument) { "Option -#{tok.short_char} does not take a value: #{tok.raw}" }
        flags
      end

      # Resolve long option name: exact match, or unique abbreviation (recorded on token).
      # @param tok [Option] long option token
      # @return [OptionValue, nil] declared option, or `nil` if not declared yet
      # @raise [BadArgument] if abbreviation is ambiguous
      def resolve_long_name(tok)
        # No abbreviation with dotted notation
        option = @registry.by_long(tok.name, allow_abbreviation: tok.dot_path.nil?)
        tok.abbreviation_of = option.option if !option.nil? && !option.option.to_s.eql?(tok.name)
        option
      end

      # Generate command line option string from option symbol
      # @param symbol  [Symbol]      option name
      # @param opt_val [String, nil] optional value placeholder
      # @return [String] formatted option string (e.g. "--option=VALUE")
      def symbol_to_option(symbol, opt_val = nil)
        result = self.class.option_name_to_line(symbol)
        opt_val.nil? ? result : "#{result}#{Option::VALUE_SEP}#{opt_val}"
      end

      # Keep value from preset or env until option is declared
      # @param option_symbol [Symbol]  option name
      # @param value         [Object]  value
      # @param source        [Symbol]  `OptionSource`
      # @param replace       [Boolean] replace a pending value from same source
      def add_pending_value(option_symbol, value, source, replace:)
        entries = (@pending_values[option_symbol] ||= [])
        index = entries.index { |e| e[:source].eql?(source) }
        if index.nil?
          entries.push({value: value, source: source})
        elsif replace
          entries[index] = {value: value, source: source}
        end
      end

      # Apply pending values (presets, env) of declared options, lowest priority first
      def apply_pending_values
        ready = @pending_values.select { |k, _| @registry.declared?(k) }
        ready.each_key { |k| @pending_values.delete(k) }
        ready.each do |option_symbol, entries|
          entries.sort_by { |e| OptionSource.priority(e[:source]) }.each do |e|
            set_option(option_symbol, e[:value], source: e[:source])
          end
        end
      end

      # Percent selector: select by this field for this value
      REGEX_LOOKUP_ID_BY_FIELD = /^%([^:]+):(.*)$/

      private_constant :REGEX_LOOKUP_ID_BY_FIELD, :HELP_BORDER
    end
  end
end
