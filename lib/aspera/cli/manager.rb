require 'aspera/colors'
require 'aspera/log'
require 'aspera/cli/extended_value'
require 'optparse'
require 'io/console'

module Aspera
  module Cli
    # raised by cli on error conditions
    class CliError < StandardError; end

    # raised when an unexpected argument is provided
    class CliBadArgument < CliError; end

    class CliNoSuchId < CliError
      def initialize(res_type,res_id)
        msg="No such #{res_type} identifier: #{res_id}"
        super(msg)
      end
    end

    # option is retrieved from another object using accessor
    class AttrAccessor
      #attr_accessor :object
      #attr_accessor :attr_symb
      def initialize(object,attr_symb)
        @object=object
        @attr_symb=attr_symb
      end

      def value
        @object.send(@attr_symb.to_s)
      end

      def value=(val)
        @object.send(@attr_symb.to_s+'=',val)
      end
    end

    # parse command line options
    # arguments options start with '-', others are commands
    # resolves on extended value syntax
    class Manager
      def self.time_to_string(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      # boolean options are set to true/false from the following values
      TRUE_VALUES=[:yes,true]
      BOOLEAN_VALUES=TRUE_VALUES.clone.push(:no,false)
      BOOLEAN_SIMPLE=[:yes,:no]
      # option name separator on command line
      OPTION_SEP_LINE='-'
      # option name separator in code (symbol)
      OPTION_SEP_NAME='_'

      private_constant :TRUE_VALUES,:BOOLEAN_VALUES,:BOOLEAN_SIMPLE,:OPTION_SEP_LINE,:OPTION_SEP_NAME

      def enum_to_bool(enum);TRUE_VALUES.include?(enum);end

      # find shortened string value in allowed symbol list
      def self.get_from_list(shortval,descr,allowed_values)
        # we accept shortcuts
        matching_exact=allowed_values.select{|i| i.to_s.eql?(shortval)}
        return matching_exact.first if matching_exact.length == 1
        matching=allowed_values.select{|i| i.to_s.start_with?(shortval)}
        raise cli_bad_arg("unknown value for #{descr}: #{shortval}",allowed_values) if matching.empty?
        raise cli_bad_arg("ambigous shortcut for #{descr}: #{shortval}",matching) unless matching.length.eql?(1)
        return enum_to_bool(matching.first) if allowed_values.eql?(BOOLEAN_VALUES)
        return matching.first
      end

      def self.cli_bad_arg(error_msg,choices)
        return CliBadArgument.new(error_msg+"\nUse:\n"+choices.map{|c| "- #{c.to_s}\n"}.sort.join(''))
      end

      attr_reader :parser
      attr_accessor :ask_missing_mandatory
      attr_accessor :ask_missing_optional

      #
      def initialize(program_name,argv,app_banner)
        # command line values not starting with '-'
        @unprocessed_cmd_line_arguments=[]
        # command line values starting with '-'
        @unprocessed_cmd_line_options=[]
        # a copy of all initial options
        @initial_cli_options=[]
        # option description: key = option symbol, value=hash, :type, :accessor, :value, :accepted
        @declared_options={}
        # do we ask missing options and arguments to user ?
        @ask_missing_mandatory=false # STDIN.isatty
        # ask optional options if not provided and in interactive
        @ask_missing_optional=false
        # those must be set before parse, parse consumes those defined only
        @unprocessed_defaults=[]
        @unprocessed_env=[]
        # Note: was initially inherited but it is prefered to have specific methods
        @parser=OptionParser.new
        @parser.program_name=program_name
        @parser.banner=app_banner
        # options can also be provided by env vars : --param-name -> ASLMCLI_PARAM_NAME
        env_prefix=program_name.upcase+OPTION_SEP_NAME
        ENV.each do |k,v|
          if k.start_with?(env_prefix)
            @unprocessed_env.push([k[env_prefix.length..-1].downcase.to_sym,v])
          end
        end
        Log.log.debug("env=#{@unprocessed_env}".red)
        # banner is empty when help is generated for every plugin
        unless app_banner.empty?
          @parser.separator("")
          @parser.separator("OPTIONS: global")
          self.set_obj_attr(:interactive,self,:ask_missing_mandatory)
          self.set_obj_attr(:ask_options,self,:ask_missing_optional)
          self.add_opt_boolean(:interactive,"use interactive input of missing params")
          self.add_opt_boolean(:ask_options,"ask even optional options")
          self.parse_options!
        end
        @unprocessed_cmd_line_options=[]
        @unprocessed_cmd_line_arguments=[]
        process_options=true
        while !argv.empty?
          value=argv.shift
          if process_options and value.start_with?('-')
            if value.eql?('--')
              process_options=false
            else
              @unprocessed_cmd_line_options.push(value)
            end
          else
            @unprocessed_cmd_line_arguments.push(value)
          end
        end
        @initial_cli_options=@unprocessed_cmd_line_options.dup
        Log.log.debug("add_cmd_line_options:commands/args=#{@unprocessed_cmd_line_arguments},options=#{@unprocessed_cmd_line_options}".red)
      end

      def prompt_user_input(prompt,sensitive)
        return STDIN.getpass("#{prompt}> ") if sensitive
        print "#{prompt}> "
        return STDIN.gets.chomp
      end

      def get_interactive(type,descr,expected=:single)
        if !@ask_missing_mandatory
          if expected.is_a?(Array)
            raise self.class.cli_bad_arg("missing: #{descr}",expected)
          end
          raise CliBadArgument,"missing argument (#{expected}): #{descr}"
        end
        result=nil
        # Note: mandatory parenthesis here !
        sensitive = (type.eql?(:option) and @declared_options[descr.to_sym][:sensitive].eql?(true))
        default_prompt="#{type}: #{descr}"
        # ask interactively
        case expected
        when :multiple
          result=[]
          puts " (one per line, end with empty line)"
          loop do
            entry=prompt_user_input(default_prompt,sensitive)
            break if entry.empty?
            result.push(ExtendedValue.instance.evaluate(entry))
          end
        when :single
          result=ExtendedValue.instance.evaluate(prompt_user_input(default_prompt,sensitive))
        else # one fixed
          result=self.class.get_from_list(prompt_user_input("#{expected.join(' ')}\n#{default_prompt}",sensitive),descr,expected)
        end
        return result
      end

      def get_next_command(command_list); return get_next_argument('command',command_list); end

      # @param expected is
      #    - Array of allowed value (single value)
      #    - :multiple for remaining values
      #    - :single for a single unconstrained value
      # @param is_type : :mandatory or :optional
      # @return value, list or nil
      def get_next_argument(descr,expected=:single,is_type=:mandatory)
        result=nil
        if !@unprocessed_cmd_line_arguments.empty?
          # there are values
          case expected
          when :single
            result=ExtendedValue.instance.evaluate(@unprocessed_cmd_line_arguments.shift)
          when :multiple
            result = @unprocessed_cmd_line_arguments.shift(@unprocessed_cmd_line_arguments.length).map{|v|ExtendedValue.instance.evaluate(v)}
            # if expecting list and only one arg of type array : it is the list
            if result.length.eql?(1) and result.first.is_a?(Array)
              result=result.first
            end
          else
            result=self.class.get_from_list(@unprocessed_cmd_line_arguments.shift,descr,expected)
          end
        else
          # no value provided
          if is_type.eql?(:mandatory)
            result=get_interactive(:argument,descr,expected)
          end
        end
        Log.log.debug("#{descr}=#{result}")
        return result
      end

      # declare option of type :accessor, or :value
      def declare_option(option_symbol,type)
        Log.log.debug("declare_option: #{option_symbol}: #{type}: skip=#{@declared_options.has_key?(option_symbol)}".green)
        if @declared_options.has_key?(option_symbol)
          raise "INTERNAL ERROR: option #{option_symbol} already declared. only accessor can be redeclared and ignored" unless @declared_options[option_symbol][:type].eql?(:accessor)
          return
        end
        @declared_options[option_symbol]={:type=>type}
        # by default passwords and secrets are sensitive, else specify when declaring the option
        set_is_sensitive(option_symbol) if !%w{password secret key}.select{|i| option_symbol.to_s.end_with?(i)}.empty?
      end

      def set_is_sensitive(option_symbol)
        @declared_options[option_symbol][:sensitive]=true
      end

      # define option with handler
      def set_obj_attr(option_symbol,object,attr_symb,default_value=nil)
        Log.log.debug("set attr obj #{option_symbol} (#{object},#{attr_symb})")
        declare_option(option_symbol,:accessor)
        @declared_options[option_symbol][:accessor]=AttrAccessor.new(object,attr_symb)
        set_option(option_symbol,default_value,"default obj attr") if !default_value.nil?
      end

      # set an option value by name, either store value or call handler
      def set_option(option_symbol,value,where="default")
        if ! @declared_options.has_key?(option_symbol)
          Log.log.debug("set unknown option: #{option_symbol}")
          raise "ERROR"
          #declare_option(option_symbol)
        end
        value=ExtendedValue.instance.evaluate(value)
        Log.log.debug("set_option(#{where}) #{option_symbol}=#{value}")
        if @declared_options[option_symbol][:values].eql?(BOOLEAN_VALUES)
          value=enum_to_bool(value)
        end
        Log.log.debug("set #{option_symbol}=#{value} (#{@declared_options[option_symbol][:type]}) : #{where}".blue)
        case @declared_options[option_symbol][:type]
        when :accessor
          @declared_options[option_symbol][:accessor].value=value
        when :value
          @declared_options[option_symbol][:value]=value
        else # nil or other
          raise "error"
        end
      end

      # get an option value by name
      # either return value or call handler, can return nil
      # ask interactively if requested/required
      def get_option(option_symbol,is_type=:optional)
        result=nil
        if @declared_options.has_key?(option_symbol)
          case @declared_options[option_symbol][:type]
          when :accessor
            result=@declared_options[option_symbol][:accessor].value
          when :value
            result=@declared_options[option_symbol][:value]
          else
            raise "unknown type"
          end
          Log.log.debug("get #{option_symbol} (#{@declared_options[option_symbol][:type]}) : #{result}")
        end
        Log.log.debug("interactive=#{@ask_missing_mandatory}")
        if result.nil?
          if !@ask_missing_mandatory
            if is_type.eql?(:mandatory)
              raise CliBadArgument,"Missing mandatory option: #{option_symbol}"
            end
          else # ask_missing_mandatory
            if @ask_missing_optional or is_type.eql?(:mandatory)
              expected=:single
              #print "please enter: #{option_symbol.to_s}"
              if @declared_options.has_key?(option_symbol) and @declared_options[option_symbol].has_key?(:values)
                expected=@declared_options[option_symbol][:values]
              end
              result=get_interactive(:option,option_symbol.to_s,expected)
              set_option(option_symbol,result,"interactive")
            end
          end
        end
        return result
      end

      # param must be hash
      def add_option_preset(preset_hash,op=:push)
        Log.log.debug("add_option_preset=#{preset_hash}")
        raise "internal error: setting default with no hash: #{preset_hash.class}" if !preset_hash.is_a?(Hash)
        # incremental override
        preset_hash.each{|k,v|@unprocessed_defaults.send(op,[k.to_sym,v])}
      end

      # generate command line option from option symbol
      def symbol_to_option(symbol,opt_val)
        result='--'+symbol.to_s.gsub(OPTION_SEP_NAME,OPTION_SEP_LINE)
        result=result+'='+opt_val unless opt_val.nil?
        return result
      end

      def highlight_current(value)
        STDOUT.isatty ? value.to_s.red.bold : "[#{value}]"
      end

      # define an option with restricted values
      def add_opt_list(option_symbol,values,help,*on_args)
        declare_option(option_symbol,:value)
        Log.log.debug("add_opt_list #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,'ENUM'))
        # this option value must be a symbol
        @declared_options[option_symbol][:values]=values
        value=get_option(option_symbol)
        help_values=values.map{|i|i.eql?(value)?highlight_current(i):i}.join(', ')
        if values.eql?(BOOLEAN_VALUES)
          help_values=BOOLEAN_SIMPLE.map{|i|((i.eql?(:yes) and value) or (i.eql?(:no) and not value))?highlight_current(i):i}.join(', ')
        end
        on_args.push(values)
        on_args.push("#{help}: #{help_values}")
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args){|v|set_option(option_symbol,self.class.get_from_list(v.to_s,help,values),"cmdline")}
      end

      def add_opt_boolean(option_symbol,help,*on_args)
        add_opt_list(option_symbol,BOOLEAN_VALUES,help,*on_args)
      end

      # define an option with open values
      def add_opt_simple(option_symbol,*on_args)
        declare_option(option_symbol,:value)
        Log.log.debug("add_opt_simple #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,"VALUE"))
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args) { |v| set_option(option_symbol,v,"cmdline") }
      end

      # define an option with date format
      def add_opt_date(option_symbol,*on_args)
        declare_option(option_symbol,:value)
        Log.log.debug("add_opt_date #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,"DATE"))
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args) do |v|
          case v
          when 'now'; set_option(option_symbol,Manager.time_to_string(Time.now),"cmdline")
          when /^-([0-9]+)h/; set_option(option_symbol,Manager.time_to_string(Time.now-$1.to_i*3600),"cmdline")
          else set_option(option_symbol,v,"cmdline")
          end
        end
      end

      # define an option without value
      def add_opt_switch(option_symbol,*on_args,&block)
        Log.log.debug("add_opt_on #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,nil))
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args,&block)
      end

      # check if there were unprocessed values to generate error
      def command_or_arg_empty?
        return @unprocessed_cmd_line_arguments.empty?
      end

      # unprocessed options or arguments ?
      def final_errors
        result=[]
        result.push("unprocessed options: #{@unprocessed_cmd_line_options}") unless @unprocessed_cmd_line_options.empty?
        result.push("unprocessed values: #{@unprocessed_cmd_line_arguments}") unless @unprocessed_cmd_line_arguments.empty?
        return result
      end

      # get all original options  on command line used to generate a config in config file
      def get_options_table(remove_from_remaining=true)
        result={}
        @initial_cli_options.each do |optionval|
          case optionval
          when /^--([^=]+)$/
            # ignore
          when /^--([^=]+)=(.*)$/
            name=$1
            value=$2
            name.gsub!(OPTION_SEP_LINE,OPTION_SEP_NAME)
            value=ExtendedValue.instance.evaluate(value)
            Log.log.debug("option #{name}=#{value}")
            result[name]=value
            @unprocessed_cmd_line_options.delete(optionval) if remove_from_remaining
          else
            raise CliBadArgument,"wrong option format: #{optionval}"
          end
        end
        return result
      end

      # return options as taken from config file and command line just before command execution
      def declared_options(all=true)
        return @declared_options.keys.inject({}) do |h,option_symb|
          v=get_option(option_symb)
          h[option_symb.to_s]=v if all or !v.nil?
          h
        end
      end

      def apply_options_preset(preset,where,force=false)
        unprocessed=[]
        preset.each do |pair|
          k,v=*pair
          if @declared_options.has_key?(k)
            # constrained parameters as string are revert to symbol
            if @declared_options[k].has_key?(:values) and v.is_a?(String)
              v=self.class.get_from_list(v,k.to_s+" in #{where}",@declared_options[k][:values])
            end
            set_option(k,v,where)
          else
            unprocessed.push(pair)
          end
        end
        # keep only unprocessed values for next parse
        preset.clear
        preset.push(*unprocessed)
      end

      # removes already known options from the list
      def parse_options!
        Log.log.debug("parse_options!".red)
        # first conf file, then env var
        apply_options_preset(@unprocessed_defaults,"file")
        apply_options_preset(@unprocessed_env,"env")
        # command line override
        unknown_options=[]
        begin
          # remove known options one by one, exception if unknown
          Log.log.debug("before parse".red)
          @parser.parse!(@unprocessed_cmd_line_options)
          Log.log.debug("After parse".red)
        rescue OptionParser::InvalidOption => e
          Log.log.debug("InvalidOption #{e}".red)
          # save for later processing
          unknown_options.push(e.args.first)
          retry
        end
        Log.log.debug("remains: #{unknown_options}")
        # set unprocessed options for next time
        @unprocessed_cmd_line_options=unknown_options
      end
    end
  end
end
