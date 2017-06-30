require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/fasp_manager_resume'
require 'asperalm/log'
require 'optparse'
require 'json'

module Asperalm
  module Cli
    class CliBadArgument < StandardError
    end

    class CliError < StandardError
    end

    # parse options in command line
    class OptParser < OptionParser
      def self.time_to_string(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      # consume elements of array, those starting with minus are options, others are commands
      def initialize
        @command_and_args=[]
        @options=[]
        @attr_procs={}
        @attr_values={}
        super
      end

      def set_argv(argv)
        @options=[]
        @command_and_args=[]
        while !argv.empty?
          if argv.first =~ /^-/
            @options.push(argv.shift)
          else
            @command_and_args.push(argv.shift)
          end
        end
        Log.log.debug("set_argv:commands=#{@command_and_args},args=#{@options}".red)
      end

      def self.value_modifier; ['file','env', 'val', 'val64', 'json', 'none']; end

      # parse an option value, special behavior for file:, env:, val:
      def self.get_extended_value(name_or_descr,value)
        if value.is_a?(String)
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
          elsif m=value.match(/^@json:(.*)/) then
            value=JSON.parse(m[1])
          elsif value.eql?('@none') then
            value=nil
          end
        end
        value
      end

      def command_or_arg_empty?
        return @command_and_args.empty?
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
        if @command_and_args.empty? then
          raise CliBadArgument,"missing action, one of: #{allowed_values.map {|x| x.to_s}.join(', ')}"
        end
        return self.class.get_from_list(@command_and_args.shift,descr,allowed_values)
      end

      # just get next value
      def get_next_arg_value(descr)
        if @command_and_args.empty? then
          raise CliBadArgument,"expecting value: #{descr}"
        end
        return self.class.get_extended_value(descr,@command_and_args.shift)
      end

      def get_remaining_arguments(descr,minus=0)
        raise CliBadArgument,"missing: #{descr}" if @command_and_args.empty?
        raise CliBadArgument,"missing args after: #{descr}" if @command_and_args.length <= minus
        filelist = @command_and_args.shift(@command_and_args.length-minus)
        Log.log.debug("#{descr}=#{filelist}")
        return filelist
      end

      def set_handler(option_symbol,&block)
        Log.log.debug("set handler #{option_symbol} (#{block})")
        @attr_procs[option_symbol]=block
      end

      def set_option(option_symbol,value)
        value=self.class.get_extended_value(option_symbol,value)
        if @attr_procs.has_key?(option_symbol)
          Log.log.debug("set #{option_symbol}=#{value} (method)".blue)
          @attr_procs[option_symbol].call(:set,value) # TODO ? check
        else
          Log.log.debug("set #{option_symbol}=#{value} (value)".blue)
          @attr_values[option_symbol]=value
        end

      end

      # can return nil
      def get_option(option_symbol)
        if @attr_procs.has_key?(option_symbol)
          Log.log.debug("get #{option_symbol} (method)")
          return @attr_procs[option_symbol].call(:get,nil) # TODO ? check
        else
          Log.log.debug("get #{option_symbol} (value)")
          return @attr_values[option_symbol]
        end
      end

      def set_defaults(values)
        Log.log.info("set_defaults=#{values}")
        return if values.nil?
        params=values.keys
        Log.log.info("params=#{params}")
        params.each { |option_symbol|
          set_option(option_symbol,values[option_symbol]) #if values.has_key?(option_symbol)
        }
      end

      def add_opt_list(option_symbol,values,help,*args)
        Log.log.info("add_opt_list #{option_symbol}->#{args}")
        value=get_option(option_symbol)
        self.on( *args , values, "#{help}. Values=(#{values.join(',')}), current=#{value}") do |v|
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
        return @options
      end

      # removes already known options from the list
      def parse_options!
        Log.log.debug("parse_options!")
        unknown_options=[]
        begin
          self.parse!(@options)
        rescue OptionParser::InvalidOption => e
          unknown_options.push(e.args.first)
          retry
        end
        Log.log.debug("remains: #{unknown_options}")
        # set unprocessed options for next time
        @options=unknown_options
      end
    end
  end
end
