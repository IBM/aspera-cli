# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/error'
require 'aspera/cli/special_values'
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

    # Type specifiers for the `allowed:` parameter of option declarations.
    # Public API: STRING_ARRAY, SYMBOL_ARRAY, INTEGER, BOOLEAN, NONE.
    # Internal (do not pass as `allowed:`):
    #   ENUM   - derived internally when `allowed:` is an Array<Symbol> (enum list)
    #   STRING - the implicit default; equivalent to omitting `allowed:` entirely
    module Type
      # Option value is a String or Array of Strings (cumulative)
      STRING_ARRAY = [Array, String].freeze
      # Option value is a Symbol from a constrained list; use as prefix: SYMBOL_ARRAY + [:val1, :val2]
      SYMBOL_ARRAY = [Array, Symbol].freeze
      # Option value is coerced to Integer
      INTEGER = [Integer].freeze
      # Option value is a Boolean
      BOOLEAN = BoolValue::TYPES
      # Option has no value — it is a flag switch (e.g. `-N`, `--help`)
      NONE = [].freeze
      # Internal: derived when allowed: is an Array<Symbol>; do not pass directly
      ENUM   = [Symbol].freeze
      # Internal: implicit default (String); equivalent to omitting allowed: entirely
      STRING = [String].freeze
    end

    # Description of option, how to manage
    class OptionValue
      # [Array(Class)] List of allowed types
      attr_reader :types, :sensitive, :schema, :option, :deprecation
      # [Array] List of allowed values (Symbols and specific values)
      attr_accessor :values
      # [String] Help section group name (set by Parser#group)
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
      def initialize(option:, description: nil, allowed: Type::STRING, handler: nil, deprecation: nil, schema: nil)
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
        # Derive allowed type from schema when not explicitly provided
        if (allowed.nil? || allowed.eql?(Type::STRING)) && schema
          schema_reader = Schema::Registry.instance.reader(schema) rescue nil
          schema_node   = schema_reader&.current
          if schema_node
            case schema_node['type']
            when 'object' then allowed = Hash
            when 'array'  then allowed = Array
            else
              # No top-level type: inspect oneOf/anyOf branches; if all resolve to 'object', infer Hash
              composite_key = (%w[oneOf anyOf] & schema_node.keys).first
              if composite_key
                branch_types = schema_node[composite_key].map do |branch|
                  resolved = branch['$ref'] ? schema_reader.resolve_ref(branch['$ref']).current : branch
                  resolved['type']
                end
                if branch_types.all?('object')
                  allowed = Hash
                else
                  Aspera.assert(
                    !allowed.nil? && !allowed.eql?(Type::STRING),
                    "option :#{option}: schema '#{schema}' has mixed-type oneOf branches #{branch_types.uniq}: specify allowed: explicitly"
                  )
                end
              end
            end
          end
        end
        if !allowed.nil?
          allowed = [allowed] if allowed.is_a?(Class)
          Aspera.assert_type(allowed, Array)
          if allowed.take(Type::SYMBOL_ARRAY.length) == Type::SYMBOL_ARRAY
            # Special case: array of defined symbol values
            @types = Type::SYMBOL_ARRAY
            @values = allowed[Type::SYMBOL_ARRAY.length..]
            # Default value for symbol array when no value has been set yet
            assign_value([], where: 'array default', warn_deprecation: false) if value(log: false).nil?
          elsif allowed.all?(Class)
            @types = allowed
            @values = BoolValue::ALL if allowed.eql?(Type::BOOLEAN)
            # Default value for array/hash when no value has been set yet
            if @types.first.eql?(Array) && !@types.include?(NilClass) && value(log: false).nil?
              assign_value([], where: 'array default', warn_deprecation: false)
            elsif @types.first.eql?(Hash) && !@types.include?(NilClass) && value(log: false).nil?
              assign_value({}, where: 'hash default', warn_deprecation: false)
            end
          elsif allowed.all?(Symbol)
            @types = Type::ENUM
            @values = allowed
          else
            Aspera.error_unexpected_value(allowed)
          end
        end
        Log.log.trace1{"declare: #{@option}: #{@access} #{@object.class}.#{@read_method}".green}
      end

      # Wire (or re-wire) the getter/setter delegation for this option.
      # Safe to call after construction - used by Parser#set_handler to bind a composed
      # instance variable that did not exist at class-load time (Category C handlers).
      # @param handler [Hash] Accessor hash with keys :o (object) and :m (method symbol)
      # @return [nil]
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
        nil
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
        # Per-type coercion: String input from CLI/env/preset is normalized to the expected type.
        # Centralized here so all sources (CLI dispatch, preset, env) go through the same path.
        case @types
        when Type::ENUM
          new_value = Parser.get_from_list(new_value, @option, @values) if new_value.is_a?(String)
        when Type::BOOLEAN
          new_value = Parser.get_from_list(new_value, @option, BoolValue::ALL) if new_value.is_a?(String)
          new_value = BoolValue.true?(new_value)
        when Type::INTEGER
          new_value = Integer(new_value)
        when Type::STRING_ARRAY
          new_value = [new_value] if new_value.is_a?(String)
        when Type::SYMBOL_ARRAY
          new_value = [new_value] if new_value.is_a?(String)
          Aspera.assert_array_all(new_value, String, type: BadArgument)
          new_value = new_value.map{ |v| Parser.get_from_list(v, @option, @values)}
        else
          # nil (setting nil on a Hash/Array option resets to empty container)
          new_value = {} if new_value.nil? && @types&.first.eql?(Hash)
          new_value = [] if new_value.nil? && @types&.first.eql?(Array)
        end
        # Skip type validation for the special 'help' value on Hash options: store it as-is
        # so that get_option(schema:) can raise SchemaRequest with the contextual schema later.
        # Note: set_option already raises SchemaRequest when @schema is set, so this path is
        # only reached when @schema is nil (e.g. --query=help before schema is known).
        if new_value.eql?(Parser::HELP) && @types&.include?(Hash)
          store(new_value)
          return
        end
        Aspera.assert_type(new_value, *@types, type: BadArgument){"Option #{@option}"} if @types
        if new_value.is_a?(Hash) || new_value.is_a?(Array)
          current_value = value(log: false)
          new_value = current_value.deep_merge(new_value) if new_value.is_a?(Hash) && current_value.is_a?(Hash) && !current_value.empty?
          new_value = current_value + new_value if new_value.is_a?(Array) && current_value.is_a?(Array) && !current_value.empty?
        end
        store(new_value)
        Log.log.trace1{v = value(log: false); "#{@option} <- (#{v.class})#{v}"} # rubocop:disable Style/Semicolon
        nil
      end

      private

      def store(new_value)
        case @access
        when :local  then @object = new_value
        when :write  then @object.send(@write_method, new_value)
        when :setter then @object.send(@read_method, @option, :set, new_value)
        end
      end
    end

    # Represents a positional (non-option) CLI argument token.
    class Argument
      # @return [String] the raw argument value
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def to_s = @value
    end

    # Represents a parsed CLI option token (long or short form).
    # Pre-computed at argv-scan time; resolution against @declared_options happens later in parse_options!
    class Option
      # @return [String] raw token as it appeared in argv (e.g. "--log-level=debug", "-Pval")
      attr_reader :raw
      # @return [String, nil] option name with underscores (e.g. "log_level", "custom"); nil for short options
      attr_reader :name
      # @return [String, nil] single-char short option letter (e.g. "P"), nil for long options
      attr_reader :short_char
      # @return [Array<String>, nil] sub-keys for dot-path notation (e.g. ["field"] for --custom.field),
      #                              nil when name is the full option name (no dot)
      attr_reader :dot_path
      # @return [String, nil] inline value string, or nil if no value was provided inline
      attr_reader :value
      # @return [Boolean] true if `=` (long) or glued value (short) was present in the raw token;
      #                   false means no inline separator — value may come from the next argv token
      attr_reader :has_value

      # @param raw        [String] full raw token
      # @param name       [String, nil] option name (underscored, no prefix)
      # @param short_char [String, nil] single-char short letter
      # @param dot_path   [Array<String>, nil] dot-path sub-keys, or nil
      # @param value      [String, nil] inline value
      # @param has_value  [Boolean] whether an inline value separator was present
      def initialize(raw:, name:, short_char:, dot_path:, value:, has_value:)
        @raw        = raw
        @name       = name
        @short_char = short_char
        @dot_path   = dot_path
        @value      = value
        @has_value  = has_value
      end

      def to_s = @raw

      class << self
        # Build an Option from a raw long-option token (starts with `--`)
        # @param raw [String] e.g. "--log-level=debug" or "--custom.field" or "--log-level"
        def from_long(raw)
          without_prefix = raw.delete_prefix(PREFIX)
          eq_idx = without_prefix.index(VALUE_SEP)
          if eq_idx
            name_raw  = without_prefix[0, eq_idx]
            value     = without_prefix[eq_idx + 1..]
            has_value = true
          else
            name_raw  = without_prefix
            value     = nil
            has_value = false
          end
          parts    = name_raw.split(DotContainer::SEPARATOR)
          root     = parts.shift.gsub(NAME_SEP_LINE, NAME_SEP_SYMBOL)
          dot_path = parts.empty? ? nil : parts
          new(raw: raw, name: root, short_char: nil, dot_path: dot_path, value: value, has_value: has_value)
        end

        # Build an Option from a raw short-option token (starts with `-` but not `--`)
        # @param raw [String] e.g. "-P", "-Pval", "-h"
        def from_short(raw)
          short_char = raw[1]
          if raw.length > 2
            new(raw: raw, name: nil, short_char: short_char, dot_path: nil, value: raw[2..], has_value: true)
          else
            new(raw: raw, name: nil, short_char: short_char, dot_path: nil, value: nil, has_value: false)
          end
        end
      end

      # Option name separator on command line (e.g. `--option-name`, the `-` between words)
      NAME_SEP_LINE   = '-'
      # Option name separator in code/symbol (e.g. `:option_name`, the `_` between words)
      NAME_SEP_SYMBOL = '_'
      # Separator between option name and its inline value (e.g. `--opt=val`, the `=`)
      VALUE_SEP = '='
      # Long-option prefix (e.g. `--opt`)
      PREFIX = '--'
      private_constant :NAME_SEP_LINE, :NAME_SEP_SYMBOL, :VALUE_SEP, :PREFIX
    end

    # parse command line options
    # arguments options start with '-', others are commands
    # resolves on extended value syntax
    class Parser
      class << self
        # Find shortened string value in allowed symbol list
        def get_from_list(short_value, descr, allowed_values)
          Aspera.assert_type(short_value, String)
          # we accept shortcuts
          matching_exact = allowed_values.select{ |i| i.to_s.eql?(short_value)}
          return matching_exact.first if matching_exact.length == 1
          matching = allowed_values.select{ |i| i.to_s.start_with?(short_value)}
          raise BadArgument, "Identifier '#{short_value}' used where a #{descr} is expected: place the identifier after the command" if matching.empty? && short_value.match?(REGEX_LOOKUP_ID_BY_FIELD)
          Aspera.assert(!matching.empty?, multi_choice_assert_msg("unknown value for #{descr}: #{short_value}", allowed_values), type: BadArgument)
          Aspera.assert(matching.length.eql?(1), multi_choice_assert_msg("ambiguous shortcut for #{descr}: #{short_value}", matching), type: BadArgument)
          return BoolValue.true?(matching.first) if allowed_values.eql?(BoolValue::ALL)
          matching.first
        end

        # Find a key in a list by exact match or unique prefix match
        # @return [Object, nil] the matching key, or nil if none or ambiguous
        def match_prefix(short_value, allowed_values)
          return short_value if allowed_values.include?(short_value)
          matches = allowed_values.select{ |k| k.to_s.start_with?(short_value.to_s)}
          matches.length == 1 ? matches.first : nil
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
        # options explicitly reset to nil from CLI (e.g. --opt=@none:); preset injection skips these
        @explicitly_cleared = {}
        # options can also be provided by env vars : --param-name -> ASCLI_PARAM_NAME
        @option_pairs_batch = {}
        @option_pairs_env = {}
        # Short option char -> option symbol, e.g. {'h' => :help, 'v' => :version}
        @short_options = {}
        # Current help section group name, set by #group
        @current_group = 'global'
        env_prefix = program_name.upcase + OPTION_SEP_SYMBOL
        ENV.each do |k, v|
          @option_pairs_env[k.delete_prefix(env_prefix).downcase.to_sym] = v if k.start_with?(env_prefix)
        end
        Log.dump(:env, @option_pairs_env)
        # Ordered list of all CLI tokens after `--` splitting.
        # Each entry is a two-element array: [:option, token] or [:argument, token].
        # This is the single source of truth for CLI parsing; @unprocessed_cmd_line_options and
        # @unprocessed_cmd_line_arguments are derived views that stay in sync during parse_options!.
        # @type [Array<Array(Symbol, String)>]
        @argv_tokens = []
        # Frozen snapshot of @argv_tokens used by unprocessed_options_with_value.
        @initial_argv_tokens = [].freeze
        # command line values starting with at least one '-'
        @unprocessed_cmd_line_options = []
        # command line values *not* starting with '-'
        @unprocessed_cmd_line_arguments = []
        # a copy of all initial options (for unprocessed_options_with_value)
        @initial_cli_options = []
        # Number of original positional args before the option currently being parsed (nil = positional context).
        @current_option_args_offset = nil
        return if argv.nil?
        # true until `--` is found (stop options)
        process_options = true
        argv.each do |value|
          if process_options && value.start_with?('-')
            Log.log.trace1{"opt: #{value}"}
            if value.eql?(OPTIONS_STOP)
              process_options = false
            else
              token = value.start_with?(OPTION_PREFIX) ? Option.from_long(value) : Option.from_short(value)
              @argv_tokens.push(token)
              @unprocessed_cmd_line_options.push(value)
            end
          else
            Log.log.trace1{"arg: #{value}"}
            token = Argument.new(value)
            @argv_tokens.push(token)
            @unprocessed_cmd_line_arguments.push(value)
          end
        end
        @initial_argv_tokens = @argv_tokens.dup.freeze
        @initial_cli_options = @unprocessed_cmd_line_options.dup.freeze
        Log.log.trace1{"add_cmd_line_options:commands/arguments=#{@unprocessed_cmd_line_arguments},options=#{@unprocessed_cmd_line_options}".red}
        declare(:interactive, description: 'Use interactive input of missing params', allowed: Type::BOOLEAN, handler: {o: self, m: :ask_missing_mandatory})
        declare(:ask_options, description: 'Ask even optional options', allowed: Type::BOOLEAN, handler: {o: self, m: :ask_missing_optional})
        # do not parse options yet, let's wait for option `-h` to be overridden
      end

      # Add a type to the message if not special types
      # @param types [Array<Class>] types to add
      # @return [String] Types if relevant
      def add_types_info(types)
        return '' if !types || types.empty? || types.eql?(Type::ENUM) || types.eql?(Type::BOOLEAN) || types.eql?(Type::STRING)
        " (#{types.map(&:name).join(', ')})"
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
      # @param handler       [Hash]   handler for option value: keys: :o(object) and :m(method)
      # @param deprecation   [String] deprecation
      # @param schema        [String] schema path documenting the Hash form of this option
      # @param block [Proc] Block to execute when option is found
      def declare(option_symbol, description: nil, short: nil, allowed: nil, default: nil, handler: nil, deprecation: nil, schema: nil, &block)
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
        when Type::ENUM, Type::BOOLEAN
          # This option value must be a symbol (or array of symbols)
          set_option(option_symbol, BoolValue.true?(default), where: 'default') if option_attrs.values.eql?(BoolValue::ALL) && !default.nil?
        when Type::NONE
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

      # Low-level positional argument reader.  Prefer +Base#resolve_argument+ from action methods.
      # Direct calls from outside +Parser+ are legacy exceptions documented in ST12/ST13
      # (mixins without DSL: sync_actions, ascp_actions; setup callbacks: aoc.rb).
      # @api private
      # @param descr       [String] description for help
      # @param mandatory   [Boolean] `true`: raise error no more argument
      # @param multiple    [Boolean] `true`: return all remaining arguments (Array). String: until marker
      # @param accept_list [Array<Symbol>, NilClass] list of allowed values
      # @param validation  [Class, Array, NilClass] Accepted value type(s) or list of Symbols
      # @param aliases     [Hash] map of aliases: key = alias, value = real value
      # @param default     [Object] default value
      # @return [Object, Array, nil] one value, list or nil (if optional and no default)
      def get_next_argument(descr, mandatory: true, multiple: false, accept_list: nil, validation: Type::STRING, aliases: nil, default: nil, schema: nil)
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
        if result.is_a?(String) && validation&.eql?(Type::INTEGER)
          int_result = Integer(result, exception: false)
          raise Cli::BadArgument, "Invalid integer: #{result}" if int_result.nil?
          result = int_result
        end
        Log.log.trace1{"#{descr}=#{result}"}
        result = aliases[result] if aliases&.key?(result)
        # if value comes from JSON/YAML, it may come as Integer
        result = result.to_s if result.is_a?(Integer) && validation&.eql?(Type::STRING)
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
        if res_id.is_a?(String) && (m = Parser.percent_selector(res_id))
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

      # @return [Hash{Symbol => OptionValue}] all declared options (read-only view)
      attr_reader :declared_options

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
      # @param schema [String, nil] contextual schema path override; when set, raises SchemaRequest
      #   if the option value is 'help' (used for --query whose schema depends on the current command)
      def get_option(option_symbol, mandatory: false, schema: nil)
        Aspera.assert_type(option_symbol, Symbol)
        option_attrs = option_def(option_symbol)
        result = option_attrs.value
        # Contextual schema: raise SchemaRequest when value is 'help'
        raise SchemaRequest.new(:option, option_symbol.to_s, schema) if schema && result.eql?(HELP)
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
        # Raise immediately only when the option has a static schema: the schema is known at parse time.
        # When schema is nil (e.g. --query), 'help' is stored as-is and SchemaRequest is raised later
        # in get_option() with the contextual schema provided by the calling command.
        raise SchemaRequest.new(:option, option.option, option.schema) if option.types&.include?(Hash) && value.eql?(HELP) && option.schema
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
      # @return [nil]
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
          # Never restore an option that was explicitly cleared from the CLI (e.g. --opt=@none:)
          next if @explicitly_cleared.key?(option_symbol)
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
        @initial_argv_tokens.each_with_index do |tok, idx|
          next unless tok.is_a?(Option) && tok.short_char.nil?
          # For space-separated form: value is the immediately following :argument token (if any)
          value = tok.value || @initial_argv_tokens[idx + 1]&.then{ |t| t.value if t.is_a?(Argument)}
          # ignore options without value
          next if value.nil?
          name = tok.dot_path ? [tok.name, *tok.dot_path].join(DotContainer::SEPARATOR) : tok.name
          Log.log.debug{"option #{name}=#{value}"}
          path = [tok.name, *(tok.dot_path || [])]
          DotContainer.dotted_to_container(path, smart_convert(value), result)
          @unprocessed_cmd_line_options.delete(tok.raw)
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
        @option_pairs_batch = consume_option_pairs(@option_pairs_batch, 'set')
        # Then, env var (to override)
        @option_pairs_env = consume_option_pairs(@option_pairs_env, 'env')
        # Then, command line override.
        # Iterate @argv_tokens in order so that --opt val and -s val can consume the next argument
        # token directly, without any secondary index.
        # Process one option at a time so that @current_option_args_offset can be set before each
        # option is evaluated (used by `@:` extended value).
        deferred_tokens = []
        Log.log.trace1('Before parse')
        Log.dump(:argv_tokens, @argv_tokens, level: :trace1)
        until @argv_tokens.empty?
          tok = @argv_tokens.shift
          if tok.is_a?(Argument)
            # Positional arg: not consumed by any option — leave in @unprocessed_cmd_line_arguments as-is.
            next
          end
          # tok is an Option
          # @current_option_args_offset = number of positional args in @unprocessed_cmd_line_arguments
          # that appear BEFORE this option in the original argv order.
          # Used by args_as_extended to skip those leading args when collecting @: values.
          args_still_in_tokens = @argv_tokens.count{ |t| t.is_a?(Argument)}
          @current_option_args_offset = @unprocessed_cmd_line_arguments.length - args_still_in_tokens
          if tok.short_char
            # Short option: -X or -Xvalue
            option_sym = @short_options[tok.short_char]
            if option_sym
              raw_value = tok.value
              # No inline value and option expects a value: consume the next :argument token
              raw_value = shift_next_argument_token \
                if !tok.has_value && !@declared_options[option_sym].types.eql?(Type::NONE)
              dispatch_option(option_sym, raw_value)
            else
              deferred_tokens.push(tok)
            end
          elsif tok.dot_path
            # Dotted notation: --a.b.c=val or --a.b.c val (always takes priority over plain option lookup)
            Log.log.trace1{"Dotted option: #{tok.raw}".red}
            raw_value = tok.has_value ? tok.value : shift_next_argument_token
            if @declared_options.key?(tok.name.to_sym)
              set_option(tok.name.to_sym, DotContainer.dotted_to_container(tok.dot_path, smart_convert(raw_value), get_option(tok.name.to_sym)), where: 'dotted')
            else
              @argv_tokens.unshift(Argument.new(raw_value)) if raw_value
              deferred_tokens.push(tok)
            end
          elsif (resolved_sym = self.class.match_prefix(tok.name.to_sym, @declared_options.keys))
            # Known long option (plain, no dot-path)
            raw_value = tok.value
            # No inline `=` and option expects a value: consume the next :argument token
            raw_value = shift_next_argument_token \
              if !tok.has_value && !@declared_options[resolved_sym].types.eql?(Type::NONE)
            dispatch_option(resolved_sym, raw_value)
          else
            Log.log.trace1{"Unknown long option: #{tok.raw}".red}
            deferred_tokens.push(tok)
          end
        end
        @current_option_args_offset = nil
        Log.log.trace1('After parse')
        Log.log.trace1{"deferred: #{deferred_tokens}"}
        # Rebuild @argv_tokens for the next round by filtering @initial_argv_tokens:
        # keep only deferred option tokens and argument tokens still in @unprocessed_cmd_line_arguments.
        # This preserves the original interleaved order for correct @current_option_args_offset computation.
        deferred_raws = deferred_tokens.map(&:raw)
        remaining_args = @unprocessed_cmd_line_arguments.dup
        @argv_tokens = @initial_argv_tokens.filter_map do |t|
          if t.is_a?(Option) && deferred_raws.include?(t.raw)
            deferred_raws.delete_at(deferred_raws.index(t.raw))
            t
          elsif t.is_a?(Argument) && remaining_args.include?(t.value)
            remaining_args.delete_at(remaining_args.index(t.value))
            t
          end
        end
        # Append any arguments injected at runtime (e.g. via unshift_next_argument) not in @initial_argv_tokens.
        remaining_args.each{ |a| @argv_tokens.unshift(Argument.new(a))}
        @unprocessed_cmd_line_options = @argv_tokens.filter_map{ |t| t.raw if t.is_a?(Option)}
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
        # @current_option_args_offset is set by parse_options! to the number of args in
        # @unprocessed_cmd_line_arguments that preceded this option; nil when called from a positional context.
        skip_count = @current_option_args_offset || 0
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

      # AsciiBorder with all visible characters removed - used by help_text
      HELP_BORDER = Terminal::Table::AsciiBorder.new.tap do |b|
        b.top = false
        b.bottom = false
        b.left = false
        b.right = false
        b.remove_verticals
        b.remove_horizontals
      end.freeze

      # @param opt [OptionValue] option descriptor
      # @return [String, nil] placeholder shown in flag column: 'ENUM', 'HASH', 'INT', 'LIST', 'VALUE', or nil for flag switches
      def option_display_value(opt)
        case opt.types
        when Type::NONE then nil
        when Type::BOOLEAN then 'yes|no'
        when Type::INTEGER then 'INT'
        when Type::ENUM
          if opt.values&.any? && opt.values.length <= 4
            opt.values.join('|')
          else
            'ENUM'
          end
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

      # Dispatch a parsed CLI option to its handler.
      # @param sym       [Symbol] option symbol
      # @param raw_value [String, nil] raw string value from command line, or nil for flag switches
      def dispatch_option(sym, raw_value)
        opt = @declared_options[sym]
        if opt.types.eql?(Type::NONE)
          opt.block.call
        else
          set_option(sym, raw_value, where: SOURCE_USER)
          # Track options explicitly cleared from CLI (e.g. --opt=@none:) so that
          # subsequent preset injection does not silently restore the value.
          # Note: for Hash options, @none: evaluates to nil which is then coerced to {}
          # by assign_value, so we also check the raw evaluated value before coercion.
          cleared = get_option(sym).nil?
          cleared ||= raw_value.is_a?(String) && ExtendedValue.instance.evaluate(raw_value, context: 'explicitly_cleared check').nil?
          @explicitly_cleared[sym] = true if cleared
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
      # Apply all known options from the given pairs hash and return the remaining (unknown) pairs.
      # Pure: does not mutate the argument; the caller is responsible for storing the returned value.
      # @param option_pairs [Hash{Symbol => Object}] candidate key/value pairs
      # @param where [String] label used in log messages and error context
      # @return [Hash{Symbol => Object}] pairs whose keys were not yet declared (deferred to next round)
      def consume_option_pairs(option_pairs, where)
        Log.log.trace1{"consume_option_pairs: #{where}"}
        remaining = {}
        option_pairs.each do |k, v|
          if @declared_options.key?(k)
            set_option(k, v, where: where)
          else
            Log.log.trace1{"unprocessed: #{k}: #{v}"}
            remaining[k] = v
          end
        end
        remaining
      end

      # Consume the next Argument token from @argv_tokens (space-separated option value).
      # Also removes it from @unprocessed_cmd_line_arguments to keep both in sync.
      # @return [String, nil] the consumed argument value, or nil if the next token is not an Argument
      def shift_next_argument_token
        return unless @argv_tokens.first&.is_a?(Argument)

        tok = @argv_tokens.shift
        @unprocessed_cmd_line_arguments.delete_at(@unprocessed_cmd_line_arguments.index(tok.value))
        tok.value
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
