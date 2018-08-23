module Asperalm
  # helper class to build command line from a parameter list (key-value hash)
  # constructor takes hash: { 'param1':'value1', ...}
  # process_param is called repeatedly with all known parameters
  # add_env_args is called to get resulting param list and env var (also checks that all params were used)
  class CommandLineBuilder

    private
    # default value for command line based on option name
    def switch_name(ts_name,options)
      return options[:option_switch] if options.has_key?(:option_switch)
      return '--'+ts_name.to_s.gsub('_','-')
    end

    def env_name(ts_name,options)
      return options[:variable]
    end

    public

    BOOLEAN_CLASSES=[TrueClass,FalseClass]

    # @param job_params
    def initialize(job_params,params_definition)
      @job_params=job_params.clone # shallow copy is sufficient
      @result_env={}
      @result_args=[]
      @used_ts_keys=[]
      @params_definition=params_definition
    end

    def add_env_args(env_args)
      # warn about non translated arguments
      @job_params.each_pair{|key,val|Log.log.error("unrecognized parameter: #{key} = \"#{val}\"") if !@used_ts_keys.include?(key)}
      Log.log.debug("ENV=#{@result_env}, ARGS=#{@result_args}")
      env_args[:env].merge!(@result_env)
      env_args[:args].push(*@result_args)
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
      @params_definition.each do |k,v|
        process_param(k,v[:type],v)
      end
    end

    # Process a parameter from transfer specification and generate command line param or env var
    # @param ts_name : key in transfer spec
    # @param option_type : type of processing
    # @param options : options for type
    def process_param(ts_name,option_type,options={})
      # by default : not mandatory
      options[:mandatory]||=false
      if options.has_key?(:accepted_types)
        # single type is placed in array
        options[:accepted_types]=[options[:accepted_types]] unless options[:accepted_types].is_a?(Array)
      else
        # by default : string, unless it's without arg
        options[:accepted_types]=option_type.eql?(:opt_without_arg) ? BOOLEAN_CLASSES : [String]
      end
      # check mandatory parameter (nil is valid value)
      raise Fasp::Error.new("mandatory parameter: #{ts_name}") if options[:mandatory] and !@job_params.has_key?(ts_name)
      parameter_value=@job_params[ts_name]
      parameter_value=options[:default] if parameter_value.nil? and options.has_key?(:default)
      # check provided type
      raise Fasp::Error.new("#{ts_name} is : #{parameter_value.class} (#{parameter_value}), shall be #{options[:accepted_types]}, ") unless parameter_value.nil? or options[:accepted_types].inject(false){|m,v|m or parameter_value.is_a?(v)}
      @used_ts_keys.push(ts_name)

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
        raise Fasp::Error.new("unsupported #{ts_name}: #{parameter_value}") if newvalue.nil?
        parameter_value=newvalue
      end

      case option_type
      when :ignore # ignore this parameter
        return
      when :get_value # just get value
        return parameter_value
      when :envvar # set in env var
        # define ascp parameter in env var from transfer spec
        @result_env[env_name(ts_name,options)] = parameter_value
      when :opt_without_arg # if present and true : just add option without value
        add_param=false
        case parameter_value
        when false# nothing to put on command line, no creation by default
        when true; add_param=true
        else raise Fasp::Error.new("unsupported #{ts_name}: #{parameter_value}")
        end
        add_param=!add_param if options[:add_on_false]
        add_command_line_options([switch_name(ts_name,options)]) if add_param
      when :opt_with_arg # transform into command line option with value
        #parameter_value=parameter_value.to_s if parameter_value.is_a?(Integer)
        parameter_value=[parameter_value] unless parameter_value.is_a?(Array)
        # if transfer_spec value is an array, applies option many times
        parameter_value.each{|v|add_command_line_options([switch_name(ts_name,options),v])}
      else
        raise "Error"
      end
    end
  end
end
