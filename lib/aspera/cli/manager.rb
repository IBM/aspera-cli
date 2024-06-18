# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/error'
require 'aspera/colors'
require 'aspera/secret_hider'
require 'aspera/log'
require 'aspera/assert'
require 'io/console'
require 'optparse'

module Aspera
  module Cli
    # option is retrieved from another object using accessor
    class AttrAccessor
      # attr_accessor :object
      # attr_accessor :method_name
      def initialize(object, method_name, option_name)
        @object = object
        @method = method_name
        @option_name = option_name
        @has_writer = @object.respond_to?(writer_method)
        Log.log.debug{"AttrAccessor: #{@option_name}: #{@object.class}.#{@method}: writer=#{@has_writer}"}
        Aspera.assert(@object.respond_to?(@method)) {"#{object} does not respond to #{method_name}"}
      end

      def value
        return @object.send(@method) if @has_writer
        return @object.send(@method, @option_name, :get)
      end

      def value=(val)
        Log.log.trace1{"AttrAccessor: = #{@method} #{@option_name} :set #{val}, writer=#{@has_writer}"}
        return @object.send(writer_method, val) if @has_writer
        return @object.send(@method, @option_name, :set, val)
      end

      def writer_method
        return "#{@method}="
      end
    end

    # parse command line options
    # arguments options start with '-', others are commands
    # resolves on extended value syntax
    class Manager
      # boolean options are set to true/false from the following values
      BOOLEAN_SIMPLE = %i[no yes].freeze
      FALSE_VALUES = [BOOLEAN_SIMPLE.first, false].freeze
      TRUE_VALUES = [BOOLEAN_SIMPLE.last, true].freeze
      BOOLEAN_VALUES = [TRUE_VALUES, FALSE_VALUES].flatten.freeze

      # option name separator on command line
      OPTION_SEP_LINE = '-'
      # option name separator in code (symbol)
      OPTION_SEP_SYMBOL = '_'
      SOURCE_USER = 'cmdline' # cspell:disable-line
      TYPE_INTEGER = [Integer].freeze
      OPTION_VALUE_SEPARATOR = '='
      OPTION_PREFIX = '--'
      OPTIONS_STOP = '--'

      private_constant :FALSE_VALUES, :TRUE_VALUES, :BOOLEAN_VALUES, :OPTION_SEP_LINE, :OPTION_SEP_SYMBOL, :SOURCE_USER, :TYPE_INTEGER

      class << self
        def enum_to_bool(enum)
          Aspera.assert_values(enum, BOOLEAN_VALUES){'boolean'}
          return TRUE_VALUES.include?(enum)
        end

        def time_to_string(time)
          return time.strftime('%Y-%m-%d %H:%M:%S')
        end

        # find shortened string value in allowed symbol list
        def get_from_list(short_value, descr, allowed_values)
          # we accept shortcuts
          matching_exact = allowed_values.select{|i| i.to_s.eql?(short_value)}
          return matching_exact.first if matching_exact.length == 1
          matching = allowed_values.select{|i| i.to_s.start_with?(short_value)}
          multi_choice_assert(!matching.empty?, "unknown value for #{descr}: #{short_value}", allowed_values)
          multi_choice_assert(matching.length.eql?(1), "ambiguous shortcut for #{descr}: #{short_value}", matching)
          return enum_to_bool(matching.first) if allowed_values.eql?(BOOLEAN_VALUES)
          return matching.first
        end

        # Generates error message with list of allowed values
        # @param error_msg [String] error message
        # @param choices [Array] list of allowed values
        def multi_choice_assert(assertion, error_msg, choices)
          raise Cli::BadArgument, [error_msg, 'Use:'].concat(choices.map{|c|"- #{c}"}.sort).join("\n") unless assertion
        end

        # change option name with dash to name with underscore
        def option_line_to_name(name)
          return name.gsub(OPTION_SEP_LINE, OPTION_SEP_SYMBOL)
        end

        def option_name_to_line(name)
          return "#{OPTION_PREFIX}#{name.to_s.gsub(OPTION_SEP_SYMBOL, OPTION_SEP_LINE)}"
        end

        # @param what [Symbol] :option or :argument
        # @param descr [String] description for help
        # @param value [Object] value to check
        # @param type_list [NilClass, Class, Array[Class]] accepted value type(s)
        def validate_type(what, descr, value, type_list)
          return nil if type_list.nil?
          Aspera.assert(type_list.is_a?(Array) && type_list.all?(Class)){'types must be a Class Array'}
          raise Cli::BadArgument,
            "#{what.to_s.capitalize} #{descr} is a #{value.class} but must be #{type_list.length > 1 ? 'one of ' : ''}#{type_list.map(&:name).join(',')}" unless \
            type_list.any?{|t|value.is_a?(t)}
        end
      end

      attr_reader :parser
      attr_accessor :ask_missing_mandatory, :ask_missing_optional
      attr_writer :fail_on_missing_mandatory

      def initialize(program_name)
        # command line values *not* starting with '-'
        @unprocessed_cmd_line_arguments = []
        # command line values starting with '-'
        @unprocessed_cmd_line_options = []
        # a copy of all initial options
        @initial_cli_options = []
        # option description: key = option symbol, value=Hash, :read_write, :accessor, :value, :accepted
        @declared_options = {}
        # do we ask missing options and arguments to user ?
        @ask_missing_mandatory = false # STDIN.isatty
        # ask optional options if not provided and in interactive
        @ask_missing_optional = false
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
          if k.start_with?(env_prefix)
            @option_pairs_env[k[env_prefix.length..-1].downcase.to_sym] = v
          end
        end
        Log.log.debug{"env=#{@option_pairs_env}".red}
        @unprocessed_cmd_line_options = []
        @unprocessed_cmd_line_arguments = []
      end

      def parse_command_line(argv)
        @parser.separator('')
        @parser.separator('OPTIONS: global')
        declare(:interactive, 'Use interactive input of missing params', values: :bool, handler: {o: self, m: :ask_missing_mandatory})
        declare(:ask_options, 'Ask even optional options', values: :bool, handler: {o: self, m: :ask_missing_optional})
        parse_options!
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
        Log.log.debug{"add_cmd_line_options:commands/arguments=#{@unprocessed_cmd_line_arguments},options=#{@unprocessed_cmd_line_options}".red}
      end

      # @param descr [String] description for help
      # @param expected is
      #   - Array of allowed value (single value)
      #   - :multiple for remaining values
      #   - :single for a single unconstrained value
      #   - :integer for a single integer value
      # @param mandatory [Boolean] if true, raise error if option not set
      # @param type [Class, Array] accepted value type(s)
      # @param aliases [Hash] map of aliases: key = alias, value = real value
      # @param default [Object] default value
      # @return value, list or nil
      def get_next_argument(descr, expected: :single, mandatory: true, type: nil, aliases: nil, default: nil)
        Aspera.assert(%i[single multiple].include?(expected) || (expected.is_a?(Array) && expected.all?(Symbol))) do
          'expected must be single, multiple, or array of symbol'
        end
        Aspera.assert(type.nil? || type.is_a?(Class) || (type.is_a?(Array) && type.all?(Class))){'type must be Class or Array of Class'}
        Aspera.assert(aliases.nil? || (aliases.is_a?(Hash) && aliases.keys.all?(Symbol) && aliases.values.all?(Symbol))){'aliases must be Hash'}
        allowed_types = type
        unless allowed_types.nil?
          allowed_types = [allowed_types] unless allowed_types.is_a?(Array)
          descr = "#{descr} (#{allowed_types.join(', ')})"
        end
        result =
          if !@unprocessed_cmd_line_arguments.empty?
            # there are values
            case expected
            when :single
              ExtendedValue.instance.evaluate(@unprocessed_cmd_line_arguments.shift)
            when :multiple
              value = @unprocessed_cmd_line_arguments.shift(@unprocessed_cmd_line_arguments.length).map{|v|ExtendedValue.instance.evaluate(v)}
              # if expecting list and only one arg of type array : it is the list
              if value.length.eql?(1) && value.first.is_a?(Array)
                value = value.first
              end
              value
            when Array
              allowed_values = [].concat(expected)
              allowed_values.concat(aliases.keys) unless aliases.nil?
              self.class.get_from_list(@unprocessed_cmd_line_arguments.shift, descr, allowed_values)
            else Aspera.error_unexpected_value(expected)
            end
          elsif !default.nil? then default
            # no value provided, either get value interactively, or exception
          elsif mandatory then get_interactive(:argument, descr, expected: expected)
          end
        if result.is_a?(String) && allowed_types.eql?(TYPE_INTEGER)
          int_result = Integer(result, exception: false)
          raise Cli::BadArgument, "Invalid integer: #{result}" if int_result.nil?
          result = int_result
        end
        Log.log.debug{"#{descr}=#{result}"}
        result = aliases[result] if aliases&.key?(result)
        self.class.validate_type(:argument, descr, result, allowed_types) unless result.nil? && !mandatory
        return result
      end

      def get_next_command(command_list, aliases: nil); return get_next_argument('command', expected: command_list, aliases: aliases); end

      # Get an option value by name
      # either return value or calls handler, can return nil
      # ask interactively if requested/required
      # @param mandatory [Boolean] if true, raise error if option not set
      def get_option(option_symbol, mandatory: false, default: nil)
        Aspera.assert_type(option_symbol, Symbol)
        attributes = @declared_options[option_symbol]
        Aspera.assert(attributes){"option not declared: #{option_symbol}"}
        result = nil
        case attributes[:read_write]
        when :accessor
          result = attributes[:accessor].value
        when :value
          result = attributes[:value]
        else
          raise 'unknown type'
        end
        Log.log.debug{"(#{attributes[:read_write]}) get #{option_symbol}=#{result}"}
        result = default if result.nil?
        # do not fail for manual generation if option mandatory but not set
        result = '' if result.nil? && mandatory && !@fail_on_missing_mandatory
        # Log.log.debug{"interactive=#{@ask_missing_mandatory}"}
        if result.nil?
          if !@ask_missing_mandatory
            raise Cli::BadArgument, "Missing mandatory option: #{option_symbol}" if mandatory
          elsif @ask_missing_optional || mandatory
            # ask_missing_mandatory
            expected = :single
            # print "please enter: #{option_symbol.to_s}"
            if @declared_options.key?(option_symbol) && attributes.key?(:values)
              expected = attributes[:values]
            end
            result = get_interactive(:option, option_symbol.to_s, expected: expected)
            set_option(option_symbol, result, 'interactive')
          end
        end
        self.class.validate_type(:option, option_symbol, result, attributes[:types]) unless result.nil? && !mandatory
        return result
      end

      # set an option value by name, either store value or call handler
      def set_option(option_symbol, value, where='code override')
        Aspera.assert_type(option_symbol, Symbol)
        raise Cli::BadArgument, "Unknown option: #{option_symbol}" unless @declared_options.key?(option_symbol)
        attributes = @declared_options[option_symbol]
        Log.log.warn("#{option_symbol}: Option is deprecated: #{attributes[:deprecation]}") if attributes[:deprecation]
        value = ExtendedValue.instance.evaluate(value)
        value = Manager.enum_to_bool(value) if attributes[:values].eql?(BOOLEAN_VALUES)
        Log.log.debug{"(#{attributes[:read_write]}/#{where}) set #{option_symbol}=#{value}"}
        self.class.validate_type(:option, option_symbol, value, attributes[:types])
        case attributes[:read_write]
        when :accessor
          attributes[:accessor].value = value
        when :value
          attributes[:value] = value
        else # nil or other
          raise 'error'
        end
      end

      # declare an option
      # @param option_symbol [Symbol] option name
      # @param description [String] description for help
      # @param handler [Hash] handler for option value: keys: o (object) and m (method)
      # @param default [Object] default value
      # @param values [nil, Array, :bool, :date, :none] list of allowed values, :bool for true/false, :date for dates, :none for on/off switch
      # @param short [String] short option name
      # @param coerce [Class] one of the coerce types accepted by option parser
      # @param types [Class, Array] accepted value type(s)
      # @param block [Proc] block to execute when option is found
      def declare(option_symbol, description, handler: nil, default: nil, values: nil, short: nil, coerce: nil, types: nil, deprecation: nil, &block)
        Aspera.assert_type(option_symbol, Symbol)
        Aspera.assert(!@declared_options.key?(option_symbol)){"#{option_symbol} already declared"}
        Aspera.assert(description[-1] != '.'){"#{option_symbol} ends with dot"}
        Aspera.assert(description[0] == description[0].upcase){"#{option_symbol} description does not start with capital"}
        Aspera.assert(!['hash', 'extended value'].any?{|s|description.downcase.include?(s) }){"#{option_symbol} shall use :types"}
        opt = @declared_options[option_symbol] = {
          read_write: handler.nil? ? :value : :accessor,
          # by default passwords and secrets are sensitive, else specify when declaring the option
          sensitive:  SecretHider.secret?(option_symbol, '')
        }
        if !types.nil?
          types = [types] unless types.is_a?(Array)
          Aspera.assert(types.all?(Class)){"types must be (Array of) Class: #{types}"}
          opt[:types] = types
          description = "#{description} (#{types.map(&:name).join(', ')})"
        end
        if deprecation
          opt[:deprecation] = deprecation
          description = "#{description} (#{'deprecated'.blue}: #{deprecation})"
        end
        Log.log.debug{"declare: #{option_symbol}: #{opt[:read_write]}".green}
        if opt[:read_write].eql?(:accessor)
          Aspera.assert_type(handler, Hash)
          Aspera.assert(handler.keys.sort.eql?(%i[m o]))
          Log.log.debug{"set attr obj #{option_symbol} (#{handler[:o]},#{handler[:m]})"}
          opt[:accessor] = AttrAccessor.new(handler[:o], handler[:m], option_symbol)
        end
        set_option(option_symbol, default, 'default') unless default.nil?
        on_args = [description]
        case values
        when nil
          on_args.push(symbol_to_option(option_symbol, 'VALUE'))
          on_args.push("-#{short}VALUE") unless short.nil?
          on_args.push(coerce) unless coerce.nil?
          @parser.on(*on_args) { |v| set_option(option_symbol, v, SOURCE_USER) }
        when Array, :bool
          if values.eql?(:bool)
            values = BOOLEAN_VALUES
            set_option(option_symbol, Manager.enum_to_bool(default), 'default') unless default.nil?
          end
          # this option value must be a symbol
          opt[:values] = values
          value = get_option(option_symbol)
          help_values = values.map{|i|i.eql?(value) ? highlight_current(i) : i}.join(', ')
          if values.eql?(BOOLEAN_VALUES)
            help_values = BOOLEAN_SIMPLE.map{|i|(i.eql?(:yes) && value) || (i.eql?(:no) && !value) ? highlight_current(i) : i}.join(', ')
          end
          on_args[0] = "#{description}: #{help_values}"
          on_args.push(symbol_to_option(option_symbol, 'ENUM'))
          on_args.push(values)
          @parser.on(*on_args){|v|set_option(option_symbol, self.class.get_from_list(v.to_s, description, values), SOURCE_USER)}
        when :date
          on_args.push(symbol_to_option(option_symbol, 'DATE'))
          @parser.on(*on_args) do |v|
            time_string = case v
            when 'now' then Manager.time_to_string(Time.now)
            when /^-([0-9]+)h/ then Manager.time_to_string(Time.now - (Regexp.last_match(1).to_i * 3600))
            else v
            end
            set_option(option_symbol, time_string, SOURCE_USER)
          end
        when :none
          Aspera.assert(!block.nil?){"missing block for #{option_symbol}"}
          on_args.push(symbol_to_option(option_symbol))
          on_args.push("-#{short}") if short.is_a?(String)
          @parser.on(*on_args, &block)
        else Aspera.error_unexpected_value(values)
        end
        Log.log.debug{"on_args=#{on_args}"}
      end

      # Adds each of the keys of specified hash as an option
      # @param preset_hash [Hash] hash of options to add
      def add_option_preset(preset_hash, where, override: true)
        Aspera.assert_type(preset_hash, Hash)
        Log.log.debug{"add_option_preset: #{preset_hash}"}
        preset_hash.each do |k, v|
          option_symbol = k.to_sym
          @option_pairs_batch[option_symbol] = v unless !override && @declared_options[option_symbol]&.key?(:value)
        end
        consume_option_pairs(@option_pairs_batch, where)
      end

      # check if there were unprocessed values to generate error
      def command_or_arg_empty?
        return @unprocessed_cmd_line_arguments.empty?
      end

      # unprocessed options or arguments ?
      def final_errors
        result = []
        result.push("unprocessed options: #{@unprocessed_cmd_line_options}") unless @unprocessed_cmd_line_options.empty?
        result.push("unprocessed values: #{@unprocessed_cmd_line_arguments}") unless @unprocessed_cmd_line_arguments.empty?
        return result
      end

      # get all original options on command line used to generate a config in config file
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
            value = ExtendedValue.instance.evaluate(value)
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
        end
        return result
      end

      # removes already known options from the list
      def parse_options!
        Log.log.debug('parse_options!'.red)
        # first conf file, then env var
        consume_option_pairs(@option_pairs_batch, 'set')
        consume_option_pairs(@option_pairs_env, 'env')
        # command line override
        unknown_options = []
        begin
          # remove known options one by one, exception if unknown
          Log.log.debug('before parse'.red)
          @parser.parse!(@unprocessed_cmd_line_options)
          Log.log.debug('After parse'.red)
        rescue OptionParser::InvalidOption => e
          Log.log.debug{"InvalidOption #{e}".red}
          # save for later processing
          unknown_options.push(e.args.first)
          retry
        end
        Log.log.debug{"remains: #{unknown_options}"}
        # set unprocessed options for next time
        @unprocessed_cmd_line_options = unknown_options
      end

      def prompt_user_input(prompt, sensitive)
        return $stdin.getpass("#{prompt}> ") if sensitive
        print("#{prompt}> ")
        line = $stdin.gets
        raise 'Unexpected end of standard input' if line.nil?
        return line.chomp
      end

      # prompt user for input in a list of symbols
      # @param prompt [String] prompt to display
      # @param sym_list [Array] list of symbols to select from
      # @return [Symbol] selected symbol
      def prompt_user_input_in_list(prompt, sym_list)
        loop do
          input = prompt_user_input(prompt, false).to_sym
          if sym_list.any?{|a|a.eql?(input)}
            return input
          else
            $stderr.puts("No such #{prompt}: #{input}, select one of: #{sym_list.join(', ')}")
          end
        end
      end

      def get_interactive(type, descr, expected: :single)
        if !@ask_missing_mandatory
          raise Cli::BadArgument, "missing argument (#{expected}): #{descr}" unless expected.is_a?(Array)
          self.class.multi_choice_assert(false, "missing: #{descr}", expected)
        end
        result = nil
        sensitive = type.eql?(:option) && @declared_options[descr.to_sym].is_a?(Hash) && @declared_options[descr.to_sym][:sensitive]
        default_prompt = "#{type}: #{descr}"
        # ask interactively
        case expected
        when :multiple
          result = []
          puts(' (one per line, end with empty line)')
          loop do
            entry = prompt_user_input(default_prompt, sensitive)
            break if entry.empty?
            result.push(ExtendedValue.instance.evaluate(entry))
          end
        when :single
          result = ExtendedValue.instance.evaluate(prompt_user_input(default_prompt, sensitive))
        else # one fixed
          result = self.class.get_from_list(prompt_user_input("#{expected.join(' ')}\n#{default_prompt}", sensitive), descr, expected)
        end
        return result
      end

      private

      # generate command line option from option symbol
      def symbol_to_option(symbol, opt_val = nil)
        result = [OPTION_PREFIX, symbol.to_s.gsub(OPTION_SEP_SYMBOL, OPTION_SEP_LINE)].join
        result = [result, OPTION_VALUE_SEPARATOR, opt_val].join unless opt_val.nil?
        return result
      end

      def highlight_current(value)
        $stdout.isatty ? value.to_s.red.bold : "[#{value}]"
      end

      # try to evaluate options set ib batch
      # @param preset_pairs [Array] list of options to apply (key_sym,value)
      # @param where [String] where the options come from
      def consume_option_pairs(preset_pairs, where)
        Log.log.debug{"consume_option_pairs: #{where}"}
        processed = []
        Log.log.debug{PP.pp(@declared_options.keys)}
        preset_pairs.each do |k, v|
          if @declared_options.key?(k)
            # constrained parameters as string are revert to symbol
            if @declared_options[k].key?(:values) && v.is_a?(String)
              v = self.class.get_from_list(v, "#{k} in #{where}", @declared_options[k][:values])
            end
            set_option(k, v, where)
            processed.push(k)
          else
            Log.log.debug{"unprocessed: #{k}=#{v}"}
          end
        end
        # keep only unprocessed values for next parse
        processed.each{|k|preset_pairs.delete(k)}
      end
    end
  end
end
