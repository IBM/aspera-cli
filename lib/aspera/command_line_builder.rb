module Aspera
  # helper class to build command line from a parameter list (key-value hash)
  # constructor takes hash: { 'param1':'value1', ...}
  # process_param is called repeatedly with all known parameters
  # add_env_args is called to get resulting param list and env var (also checks that all params were used)
  class CommandLineBuilder

    private
    # default value for command line based on option name
    def switch_name(param_name,options)
      return options[:option_switch] if options.has_key?(:option_switch)
      return '--'+param_name.to_s.gsub('_','-')
    end

    def env_name(param_name,options)
      return options[:variable]
    end

    public

    BOOLEAN_CLASSES=[TrueClass,FalseClass]

    # @param param_hash
    def initialize(param_hash,params_definition)
      @param_hash=param_hash  # keep reference so that it can be modified by caller before calling `process_params`
      @params_definition=params_definition
      @result_env={}
      @result_args=[]
      @used_param_names=[]
    end

    def warn_unrecognized_params
      # warn about non translated arguments
      @param_hash.each_pair{|key,val|Log.log.warn("unrecognized parameter: #{key} = \"#{val}\"") if !@used_param_names.include?(key)}
    end

    # adds keys :env :args with resulting values after processing
    # warns if some parameters were not used
    def add_env_args(env,args)
      Log.log.debug("ENV=#{@result_env}, ARGS=#{@result_args}")
      warn_unrecognized_params
      env.merge!(@result_env)
      args.push(*@result_args)
      return nil
    end

    # transform yes/no to trye/false
    def self.yes_to_true(value)
      case value
      when 'yes'; return true
      when 'no'; return false
      end
      raise "unsupported value: #{value}"
    end

    # add options directly to ascp command line
    def add_command_line_options(options)
      return if options.nil?
      options.each{|o|@result_args.push(o.to_s)}
    end

    def process_params
      @params_definition.keys.each do |k|
        process_param(k)
      end
    end

    # Process a parameter from transfer specification and generate command line param or env var
    # @param param_name : key in transfer spec
    # @param action : type of processing: ignore getvalue envvar opt_without_arg opt_with_arg defer
    # @param options : options for type
    def process_param(param_name,action=nil)
      options=@params_definition[param_name]
      action=options[:type] if action.nil?
      # should not happen
      raise "Internal error: ask processing of param #{param_name}" if options.nil?
      # by default : not mandatory
      options[:mandatory]||=false
      if options.has_key?(:accepted_types)
        # single type is placed in array
        options[:accepted_types]=[options[:accepted_types]] unless options[:accepted_types].is_a?(Array)
      else
        # by default : string, unless it's without arg
        options[:accepted_types]=action.eql?(:opt_without_arg) ? BOOLEAN_CLASSES : [String]
      end
      # check mandatory parameter (nil is valid value)
      raise Fasp::Error.new("mandatory parameter: #{param_name}") if options[:mandatory] and !@param_hash.has_key?(param_name)
      parameter_value=@param_hash[param_name]
      parameter_value=options[:default] if parameter_value.nil? and options.has_key?(:default)
      # check provided type
      raise Fasp::Error.new("#{param_name} is : #{parameter_value.class} (#{parameter_value}), shall be #{options[:accepted_types]}, ") unless parameter_value.nil? or options[:accepted_types].inject(false){|m,v|m or parameter_value.is_a?(v)}
      @used_param_names.push(param_name) unless action.eql?(:defer)

      # process only non-nil values
      return nil if parameter_value.nil?

      if options.has_key?(:translate_values)
        # translate using conversion table
        new_value=options[:translate_values][parameter_value]
        raise "unsupported value: #{parameter_value}" if new_value.nil?
        parameter_value=new_value
      end
      raise "unsupported value: #{parameter_value}" unless options[:accepted_values].nil? or options[:accepted_values].include?(parameter_value)
      if options[:encode]
        newvalue=options[:encode].call(parameter_value)
        raise Fasp::Error.new("unsupported #{param_name}: #{parameter_value}") if newvalue.nil?
        parameter_value=newvalue
      end

      case action
      when :ignore,:defer # ignore this parameter or process later
        return
      when :get_value # just get value
        return parameter_value
      when :envvar # set in env var
        # define ascp parameter in env var from transfer spec
        @result_env[env_name(param_name,options)] = parameter_value
      when :opt_without_arg # if present and true : just add option without value
        add_param=false
        case parameter_value
        when false# nothing to put on command line, no creation by default
        when true; add_param=true
        else raise Fasp::Error.new("unsupported #{param_name}: #{parameter_value}")
        end
        add_param=!add_param if options[:add_on_false]
        add_command_line_options([switch_name(param_name,options)]) if add_param
      when :opt_with_arg # transform into command line option with value
        #parameter_value=parameter_value.to_s if parameter_value.is_a?(Integer)
        parameter_value=[parameter_value] unless parameter_value.is_a?(Array)
        # if transfer_spec value is an array, applies option many times
        parameter_value.each{|v|add_command_line_options([switch_name(param_name,options),v])}
      else
        raise "Error"
      end
    end
  end
end
