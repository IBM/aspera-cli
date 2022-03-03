require 'aspera/log'

module Aspera
  # Run +ascmd+ commands using specified executor (usually, remotely on transfer node)
  # Equivalent of SDK "command client"
  # execute: "ascmd -h" to get syntax
  # Note: "ls" can take filters: as_ls -f *.txt -f *.bin /
  class AsCmd
    # list of supported actions
    OPERATIONS=[:ls,:rm,:mv,:du,:info,:mkdir,:cp,:df,:md5sum].freeze

    #  @param command_executor [Object] provides the "execute" method, taking a command to execute, and stdin to feed to it, typically: ssh or local
    def initialize(command_executor)
      @command_executor = command_executor
    end

    # execute an "as" command on a remote server
    # @param [Symbol] one of OPERATIONS
    # @param [Array] parameters for "as" command
    # @return result of command, type depends on command (bool, array, hash)
    def execute_single(action_sym,args=nil)
      # concatenate arguments, enclose in double quotes, protect backslash and double quotes, add "as_" command and as_exit
      stdin_input=(args||[]).map{|v| '"' + v.gsub(/["\\]/n) {|s| '\\' + s } + '"'}.unshift('as_'+action_sym.to_s).join(' ')+"\nas_exit\n"
      # execute, get binary output
      bytebuffer=@command_executor.execute('ascmd',stdin_input).unpack('C*')
      # get hash or table result
      result=self.class.parse(bytebuffer,:result)
      raise 'ERROR: unparsed bytes remaining' unless bytebuffer.empty?
      # get and delete info,always present in results
      system_info=result[:info]
      result.delete(:info)
      # make single file result like a folder
      if result.has_key?(:file);result[:dir]=[result[:file]];result.delete(:file);end
      # add type field for stats
      if result.has_key?(:dir)
        result[:dir].each do |file|
          if file.has_key?(:smode)
            # Converts the first character of the file mode (see 'man ls') into a type.
            file[:type]=case file[:smode][0,1];when'd' then:directory;when'-' then:file;when'l' then:link;else;:other;end
          end
        end
      end
      # for info, second overrides first, so restore it
      case result.keys.length;when 0 then result=system_info;when 1 then result=result[result.keys.first];else raise 'error';end
      # raise error as exception
      raise Error.new(result[:errno],result[:errstr],action_sym,args) if result.is_a?(Hash) and result.keys.sort == TYPES_DESCR[:error][:fields].map{|i|i[:name]}.sort
      return result
    end # execute_single

    # This exception is raised when +ascmd+ returns an error.
    class Error < StandardError
      attr_reader :errno, :errstr, :command, :args
      def initialize(errno,errstr,cmd,args);@errno=errno;@errstr=errstr;@command=cmd;@args=args;end

      def message; "ascmd: (#{errno}) #{errstr}"; end

      def extended_message; "ascmd: errno=#{errno} errstr=\"#{errstr}\" command=\"#{command}\" args=#{args}"; end
    end # Error

    # description of result structures (see ascmdtypes.h). Base types are big endian
    # key = name of type
    TYPES_DESCR={
      result: {decode: :field_list,fields: [{name: :file,is_a: :stat},{name: :dir,is_a: :stat,special: :substruct},{name: :size,is_a: :size},{name: :error,is_a: :error},{name: :info,is_a: :info},{name: :success,is_a: nil,special: :return_true},{name: :exit,is_a: nil},{name: :df,is_a: :mnt,special: :restart_on_first},{name: :md5sum,is_a: :md5sum}]},
      stat:   {decode: :field_list,fields: [{name: :name,is_a: :zstr},{name: :size,is_a: :int64},{name: :mode,is_a: :int32,check: nil},{name: :zmode,is_a: :zstr},{name: :uid,is_a: :int32,check: nil},{name: :zuid,is_a: :zstr},{name: :gid,is_a: :int32,check: nil},{name: :zgid,is_a: :zstr},{name: :ctime,is_a: :epoch},{name: :zctime,is_a: :zstr},{name: :mtime,is_a: :epoch},{name: :zmtime,is_a: :zstr},{name: :atime,is_a: :epoch},{name: :zatime,is_a: :zstr},{name: :symlink,is_a: :zstr},{name: :errno,is_a: :int32},{name: :errstr,is_a: :zstr}]},
      info:   {decode: :field_list,fields: [{name: :platform,is_a: :zstr},{name: :version,is_a: :zstr},{name: :lang,is_a: :zstr},{name: :territory,is_a: :zstr},{name: :codeset,is_a: :zstr},{name: :lc_ctype,is_a: :zstr},{name: :lc_numeric,is_a: :zstr},{name: :lc_time,is_a: :zstr},{name: :lc_all,is_a: :zstr},{name: :dev,is_a: :zstr,special: :multiple},{name: :browse_caps,is_a: :zstr},{name: :protocol,is_a: :zstr}]},
      size:   {decode: :field_list,fields: [{name: :size,is_a: :int64},{name: :fcount,is_a: :int32},{name: :dcount,is_a: :int32},{name: :failed_fcount,is_a: :int32},{name: :failed_dcount,is_a: :int32}]},
      error:  {decode: :field_list,fields: [{name: :errno,is_a: :int32},{name: :errstr,is_a: :zstr}]},
      mnt:    {decode: :field_list,fields: [{name: :fs,is_a: :zstr},{name: :dir,is_a: :zstr},{name: :is_a,is_a: :zstr},{name: :total,is_a: :int64},{name: :used,is_a: :int64},{name: :free,is_a: :int64},{name: :fcount,is_a: :int64},{name: :errno,is_a: :int32},{name: :errstr,is_a: :zstr}]},
      md5sum: {decode: :field_list,fields: [{name: :md5sum,is_a: :zstr}]},
      int8:   {decode: :base,unpack: 'C',size: 1},
      int32:  {decode: :base,unpack: 'L>',size: 4},
      int64:  {decode: :base,unpack: 'Q>',size: 8},
      epoch:  {decode: :base,unpack: 'Q>',size: 8},
      zstr:   {decode: :base,unpack: 'Z*'},
      blist:  {decode: :buffer_list}
    }.freeze

    # protocol enum start at one, but array index start at zero
    ENUM_START=1

    private_constant :TYPES_DESCR,:ENUM_START

    class << self
      private
      # get description of structure's field, @param struct_name, @param typed_buffer provides field name
      def field_description(struct_name,typed_buffer)
        result=TYPES_DESCR[struct_name][:fields][typed_buffer[:btype]-ENUM_START]
        raise "Unrecognized field for #{struct_name}: #{typed_buffer[:btype]}\n#{typed_buffer[:buffer]}" if result.nil?
        return result
      end

      # decodes the provided buffer as provided type name
      # @return a decoded type.
      # :base : value, :buffer_list : an array of {btype,buffer}, :field_list : a hash, or array
      def parse(buffer,type_name,indent_level=nil)
        indent_level=(indent_level||-1)+1
        type_descr=TYPES_DESCR[type_name]
        raise "Unexpected type #{type_name}" if type_descr.nil?
        Log.log.debug("#{'   .'*indent_level}parse:#{type_name}:#{type_descr[:decode]}:#{buffer[0,16]}...".red)
        result=nil
        case type_descr[:decode]
        when :base
          num_bytes=type_name.eql?(:zstr) ? buffer.length : type_descr[:size]
          raise 'ERROR:not enough bytes' if buffer.length < num_bytes
          byte_array=buffer.shift(num_bytes);byte_array=[byte_array] unless byte_array.is_a?(Array)
          result=byte_array.pack('C*').unpack(type_descr[:unpack]).first
          Log.log.debug("#{'   .'*indent_level}-> base:#{byte_array} -> #{result}")
          result=Time.at(result) if type_name.eql?(:epoch)
        when :buffer_list
          result = []
          while !buffer.empty?
            btype=parse(buffer,:int8,indent_level)
            length=parse(buffer,:int32,indent_level)
            raise 'ERROR:not enough bytes' if buffer.length < length
            value=buffer.shift(length)
            result.push({btype: btype,buffer: value})
            Log.log.debug("#{'   .'*indent_level}:buffer_list[#{result.length-1}] #{result.last}")
          end
        when :field_list
          # by default the result is one struct
          result = {}
          # get individual binary fields
          parse(buffer,:blist,indent_level).each do |typed_buffer|
            # what type of field is it ?
            field_info=field_description(type_name,typed_buffer)
            Log.log.debug("#{'   .'*indent_level}+ field(special=#{field_info[:special]})=#{field_info[:name]}".green)
            case field_info[:special]
            when nil
              result[field_info[:name]]=parse(typed_buffer[:buffer],field_info[:is_a],indent_level)
            when :return_true
              result[field_info[:name]]=true
            when :substruct
              result[field_info[:name]]=parse(typed_buffer[:buffer],:blist,indent_level).map{|r|parse(r[:buffer],field_info[:is_a],indent_level)}
            when :multiple
              result[field_info[:name]]||=[]
              result[field_info[:name]].push(parse(typed_buffer[:buffer],field_info[:is_a],indent_level))
            when :restart_on_first
              fl=result[field_info[:name]]=[]
              parse(typed_buffer[:buffer],:blist,indent_level).map do |tb|
                fl.push({}) if tb[:btype].eql?(ENUM_START)
                fi=field_description(field_info[:is_a],tb)
                fl.last[fi[:name]]=parse(tb[:buffer],fi[:is_a],indent_level)
              end
            end
          end
        else raise "error: unknown decode:#{type_descr[:decode]}"
        end # is_a
        return result
      end
    end
  end
end
