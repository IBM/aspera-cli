require 'asperalm/colors'
require 'asperalm/log'
require 'optparse'
require 'json'
require 'base64'

module Asperalm
  module Cli
    # raised by cli on error conditions
    class CliError < StandardError; end

    # raised when an unexpected argument is provided
    class CliBadArgument < CliError; end

    class AttrAccessor
      attr_accessor :object
      attr_accessor :attr_symb
      def initialize(object,attr_symb)
        @object=object
        @attr_symb=attr_symb
      end
    end

    # parse options in command line
    # arguments starting with minus are options, others are commands
    class Manager
      def self.time_to_string(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      # encoders can be pipelined
      @@ENCODERS=['base64', 'json', 'zlib']

      # read value is only one
      def self.value_modifier; ['val', 'file', 'env'].push(@@ENCODERS); end

      # parse an option value, special behavior for file:, env:, val:
      def self.get_extended_value(name_or_descr,value)
        if value.is_a?(String)
          # first determine decoding
          decoding=[]
          while (m=value.match(/^@([^:]+):(.*)/)) and @@ENCODERS.include?(m[1])
            decoding.push(m[1])
            value=m[2]
          end
          # then read value
          if m=value.match(%r{^@file:(.*)}) then
            value=m[1]
            if m=value.match(%r{^~/(.*)}) then
              value=m[1]
              value=File.join(Dir.home,value)
            end
            raise CliBadArgument,"cannot open file \"#{value}\" for #{name_or_descr}" if ! File.exist?(value)
            value=File.read(value)
          elsif m=value.match(/^@env:(.*)/) then
            value=m[1]
            value=ENV[value]
          elsif m=value.match(/^@val:(.*)/) then
            value=m[1]
          elsif value.eql?('@stdin') then
            value=STDIN.gets
          end
          decoding.reverse.each do |d|
            case d
            when 'json'; value=JSON.parse(value)
            when 'base64'; value=Base64.decode64(value)
            when 'zlib'; value=Zlib::Inflate.inflate(value)
            end
          end
        end
        value
      end

      # find shortened string value in allowed symbol list
      def self.get_from_list(shortval,descr,allowed_values)
        # we accept shortcuts
        matching_exact=allowed_values.select{|i| i.to_s.eql?(shortval)}
        return matching_exact.first if matching_exact.length == 1
        matching=allowed_values.select{|i| i.to_s.start_with?(shortval)}
        case matching.length
        when 1; return matching.first
        when 0; raise cli_bad_arg("unknown value for #{descr}: #{shortval}",allowed_values)
        else; raise cli_bad_arg("ambigous shortcut for #{descr}: #{shortval}",matching)
        end
      end

      def self.cli_bad_arg(error_msg,choices)
        return CliBadArgument.new(error_msg+"\nUse:\n"+choices.map{|c| "- #{c.to_s}\n"}.join(''))
      end

      # option name separator on command line
      @@OPTION_SEP_LINE='-'
      # option name separator in code (symbol)
      @@OPTION_SEP_NAME='_'

      attr_reader :parser
      attr_accessor :use_interactive
      attr_accessor :ask_optionals

      #
      def initialize
        # command line values not starting with '-'
        @unprocessed_arguments=[]
        # command line values starting with '-'
        @unprocessed_options=[]
        # a copy of all initial options
        @all_options=[]
        # key = name of option, either Proc(set/get) or value
        @available_option={}
        # list of options whose value is a ruby symbol, not a string
        @options_symbol_list={}
        # do we ask missing options and arguments to user ?
        @use_interactive=STDIN.isatty ? :yes : :no
        # ask optional options if not provided and in interactive
        @ask_optionals=:no
        # Note: was initially inherited, but goal is to have something different
        @parser= OptionParser.new
        #super
        self.set_obj_attr(:interactive,self,:use_interactive)
        self.add_opt_list(:interactive,[:yes,:no],"use interactive input of missing params")
        self.set_obj_attr(:ask_options,self,:ask_optionals)
        self.add_opt_list(:ask_options,[:yes,:no],"ask even optional options")
      end

      # options can also be provided by env vars : --param-name -> ASLMCLI_PARAM_NAME
      def read_env_vars
        Log.log.debug("read_env_vars")
        ENV.each do |k,v|
          if k.start_with?('ASLMCLI_')
            set_option(k.gsub(/^ASLMCLI_/,'').downcase.to_sym,v)
          end
        end
      end

      # parse arguments into options and arguments
      def set_argv(argv)
        @unprocessed_options=[]
        @unprocessed_arguments=[]
        process_options=true
        while !argv.empty?
          value=argv.shift
          if process_options and value =~ /^-/
            if value.eql?('--')
              process_options=false
            else
              @unprocessed_options.push(value)
            end
          else
            @unprocessed_arguments.push(value)
          end
        end
        @all_options=@unprocessed_options.dup
        Log.log.debug("set_argv:commands/args=#{@unprocessed_arguments},options=#{@unprocessed_options}".red)
      end

      def get_interactive(descr,expected=:single)
        if !@use_interactive.eql?(:yes)
          if expected.is_a?(Array)
            raise self.class.cli_bad_arg("missing: #{descr}",expected)
          end
          raise CliBadArgument,"missing argument (#{expected}): #{descr}"
        end
        # ask interactively
        case expected
        when :multiple
          result=[]
          puts " (one per line, end with empty line)"
          loop do
            print "#{descr}> "
            entry=STDIN.gets.chomp
            break if entry.empty?
            result.push(self.class.get_extended_value(descr,entry))
          end
        when :single
          print "#{descr}> "
          result=self.class.get_extended_value(descr,STDIN.gets.chomp)
        else # one fixed
          print "#{expected.join(' ')}\n#{descr}> "
          result=self.class.get_from_list(STDIN.gets.chomp,descr,expected)
        end
      end

      # expected is array of allowed value (single value)
      # or :multiple for remaining values
      # or :single for a single unconstrained value
      def get_next_argument(descr,expected=:single)
        if @unprocessed_arguments.empty?
          result=get_interactive(descr,expected)
        else # there are values
          case expected
          when :single
            result=self.class.get_extended_value(descr,@unprocessed_arguments.shift)
          when :multiple
            result = @unprocessed_arguments.shift(@unprocessed_arguments.length).map{|v|self.class.get_extended_value(descr,v)}
          else
            result=self.class.get_from_list(@unprocessed_arguments.shift,descr,expected)
          end
        end
        Log.log.debug("#{descr}=#{result}")
        return result
      end

      def set_obj_attr(option_symbol,object,attr_symb,default_value=nil)
        Log.log.debug("set attr obj #{option_symbol} (#{object},#{attr_symb})")
        Log.log.error("handler already set for #{option_symbol}") if @available_option.has_key?(option_symbol)
        @available_option[option_symbol]=AttrAccessor.new(object,attr_symb)
        set_option(option_symbol,default_value) if !default_value.nil?
      end

      # set an option value by name, either store value or call handler
      def set_option(option_symbol,value)
        source=nil
        value=self.class.get_extended_value(option_symbol,value)
        case @available_option[option_symbol]
        when AttrAccessor
          source="accessor"
          @available_option[option_symbol].object.send(@available_option[option_symbol].attr_symb.to_s+'=',value)
        else # nil or other
          source="value"
          @available_option[option_symbol]=value
        end
        Log.log.debug("set #{option_symbol}=#{value} (#{source})".blue)
      end

      # get an option value by name
      # either return value or call handler, can return nil
      # ask interactively if requested/required
      def get_option(option_symbol,is_type=:optional)
        result=nil
        source=nil
        case @available_option[option_symbol]
        when AttrAccessor
          source="accessor"
          result=@available_option[option_symbol].object.send(@available_option[option_symbol].attr_symb)
        else
          # Note1: convert string option to symbol
          if @options_symbol_list.has_key?(option_symbol) and # constrained by specific values
          @available_option[option_symbol].is_a?(String) # its a string (from conf file)
            @available_option[option_symbol]=self.class.get_from_list(@available_option[option_symbol],option_symbol.to_s+" in conf file",@options_symbol_list[option_symbol])
          end
          source="value"
          result=@available_option[option_symbol]
        end
        Log.log.debug("get #{option_symbol} (#{source}) : #{result}")
        if result.nil?
          if !@use_interactive.eql?(:yes)
            if is_type.eql?(:mandatory)
              raise CliBadArgument,"Missing option in context: #{option_symbol}"
            end
          else # use_interactive
            if @ask_optionals.eql?(:yes) or is_type.eql?(:mandatory)
              expected=:single
              #print "please enter: #{option_symbol.to_s}"
              if @options_symbol_list.has_key?(option_symbol)
                expected=@options_symbol_list[option_symbol]
              end
              result=get_interactive(option_symbol.to_s,expected)
              set_option(option_symbol,result)
            end
          end
        end
        return result
      end

      # param must be hash
      def set_defaults(values)
        Log.log.debug("set_defaults=#{values}")
        raise "internal error: setting default with no hash: #{values.class}" if !values.is_a?(Hash)
        # 1- in conf file, key is string, in config, key is symbol
        # 2- value may be string, but symbol expected for value lists, but options may not be already declared, see Note1
        values.each{|k,v|set_option(k.to_sym,v)}
      end

      # generate command line option from option symbol
      def symbol_to_option(symbol,opt_val)
        result='--'+symbol.to_s.gsub(@@OPTION_SEP_NAME,@@OPTION_SEP_LINE)
        result=result+'='+opt_val if (!opt_val.nil?)
        return result
      end

      # define an option with restricted values
      def add_opt_list(option_symbol,values,help,*on_args)
        Log.log.debug("add_opt_list #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,'ENUM'))
        # this option value must be a symbol
        @options_symbol_list[option_symbol]=values
        value=get_option(option_symbol)
        on_args.push(values)
        on_args.push("#{help}. Values=(#{values.join(',')}), current=#{value}")
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args){|v|set_option(option_symbol,self.class.get_from_list(v.to_s,help,values))}
      end

      # define an option with open values
      def add_opt_simple(option_symbol,opt_val,*on_args)
        Log.log.debug("add_opt_simple #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,opt_val))
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args) { |v| set_option(option_symbol,v) }
      end

      # define an option with date format
      def add_opt_date(option_symbol,opt_val,*on_args)
        Log.log.debug("add_opt_date #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,opt_val))
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args) do |v|
          case v
          when 'now'; set_option(option_symbol,Manager.time_to_string(Time.now))
          when /^-([0-9]+)h/; set_option(option_symbol,Manager.time_to_string(Time.now-$1.to_i*3600))
          else set_option(option_symbol,v)
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
        return @unprocessed_arguments.empty?
      end

      def fail_if_unprocessed
        # unprocessed options or arguments ?
        raise CliBadArgument,"unprocessed options: #{@unprocessed_options}" unless @unprocessed_options.empty?
        raise CliBadArgument,"unprocessed values: #{@unprocessed_arguments}" unless @unprocessed_arguments.empty?
      end

      # get all original options  on command line used to generate a config in config file
      def get_options_table(remove_from_remaining=true)
        result={}
        @all_options.each do |optionval|
          case optionval
          when /^--([^=]+)$/
            # ignore
          when /^--([^=]+)=(.*)$/
            name=$1
            value=$2
            name.gsub!(@@OPTION_SEP_LINE,@@OPTION_SEP_NAME)
            value=self.class.get_extended_value(name,value)
            Log.log.debug("option #{name}=#{value}")
            result[name]=value
            @unprocessed_options.delete(optionval) if remove_from_remaining
          else
            raise CliBadArgument,"wrong option format: #{optionval}"
          end
        end
        #@unprocessed_options=[]
        return result
      end
      
      # return options as taken from config file and command line just before command execution
      def get_current_options
        return @available_option.keys.inject({}) do |h,option_symb|
          h[option_symb.to_s]=get_option(option_symb)
          h
        end
      end

      # removes already known options from the list
      def parse_options!
        Log.log.debug("parse_options!")
        unknown_options=[]
        begin
          @parser.parse!(@unprocessed_options)
        rescue OptionParser::InvalidOption => e
          unknown_options.push(e.args.first)
          retry
        end
        Log.log.debug("remains: #{unknown_options}")
        # set unprocessed options for next time
        @unprocessed_options=unknown_options
      end
    end
  end
end
