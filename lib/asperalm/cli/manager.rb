require 'asperalm/colors'
require 'asperalm/log'
require 'optparse'
require 'json'
require 'base64'
require 'csv'

module Asperalm
  module Cli
    # raised by cli on error conditions
    class CliError < StandardError; end

    # raised when an unexpected argument is provided
    class CliBadArgument < CliError; end

    # option is retrieve from another object
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
    # resolves on extendede value syntax
    class Manager
      def self.time_to_string(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      # decoders can be pipelined
      @@DECODERS=['base64', 'json', 'zlib', 'ruby', 'csvt']

      # there shall be zero or one reader only
      def self.value_reader; ['val', 'file', 'env'].push(@@DECODERS); end

      # parse an option value, special behavior for file:, env:, val:
      def self.get_extended_value(name_or_descr,value)
        if value.is_a?(String)
          # first determine decoders, in reversed order
          decoders_reversed=[]
          while (m=value.match(/^@([^:]+):(.*)/)) and @@DECODERS.include?(m[1])
            decoders_reversed.unshift(m[1])
            value=m[2]
          end
          # then read value
          if m=value.match(%r{^@file:(.*)}) then
            value=File.read(File.expand_path(m[1]))
            #raise CliBadArgument,"cannot open file \"#{value}\" for #{name_or_descr}" if ! File.exist?(value)
          elsif m=value.match(/^@env:(.*)/) then
            value=ENV[m[1]]
          elsif m=value.match(/^@val:(.*)/) then
            value=m[1]
          elsif value.eql?('@stdin') then
            value=STDIN.gets
          end
          decoders_reversed.each do |d|
            case d
            when 'json'; value=JSON.parse(value)
            when 'ruby'; value=eval(value)
            when 'base64'; value=Base64.decode64(value)
            when 'zlib'; value=Zlib::Inflate.inflate(value)
            when 'csvt'
              col_titles=nil
              hasharray=[]
              CSV.parse(value).each do |values|
                next if values.empty?
                if col_titles.nil?
                  col_titles=values
                else
                  entry={}
                  col_titles.each{|title|entry[title]=values.shift}
                  hasharray.push(entry)
                end
              end
              value=hasharray
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
        @initial_cli_options=[]
        # option description: key = option symbol, value=hash, :type, :accessor, :value, :accepted
        @declared_options={}
        # do we ask missing options and arguments to user ?
        @use_interactive=STDIN.isatty ? :yes : :no
        # ask optional options if not provided and in interactive
        @ask_optionals=:no
        # Note: was initially inherited, but goal is to have something different
        @parser=OptionParser.new
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
            set_option(k.gsub(/^ASLMCLI_/,'').downcase.to_sym,v,"env var")
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
          if process_options and value.start_with?('-')
            if value.eql?('--')
              process_options=false
            else
              @unprocessed_options.push(value)
            end
          else
            @unprocessed_arguments.push(value)
          end
        end
        @initial_cli_options=@unprocessed_options.dup
        Log.log.debug("set_argv:commands/args=#{@unprocessed_arguments},options=#{@unprocessed_options}".red)
      end

      def get_interactive(type,descr,expected=:single)
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
            print "#{type}: #{descr}> "
            entry=STDIN.gets.chomp
            break if entry.empty?
            result.push(self.class.get_extended_value(descr,entry))
          end
        when :single
          print "#{type}: #{descr}> "
          result=self.class.get_extended_value(descr,STDIN.gets.chomp)
        else # one fixed
          print "#{expected.join(' ')}\n#{type}: #{descr}> "
          result=self.class.get_from_list(STDIN.gets.chomp,descr,expected)
        end
      end

      # expected is array of allowed value (single value)
      # or :multiple for remaining values
      # or :single for a single unconstrained value
      def get_next_argument(descr,expected=:single,is_type=:mandatory)
        if is_type.eql?(:mandatory) and @unprocessed_arguments.empty?
          result=get_interactive(:argument,descr,expected)
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

      def declare_option(option_symbol,type=:value)
        Log.log.debug("declare_option: #{option_symbol}".bg_green)
        if @declared_options.has_key?(option_symbol)
          Log.log.debug("opt type: #{@declared_options[option_symbol][:type]} -> #{type}")
          if @declared_options[option_symbol][:type].eql?(:value)
            @declared_options[option_symbol][:type]=type
          end
        else
          @declared_options[option_symbol]={:type=>type}
        end
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
          declare_option(option_symbol)
        end
        value=self.class.get_extended_value(option_symbol,value)
        # constrained parameters as string are revert to symbol
        if @declared_options[option_symbol].has_key?(:values) and value.is_a?(String)
          value=self.class.get_from_list(value,option_symbol.to_s+" in conf file",@declared_options[option_symbol][:values])
        end
        Log.log.debug("set #{option_symbol}=#{value} (#{@declared_options[option_symbol][:type]})".blue)
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
          else
            result=@declared_options[option_symbol][:value]
          end
          Log.log.debug("get #{option_symbol} (#{@declared_options[option_symbol][:type]}) : #{result}")
        end
        if result.nil?
          if !@use_interactive.eql?(:yes)
            if is_type.eql?(:mandatory)
              raise CliBadArgument,"Missing option in context: #{option_symbol}"
            end
          else # use_interactive
            if @ask_optionals.eql?(:yes) or is_type.eql?(:mandatory)
              expected=:single
              #print "please enter: #{option_symbol.to_s}"
              if @declared_options[option_symbol].has_key?(:values)
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
      def set_defaults(preset_hash)
        Log.log.debug("set_defaults=#{preset_hash}")
        raise "internal error: setting default with no hash: #{preset_hash.class}" if !preset_hash.is_a?(Hash)
        # 1- in conf file, key is string, in config, key is symbol
        # 2- value may be string, but symbol expected for value lists, but options may not be already declared, see Note1
        preset_hash.each{|k,v|set_option(k.to_sym,v,"conf file")}
      end

      # generate command line option from option symbol
      def symbol_to_option(symbol,opt_val)
        result='--'+symbol.to_s.gsub(@@OPTION_SEP_NAME,@@OPTION_SEP_LINE)
        result=result+'='+opt_val unless opt_val.nil?
        return result
      end

      def highlight_current(value)
        STDOUT.isatty ? value.to_s.red.bold : "[#{value}]"
      end

      # define an option with restricted values
      def add_opt_list(option_symbol,values,help,*on_args)
        declare_option(option_symbol)
        Log.log.debug("add_opt_list #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,'ENUM'))
        # this option value must be a symbol
        @declared_options[option_symbol][:values]=values
        value=get_option(option_symbol)
        help_values=values.map{|i|i.eql?(value)?highlight_current(i):i}.join(', ')
        on_args.push(values)
        on_args.push("#{help}: #{help_values}")
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args){|v|set_option(option_symbol,self.class.get_from_list(v.to_s,help,values),"cmdline")}
      end

      # define an option with open values
      def add_opt_simple(option_symbol,*on_args)
        declare_option(option_symbol)
        Log.log.debug("add_opt_simple #{option_symbol}")
        on_args.unshift(symbol_to_option(option_symbol,"VALUE"))
        Log.log.debug("on_args=#{on_args}")
        @parser.on(*on_args) { |v| set_option(option_symbol,v,"cmdline") }
      end

      # define an option with date format
      def add_opt_date(option_symbol,*on_args)
        declare_option(option_symbol)
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
        @initial_cli_options.each do |optionval|
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
        return @declared_options.keys.inject({}) do |h,option_symb|
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
