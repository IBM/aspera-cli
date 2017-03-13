require 'optparse'

module Asperalm
  class OptParser < OptionParser
    # parse an option value, special behavior for file:, env:, val:
    def self.get_extended_value(pname,value)
      if m=value.match(/^@file:(.*)/) then
        value=m[1]
        if m=value.match(/^~\/(.*)/) then
          value=m[1]
          value=File.join(Dir.home,value)
        end
        raise OptionParser::InvalidArgument,"cannot open file \"#{value}\" for #{pname}" if ! File.exist?(value)
        value=File.read(value)
      elsif m=value.match(/^@env:(.*)/) then
        value=m[1]
        value=ENV[value]
      elsif m=value.match(/^@val:(.*)/) then
        value=m[1]
      end
      value
    end

    def self.get_next_arg_from_list(argv,descr,action_list)
      if argv.empty? then
        raise OptionParser::InvalidArgument,"missing action, one of: #{action_list.map {|x| x.to_s}.join(', ')}"
      end
      action=argv.shift.to_sym
      if !action_list.include?(action) then
        raise OptionParser::InvalidArgument,"unexpected value for #{descr}: #{action}, one of: #{action_list.map {|x| x.to_s}.join(', ')}"
      end
      return action
    end

    def self.get_next_arg_value(argv,descr)
      if argv.empty? then
        raise OptionParser::InvalidArgument,"expecting value: #{descr}"
      end
      return get_extended_value(descr,argv.shift)
    end

    def initialize(obj)
      @obj=obj
      super
    end

    def parse_ex!(argv)
      options=[]
      while !argv.empty? and argv.first =~ /^-/
        options.push argv.shift
      end
      thelogger.info("split -#{options}-#{argv}-")
      self.parse!(options)
    end

    def exit_with_usage
      STDERR.puts self
      Process.exit 1
    end

    def thelogger
      @obj.instance_variable_get('@logger')
    end

    def set_obj_val(pname,value)
      value=self.class.get_extended_value(pname,value)
      method='set_'+pname.to_s
      if @obj.respond_to?(method) then
        @obj.send(method,value)
      else
        @obj.instance_variable_set('@'+pname.to_s,value)
      end
      thelogger.info("set #{pname} to #{value}")
    end

    def set_defaults(values)
      return if values.nil?
      params=@obj.send('opt_names')
      thelogger.info("defaults=#{values}")
      thelogger.info("params=#{params}")
      params.each { |pname|
        set_obj_val(pname,values[pname]) if values.has_key?(pname)
      }
    end

    def add_opt_list(pname,help,*args)
      thelogger.info("add_opt_list #{pname}->#{args}")
      values=@obj.send('get_'+pname.to_s+'s')
      method='get_'+pname.to_s
      if @obj.respond_to?(method) then
        value=@obj.send(method)
      else
        value=@obj.instance_variable_get('@'+pname.to_s)
      end
      self.on( *args , values, "#{help}. Values=(#{values.join(',')}), current=#{value}") do |v|
        theval = v.to_sym
        if values.include?(theval) then
          set_obj_val(pname,theval)
        else
          raise OptionParser::InvalidArgument,"unknown value for #{pname}: #{v}"
        end
      end
    end

    def add_opt_simple(pname,*args)
      thelogger.info("add_opt_simple #{pname}->#{args}")
      self.on(*args) { |v| set_obj_val(pname,v) }
    end

    def get_option_optional(pname)
      return @obj.instance_variable_get('@'+pname.to_s)
    end

    def get_option_mandatory(pname)
      value=get_option_optional(pname)
      if value.nil? then
        raise OptionParser::InvalidArgument,"Missing option in context: #{pname}"
      end
      return value
    end
  end
end #module Asperalm
