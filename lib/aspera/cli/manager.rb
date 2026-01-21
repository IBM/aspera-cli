# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/error'
require 'aspera/colors'
require 'aspera/secret_hider'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/dot_container'
require 'io/console'
require 'optparse'

module Aspera
  module Cli
    # Constants to be used as parameter `allowed:` for `OptionValue`
    module Allowed
      # This option can be set to a single string or array, multiple times, and gives Array of String
      TYPES_STRING_ARRAY = [Array, String].freeze
      # A list of symbols with constrained values
      TYPES_SYMBOL_ARRAY = [Array, Symbol].freeze
      # Value will be coerced to int
      TYPES_INTEGER = [Integer].freeze
      TYPES_BOOLEAN = [FalseClass, TrueClass].freeze
      # no value at all, it's a switch
      TYPES_NONE = [].freeze
      TYPES_ENUM = [Symbol].freeze
      TYPES_STRING = [String].freeze
    end

    # Description of option, how to manage
    class OptionValue
      # [Array(Class)] List of allowed types
      attr_reader :types, :sensitive
      # [Array] List of allowed values (Symbols and specific values)
      attr_accessor :values

      # @param option      [Symbol] Name of option
      # @param description [String] Description for help
      # @param allowed  [nil,Class,Array<Class>,Array<Symbol>] Allowed values
      # @param handler       [Hash] Accessor: keys: :o(object) and :m(method)
      # @param deprecation [String] Deprecation message
      # `allowed`:
      # - `nil` No validation, so just a string
      # - `Class` The single allowed Class
      # - `Array<Class>` Multiple allowed classes
      # - `Array<Symbol>` List of allowed values
      def initialize(option:, description:, allowed: Allowed::TYPES_STRING, handler: nil, deprecation: nil)
        Log.log.trace1{"option: #{option}, allowed: #{allowed}"}
        @option = option
        @description = description
        # by default passwords and secrets are sensitive, else specify when declaring the option
        @sensitive = SecretHider.instance.secret?(@option, '')
        # either the value, or object giving value
        @object = handler&.[](:o)
        @read_method = handler&.[](:m)
        @write_method = @read_method ? "#{@read_method}=".to_sym : nil
        @deprecation = deprecation
        @access = if @object.nil?
          :local
        elsif @object.respond_to?(@write_method)
          :write
        else
          :setter
        end
        Aspera.assert(@object.respond_to?(@read_method)){"#{@object} does not respond to #{@read_method}"} unless @access.eql?(:local)
        @types = nil
        @values = nil
        if !allowed.nil?
          allowed = [allowed] if allowed.is_a?(Class)
          Aspera.assert_type(allowed, Array)
          if allowed.take(Allowed::TYPES_SYMBOL_ARRAY.length) == Allowed::TYPES_SYMBOL_ARRAY
            # Special case: array of defined symbol values
            @types = Allowed::TYPES_SYMBOL_ARRAY
            @values = allowed[Allowed::TYPES_SYMBOL_ARRAY.length..-1]
          elsif allowed.all?(Class)
            @types = allowed
            @values = Manager::BOOLEAN_VALUES if allowed.eql?(Allowed::TYPES_BOOLEAN)
            # Default value for array
            @object ||= [] if @types.first.eql?(Array) && !@types.include?(NilClass)
            @object ||= {} if @types.first.eql?(Hash) && !@types.include?(NilClass)
          elsif allowed.all?(Symbol)
            @types = Allowed::TYPES_ENUM
            @values = allowed
          else
            Aspera.error_unexpected_value(allowed)
          end
        end
        Log.log.trace1{"declare: #{@option}: #{@access} #{@object.class}.#{@read_method}".green}
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
        return current_value
      end

      # Assign value to option.
      # Value can be a String, then evaluated with ExtendedValue, or directly a value.
      # @param value [String, Object] Value to assign to option
      def assign_value(value, where:)
        Aspera.assert(!@deprecation, type: warn){"Option #{@option} is deprecated: #{@deprecation}"}
        new_value = ExtendedValue.instance.evaluate(value, context: "option: #{@option}", allowed: @types)
        Log.log.trace1{"#{where}: #{@option} <- (#{new_value.class})#{new_value}"}
        new_value = Manager.enum_to_bool(new_value) if @types.eql?(Allowed::TYPES_BOOLEAN)
        new_value = Integer(new_value) if @types.eql?(Allowed::TYPES_INTEGER)
        new_value = [new_value] if @types.eql?(Allowed::TYPES_STRING_ARRAY) && new_value.is_a?(String)
        # Setting a Hash to null set an empty hash
        new_value = {} if new_value.eql?(nil) && @types&.first.eql?(Hash)
        # Setting a Array to null set an empty hash
        new_value = [] if new_value.eql?(nil) && @types&.first.eql?(Array)
        if @types.eql?(Aspera::Cli::Allowed::TYPES_SYMBOL_ARRAY)
          new_value = [new_value] if new_value.is_a?(String)
          Aspera.assert_type(new_value, Array, type: BadArgument)
          Aspera.assert_array_all(new_value, String, type: BadArgument)
          new_value = new_value.map{ |v| Manager.get_from_list(v, @option, @values)}
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
      end
    end

    # parse command line options
    # arguments options start with '-', others are commands
    # resolves on extended value syntax
    class Manager
      BOOLEAN_SIMPLE = %i[no yes].freeze
      class << self
        # @return `true` if value is a value for `true` in BOOLEAN_VALUES
        def enum_to_bool(enum)
          Aspera.assert_values(enum, BOOLEAN_VALUES){'boolean'}
          return TRUE_VALUES.include?(enum)
        end

        # @return :yes ot :no
        def enum_to_yes_no(enum)
          Aspera.assert_values(enum, BOOLEAN_VALUES){'boolean'}
          return TRUE_VALUES.include?(enum) ? BOOL_YES : BOOL_NO
        end

        # Find shortened string value in allowed symbol list
        def get_from_list(short_value, descr, allowed_values)
          Aspera.assert_type(short_value, String)
          # we accept shortcuts
          matching_exact = allowed_values.select{ |i| i.to_s.eql?(short_value)}
          return matching_exact.first if matching_exact.length == 1
          matching = allowed_values.select{ |i| i.to_s.start_with?(short_value)}
          Aspera.assert(!matching.empty?, multi_choice_assert_msg("unknown value for #{descr}: #{short_value}", allowed_values), type: BadArgument)
          Aspera.assert(matching.length.eql?(1), multi_choice_assert_msg("ambiguous shortcut for #{descr}: #{short_value}", matching), type: BadArgument)
          return enum_to_bool(matching.first) if allowed_values.eql?(BOOLEAN_VALUES)
          return matching.first
        end

        # Generates error message with list of allowed values
        # @param error_msg [String] error message
        # @param accept_list [Array] list of allowed values
        def multi_choice_assert_msg(error_msg, accept_list)
          [error_msg, 'Use:'].concat(accept_list.map{ |c| "- #{c}"}.sort).join("\n")
        end

        # change option name with dash to name with underscore
        def option_line_to_name(name)
          return name.gsub(OPTION_SEP_LINE, OPTION_SEP_SYMBOL)
        end

        def option_name_to_line(name)
          return "#{OPTION_PREFIX}#{name.to_s.gsub(OPTION_SEP_SYMBOL, OPTION_SEP_LINE)}"
        end
      end

      attr_reader :parser
      attr_accessor :ask_missing_mandatory, :ask_missing_optional
      attr_writer :fail_on_missing_mandatory

      def initialize(program_name, argv = nil)
        # command line values *not* starting with '-'
        @unprocessed_cmd_line_arguments = []
        # command line values starting with '-'
        @unprocessed_cmd_line_options = []
        # a copy of all initial options
        @initial_cli_options = []
        # option description: option_symbol => OptionValue
        @declared_options = {}
        # do we ask missing options and arguments to user ?
        @ask_missing_mandatory = false # STDIN.isatty
        # ask optional options if not provided and in interactive
        @ask_missing_optional = false
        # get_option fails if a mandatory parameter is asked
        @fail_on_missing_mandatory = true
        # Array of [key(sym), value]
        # those must be set before parse
        # parse consumes those defined only
        @option_pairs_batch = {}
        @option_pairs_env = {}
        # NOTE: was initially inherited but it is preferred to have specific methods
        @parser = OptionParser.new
        @parser.program_name = program_name
        # options can also be provided by env vars : --param-name -> ASCLI_PARAM_NAME
        env_prefix = program_name.upcase + OPTION_SEP_SYMBOL
        ENV.each do |k, v|
          @option_pairs_env[k[env_prefix.length..-1].downcase.to_sym] = v if k.start_with?(env_prefix)
        end
        Log.log.debug{"env=#{@option_pairs_env}".red}
        @unprocessed_cmd_line_options = []
        @unprocessed_cmd_line_arguments = []
        return if argv.nil?
        # true until `--` is found (stop options)
        process_options = true
        until argv.empty?
          value = argv.shift
          if process_options && value.start_with?('-')
            Log.log.trace1{"opt: #{value}"}
            if value.eql?(OPTIONS_STOP)
              process_options = false
            else
              @unprocessed_cmd_line_options.push(value)
            end
          else
            Log.log.trace1{"arg: #{value}"}
            @unprocessed_cmd_line_arguments.push(value)
          end
        end
        @initial_cli_options = @unprocessed_cmd_line_options.dup.freeze
        Log.log.trace1{"add_cmd_line_options:commands/arguments=#{@unprocessed_cmd_line_arguments},options=#{@unprocessed_cmd_line_options}".red}
        @parser.separator('')
        @parser.separator('OPTIONS: global')
        declare(:interactive, 'Use interactive input of missing params', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :ask_missing_mandatory})
        declare(:ask_options, 'Ask even optional options', allowed: Allowed::TYPES_BOOLEAN, handler: {o: self, m: :ask_missing_optional})
        # do not parse options yet, let's wait for option `-h` to be overridden
      end

      # Declare an option
      # @param option_symbol [Symbol] option name
      # @param description   [String] description for help
      # @param short         [String] short option name
      # @param allowed       [Object] Allowed values, see `OptionValue`
      # @param default       [Object] default value
      # @param handler       [Hash]   handler for option value: keys: :o(object) and :m(method)
      # @param deprecation   [String] deprecation
      # @param block [Proc] Block to execute when option is found
      def declare(option_symbol, description, short: nil, allowed: nil, default: nil, handler: nil, deprecation: nil, &block)
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(!@declared_options.key?(option_symbol)){"#{option_symbol} already declared"}
        Aspera.assert(description[-1] != '.'){"#{option_symbol} ends with dot"}
        Aspera.assert(description[0] == description[0].upcase){"#{option_symbol} description does not start with an uppercase"}
        Aspera.assert(!['hash', 'extended value'].any?{ |s| description.downcase.include?(s)}){"#{option_symbol} shall use :allowed"}
        Aspera.assert_type(handler, Hash) if handler
        Aspera.assert(handler.keys.sort.eql?(%i[m o])) if handler
        option_attrs = @declared_options[option_symbol] = OptionValue.new(
          option:      option_symbol,
          description: description,
          allowed:     allowed,
          handler:     handler,
          deprecation: deprecation
        )
        real_types = option_attrs.types&.reject{ |i| [NilClass, String, Symbol].include?(i)}
        description = "#{description} (#{real_types.map(&:name).join(', ')})" if real_types && !real_types.empty? && !real_types.eql?(Allowed::TYPES_ENUM) && !real_types.eql?(Allowed::TYPES_BOOLEAN) && !real_types.eql?(Allowed::TYPES_STRING)
        description = "#{description} (#{'deprecated'.blue}: #{deprecation})" if deprecation
        set_option(option_symbol, default, where: 'default') unless default.nil?
        on_args = [description]
        case option_attrs.types
        when Allowed::TYPES_ENUM, Allowed::TYPES_BOOLEAN
          # This option value must be a symbol (or array of symbols)
          set_option(option_symbol, Manager.enum_to_bool(default), where: 'default') if option_attrs.values.eql?(BOOLEAN_VALUES) && !default.nil?
          value = get_option(option_symbol)
          help_values =
            if option_attrs.types.eql?(Allowed::TYPES_BOOLEAN)
              highlight_current_in_list(BOOLEAN_SIMPLE, self.class.enum_to_yes_no(value))
            else
              highlight_current_in_list(option_attrs.values, value)
            end
          on_args[0] = "#{description}: #{help_values}"
          on_args.push(symbol_to_option(option_symbol, 'ENUM'))
          # on_args.push(option_attrs.values)
          @parser.on(*on_args) do |v|
            set_option(option_symbol, self.class.get_from_list(v.to_s, description, option_attrs.values), where: SOURCE_USER)
          end
        when Allowed::TYPES_NONE
          Aspera.assert_type(block, Proc){"missing execution block for #{option_symbol}"}
          on_args.push(symbol_to_option(option_symbol))
          on_args.push("-#{short}") if short.is_a?(String)
          @parser.on(*on_args, &block)
        else
          on_args.push(symbol_to_option(option_symbol, 'VALUE'))
          on_args.push("-#{short}VALUE") unless short.nil?
          # coerce integer
          on_args.push(Integer) if option_attrs.types.eql?(Allowed::TYPES_INTEGER)
          @parser.on(*on_args) do |v|
            set_option(option_symbol, v, where: SOURCE_USER)
          end
        end
        Log.log.trace1{"on_args=#{on_args}"}
      end

      # @param descr       [String] description for help
      # @param mandatory   [Boolean] if true, raise error if option not set
      # @param multiple    [Boolean] if true, return remaining arguments (Array)
      # @param accept_list [Array, NilClass] list of allowed values (Symbol)
      # @param validation  [Class, Array, NilClass] Accepted value type(s) or list of Symbols
      # @param aliases     [Hash] map of aliases: key = alias, value = real value
      # @param default     [Object] default value
      # @return one value, list or nil (if optional and no default)
      def get_next_argument(descr, mandatory: true, multiple: false, accept_list: nil, validation: Allowed::TYPES_STRING, aliases: nil, default: nil)
        Aspera.assert_array_all(accept_list, Symbol) unless accept_list.nil?
        Aspera.assert_hash_all(aliases, Symbol, Symbol) unless aliases.nil?
        validation = Symbol unless accept_list.nil?
        validation = [validation] unless validation.is_a?(Array) || validation.nil?
        Aspera.assert_array_all(validation, Class){'validation'} unless validation.nil?
        descr = "#{descr} (#{validation.join(', ')})" unless validation.nil? || validation.eql?(Allowed::TYPES_STRING)
        result =
          if !@unprocessed_cmd_line_arguments.empty?
            how_many = multiple ? @unprocessed_cmd_line_arguments.length : 1
            values = @unprocessed_cmd_line_arguments.shift(how_many)
            values = values.map{ |v| ExtendedValue.instance.evaluate(v, context: "argument: #{descr}", allowed: validation)}
            # if expecting list and only one arg of type array : it is the list
            values = values.first if multiple && values.length.eql?(1) && values.first.is_a?(Array)
            if accept_list
              allowed_values = [].concat(accept_list)
              allowed_values.concat(aliases.keys) unless aliases.nil?
              values = values.map{ |v| self.class.get_from_list(v, descr, allowed_values)}
            end
            multiple ? values : values.first
          elsif !default.nil? then default
            # no value provided, either get value interactively, or exception
          elsif mandatory then get_interactive(descr, multiple: multiple, accept_list: accept_list)
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
            raise Cli::BadArgument,
              "Argument #{descr} is a #{value.class} but must be #{'one of: ' if validation.length > 1}#{validation.map(&:name).join(', ')}" unless validation.any?{ |t| value.is_a?(t)}
          end
        end
        return result
      end

      def get_next_command(command_list, aliases: nil); return get_next_argument('command', accept_list: command_list, aliases: aliases); end

      # Get an option value by name
      # either return value or calls handler, can return nil
      # ask interactively if requested/required
      # @param mandatory [Boolean] if true, raise error if option not set
      def get_option(option_symbol, mandatory: false)
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(@declared_options.key?(option_symbol), type: Cli::BadArgument){"Unknown option: #{option_symbol}"}
        option_attrs = @declared_options[option_symbol]
        result = option_attrs.value
        # Do not fail for manual generation if option mandatory but not set
        return :skip_missing_mandatory if result.nil? && mandatory && !@fail_on_missing_mandatory
        if result.nil?
          if !@ask_missing_mandatory
            Aspera.assert(!mandatory, type: Cli::BadArgument){"Missing mandatory option: #{option_symbol}"}
          elsif @ask_missing_optional || mandatory
            # ask_missing_mandatory
            result = get_interactive(option_symbol.to_s, check_option: true, accept_list: option_attrs.values)
            set_option(option_symbol, result, where: 'interactive')
          end
        end
        return result
      end

      # Set an option value by name, either store value or call handler
      # String is given to extended value
      # @param option_symbol [Symbol] option name
      # @param value [String] Value to set
      # @param where [String] Where the value comes from
      def set_option(option_symbol, value, where: 'code override')
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(@declared_options.key?(option_symbol), type: Cli::BadArgument){"Unknown option: #{option_symbol}"}
        @declared_options[option_symbol].assign_value(value, where: where)
      end

      # Set option to `nil`
      def clear_option(option_symbol)
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(@declared_options.key?(option_symbol), type: Cli::BadArgument){"Unknown option: #{option_symbol}"}
        @declared_options[option_symbol].clear
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
        return @unprocessed_cmd_line_arguments.empty?
      end

      # Unprocessed options or arguments ?
      def final_errors
        result = []
        result.push("unprocessed options: #{@unprocessed_cmd_line_options}") unless @unprocessed_cmd_line_options.empty?
        result.push("unprocessed values: #{@unprocessed_cmd_line_arguments}") unless @unprocessed_cmd_line_arguments.empty?
        return result
      end

      # Get all original options on command line used to generate a config in config file
      # @return [Hash] options as taken from config file and command line just before command execution
      def unprocessed_options_with_value
        result = {}
        @initial_cli_options.each do |option_value|
          case option_value
          when /^#{OPTION_PREFIX}([^=]+)$/o
            # ignore
          when /^#{OPTION_PREFIX}([^=]+)=(.*)$/o
            name = Regexp.last_match(1)
            value = Regexp.last_match(2)
            name.gsub!(OPTION_SEP_LINE, OPTION_SEP_SYMBOL)
            value = ExtendedValue.instance.evaluate(value, context: "option: #{name}")
            Log.log.debug{"option #{name}=#{value}"}
            result[name] = value
            @unprocessed_cmd_line_options.delete(option_value)
          else
            raise Cli::BadArgument, "wrong option format: #{option_value}"
          end
        end
        return result
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
        return result
      end

      # Removes already known options from the list
      def parse_options!
        Log.log.trace1('parse_options!'.red)
        # First options from conf file
        consume_option_pairs(@option_pairs_batch, 'set')
        # Then, env var (to override)
        consume_option_pairs(@option_pairs_env, 'env')
        # Then, command line override
        unknown_options = []
        begin
          # remove known options one by one, exception if unknown
          Log.log.trace1('Before parse')
          Log.dump(:unprocessed_cmd_line_options, @unprocessed_cmd_line_options)
          @parser.parse!(@unprocessed_cmd_line_options)
          Log.log.trace1('After parse')
        rescue OptionParser::InvalidOption => e
          Log.log.trace1{"InvalidOption #{e}".red}
          # An option like --a.b.c=d does: a={"b":{"c":ext_val(d)}}
          if (m = e.args.first.match(/^--([a-z\-]+)\.([^=]+)=(.+)$/))
            option, path, value = m.captures
            option_sym = self.class.option_line_to_name(option).to_sym
            if @declared_options.key?(option_sym)
              set_option(option_sym, DotContainer.dotted_to_container(path, smart_convert(value), get_option(option_sym)), where: 'dotted')
              retry
            end
          end
          # save for later processing
          unknown_options.push(e.args.first)
          retry
        end
        Log.log.trace1{"remains: #{unknown_options}"}
        # set unprocessed options for next time
        @unprocessed_cmd_line_options = unknown_options
      end

      def prompt_user_input(prompt, sensitive: false)
        return $stdin.getpass("#{prompt}> ") if sensitive
        print("#{prompt}> ")
        line = $stdin.gets
        Aspera.assert_type(line, String){'Unexpected end of standard input'}
        return line.chomp
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
      # @param multiple     [Boolean] true if multiple values expected
      # @param accept_list  [Array] list of expected values
      def get_interactive(descr, check_option: false, multiple: false, accept_list: nil)
        option_attrs = @declared_options[descr.to_sym]
        what = option_attrs ? 'option' : 'argument'
        if !@ask_missing_mandatory
          message = "missing #{what}: #{descr}"
          if accept_list.nil?
            raise Cli::BadArgument, message
          else
            Aspera.assert(false, self.class.multi_choice_assert_msg(message, accept_list), type: Cli::MissingArgument)
          end
        end
        default_prompt = "#{what}: #{descr}"
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
        return result
      end

      # Read remaining args and build an Array or Hash
      # @param value [nil] Argument to `@:` extended value
      def args_as_extended(arg)
        # This extended value does not take args (`@:`)
        ExtendedValue.assert_no_value(arg, :p)
        result = nil
        get_next_argument(:args, multiple: true).each do |arg|
          Aspera.assert(arg.include?(OPTION_VALUE_SEPARATOR)){"Positional argument: #{arg} does not inlude #{OPTION_VALUE_SEPARATOR}"}
          path, value = arg.split(OPTION_VALUE_SEPARATOR, 2)
          result = DotContainer.dotted_to_container(path, smart_convert(value), result)
        end
        result
      end

      # ======================================================
      private

      # Using dotted hash notation, convert value to bool, int, float or extended value
      # @param value [String] The value to convert to appropriate type
      # @return the converted value
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
        return result
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
      # boolean options are set to true/false from the following values
      BOOL_YES = BOOLEAN_SIMPLE.last
      BOOL_NO = BOOLEAN_SIMPLE.first
      FALSE_VALUES = [BOOL_NO, false].freeze
      TRUE_VALUES = [BOOL_YES, true].freeze
      BOOLEAN_VALUES = (TRUE_VALUES + FALSE_VALUES).freeze

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

      private_constant :BOOL_YES, :BOOL_NO, :FALSE_VALUES, :TRUE_VALUES, :OPTION_SEP_LINE, :OPTION_SEP_SYMBOL, :OPTION_VALUE_SEPARATOR, :OPTION_PREFIX, :OPTIONS_STOP, :SOURCE_USER
    end
  end
end
