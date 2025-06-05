# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'yaml'
module Aspera
  # helper class to build command line from a parameter list (key-value hash)
  # constructor takes hash: { 'param1':'value1', ...}
  # process_param is called repeatedly with all known parameters
  # add_env_args is called to get resulting param list and env var (also checks that all params were used)
  class CommandLineBuilder
    # description    [String]   Description
    # type           [String]   Accepted type for non-enum
    # default        [String]   Default value if not specified
    # enum           [Array]    Set with list of values for enum types accepted in transfer spec
    # x-type         [String]   Additional type possible
    # x-cli-envvar   [String]   Name of env var
    # x-cli-option   [String]   Command line option (starts with "-")
    # x-cli-switch   [Bool]     true if option has no arg, else by default option has a value
    # x-cli-special  [Bool]     true if special handling (defered)
    # x-cli-enum-convert [Hash] Conversion for enum ts to arg
    # x-cli-convert  [String]   method name for Convert object
    # x-agents       [Array]    Supported agents (for doc only), if not specified: all
    # x-tspec        [String ]  (async) true if same name in transfer spec, else name in transfer spec
    # x-deprecation  [String ]  Deprecation message for doc
    SCHEMA_KEYS = %w[
      description
      type
      default
      enum
      required
      $comment
      x-type
      x-cli-envvar
      x-cli-option
      x-cli-switch
      x-cli-special
      x-cli-enum-convert
      x-cli-convert
      x-agents
      x-tspec
      x-deprecation
    ].freeze

    CLI_AGENT = 'direct'

    private_constant :SCHEMA_KEYS, :CLI_AGENT

    class << self
      # @return true if given agent supports that field
      def supported_by_agent(agent, properties)
        !properties.key?('x-agents') || properties['x-agents'].include?(agent)
      end

      # Called by provider of definition before constructor of this class so that schema has all mandatory fields
      def read_schema(source_path, suffix=nil)
        suffix = "_#{suffix}" unless suffix.nil?
        schema = YAML.load_file("#{source_path[0..-4]}#{suffix}.schema.yaml")
        schema['properties'].each do |name, properties|
          Aspera.assert_type(properties, Hash){name}
          unsupported_keys = properties.keys - SCHEMA_KEYS
          Aspera.assert(unsupported_keys.empty?){"Unsupported definition keys: #{unsupported_keys}"}
          # by default : string, unless it's without arg
          properties['type'] ||= properties['x-cli-switch'] ? 'boolean' : 'string'
          # add default cli option name if not present, and if supported in "direct".
          properties['x-cli-option'] = '--' + name.to_s.tr('_', '-') if !properties.key?('x-cli-option') && !properties['x-cli-envvar'] && (properties.key?('x-cli-switch') || supported_by_agent(CLI_AGENT, properties))
          properties.freeze
        end
        schema['required'] = [] unless schema.key?('required')
        schema.freeze
      end
    end

    # @param [Hash] object with parameters
    # @param [Hash] schema JSON schema
    def initialize(object, schema, convert)
      @object = object # keep reference so that it can be modified by caller before calling `process_params`
      @schema = schema
      @convert = convert
      @result = {
        env:  {},
        args: []
      }
      @processed_parameters = []
    end

    # Change required-ness of property in schema
    def required(name, required)
      if required
        @schema['required'].push(name) unless @schema['required'].include?(name)
      else
        @schema['required'].delete(name)
      end
    end

    # Add processed parameters to env and args, warns about unused parameters
    # @param [Hash] env_args with :env and :args
    def add_env_args(env_args)
      Log.log.debug{"add_env_args: ENV=#{@result[:env]}, ARGS=#{@result[:args]}"}
      # warn about non translated arguments
      @object.each_pair do |name, value|
        Log.log.warn{raise "Unknown transfer spec parameter: #{name} = \"#{value}\""} unless @processed_parameters.include?(name)
      end
      # set result
      env_args[:env].merge!(@result[:env])
      env_args[:args].concat(@result[:args])
      return nil
    end

    # add options directly to command line
    def add_command_line_options(options)
      return if options.nil?
      options.each{ |o| @result[:args].push(o.to_s)}
    end

    def process_params
      @schema['properties'].each_key do |k|
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
      properties = @schema['properties'][name]
      # should not happen
      if properties.nil?
        Log.log.warn{"Unknown parameter #{name}"}
        return
      end
      # check mandatory parameter (nil is valid value), TODO: change exception ?
      raise Transfer::Error, "Missing mandatory parameter: #{name}" if @schema['required'].include?(name) && !properties['x-cli-special'] && !@object.key?(name)
      parameter_value = @object[name]
      # no default setting
      # parameter_value=properties['default'] if parameter_value.nil? and properties.has_key?('default')
      # Check parameter type
      expected_classes = case properties['type']
      when 'string' then [String]
      when 'array' then [Array]
      when 'object' then [Hash]
      when 'integer' then [Integer]
      when 'boolean' then [TrueClass, FalseClass]
      else Aspera.error_unexpected_value(properties['type'])
      end
      expected_classes.push(properties['x-type']) if properties.key?('x-type')
      # check that value is of expected type
      raise Transfer::Error, "#{name} is : #{parameter_value.class} (#{parameter_value}), shall be #{properties['type']}, " \
        unless parameter_value.nil? || expected_classes.include?(parameter_value.class)
      # special processing will be requested with type get_value
      @processed_parameters.push(name) if !properties['x-cli-special'] || read

      # process only non-nil values
      return nil if parameter_value.nil?

      # check that value is of an accepted type (string, integer, boolean)
      raise "Enum value #{parameter_value} is not allowed for #{name}" if properties.key?('enum') && !properties['enum'].include?(parameter_value)

      # convert some values if value on command line needs processing from value in structure
      if (convert = properties['x-cli-enum-convert'])
        # translate using conversion table
        new_value = convert[parameter_value]
        raise "Unsupported value: #{parameter_value}, expect: #{convert.keys.join(', ')}" if new_value.nil?
        parameter_value = new_value
      elsif (convert = properties['x-cli-convert'])
        # "convert" has name of encoding method
        converted_value = @convert.send(convert, parameter_value)
        raise Transfer::Error, "unsupported #{name}: #{parameter_value}" if converted_value.nil?
        parameter_value = converted_value
      end

      return unless self.class.supported_by_agent(CLI_AGENT, properties)

      if read
        # just get value (deferred)
        return parameter_value
      elsif properties['x-cli-special']
        # process later
        return
      elsif properties.key?('x-cli-envvar')
        # set in env var
        @result[:env][properties['x-cli-envvar']] = parameter_value
      elsif properties['x-cli-switch']
        # if present and true : just add option without value
        add_param = false
        case parameter_value
        when false then nil # nothing to put on command line, no creation by default
        when true then add_param = true
        else Aspera.error_unexpected_value(parameter_value){name}
        end
        # add_param = !add_param if properties[:add_on_false]
        add_command_line_options([properties['x-cli-option']]) if add_param
      else
        # transform into command line option with value
        # parameter_value=parameter_value.to_s if parameter_value.is_a?(Integer)
        parameter_value = [parameter_value] unless parameter_value.is_a?(Array)
        # if transfer_spec value is an array, applies option many times
        parameter_value.each{ |v| add_command_line_options([properties['x-cli-option'], v])}
      end
    end
  end
end
