require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/fasp_manager_resume'
require 'asperalm/log'
require 'optparse'
require 'json'
require 'base64'

module Asperalm
  module Cli
    # raised by cli on error conditions
    class CliError < StandardError
    end

    # raised when an unexpected argument is provided
    class CliBadArgument < CliError
    end

    # parse options in command line
    class OptParser < OptionParser
      def self.time_to_string(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      # consume elements of array, those starting with minus are options, others are commands
      def initialize
        # command line values not starting with '-'
        @unprocessed_command_and_args=[]
        # command line values starting with '-'
        @unprocessed_options=[]
        # key = name of option, either Proc(set/get) or value
        @available_option={}
        @sym_options=[]
        super
      end

      def read_env_vars
        Log.log.debug("read_env_vars")
        # options can also be provided by env vars : --param-name -> ASLMCLI_PARAM_NAME
        ENV.each do |k,v|
          if k.start_with?('ASLMCLI_')
            set_option(k.gsub(/^ASLMCLI_/,'').downcase.to_sym,v)
          end
        end
      end

      def set_argv(argv)
        @unprocessed_options=[]
        @unprocessed_command_and_args=[]
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
            @unprocessed_command_and_args.push(value)
          end
        end
        Log.log.debug("set_argv:commands/args=#{@unprocessed_command_and_args},options=#{@unprocessed_options}".red)
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

      def command_or_arg_empty?
        return @unprocessed_command_and_args.empty?
      end

      def self.get_from_list(shortval,descr,allowed_values)
        # we accept shortcuts
        matching_exact=allowed_values.select{|i| i.to_s.eql?(shortval)}
        return matching_exact.first if matching_exact.length == 1
        matching=allowed_values.select{|i| i.to_s.start_with?(shortval)}
        case matching.length
        when 1; return matching.first
        when 0; raise CliBadArgument,"unexpected value for #{descr}: #{shortval}, one of: #{allowed_values.map {|x| x.to_s}.join(', ')}"
        else; raise CliBadArgument,"ambigous value for #{descr}: #{shortval}, one of: #{matching.map {|x| x.to_s}.join(', ')}"
        end
      end

      # get next argument, must be from the value list
      def get_next_arg_from_list(descr,allowed_values)
        if @unprocessed_command_and_args.empty? then
          raise CliBadArgument,"missing action, one of: #{allowed_values.map {|x| x.to_s}.join(', ')}"
        end
        return self.class.get_from_list(@unprocessed_command_and_args.shift,descr,allowed_values)
      end

      # just get next value (expanded)
      def get_next_arg_value(descr)
        if @unprocessed_command_and_args.empty? then
          raise CliBadArgument,"expecting value: #{descr}"
        end
        return self.class.get_extended_value(descr,@unprocessed_command_and_args.shift)
      end

      def get_remaining_arguments(descr,minus=0)
        raise CliBadArgument,"missing: #{descr}" if @unprocessed_command_and_args.empty?
        raise CliBadArgument,"missing args after: #{descr}" if @unprocessed_command_and_args.length <= minus
        arguments = @unprocessed_command_and_args.shift(@unprocessed_command_and_args.length-minus)
        arguments = arguments.map{|v|self.class.get_extended_value(descr,v)}
        Log.log.debug("#{descr}=#{arguments}")
        return arguments
      end

      def set_handler(option_symbol,&block)
        Log.log.debug("set handler #{option_symbol} (#{block})")
        Log.log.error("handler already set for #{option_symbol}") if @available_option.has_key?(option_symbol)
        @available_option[option_symbol]=block
      end

      # set an option value by name, either store value or call handler
      def set_option(option_symbol,value)
        value=self.class.get_extended_value(option_symbol,value)
        if @available_option.has_key?(option_symbol) and @available_option[option_symbol].is_a?(Proc)
          Log.log.debug("set #{option_symbol}=#{value} (method)".blue)
          @available_option[option_symbol].call(:set,value) # TODO ? check
        else
          Log.log.debug("set #{option_symbol}=#{value} (value)".blue)
          @available_option[option_symbol]=value
        end

      end

      # get an option value by name, either return value or call handler, can return nil
      def get_option(option_symbol)
        if @available_option.has_key?(option_symbol) and @available_option[option_symbol].is_a?(Proc)
          Log.log.debug("get #{option_symbol} (method)")
          return @available_option[option_symbol].call(:get,nil) # TODO ? check
        else
          Log.log.debug("get #{option_symbol} (value)")
          # convert option to symbol if it came from conf file...
          @available_option[option_symbol]=@available_option[option_symbol].to_sym if @sym_options.include?(option_symbol) and !@available_option[option_symbol].nil? and !@available_option[option_symbol].is_a?(Symbol)
          return @available_option[option_symbol]
        end
      end

      def set_defaults(values)
        Log.log.info("set_defaults=#{values}")
        raise "internal error: setting default with no hash: #{values.class}" if !values.is_a?(Hash)
        values.each { |k,v|
          # in conf file, key is string, in config, key is symbol
          set_option(k.to_sym,v)
        }
      end

      def add_opt_list(option_symbol,values,help,*args)
        Log.log.info("add_opt_list #{option_symbol}->#{args}")
        @sym_options.push(option_symbol)
        value=get_option(option_symbol)
        args.push(values)
        args.push("#{help}. Values=(#{values.join(',')}), current=#{value}")
        self.on( *args ) do |v|
          set_option(option_symbol,self.class.get_from_list(v.to_s,help,values))
        end
      end

      def add_opt_simple(option_symbol,*args)
        Log.log.info("add_opt_simple #{option_symbol}->#{args}")
        self.on(*args) { |v| set_option(option_symbol,v) }
      end

      def add_opt_date(option_symbol,*args)
        Log.log.info("add_opt_date #{option_symbol}->#{args}")
        self.on(*args) { |v|
          case v
          when 'now'; set_option(option_symbol,OptParser.time_to_string(Time.now))
          when /^-([0-9]+)h/; set_option(option_symbol,OptParser.time_to_string(Time.now-$1.to_i*3600))
          else set_option(option_symbol,v)
          end
        }
      end

      def add_opt_on(option_symbol,*args,&block)
        Log.log.info("add_opt_on #{option_symbol}->#{args}")
        self.on(*args,&block)
      end

      def get_option_mandatory(option_symbol)
        value=get_option(option_symbol)
        if value.nil? then
          raise CliBadArgument,"Missing option in context: #{option_symbol}"
        end
        return value
      end

      def unprocessed_options
        return @unprocessed_options
      end

      # removes already known options from the list
      def parse_options!
        Log.log.debug("parse_options!")
        unknown_options=[]
        begin
          self.parse!(@unprocessed_options)
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
