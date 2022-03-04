module Aspera
  # helper class to build command line from a parameter list (key-value hash)
  # constructor takes hash: { 'param1':'value1', ...}
  # process_param is called repeatedly with all known parameters
  # add_env_args is called to get resulting param list and env var (also checks that all params were used)
  class CommandLineBuilder
    # transform yes/no to true/false
    def self.yes_to_true(value)
      case value
      when 'yes' then return true
      when 'no' then return false
      end
      raise "unsupported value: #{value}"
    end

    # Called by provider of definition before constructor of this class so that params_definition has all mandatory fields
    def self.normalize_description(d)
      d.each do |param_name,options|
        raise "Expecting Hash, but have #{options.class} in #{param_name}" unless options.is_a?(Hash)
        #options[:accepted_types]=:bool if options[:cltype].eql?(:envvar) and !options.has_key?(:accepted_types)
        # by default : not mandatory
        options[:mandatory]||=false
        options[:desc]||=''
        # by default : string, unless it's without arg
        if !options.has_key?(:accepted_types)
          options[:accepted_types]=options[:cltype].eql?(:opt_without_arg) ? :bool : :string
        end
        # single type is placed in array
        options[:accepted_types]=[options[:accepted_types]] unless options[:accepted_types].is_a?(Array)
        if !options.has_key?(:clswitch) and options.has_key?(:cltype) and [:opt_without_arg,:opt_with_arg].include?(options[:cltype])
          options[:clswitch]='--'+param_name.to_s.gsub('_','-')
        end
      end
    end

    private

    # clvarname : command line variable name
    def env_name(_param_name,options)
      return options[:clvarname]
    end

    public

    attr_reader :params_definition

    # @param param_hash
    def initialize(param_hash,params_definition)
      @param_hash=param_hash # keep reference so that it can be modified by caller before calling `process_params`
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
      # should not happen
      if options.nil?
        Log.log.warn("Unknown parameter #{param_name}")
        return
      end
      action=options[:cltype] if action.nil?
      # check mandatory parameter (nil is valid value)
      raise Fasp::Error, "Missing mandatory parameter: #{param_name}" if options[:mandatory] and !@param_hash.has_key?(param_name)
      parameter_value=@param_hash[param_name]

      #parameter_value=options[:default] if parameter_value.nil? and options.has_key?(:default)

      # Check parameter type
      expected_classes=options[:accepted_types].map do |s|
        case s
        when :string then String
        when :array then Array
        when :hash then Hash
        when :int then Integer
        when :bool then [TrueClass,FalseClass]
        else raise "INTERNAL: unexpected value: #{s}"
        end
      end.flatten
      raise Fasp::Error,
"#{param_name} is : #{parameter_value.class} (#{parameter_value}), shall be #{options[:accepted_types]}, " unless parameter_value.nil? or expected_classes.include?(parameter_value.class)
      @used_param_names.push(param_name) unless action.eql?(:defer)

      # process only non-nil values
      return nil if parameter_value.nil?

      # check that value is of an accepted type (string, int bool)
      raise "Value #{parameter_value} is not allowed for #{param_name}" if options.has_key?(:enum) and !options[:enum].include?(parameter_value)

      # convert some values if value on command line needs processing from value in structure
      case options[:clconvert]
      when Hash
        # translate using conversion table
        new_value=options[:clconvert][parameter_value]
        raise "unsupported value: #{parameter_value}, expect: #{options[:clconvert].keys.join(', ')}" if new_value.nil?
        parameter_value=new_value
      when String
        # :clconvert has name of class and encoding method
        convclass,convmethod=options[:clconvert].split('.')
        newvalue=Kernel.const_get(convclass).send(convmethod,parameter_value)
        raise Fasp::Error, "unsupported #{param_name}: #{parameter_value}" if newvalue.nil?
        parameter_value=newvalue
      when NilClass
      else raise "not expected type for clconvert #{options[:clconvert].class} for #{param_name}"
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
        when false # nothing to put on command line, no creation by default
        when true then add_param=true
        else raise Fasp::Error, "unsupported #{param_name}: #{parameter_value}"
        end
        add_param=!add_param if options[:add_on_false]
        add_command_line_options([options[:clswitch]]) if add_param
      when :opt_with_arg # transform into command line option with value
        #parameter_value=parameter_value.to_s if parameter_value.is_a?(Integer)
        parameter_value=[parameter_value] unless parameter_value.is_a?(Array)
        # if transfer_spec value is an array, applies option many times
        parameter_value.each{|v|add_command_line_options([options[:clswitch],v])}
      when NilClass
        Log.log.debug("Ignoring parameter: #{param_name}")
      else
        raise "ERROR: unknown action: #{action}/#{action.class}"
      end
    end
  end
end
