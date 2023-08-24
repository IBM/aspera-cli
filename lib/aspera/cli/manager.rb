# frozen_string_literal: true

require 'aspera/colors'
require 'aspera/log'
require 'aspera/secret_hider'
require 'aspera/cli/extended_value'
require 'optparse'
require 'io/console'

module Aspera
  module Cli
    # raised by cli on error conditions
    class CliError < StandardError; end

    # raised when an unexpected argument is provided
    class CliBadArgument < Aspera::Cli::CliError; end

    class CliNoSuchId < Aspera::Cli::CliError
      def initialize(res_type, res_id)
        msg = "No such #{res_type} identifier: #{res_id}"
        super(msg)
      end
    end

    # option is retrieved from another object using accessor
    class AttrAccessor
      # attr_accessor :object
      # attr_accessor :attr_symb
      def initialize(object, attr_symb)
        @object = object
        @attr_symb = attr_symb
      end

      def value
        return @object.send(@attr_symb)
      end

      def value=(val)
        @object.send("#{@attr_symb}=", val)
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
      OPTION_SEP_SYMB = '_'

      private_constant :FALSE_VALUES, :TRUE_VALUES, :BOOLEAN_VALUES, :OPTION_SEP_LINE, :OPTION_SEP_SYMB

      class << self
        def enum_to_bool(enum)
          raise "Value not valid for boolean: [#{enum}]/#{enum.class}" unless BOOLEAN_VALUES.include?(enum)
          return TRUE_VALUES.include?(enum)
        end

        def time_to_string(time)
          return time.strftime('%Y-%m-%d %H:%M:%S')
        end

        # find shortened string value in allowed symbol list
        def get_from_list(shortval, descr, allowed_values)
          # we accept shortcuts
          matching_exact = allowed_values.select{|i| i.to_s.eql?(shortval)}
          return matching_exact.first if matching_exact.length == 1
          matching = allowed_values.select{|i| i.to_s.start_with?(shortval)}
          raise CliBadArgument, bad_arg_message_multi("unknown value for #{descr}: #{shortval}", allowed_values) if matching.empty?
          raise CliBadArgument, bad_arg_message_multi("ambiguous shortcut for #{descr}: #{shortval}", matching) unless matching.length.eql?(1)
          return enum_to_bool(matching.first) if allowed_values.eql?(BOOLEAN_VALUES)
          return matching.first
        end

        def bad_arg_message_multi(error_msg, choices)
          return [error_msg, 'Use:'].concat(choices.map{|c|"- #{c}"}.sort).join("\n")
        end

        # change option name with dash to name with underscore
        def option_line_to_name(name)
          return name.gsub(OPTION_SEP_LINE, OPTION_SEP_SYMB)
        end

        def option_name_to_line(name)
          return "--#{name.to_s.gsub(OPTION_SEP_SYMB, OPTION_SEP_LINE)}"
        end
      end

      attr_reader :parser
      attr_accessor :ask_missing_mandatory, :ask_missing_optional
      attr_writer :fail_on_missing_mandatory

      def initialize(program_name, argv: nil)
        # command line values not starting with '-'
        @unprocessed_cmd_line_arguments = []
        # command line values starting with '-'
        @unprocessed_cmd_line_options = []
        # a copy of all initial options
        @initial_cli_options = []
        # option description: key = option symbol, value=hash, :read_write, :accessor, :value, :accepted
        @declared_options = {}
        # do we ask missing options and arguments to user ?
        @ask_missing_mandatory = false # STDIN.isatty
        # ask optional options if not provided and in interactive
        @ask_missing_optional = false
        @fail_on_missing_mandatory = true
        # those must be set before parse, parse consumes those defined only
        @unprocessed_defaults = []
        @unprocessed_env = []
        # NOTE: was initially inherited but it is preferred to have specific methods
        @parser = OptionParser.new
        @parser.program_name = program_name
        # options can also be provided by env vars : --param-name -> ASCLI_PARAM_NAME
        env_prefix = program_name.upcase + OPTION_SEP_SYMB
        ENV.each do |k, v|
          if k.start_with?(env_prefix)
            @unprocessed_env.push([k[env_prefix.length..-1].downcase.to_sym, v])
          end
        end
        Log.log.debug{"env=#{@unprocessed_env}".red}
        @unprocessed_cmd_line_options = []
        @unprocessed_cmd_line_arguments = []
        # argv is nil when help is generated for every plugin
        unless argv.nil?
          @parser.separator('')
          @parser.separator('OPTIONS: global')
          declare(:interactive, 'Use interactive input of missing params', values: :bool, handler: {o: self, m: :ask_missing_mandatory})
          declare(:ask_options, 'Ask even optional options', values: :bool, handler: {o: self, m: :ask_missing_optional})
          parse_options!
          process_options = true
          until argv.empty?
            value = argv.shift
            if process_options && value.start_with?('-')
              if value.eql?('--')
                process_options = false
              else
                @unprocessed_cmd_line_options.push(value)
              end
            else
              @unprocessed_cmd_line_arguments.push(value)
            end
          end
        end
        @initial_cli_options = @unprocessed_cmd_line_options.dup
        Log.log.debug{"add_cmd_line_options:commands/args=#{@unprocessed_cmd_line_arguments},options=#{@unprocessed_cmd_line_options}".red}
      end

      # @param expected is
      #    - Array of allowed value (single value)
      #    - :multiple for remaining values
      #    - :single for a single unconstrained value
      # @param mandatory true/false
      # @param type expected class for result
      # @param aliases list of aliases for the value
      # @return value, list or nil
      def get_next_argument(descr, expected: :single, mandatory: true, type: nil, aliases: nil, default: nil)
        unless type.nil?
          raise 'internal: type must be a Class' unless type.is_a?(Class)
          descr = "#{descr} (#{type})"
        end
        result = default
        if !@unprocessed_cmd_line_arguments.empty?
          # there are values
          case expected
          when :single
            result = ExtendedValue.instance.evaluate(@unprocessed_cmd_line_arguments.shift)
          when :multiple
            result = @unprocessed_cmd_line_arguments.shift(@unprocessed_cmd_line_arguments.length).map{|v|ExtendedValue.instance.evaluate(v)}
            # if expecting list and only one arg of type array : it is the list
            if result.length.eql?(1) && result.first.is_a?(Array)
              result = result.first
            end
          when Array
            allowed_values = [].concat(expected)
            allowed_values.concat(aliases.keys) unless aliases.nil?
            raise "internal error: only symbols allowed: #{allowed_values}" unless allowed_values.all?(Symbol)
            result = self.class.get_from_list(@unprocessed_cmd_line_arguments.shift, descr, allowed_values)
          else
            raise 'internal error'
          end
        elsif mandatory
          # no value provided
          result = get_interactive(:argument, descr, expected: expected)
        end
        Log.log.debug{"#{descr}=#{result}"}
        result = aliases[result] if !aliases.nil? && aliases.key?(result)
        raise "argument shall be #{type.name}" unless type.nil? || result.is_a?(type)
        return result
      end

      def get_next_command(command_list, aliases: nil); return get_next_argument('command', expected: command_list, aliases: aliases); end

      # Get an option value by name
      # either return value or calls handler, can return nil
      # ask interactively if requested/required
      # @param is_type :mandatory or :optional
      def get_option(option_symbol, is_type: :optional, allowed_types: nil)
        result = nil
        if @declared_options.key?(option_symbol)
          case @declared_options[option_symbol][:read_write]
          when :accessor
            result = @declared_options[option_symbol][:accessor].value
          when :value
            result = @declared_options[option_symbol][:value]
          else
            raise 'unknown type'
          end
          Log.log.debug{"(#{@declared_options[option_symbol][:read_write]}) get #{option_symbol}=#{result}"}
        end
        # do not fail for manual generation if option mandatory but not set
        result = '' if result.nil? && is_type.eql?(:mandatory) && !@fail_on_missing_mandatory
        # Log.log.debug{"interactive=#{@ask_missing_mandatory}"}
        if result.nil?
          if !@ask_missing_mandatory
            raise CliBadArgument, "Missing mandatory option: #{option_symbol}" if is_type.eql?(:mandatory)
          elsif @ask_missing_optional || is_type.eql?(:mandatory)
            # ask_missing_mandatory
            expected = :single
            # print "please enter: #{option_symbol.to_s}"
            if @declared_options.key?(option_symbol) && @declared_options[option_symbol].key?(:values)
              expected = @declared_options[option_symbol][:values]
            end
            result = get_interactive(:option, option_symbol.to_s, expected: expected)
            set_option(option_symbol, result, 'interactive')
          end
        end
        raise "option #{option_symbol} is #{result.class} but must be one of #{allowed_types}" unless allowed_types.nil? || allowed_types.any?{|t|result.is_a?(t)}
        return result
      end

      # set an option value by name, either store value or call handler
      def set_option(option_symbol, value, where='code override')
        raise CliBadArgument, "Unknown option: #{option_symbol}" unless @declared_options.key?(option_symbol)
        attributes = @declared_options[option_symbol]
        Log.log.warn("#{option_symbol}: Option is deprecated: #{attributes[:deprecation]}") if attributes[:deprecation]
        value = ExtendedValue.instance.evaluate(value)
        value = Manager.enum_to_bool(value) if attributes[:values].eql?(BOOLEAN_VALUES)
        Log.log.debug{"(#{attributes[:read_write]}/#{where}) set #{option_symbol}=#{value}"}
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
      # @param coerce [Class] one of the coerce types accepted par option parser
      # @param types [Class, Array] accepted value type(s)
      # @param block [Proc] block to execute when option is found
      def declare(option_symbol, description, handler: nil, default: nil, values: nil, short: nil, coerce: nil, types: nil, deprecation: nil, &block)
        raise "INTERNAL ERROR: #{option_symbol} already declared" if @declared_options.key?(option_symbol)
        raise "INTERNAL ERROR: #{option_symbol} ends with dot" unless description[-1] != '.'
        raise "INTERNAL ERROR: #{option_symbol} does not start with capital" unless description[0] == description[0].upcase
        raise "INTERNAL ERROR: #{option_symbol} shall use :types" if description.downcase.include?('hash') || description.downcase.include?('extended value')
        opt = @declared_options[option_symbol] = {
          read_write: handler.nil? ? :value : :accessor,
          # by default passwords and secrets are sensitive, else specify when declaring the option
          sensitive:  SecretHider.secret?(option_symbol, '')
        }
        if !types.nil?
          types = [types] unless types.is_a?(Array)
          raise "INTERNAL ERROR: types must be classes: #{types}" unless types.all?(Class)
          opt[:types] = types
          description = "#{description} (#{types.map(&:name).join(', ')})"
        end
        if deprecation
          opt[:deprecation] = deprecation
          description = "#{description} (#{'deprecated'.blue}: #{deprecation})"
        end
        Log.log.debug{"declare: #{option_symbol}: #{opt[:read_write]}".green}
        if opt[:read_write].eql?(:accessor)
          raise 'internal error' unless handler.is_a?(Hash)
          raise 'internal error' unless handler.keys.sort.eql?(%i[m o])
          Log.log.debug{"set attr obj #{option_symbol} (#{handler[:o]},#{handler[:m]})"}
          opt[:accessor] = AttrAccessor.new(handler[:o], handler[:m])
        end
        set_option(option_symbol, default, 'default') unless default.nil?
        on_args = [description]
        case values
        when nil
          on_args.push(symbol_to_option(option_symbol, 'VALUE'))
          on_args.push("-#{short}VALUE") unless short.nil?
          on_args.push(coerce) unless coerce.nil?
          @parser.on(*on_args) { |v| set_option(option_symbol, v, 'cmdline') }
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
          @parser.on(*on_args){|v|set_option(option_symbol, self.class.get_from_list(v.to_s, description, values), 'cmdline')}
        when :date
          on_args.push(symbol_to_option(option_symbol, 'DATE'))
          @parser.on(*on_args) do |v|
            time_string = case v
            when 'now' then Manager.time_to_string(Time.now)
            when /^-([0-9]+)h/ then Manager.time_to_string(Time.now - (Regexp.last_match(1).to_i * 3600))
            else v
            end
            set_option(option_symbol, time_string, 'cmdline')
          end
        when :none
          raise "internal error: missing block for #{option_symbol}" if block.nil?
          on_args.push(symbol_to_option(option_symbol, nil))
          on_args.push("-#{short}") if short.is_a?(String)
          @parser.on(*on_args, &block)
        else raise 'internal error'
        end
        Log.log.debug{"on_args=#{on_args}"}
      end

      # Adds each of the keys of specified hash as an option
      # @param preset_hash [Hash] hash of options to add
      def add_option_preset(preset_hash, op: :push)
        Log.log.debug{"add_option_preset=#{preset_hash}"}
        raise "internal error: default expects Hash: #{preset_hash.class}" unless preset_hash.is_a?(Hash)
        # incremental override
        preset_hash.each{|k, v|@unprocessed_defaults.send(op, [k.to_sym, v])}
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
      def get_options_table(remove_from_remaining: true)
        result = {}
        @initial_cli_options.each do |optionval|
          case optionval
          when /^--([^=]+)$/
            # ignore
          when /^--([^=]+)=(.*)$/
            name = Regexp.last_match(1)
            value = Regexp.last_match(2)
            name.gsub!(OPTION_SEP_LINE, OPTION_SEP_SYMB)
            value = ExtendedValue.instance.evaluate(value)
            Log.log.debug{"option #{name}=#{value}"}
            result[name] = value
            @unprocessed_cmd_line_options.delete(optionval) if remove_from_remaining
          else
            raise CliBadArgument, "wrong option format: #{optionval}"
          end
        end
        return result
      end

      # return options as taken from config file and command line just before command execution
      def declared_options(only_defined: false)
        result = {}
        @declared_options.each_key do |option_symb|
          v = get_option(option_symb)
          result[option_symb.to_s] = v unless only_defined && v.nil?
        end
        return result
      end

      # removes already known options from the list
      def parse_options!
        Log.log.debug('parse_options!'.red)
        # first conf file, then env var
        apply_options_preset(@unprocessed_defaults, 'file')
        apply_options_preset(@unprocessed_env, 'env')
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

      private

      def prompt_user_input(prompt, sensitive)
        return $stdin.getpass("#{prompt}> ") if sensitive
        print("#{prompt}> ")
        return $stdin.gets.chomp
      end

      def get_interactive(type, descr, expected: :single)
        if !@ask_missing_mandatory
          raise CliBadArgument, self.class.bad_arg_message_multi("missing: #{descr}", expected) if expected.is_a?(Array)
          raise CliBadArgument, "missing argument (#{expected}): #{descr}"
        end
        result = nil
        sensitive = type.eql?(:option) && @declared_options[descr.to_sym][:sensitive]
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

      # generate command line option from option symbol
      def symbol_to_option(symbol, opt_val)
        result = '--' + symbol.to_s.gsub(OPTION_SEP_SYMB, OPTION_SEP_LINE)
        result = result + '=' + opt_val unless opt_val.nil?
        return result
      end

      def highlight_current(value)
        $stdout.isatty ? value.to_s.red.bold : "[#{value}]"
      end

      def apply_options_preset(preset, where)
        unprocessed = []
        preset.each do |pair|
          k, v = *pair
          if @declared_options.key?(k)
            # constrained parameters as string are revert to symbol
            if @declared_options[k].key?(:values) && v.is_a?(String)
              v = self.class.get_from_list(v, k.to_s + " in #{where}", @declared_options[k][:values])
            end
            set_option(k, v, where)
          else
            unprocessed.push(pair)
          end
        end
        # keep only unprocessed values for next parse
        preset.clear
        preset.push(*unprocessed)
      end
    end
  end
end
