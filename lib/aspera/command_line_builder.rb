# frozen_string_literal: true

module Aspera
  # helper class to build command line from a parameter list (key-value hash)
  # constructor takes hash: { 'param1':'value1', ...}
  # process_param is called repeatedly with all known parameters
  # add_env_args is called to get resulting param list and env var (also checks that all params were used)
  class CommandLineBuilder
    # parameter with one of those tags is a command line option with --
    CLI_OPTION_TYPE_SWITCH = %i[opt_without_arg opt_with_arg].freeze
    CLI_OPTION_TYPES = %i[special ignore envvar].concat(CLI_OPTION_TYPE_SWITCH).freeze
    OPTIONS_KEYS = %i[desc accepted_types default enum agents required cli ts].freeze
    CLI_KEYS = %i[type switch convert variable].freeze

    private_constant :CLI_OPTION_TYPE_SWITCH, :OPTIONS_KEYS, :CLI_KEYS

    class << self
      # transform yes/no to true/false
      def yes_to_true(value)
        case value
        when 'yes' then return true
        when 'no' then return false
        end
        raise "unsupported value: #{value}"
      end

      # Called by provider of definition before constructor of this class so that params_definition has all mandatory fields
      def normalize_description(full_description)
        full_description.each do |name, options|
          raise "Expecting Hash, but have #{options.class} in #{name}" unless options.is_a?(Hash)
          unsupported_keys = options.keys - OPTIONS_KEYS
          raise "Unsupported definition keys: #{unsupported_keys}" unless unsupported_keys.empty?
          raise "Missing key: cli for #{name}" unless options.key?(:cli)
          raise 'Key: cli must be Hash' unless options[:cli].is_a?(Hash)
          raise 'Missing key: cli.type' unless options[:cli].key?(:type)
          raise "Unsupported processing type for #{name}: #{options[:cli][:type]}" unless CLI_OPTION_TYPES.include?(options[:cli][:type])
          # by default : optional
          options[:mandatory] ||= false
          options[:desc] ||= ''
          cli = options[:cli]
          unsupported_cli_keys = cli.keys - CLI_KEYS
          raise "Unsupported cli keys: #{unsupported_cli_keys}" unless unsupported_cli_keys.empty?
          # by default : string, unless it's without arg
          options[:accepted_types] ||= options[:cli][:type].eql?(:opt_without_arg) ? :bool : :string
          # single type is placed in array
          options[:accepted_types] = [options[:accepted_types]] unless options[:accepted_types].is_a?(Array)
          # add default switch name if not present
          if !cli.key?(:switch) && cli.key?(:type) && CLI_OPTION_TYPE_SWITCH.include?(cli[:type])
            cli[:switch] = '--' + name.to_s.tr('_', '-')
          end
        end
      end
    end

    attr_reader :params_definition

    # @param param_hash
    def initialize(param_hash, params_definition)
      @param_hash = param_hash # keep reference so that it can be modified by caller before calling `process_params`
      @params_definition = params_definition
      @result_env = {}
      @result_args = []
      @used_param_names = []
    end

    # adds keys :env :args with resulting values after processing
    # warns if some parameters were not used
    def add_env_args(env, args)
      Log.log.debug{"ENV=#{@result_env}, ARGS=#{@result_args}"}
      # warn about non translated arguments
      @param_hash.each_pair{|key, val|Log.log.warn{"unrecognized parameter: #{key} = \"#{val}\""} if !@used_param_names.include?(key)}
      # set result
      env.merge!(@result_env)
      args.push(*@result_args)
      return nil
    end

    # add options directly to command line
    def add_command_line_options(options)
      return if options.nil?
      options.each{|o|@result_args.push(o.to_s)}
    end

    def process_params
      @params_definition.each_key do |k|
        process_param(k)
      end
    end

    def read_param(name)
      return process_param(name, read: true)
    end

    private

    # Process a parameter from transfer specification and generate command line param or env var
    # @param name [String] of parameter
    # @param read [TrueClass,FalseClass] read and return value of parameter instead of normal processing (for special)
    def process_param(name, read: false)
      options = @params_definition[name]
      # should not happen
      if options.nil?
        Log.log.warn{"Unknown parameter #{name}"}
        return
      end
      processing_type = read ? :get_value : options[:cli][:type]
      # check mandatory parameter (nil is valid value)
      raise Fasp::Error, "Missing mandatory parameter: #{name}" if options[:mandatory] && !@param_hash.key?(name)
      parameter_value = @param_hash[name]
      # no default setting
      # parameter_value=options[:default] if parameter_value.nil? and options.has_key?(:default)
      # Check parameter type
      expected_classes = options[:accepted_types].map do |type_symbol|
        case type_symbol
        when :string then String
        when :array then Array
        when :hash then Hash
        when :int then Integer
        when :bool then [TrueClass, FalseClass]
        else raise "INTERNAL: unexpected value: #{type_symbol}"
        end
      end.flatten
      # check that value is of expected type
      raise Fasp::Error, "#{name} is : #{parameter_value.class} (#{parameter_value}), shall be #{options[:accepted_types]}, " \
        unless parameter_value.nil? || expected_classes.include?(parameter_value.class)
      # special processing will be requested with type get_value
      @used_param_names.push(name) unless processing_type.eql?(:special)

      # process only non-nil values
      return nil if parameter_value.nil?

      # check that value is of an accepted type (string, int bool)
      raise "Enum value #{parameter_value} is not allowed for #{name}" if options.key?(:enum) && !options[:enum].include?(parameter_value)

      # convert some values if value on command line needs processing from value in structure
      case options[:cli][:convert]
      when Hash
        # translate using conversion table
        new_value = options[:cli][:convert][parameter_value]
        raise "unsupported value: #{parameter_value}, expect: #{options[:cli][:convert].keys.join(', ')}" if new_value.nil?
        parameter_value = new_value
      when String
        # :convert has name of class and encoding method
        conversion_class, conversion_method = options[:cli][:convert].split('.')
        converted_value = Kernel.const_get(conversion_class).send(conversion_method, parameter_value)
        raise Fasp::Error, "unsupported #{name}: #{parameter_value}" if converted_value.nil?
        parameter_value = converted_value
      when NilClass
      else raise "not expected type for convert #{options[:cli][:convert].class} for #{name}"
      end

      case processing_type
      when :get_value # just get value (deferred)
        return parameter_value
      when :ignore, :special # ignore this parameter or process later
        return
      when :envvar # set in env var
        raise 'error' unless options[:cli].key?(:variable)
        @result_env[options[:cli][:variable]] = parameter_value
      when :opt_without_arg # if present and true : just add option without value
        add_param = false
        case parameter_value
        when false then nil # nothing to put on command line, no creation by default
        when true then add_param = true
        else raise Fasp::Error, "unsupported #{name}: #{parameter_value}"
        end
        add_param = !add_param if options[:add_on_false]
        add_command_line_options([options[:cli][:switch]]) if add_param
      when :opt_with_arg # transform into command line option with value
        # parameter_value=parameter_value.to_s if parameter_value.is_a?(Integer)
        parameter_value = [parameter_value] unless parameter_value.is_a?(Array)
        # if transfer_spec value is an array, applies option many times
        parameter_value.each{|v|add_command_line_options([options[:cli][:switch], v])}
      else
        raise "ERROR: unknown option processing type: #{processing_type}/#{processing_type.class}"
      end
    end
  end
end
