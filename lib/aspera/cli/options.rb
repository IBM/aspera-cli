# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/error'
require 'aspera/cli/terminal_formatter'
require 'aspera/colors'
require 'aspera/secret_hider'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/dot_container'
require 'aspera/schema/registry'
require 'io/console'
require 'terminal-table'

module Aspera
  module Cli
    # Exception raised when schema is asked (`help`)
    class SchemaRequest < Error
      # @return [String, nil] path to schema file
      attr_reader :path

      # @param type [Symbol] :argument or :option
      # @param name [String] name of the option/argument
      # @param schema_path [String, nil] path to schema file, or `nil` if not available
      def initialize(type, name, schema_path)
        super("#{type}: #{name}")
        @path = schema_path
      end
    end

    module BoolValue
      # boolean options are set to true/false from the following values
      YES_SYM = :yes
      NO_SYM = :no
      FALSE_VALUES = [NO_SYM, false].freeze
      TRUE_VALUES = [YES_SYM, true].freeze
      private_constant :YES_SYM, :NO_SYM, :FALSE_VALUES, :TRUE_VALUES
      # Boolean values
      # @return [Array<true, false, :yes, :no>]
      ALL = (TRUE_VALUES + FALSE_VALUES).freeze
      # `false` and `true`
      TYPES = [FalseClass, TrueClass].freeze
      SYMBOLS = [NO_SYM, YES_SYM].freeze
      # @return [Boolean] `true` if value is a value for `true` in ALL
      def true?(enum)
        Aspera.assert_values(enum, ALL){'boolean'}
        TRUE_VALUES.include?(enum)
      end

      # @return [:yes, :no]
      def to_sym(enum)
        Aspera.assert_values(enum, ALL){'boolean'}
        TRUE_VALUES.include?(enum) ? YES_SYM : NO_SYM
      end

      # @return [Boolean] `true` if value is a value for `true` or `false` in ALL
      def symbol?(sym)
        ALL.include?(sym)
      end
      module_function :true?, :to_sym, :symbol?
    end

    # Constants to be used as parameter `allowed:` for `OptionValue`
    module Allowed
      # This option can be set to a single string or array, multiple times, and gives Array of String
      TYPES_STRING_ARRAY = [Array, String].freeze
      # A list of symbols with constrained values
      TYPES_SYMBOL_ARRAY = [Array, Symbol].freeze
      # Value will be coerced to int
      TYPES_INTEGER = [Integer].freeze
      TYPES_BOOLEAN = BoolValue::TYPES
      # No value at all for the option, it's a switch, like `-N`
      TYPES_NONE = [].freeze
      # Symbol
      TYPES_ENUM = [Symbol].freeze
      # String
      TYPES_STRING = [String].freeze
    end

    # Description of option, how to manage
    class OptionValue
      # [Array(Class)] List of allowed types
      attr_reader :types, :sensitive, :schema, :option
      # [Array] List of allowed values (Symbols and specific values)
      attr_accessor :values
      # [String] Help section group name (set by Options#group)
      attr_accessor :group
      # [Proc, nil] Block to call for flag options (TYPES_NONE)
      attr_accessor :block

      # @param option [Symbol] Name of option
      # @param description [String, nil] Description for help; if nil, derived from schema
      # @param allowed [nil,Class,Array<Class>,Array<Symbol>] Allowed values
      # @param handler [Hash, nil] Accessor: keys: :o(object) and :m(method); nil for local storage
      # @param deprecation [String] Deprecation message
      # @param schema [String] Declaration of schema
      # `allowed`:
      # - `nil` No validation, so just a string
      # - `Class` The single allowed Class
      # - `Array<Class>` Multiple allowed classes
      # - `Array<Symbol>` List of allowed values
      def initialize(option:, description: nil, allowed: Allowed::TYPES_STRING, handler: nil, deprecation: nil, schema: nil)
        Log.log.trace1{"option: #{option}, allowed: #{allowed}"}
        @option = option
        @description = description
        @group = nil
        @block = nil
        # by default passwords and secrets are sensitive, else specify when declaring the option
        @sensitive = SecretHider.instance.secret?(@option, '')
        @deprecation = deprecation
        @schema = schema
        # Start with local storage; bind_handler wires the delegation if a handler is given.
        @object = nil
        @read_method = nil
        @write_method = nil
        @access = :local
        bind_handler(handler) unless handler.nil?
        @types = nil
        @values = nil
        if !allowed.nil?
          allowed = [allowed] if allowed.is_a?(Class)
          Aspera.assert_type(allowed, Array)
          if allowed.take(Allowed::TYPES_SYMBOL_ARRAY.length) == Allowed::TYPES_SYMBOL_ARRAY
            # Special case: array of defined symbol values
            @types = Allowed::TYPES_SYMBOL_ARRAY
            @values = allowed[Allowed::TYPES_SYMBOL_ARRAY.length..]
            # Default value for symbol array when no value has been set yet
            assign_value([], where: 'array default', warn_deprecation: false) if value(log: false).nil?
          elsif allowed.all?(Class)
            @types = allowed
            @values = BoolValue::ALL if allowed.eql?(Allowed::TYPES_BOOLEAN)
            # Default value for array/hash when no value has been set yet
            if @types.first.eql?(Array) && !@types.include?(NilClass) && value(log: false).nil?
              assign_value([], where: 'array default', warn_deprecation: false)
            elsif @types.first.eql?(Hash) && !@types.include?(NilClass) && value(log: false).nil?
              assign_value({}, where: 'hash default', warn_deprecation: false)
            end
          elsif allowed.all?(Symbol)
            @types = Allowed::TYPES_ENUM
            @values = allowed
          else
            Aspera.error_unexpected_value(allowed)
          end
        end
        Log.log.trace1{"declare: #{@option}: #{@access} #{@object.class}.#{@read_method}".green}
      end

      # Wire (or re-wire) the getter/setter delegation for this option.
      # Safe to call after construction — used by Options#set_handler to bind a composed
      # instance variable that did not exist at class-load time (Category C handlers).
      # @param handler [Hash] Accessor hash with keys :o (object) and :m (method symbol)
      # @return [void]
      def bind_handler(handler)
        Aspera.assert_type(handler, Hash){'handler'}
        # Capture any value already stored locally before switching to delegated storage.
        # This transfers defaults (and any preset values already applied) to the new target.
        pending_value = @access.eql?(:local) ? @object : nil
        @object       = handler[:o]
        @read_method  = handler[:m]
        @write_method = "#{@read_method}=".to_sym
        @access = if @object.respond_to?(@write_method)
          :write
        else
          :setter
        end
        Aspera.assert(@object.respond_to?(@read_method)){"#{@object} does not respond to #{@read_method}"}
        Log.log.trace1{"bind_handler: #{@option}: #{@access} #{@object.class}.#{@read_method}".green}
        # Push the pending local value to the new target if one was stored
        assign_value(pending_value, where: 'bind_handler', warn_deprecation: false) unless pending_value.nil?
      end

      # @return [String] description of the option: explicit one, or first line of schema description
      def description
        return @description unless @description.nil?
        return if @schema.nil?
        schema_node = Schema::Registry.instance.reader(@schema).current
        first_line = (schema_node['title'] || schema_node['description'].to_s).lines.first.to_s.strip
        first_line.end_with?('.') ? first_line[0..-2] : first_line
      end

      def clear
        @object = nil
      end

      def value(log: true)
        current_value =
          case @access
          when :local then @object
          when :write then @object.send(@read_method)
          when :setter then @object.send(@read_method, @option, :get)
          end
        Log.log.trace1{"#{@option} -> (#{current_value.class})#{current_value}"} if log
        current_value
      end

      # Assign value to option.
      # Value can be a `String`, then evaluated with `ExtendedValue`, or directly a value.
      # @param value [String, Object] Value to assign to option
      # @param where [String] Where the value is assigned from
      # @param warn_deprecation [Boolean] Emit deprecation warning (false for internal transfers)
      # @return [nil]
      def assign_value(value, where:, warn_deprecation: true)
        Aspera.assert(!@deprecation, type: :warn){"Option #{@option} is deprecated: #{@deprecation}"} if warn_deprecation
        new_value = ExtendedValue.instance.evaluate(value, context: "option: #{@option}", allowed: @types)
        Log.log.trace1{"#{where}: #{@option} <- (#{new_value.class})#{new_value}"}
        new_value = BoolValue.true?(new_value) if @types.eql?(Allowed::TYPES_BOOLEAN)
        new_value = Integer(new_value) if @types.eql?(Allowed::TYPES_INTEGER)
        new_value = [new_value] if @types.eql?(Allowed::TYPES_STRING_ARRAY) && new_value.is_a?(String)
        # Setting a Hash to null set an empty hash
        new_value = {} if new_value.eql?(nil) && @types&.first.eql?(Hash)
        # Setting a Array to null set an empty array
        new_value = [] if new_value.eql?(nil) && @types&.first.eql?(Array)
        if @types.eql?(Aspera::Cli::Allowed::TYPES_SYMBOL_ARRAY)
          new_value = [new_value] if new_value.is_a?(String)
          Aspera.assert_array_all(new_value, String, type: BadArgument)
          new_value = new_value.map{ |v| Options.get_from_list(v, @option, @values)}
        end
        Aspera.assert_type(new_value, *@types, type: BadArgument){"Option #{@option}"} if @types
        if new_value.is_a?(Hash) || new_value.is_a?(Array)
          current_value = value(log: false)
          new_value = current_value.deep_merge(new_value) if new_value.is_a?(Hash) && current_value.is_a?(Hash) && !current_value.empty?
          new_value = current_value + new_value if new_value.is_a?(Array) && current_value.is_a?(Array) && !current_value.empty?
        end
        case @access
        when :local then @object = new_value
        when :write then @object.send(@write_method, new_value)
        when :setter then @object.send(@read_method, @option, :set, new_value)
        end
        Log.log.trace1{v = value(log: false); "#{@option} <- (#{v.class})#{v}"} # rubocop:disable Style/Semicolon
        nil
      end
    end

    # parse command line options
    # arguments options start with '-', others are commands
    # resolves on extended value syntax
    class Options
      class << self
        # Find shortened string value in allowed symbol list
        def get_from_list(short_value, descr, allowed_values)
          Aspera.assert_type(short_value, String)
          # we accept shortcuts
          matching_exact = allowed_values.select{ |i| i.to_s.eql?(short_value)}
          return matching_exact.first if matching_exact.length == 1
          matching = allowed_values.select{ |i| i.to_s.start_with?(short_value)}
          Aspera.assert(!matching.empty?, multi_choice_assert_msg("unknown value for #{descr}: #{short_value}", allowed_values), type: BadArgument)
          Aspera.assert(matching.length.eql?(1), multi_choice_assert_msg("ambiguous shortcut for #{descr}: #{short_value}", matching), type: BadArgument)
          return BoolValue.true?(matching.first) if allowed_values.eql?(BoolValue::ALL)
          matching.first
        end

        # Generates error message with list of allowed values
        # @param error_msg [String] Error message
        # @param accept_list [Array<Symbol>] List of allowed values
        def multi_choice_assert_msg(error_msg, accept_list)
          [error_msg, 'Use:', *accept_list.map{ |choice| "- #{choice}"}.sort].join("\n")
        end

        # Change option name with dash to name with underscore
        # @param name [String] option name with dash separators
        # @return [String] option name with underscore separators
        def option_line_to_name(name)
          name.gsub(OPTION_SEP_LINE, OPTION_SEP_SYMBOL)
        end

        def option_name_to_line(name)
          "#{OPTION_PREFIX}#{name.to_s.gsub(OPTION_SEP_SYMBOL, OPTION_SEP_LINE)}"
        end

        # @return [Hash{Symbol => String}, nil] `{field:,value:}` if identifier is a percent selector, else `nil`
        def percent_selector(identifier)
          Aspera.assert_type(identifier, String)
          if (m = identifier.match(REGEX_LOOKUP_ID_BY_FIELD))
            return {field: m[1], value: ExtendedValue.instance.evaluate(m[2], context: "percent selector: #{m[1]}")}
          end
          nil
        end
      end

      attr_accessor :ask_missing_mandatory, :ask_missing_optional, :help_requested
      attr_writer :fail_on_missing_mandatory

      # @param program_name [String] Name of the program
      # @param argv [Array<String>, nil] Command line arguments to parse
      def initialize(program_name, argv = nil)
        # command line values *not* starting with '-'
        @unprocessed_cmd_line_arguments = []
        # command line values starting with at least one '-'
        @unprocessed_cmd_line_options = []
        # a copy of all initial options
        @initial_cli_options = []
        # Option descriptions: maps option symbol to its OptionValue descriptor
        # @type [Hash{Symbol => OptionValue}]
        @declared_options = {}
        # do we ask missing options and arguments to user ?
        @ask_missing_mandatory = false # STDIN.isatty
        # ask optional options if not provided and in interactive
        @ask_missing_optional = false
        # get_option fails if a mandatory parameter is asked
        @fail_on_missing_mandatory = true
        # set to true when --help / -h is parsed
        @help_requested = false
        # Array of [key(sym), value]
        # those must be set before parse
        # parse consumes those defined only
        @option_pairs_batch = {}
        @option_pairs_env = {}
        # Short option char -> option symbol, e.g. {'h' => :help, 'v' => :version}
        @short_options = {}
        # Current help section group name, set by #group
        @current_group = 'global'
        # options can also be provided by env vars : --param-name -> ASCLI_PARAM_NAME
        env_prefix = program_name.upcase + OPTION_SEP_SYMBOL
        ENV.each do |k, v|
          @option_pairs_env[k.delete_prefix(env_prefix).downcase.to_sym] = v if k.start_with?(env_prefix)
        end
        Log.log.debug{"env=#{@option_pairs_env}".red}
        @unprocessed_cmd_line_options = []
        @unprocessed_cmd_line_arguments = []
        # For each option string: list (one entry per occurrence) of the number of positional args
        # that appear before it in original argv. Used by `@:` in option values to skip preceding args.
        # @type [Hash{String => Array<Integer>}]
        @args_before_option = {}
        return if argv.nil?
        # true until `--` is found (stop options)
        process_options = true
        arg_count = 0
        argv.each do |value|
          if process_options && value.start_with?('-')
            Log.log.trace1{"opt: #{value}"}
            if value.eql?(OPTIONS_STOP)
              process_options = false
            else
              @unprocessed_cmd_line_options.push(value)
              (@args_before_option[value] ||= []).push(arg_count)
            end
          else
            Log.log.trace1{"arg: #{value}"}
            @unprocessed_cmd_line_arguments.push(value)
            arg_count += 1
          end
        end
        # Total positional args at parse time — used in args_as_extended to compute how many to skip.
        @arg_total_count = @unprocessed_cmd_line_arguments.length
        # Number of original positional args before the option currently being parsed (nil = positional context).
        @current_option_args_offset = nil
        @initial_cli_options = @unprocessed_cmd_line_options.dup.freeze
        Log.log.trace1{"add_cmd_line_options:commands/arguments=#{@unprocessed_cmd_line_arguments},options=#{@unprocessed_cmd_line_options}".red}
        declare(:interactive, 'Use interactive input of missing params', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :ask_missing_mandatory})
        declare(:ask_options, 'Ask even optional options', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :ask_missing_optional})
        # do not parse options yet, let's wait for option `-h` to be overridden
      end

      # Add a type to the message if not special types
      # @param types [Array<Class>] types to add
      # @return [String] Types if relevant
      def add_types_info(types)
        return '' if !types || types.empty? || types.eql?(Allowed::TYPES_ENUM) || types.eql?(Allowed::TYPES_BOOLEAN) || types.eql?(Allowed::TYPES_STRING)
        " (#{types.map(&:name).join(', ')})"
      end

      # Declare an option
      # @param option_symbol [Symbol] option name
      # @param description   [String, nil] description for help; if nil, derived from schema
      # @param short         [String] short option name
      # @param allowed       [Object] Allowed values, see `OptionValue`
      # @param default       [Object] default value
      # @param handler       [Hash]   handler for option value: keys: :o(object) and :m(method)
      # @param deprecation   [String] deprecation
      # @param schema        [String] Definition of schema for Hash parameters
      # @param block [Proc] Block to execute when option is found
      def declare(option_symbol, description = nil, short: nil, allowed: nil, default: nil, handler: nil, deprecation: nil, schema: nil, &block)
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(!@declared_options.key?(option_symbol)){"#{option_symbol} already declared"}
        Aspera.assert_type(handler, Hash) if handler
        Aspera.assert(handler.keys.sort.eql?(%i[m o]), 'handler must have keys :m and :o') if handler
        option_attrs = @declared_options[option_symbol] = OptionValue.new(
          option:      option_symbol,
          description: description,
          allowed:     allowed,
          handler:     handler,
          deprecation: deprecation,
          schema:      schema
        )
        option_attrs.group = @current_group
        description = option_attrs.description
        Aspera.assert(!description.nil?){"#{option_symbol}: no description and no schema to derive one from"}
        Aspera.assert(description[-1] != '.'){"#{option_symbol} ends with dot"}
        Aspera.assert(description[0] == description[0].upcase){"#{option_symbol} description does not start with an uppercase"}
        Aspera.assert(!['hash', 'extended value'].any?{ |s| description.downcase.include?(s)}){"#{option_symbol} shall use :allowed instead of hash/extended value in option description"}
        set_option(option_symbol, default, where: 'default') unless default.nil?
        case option_attrs.types
        when Allowed::TYPES_ENUM, Allowed::TYPES_BOOLEAN
          # This option value must be a symbol (or array of symbols)
          set_option(option_symbol, BoolValue.true?(default), where: 'default') if option_attrs.values.eql?(BoolValue::ALL) && !default.nil?
        when Allowed::TYPES_NONE
          Aspera.assert_type(block, Proc){"missing execution block for #{option_symbol}"}
          option_attrs.block = block
        end
        @short_options[short] = option_symbol unless short.nil?
        Log.log.trace1{"declare: #{option_symbol}, group: #{@current_group}, short: #{short}"}
      end

      # Set the current help section group name for subsequent declarations
      # @param name [String] group name, shown as section header in help text
      def group(name)
        @current_group = name
      end

      # Rename all options currently tagged with @current_group to a new name,
      # then update @current_group. Used by add_manual_header when a plugin
      # declares its options before its group name is known (e.g. Plugins::Config).
      # @param name [String] new group name
      def rename_current_group(name)
        @declared_options.each_value{ |opt| opt.group = name if opt.group.eql?(@current_group)}
        @current_group = name
      end

      # @param descr       [String] description for help
      # @param mandatory   [Boolean] `true`: raise error no more argument
      # @param multiple    [Boolean] `true`: return all remaining arguments (Array). String: until marker
      # @param accept_list [Array<Symbol>, NilClass] list of allowed values
      # @param validation  [Class, Array, NilClass] Accepted value type(s) or list of Symbols
      # @param aliases     [Hash] map of aliases: key = alias, value = real value
      # @param default     [Object] default value
      # @return [Object, Array, nil] one value, list or nil (if optional and no default)
      def get_next_argument(descr, mandatory: true, multiple: false, accept_list: nil, validation: Allowed::TYPES_STRING, aliases: nil, default: nil, schema: nil)
        Aspera.assert_array_all(accept_list, Symbol) unless accept_list.nil?
        Aspera.assert_hash_all(aliases, Symbol, Symbol) unless aliases.nil?
        validation = Symbol unless accept_list.nil?
        validation = [validation] unless validation.is_a?(Array) || validation.nil?
        Aspera.assert_array_all(validation, Class){'validation'} unless validation.nil?
        descr = "#{descr}#{add_types_info(validation)}"
        result =
          if !@unprocessed_cmd_line_arguments.empty?
            case multiple
            when true
              values = @unprocessed_cmd_line_arguments.shift(@unprocessed_cmd_line_arguments.length)
            when false
              values = [@unprocessed_cmd_line_arguments.shift]
            when String
              index = @unprocessed_cmd_line_arguments.index(multiple)
              if index
                values = @unprocessed_cmd_line_arguments.shift(index)
                @unprocessed_cmd_line_arguments.shift # remove end marker
              else
                values = @unprocessed_cmd_line_arguments.shift(@unprocessed_cmd_line_arguments.length)
              end
            else Aspera.error_unexpected_value(multiple){'multiple'}
            end
            values = values.map{ |v| ExtendedValue.instance.evaluate(v, context: "argument: #{descr}", allowed: validation)}
            # If expecting list and only one arg of type array : it is the list
            values = values.first if multiple && values.length.eql?(1) && values.first.is_a?(Array)
            if accept_list
              allowed_values = [].concat(accept_list)
              allowed_values.concat(aliases.keys) unless aliases.nil?
              values = values.map{ |v| self.class.get_from_list(v, descr, allowed_values)}
            end
            multiple ? values : values.first
          elsif !default.nil? then default
            # no value provided, either get value interactively, or exception
          elsif mandatory then get_interactive(descr, multiple: multiple, accept_list: accept_list, schema: schema)
          end
        if result.is_a?(String) && validation&.eql?(Allowed::TYPES_INTEGER)
          int_result = Integer(result, exception: false)
          raise Cli::BadArgument, "Invalid integer: #{result}" if int_result.nil?
          result = int_result
        end
        Log.log.trace1{"#{descr}=#{result}"}
        result = aliases[result] if aliases&.key?(result)
        # if value comes from JSON/YAML, it may come as Integer
        result = result.to_s if result.is_a?(Integer) && validation&.eql?(Allowed::TYPES_STRING)
        if validation && (mandatory || !result.nil?)
          value_list = multiple ? result : [result]
          value_list.each do |value|
            raise SchemaRequest.new(:argument, descr, schema) if validation.include?(Hash) && value.eql?(HELP)
            raise Cli::BadArgument,
              "Argument #{descr} is a #{value.class} but must be #{'one of: ' if validation.length > 1}#{validation.map(&:name).join(', ')}" unless validation.any?{ |t| value.is_a?(t)}
          end
        end
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
        if res_id.is_a?(String) && (m = Options.percent_selector(res_id))
          Aspera.assert(block_given?, type: Cli::BadArgument){"Percent syntax for #{description} not supported in this context"}
          res_id = yield(m[:field], m[:value])
        end
        res_id
      end

      def get_next_command(command_list, aliases: nil); get_next_argument('command', accept_list: command_list, aliases: aliases); end

      # Check whether an option has already been declared in this manager
      # @param option_symbol [Symbol] name of the option
      # @return [Boolean]
      def option_declared?(option_symbol)
        @declared_options.key?(option_symbol)
      end

      # Get an option definition by name
      # @param option_symbol [Symbol] name of the option
      # @return [OptionValue] Option definition
      # @raise [Cli::BadArgument] if option not found
      def option_def(option_symbol)
        Aspera.assert(@declared_options.key?(option_symbol), type: Cli::BadArgument){"Unknown option: #{option_symbol}"}
        @declared_options[option_symbol]
      end

      # Get an option value by name
      # either return value or calls handler, can return nil
      # ask interactively if requested/required
      # @param option_symbol [Symbol] name of the option to retrieve
      # @param mandatory [Boolean] if true, raise error if option not set
      def get_option(option_symbol, mandatory: false)
        Aspera.assert_type(option_symbol, Symbol)
        option_attrs = option_def(option_symbol)
        result = option_attrs.value
        # Do not fail for manual generation if option mandatory but not set
        return :skip_missing_mandatory if result.nil? && mandatory && !@fail_on_missing_mandatory
        if result.nil?
          if !@ask_missing_mandatory
            Aspera.assert(!mandatory, type: Cli::BadArgument){"Missing mandatory option: #{option_symbol}"}
          elsif @ask_missing_optional || mandatory
            # ask_missing_mandatory
            result = get_interactive(option_symbol.to_s, check_option: true, accept_list: option_attrs.values, schema: option_attrs.schema)
            set_option(option_symbol, result, where: 'interactive')
          end
        end
        result
      end

      # Set an option value by name, either store value or call handler
      # String is given to extended value
      # @param option_symbol [Symbol] option name
      # @param value [String] Value to set
      # @param where [String] Where the value comes from
      def set_option(option_symbol, value, where: 'code override')
        Aspera.assert_type(option_symbol, Symbol)
        option = option_def(option_symbol)
        raise SchemaRequest.new(:option, option.option, option.schema) if option.types&.include?(Hash) && value.eql?(HELP)
        option.assign_value(value, where: where)
      end

      # Set option to `nil`
      def clear_option(option_symbol)
        Aspera.assert_type(option_symbol, Symbol)
        option_def(option_symbol).clear
      end

      # Bind (or re-bind) a runtime handler to an already-declared option.
      # Called from plugin initialize() for Category C handlers whose target object
      # (e.g. @gen_options) is created after class-load time.
      # @param option_symbol [Symbol] name of the already-declared option
      # @param object [Object] the target object for get/set delegation
      # @param method [Symbol] accessor method name on object
      # @return [void]
      def set_handler(option_symbol, object:, method:)
        Aspera.assert_type(option_symbol, Symbol)
        option_def(option_symbol).bind_handler(o: object, m: method)
      end

      # Adds each of the keys of specified hash as an option
      # @param preset_hash [Hash]    Options to add
      # @param where       [String]  Where the value comes from
      # @param override    [Boolean] Override if already present
      def add_option_preset(preset_hash, where, override: true)
        Aspera.assert_type(preset_hash, Hash)
        Log.log.debug{"add_option_preset: #{preset_hash}, #{where}, #{override}"}
        preset_hash.each do |k, v|
          option_symbol = k.to_sym
          @option_pairs_batch[option_symbol] = v if override || !@option_pairs_batch.key?(option_symbol)
        end
      end

      # Allows a plugin to add an argument as next argument to process
      def unshift_next_argument(argument)
        @unprocessed_cmd_line_arguments.unshift(argument)
      end

      # Check if there were unprocessed values to generate error
      def command_or_arg_empty?
        @unprocessed_cmd_line_arguments.empty?
      end

      # Unprocessed options or arguments ?
      def final_errors
        result = []
        result.push("unprocessed options: #{@unprocessed_cmd_line_options}") unless @unprocessed_cmd_line_options.empty?
        result.push("unprocessed values: #{@unprocessed_cmd_line_arguments}") unless @unprocessed_cmd_line_arguments.empty?
        result
      end

      # Get all original options on command line used to generate a config in config file
      # @return [Hash] options as taken from config file and command line just before command execution
      def unprocessed_options_with_value
        result = {}
        @initial_cli_options.each do |option_argument|
          # ignore short options
          next unless option_argument.start_with?(OPTION_PREFIX)
          name, value = option_argument.delete_prefix(OPTION_PREFIX).split(OPTION_VALUE_SEPARATOR, 2)
          # ignore options without value
          next if value.nil?
          Log.log.debug{"option #{name}=#{value}"}
          path = name.split(DotContainer::SEPARATOR)
          path[0] = self.class.option_line_to_name(path[0])
          DotContainer.dotted_to_container(path, smart_convert(value), result)
          @unprocessed_cmd_line_options.delete(option_argument)
        end
        result
      end

      # @param only_defined [Boolean] if true, only return options that were defined
      # @return [Hash] options as taken from config file and command line just before command execution
      def known_options(only_defined: false)
        result = {}
        @declared_options.each_key do |option_symbol|
          v = get_option(option_symbol)
          result[option_symbol] = v unless only_defined && v.nil?
        rescue => e
          result[option_symbol] = e.to_s
        end
        result
      end

      # Removes already known options from the list
      def parse_options!
        Log.log.trace1('parse_options!'.red)
        # First options from conf file
        consume_option_pairs(@option_pairs_batch, 'set')
        # Then, env var (to override)
        consume_option_pairs(@option_pairs_env, 'env')
        # Then, command line override: process one option at a time so that @current_option_args_offset
        # can be set before each option is evaluated (used by `@:` extended value in option values).
        unknown_options = []
        Log.log.trace1('Before parse')
        Log.dump(:unprocessed_cmd_line_options, @unprocessed_cmd_line_options, level: :trace1)
        until @unprocessed_cmd_line_options.empty?
          opt = @unprocessed_cmd_line_options.shift
          # Expose args_before for this option so `args_as_extended` can skip args preceding it.
          # Peek (first) without consuming — consumed only if this option is processed (not deferred).
          @current_option_args_offset = @args_before_option[opt]&.first
          if opt.start_with?(OPTION_PREFIX)
            # Long option: --name or --name=value
            name_raw, raw_value = opt.delete_prefix(OPTION_PREFIX).split(OPTION_VALUE_SEPARATOR, 2)
            option_sym = self.class.option_line_to_name(name_raw).to_sym
            if @declared_options.key?(option_sym)
              dispatch_option(option_sym, raw_value)
              @args_before_option[opt]&.shift # consumed: advance to next occurrence
            else
              # Dotted notation: --a.b.c=d does: a={"b":{"c":ext_val(d)}}
              Log.log.trace1{"Unknown long option: #{opt}".red}
              if !raw_value.nil?
                path = name_raw.split(DotContainer::SEPARATOR)
                root_sym = self.class.option_line_to_name(path.shift).to_sym
                if @declared_options.key?(root_sym)
                  set_option(root_sym, DotContainer.dotted_to_container(path, smart_convert(raw_value), get_option(root_sym)), where: 'dotted')
                  @args_before_option[opt]&.shift # consumed: advance to next occurrence
                  next
                end
              end
              # Unknown option: defer to next parse_options! round, do not consume the recorded offset
              unknown_options.push(opt)
            end
          elsif opt.start_with?('-') && (option_sym = @short_options[opt[1]])
            # Short option: -h, -v
            dispatch_option(option_sym, nil)
            @args_before_option[opt]&.shift # consumed: advance to next occurrence
          else
            unknown_options.push(opt)
          end
        end
        @current_option_args_offset = nil
        Log.log.trace1('After parse')
        Log.log.trace1{"remains: #{unknown_options}"}
        # Set unprocessed options for next time
        @unprocessed_cmd_line_options = unknown_options
      end

      def prompt_user_input(prompt, sensitive: false)
        return $stdin.getpass("#{prompt}> ") if sensitive
        print("#{prompt}> ")
        line = $stdin.gets
        Aspera.assert_type(line, String){'Unexpected end of standard input'}
        line.chomp
      end

      # prompt user for input in a list of symbols
      # @param prompt [String] prompt to display
      # @param sym_list [Array] list of symbols to select from
      # @return [Symbol] selected symbol
      def prompt_user_input_in_list(prompt, sym_list)
        loop do
          input = prompt_user_input(prompt).to_sym
          if sym_list.any?{ |a| a.eql?(input)}
            return input
          else
            $stderr.puts("No such #{prompt}: #{input}, select one of: #{sym_list.join(', ')}") # rubocop:disable Style/StderrPuts
          end
        end
      end

      # Prompt user for input in a list of symbols
      # @param descr        [String] description for help
      # @param check_option [Boolean] Check attributes of option with name=descr
      # @param multiple     [Boolean, String] `true` if multiple values expected
      # @param accept_list  [Array<Symbol>,NilClass] List of expected values
      # @return [String] user input
      def get_interactive(descr, check_option: false, multiple: false, accept_list: nil, schema: nil)
        option_attrs = @declared_options[descr.to_sym]
        what = option_attrs ? 'option' : 'argument'
        default_prompt = "#{what}: #{descr}"
        if !@ask_missing_mandatory
          message = "Missing #{default_prompt}"
          message = self.class.multi_choice_assert_msg(message, accept_list) if accept_list
          message += "\n#{TerminalFormatter::HINT}Give `#{HELP}` as argument to retrieve the schema of the missing argument." if schema
          raise Cli::MissingArgument, message
        end
        # ask interactively
        result = []
        puts(' (one per line, end with empty line)') if multiple
        loop do
          prompt = default_prompt
          prompt = "#{accept_list.join(' ')}\n#{default_prompt}" if accept_list
          entry = prompt_user_input(prompt, sensitive: option_attrs&.sensitive)
          break if entry.empty? && multiple
          entry = ExtendedValue.instance.evaluate(entry, context: 'interactive input')
          entry = self.class.get_from_list(entry, descr, accept_list) if accept_list
          return entry unless multiple
          result.push(entry)
        end
        result
      end

      # Read remaining args and build an `Array` or `Hash`
      # @param value [String] Argument to `@:` extended value
      # @return [Hash, Array] Object representing dot-path values
      def args_as_extended(end_marker)
        # This extended value does not take args (`@:`)
        # ExtendedValue.assert_no_value(end_marker, :p)
        end_marker = SpecialValues::EOA if end_marker.empty?
        # When called from an option value, skip positional args that appear before the option in argv.
        # @current_option_args_offset holds the number of original args before the option (nil = positional context).
        # The number to actually skip = args_before_option - args_already_consumed (clamped to 0).
        skip_count = if @current_option_args_offset
          [@current_option_args_offset - (@arg_total_count - @unprocessed_cmd_line_arguments.length), 0].max
        else
          0
        end
        skipped = skip_count.positive? ? @unprocessed_cmd_line_arguments.shift(skip_count) : []
        Log.log.trace1{"args_as_extended: skipping #{skipped.length} args before option: #{skipped}"} unless skipped.empty?
        result = nil
        get_next_argument('args', multiple: end_marker).each do |argument|
          Aspera.assert(argument.include?(OPTION_VALUE_SEPARATOR)){"Positional argument: #{argument} does not include #{OPTION_VALUE_SEPARATOR}"}
          path, value = argument.split(OPTION_VALUE_SEPARATOR, 2)
          result = DotContainer.dotted_to_container(path.split(DotContainer::SEPARATOR), smart_convert(value), result)
        end
        # Restore skipped args so they remain available for command dispatching
        @unprocessed_cmd_line_arguments.unshift(*skipped) unless skipped.empty?
        result
      end

      # Generate help text for all declared options, grouped by section.
      # @param banner [String, nil] Optional banner text to prepend
      # @return [String] Formatted help text
      def help_text(banner: nil)
        rows = []
        current_group = nil
        @declared_options.each do |sym, opt|
          if opt.group != current_group
            current_group = opt.group
            rows << [{value: "OPTIONS: #{current_group}", colspan: 2}]
          end
          short_char = @short_options.key(sym)
          short_part = short_char ? "-#{short_char}, " : '    '
          flag = "#{short_part}#{symbol_to_option(sym, option_display_value(opt))}"
          rows << [flag, opt.description]
        end
        table = Terminal::Table.new(rows: rows, style: {border: HELP_BORDER, padding_left: 0, padding_right: 2})
        banner.nil? ? table.to_s : "#{banner}\n#{table}"
      end

      # ======================================================
      private

      # AsciiBorder with all visible characters removed — used by help_text
      HELP_BORDER = Terminal::Table::AsciiBorder.new.tap do |b|
        b.top = false
        b.bottom = false
        b.left = false
        b.right = false
        b.remove_verticals
        b.remove_horizontals
      end.freeze

      # @param opt [OptionValue] option descriptor
      # @return [String, nil] placeholder shown in flag column: 'ENUM', 'VALUE', or nil for flag switches
      def option_display_value(opt)
        case opt.types
        when Allowed::TYPES_NONE then nil
        when Allowed::TYPES_ENUM, Allowed::TYPES_BOOLEAN then 'ENUM'
        else 'VALUE'
        end
      end

      # Dispatch a parsed CLI option to its handler.
      # @param sym       [Symbol] option symbol
      # @param raw_value [String, nil] raw string value from command line, or nil for flag switches
      def dispatch_option(sym, raw_value)
        opt = @declared_options[sym]
        case opt.types
        when Allowed::TYPES_NONE
          opt.block.call
        when Allowed::TYPES_ENUM, Allowed::TYPES_BOOLEAN
          set_option(sym, self.class.get_from_list(raw_value.to_s, opt.description, opt.values), where: SOURCE_USER)
        else
          raw_value = Integer(raw_value) if opt.types.eql?(Allowed::TYPES_INTEGER)
          set_option(sym, raw_value, where: SOURCE_USER)
        end
      end

      # Using dotted hash notation, convert value to bool, int, float or extended value
      # @param value [String] The value to convert to appropriate type
      # @return [Boolean, Integer, Float, String, Array, Hash] the converted value
      def smart_convert(value)
        case value
        when 'true'  then true
        when 'false' then false
        else
          Integer(value, exception: false) ||
            Float(value, exception: false) ||
            ExtendedValue.instance.evaluate(value, context: 'dotted expression')
        end
      end

      # generate command line option from option symbol
      def symbol_to_option(symbol, opt_val = nil)
        result = [OPTION_PREFIX, symbol.to_s.gsub(OPTION_SEP_SYMBOL, OPTION_SEP_LINE)].join
        result = [result, OPTION_VALUE_SEPARATOR, opt_val].join unless opt_val.nil?
        result
      end

      # TODO: use formatter
      # Highlight current value in list
      # @param list    [Array<Symbol>] List of possible values
      # @param current [Symbol]        Current value
      # @return [String] comma separated sorted list of values, with the current value highlighted
      def highlight_current_in_list(list, current)
        list.sort.map do |i|
          if i.eql?(current)
            $stdout.isatty ? i.to_s.red.bold : "[#{i}]"
          else
            i
          end
        end.join(', ')
      end

      # Try to evaluate options set in batch
      # @param unprocessed_options [Array] list of options to apply (key_sym,value)
      # @param where [String] where the options come from
      def consume_option_pairs(unprocessed_options, where)
        Log.log.trace1{"consume_option_pairs: #{where}"}
        options_to_set = {}
        unprocessed_options.each do |k, v|
          if @declared_options.key?(k)
            # constrained parameters as string are revert to symbol
            v = self.class.get_from_list(v, "#{k} in #{where}", @declared_options[k].values) if @declared_options[k].values && v.is_a?(String)
            options_to_set[k] = v
          else
            Log.log.trace1{"unprocessed: #{k}: #{v}"}
          end
        end
        options_to_set.each do |k, v|
          set_option(k, v, where: where)
          # keep only unprocessed values for next parse
          unprocessed_options.delete(k)
        end
      end

      # Option name separator on command line, e.g. in --option-blah, third "-"
      OPTION_SEP_LINE = '-'
      # Option name separator in code (symbol), e.g. in :option_blah, the "_"
      OPTION_SEP_SYMBOL = '_'
      # Option value separator on command line, e.g. in --option-blah=foo, the "="
      OPTION_VALUE_SEPARATOR = '='
      # Starts an option, e.g. in --option-blah, the two first "--"
      OPTION_PREFIX = '--'
      # when this is alone, this stops option processing
      OPTIONS_STOP = '--'
      SOURCE_USER = 'cmdline' # cspell:disable-line
      # Percent selector: select by this field for this value
      REGEX_LOOKUP_ID_BY_FIELD = /^%([^:]+):(.*)$/
      # Ask for schema of Extended value
      HELP = 'help'

      private_constant :OPTION_SEP_LINE, :OPTION_SEP_SYMBOL, :OPTION_VALUE_SEPARATOR, :OPTION_PREFIX, :OPTIONS_STOP, :SOURCE_USER, :REGEX_LOOKUP_ID_BY_FIELD, :HELP_BORDER
    end
  end
end
