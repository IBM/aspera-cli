require 'asperalm/rest'
require 'asperalm/colors'
require 'asperalm/fasp_manager_resume'
require 'asperalm/log'
require 'xmlsimple'
require 'optparse'

module Asperalm
  module Cli
    class CliBadArgument < StandardError
    end
    
    # base class for plugins modules
    class OptParser < OptionParser
      def initialize(argv)
        @mycommand_and_args=[]
        @myoptions=[]
        while !argv.empty?
          if argv.first =~ /^-/
            @myoptions.push(argv.shift)
          else
            @mycommand_and_args.push(argv.shift)
          end
        end
        Log.log.debug("parse_commands->#{@mycommand_and_args},args=#{@myoptions}")
        @attr_procs={}
        @attr_values={}
        super
      end
      
      # parse an option value, special behavior for file:, env:, val:
      def self.get_extended_value(name_or_descr,value)
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
        value
      end

      def command_or_arg_empty?
        return @mycommand_and_args.empty?
      end
      
      # get next argument, must be from the value list
      def get_next_arg_from_list(descr,allowed_values)
        if @mycommand_and_args.empty? then
          raise CliBadArgument,"missing action, one of: #{allowed_values.map {|x| x.to_s}.join(', ')}"
        end
        action=@mycommand_and_args.shift.to_sym
        if !allowed_values.include?(action) then
          raise CliBadArgument,"unexpected value for #{descr}: #{action}, one of: #{allowed_values.map {|x| x.to_s}.join(', ')}"
        end
        return action
      end

      # just get next value
      def get_next_arg_value(descr)
        if @mycommand_and_args.empty? then
          raise CliBadArgument,"expecting value: #{descr}"
        end
        return self.class.get_extended_value(descr,@mycommand_and_args.shift)
      end

      def get_remaining_arguments(descr)
        filelist = @mycommand_and_args.pop(@mycommand_and_args.length)
        Log.log.debug("#{descr}=#{filelist}")
        if filelist.empty? then
          raise CliBadArgument,"missing #{descr}"
        end
        return filelist
      end

      def exit_with_usage(error_text)
        STDERR.puts self
        STDERR.puts "\n"+"ERROR:".bg_red().gray().blink()+" #{error_text}\n\n" if !error_text.nil?
        Process.exit 1
      end

      def set_handler(option_symbol,&block)
        Log.log.debug("set handler #{option_symbol} (#{block})")
        @attr_procs[option_symbol]=block
      end
      
      def set_option(option_symbol,value)
        value=self.class.get_extended_value(option_symbol,value)
        if @attr_procs.has_key?(option_symbol)
          Log.log.debug("set #{option_symbol} (method)")
           @attr_procs[option_symbol].call(:set,value) # TODO ? check
          else
        Log.log.debug("set #{option_symbol} (value)")
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
          theval = v.to_sym
          raise CliBadArgument,"unknown value for #{option_symbol}: #{v}" unless values.include?(theval)
          set_option(option_symbol,theval)
        end
      end

      def add_opt_simple(option_symbol,*args)
        Log.log.info("add_opt_simple #{option_symbol}->#{args}")
        self.on(*args) { |v| set_option(option_symbol,v) }
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

      def parse_options!()
        self.parse!(@myoptions)
      end

    end
  end
end
