# frozen_string_literal: true

# cspell:ignore ascmd smode errstr zstr zmode zuid zgid zctime zatime zmtime fcount dcount btype blist codeset lc_ctype ascmdtypes
require 'aspera/log'
require 'aspera/assert'

module Aspera
  # Run +ascmd+ commands using specified executor (usually, remotely on transfer node)
  # Equivalent of SDK "command client"
  # execute: "ascmd -h" to get syntax
  # Note: "ls" can take filters: as_ls -f *.txt -f *.bin /
  class AsCmd
    # number of arguments for each operation
    OPS_ARGS = {
      cp:     2,
      df:     0,
      du:     1,
      info:   nil,
      ls:     1,
      md5sum: 1,
      mkdir:  1,
      mv:     2,
      rm:     1
    }.freeze
    private_constant :OPS_ARGS
    # list of supported actions
    OPERATIONS = OPS_ARGS.keys.freeze

    #  @param command_executor [Object] provides the "execute" method, taking a command to execute, and stdin to feed to it, typically: ssh or local
    def initialize(command_executor)
      @command_executor = command_executor
    end

    # execute an "as" command on a remote server
    # @param [Symbol] one of OPERATIONS
    # @param [Array] parameters for "as" command
    # @return result of command, type depends on command (bool, array, hash)
    def execute_single(action_sym, arguments)
      arguments = [] if arguments.nil?
      Log.log.debug{"execute_single:#{action_sym}:#{arguments}"}
      Aspera.assert_type(action_sym, Symbol)
      Aspera.assert_type(arguments, Array)
      Aspera.assert(arguments.all?(String), 'arguments must be strings')
      # lines of commands (String's)
      command_lines = []
      # add "as_" command
      main_command = "as_#{action_sym}"
      arg_batches =
        if OPS_ARGS[action_sym].nil? || OPS_ARGS[action_sym].zero?
          [arguments]
        else
          # split arguments into batches
          arguments.each_slice(OPS_ARGS[action_sym]).to_a
        end
      arg_batches.each do |args|
        command = [main_command]
        # enclose arguments in double quotes, protect backslash and double quotes
        args.each do |v|
          command.push(%Q{"#{v.gsub(/["\\]/){|s|"\\#{s}"}}"})
        end
        command_lines.push(command.join(' '))
      end
      command_lines.push('as_exit')
      command_lines.push('')
      # execute the main command and then exit
      stdin_input = command_lines.join("\n")
      Log.log.trace1{"execute_single:#{stdin_input}"}
      # execute, get binary output
      byte_buffer = @command_executor.execute('ascmd', stdin_input).unpack('C*')
      raise 'ERROR: empty answer from server' if byte_buffer.empty?
      # get hash or table result
      result = self.class.parse(byte_buffer, :result)
      raise 'ERROR: unparsed bytes remaining' unless byte_buffer.empty?
      # get and delete info,always present in results
      system_info = result[:info]
      result.delete(:info)
      # make single file result like a folder
      result[:dir] = [result.delete(:file)] if result.key?(:file)
      # add type field for stats
      if result.key?(:dir)
        result[:dir].each do |file|
          if file.key?(:smode)
            # Converts the first character of the file mode (see 'man ls') into a type.
            file[:type] = case file[:smode][0, 1]; when 'd' then:directory; when '-' then:file; when 'l' then:link; else; :other; end # rubocop:disable Style/Semicolon
          end
        end
      end
      # for info, second overrides first, so restore it
      case result.keys.length
      when 0 then result = system_info
      when 1 then result = result[result.keys.first]
      else Aspera.error_unexpected_value(result.keys.length)
      end
      # raise error as exception
      raise Error.new(result[:errno], result[:errstr], action_sym, arguments) if
        result.is_a?(Hash) && (result.keys.sort == TYPES_DESCR[:error][:fields].map{|i|i[:name]}.sort)
      return result
    end

    # This exception is raised when +ascmd+ returns an error.
    class Error < StandardError
      def initialize(errno, errstr, cmd, arguments)
        super(); @errno = errno; @errstr = errstr; @command = cmd; @arguments = arguments; end # rubocop:disable Style/Semicolon

      def message; "ascmd: #{@errstr} (#{@errno})"; end
      def extended_message; "ascmd: errno=#{@errno} errstr=\"#{@errstr}\" command=#{@command} arguments=#{@arguments&.join(',')}"; end
    end

    # protocol is based on Type-Length-Value
    # type start at one, but array index start at zero
    ENUM_START = 1

    # description of result structures (see ascmdtypes.h).
    # Base types are big endian
    # key = name of type
    # index in array: fields is the type (minus ENUM_START)
    # decoding always start at `result`
    # some fields have special handling indicated by `special`
    TYPES_DESCR = {
      result: {decode: :field_list,
               fields: [{name: :file, is_a: :stat}, {name: :dir, is_a: :stat, special: :sub_struct}, {name: :size, is_a: :size}, {name: :error, is_a: :error},
                        {name: :info, is_a: :info}, {name: :success, is_a: nil, special: :return_true}, {name: :exit, is_a: nil},
                        {name: :df, is_a: :mnt, special: :restart_on_first}, {name: :md5sum, is_a: :md5sum}]},
      stat:   {decode: :field_list,
               fields: [{name: :name, is_a: :zstr}, {name: :size, is_a: :int64}, {name: :mode, is_a: :int32, check: nil}, {name: :zmode, is_a: :zstr},
                        {name: :uid, is_a: :int32, check: nil}, {name: :zuid, is_a: :zstr}, {name: :gid, is_a: :int32, check: nil}, {name: :zgid, is_a: :zstr},
                        {name: :ctime, is_a: :epoch}, {name: :zctime, is_a: :zstr}, {name: :mtime, is_a: :epoch}, {name: :zmtime, is_a: :zstr},
                        {name: :atime, is_a: :epoch}, {name: :zatime, is_a: :zstr}, {name: :symlink, is_a: :zstr}, {name: :errno, is_a: :int32},
                        {name: :errstr, is_a: :zstr}]},
      info:   {decode: :field_list,
               fields: [{name: :platform, is_a: :zstr}, {name: :version, is_a: :zstr}, {name: :lang, is_a: :zstr}, {name: :territory, is_a: :zstr},
                        {name: :codeset, is_a: :zstr}, {name: :lc_ctype, is_a: :zstr}, {name: :lc_numeric, is_a: :zstr}, {name: :lc_time, is_a: :zstr},
                        {name: :lc_all, is_a: :zstr}, {name: :dev, is_a: :zstr, special: :multiple}, {name: :browse_caps, is_a: :zstr},
                        {name: :protocol, is_a: :zstr}]},
      size:   {decode: :field_list,
               fields: [{name: :size, is_a: :int64}, {name: :fcount, is_a: :int32}, {name: :dcount, is_a: :int32}, {name: :failed_fcount, is_a: :int32},
                        {name: :failed_dcount, is_a: :int32}]},
      error:  {decode: :field_list,
               fields: [{name: :errno, is_a: :int32}, {name: :errstr, is_a: :zstr}]},
      mnt:    {decode: :field_list,
               fields: [{name: :fs, is_a: :zstr}, {name: :dir, is_a: :zstr}, {name: :is_a, is_a: :zstr}, {name: :total, is_a: :int64},
                        {name: :used, is_a: :int64}, {name: :free, is_a: :int64}, {name: :fcount, is_a: :int64}, {name: :errno, is_a: :int32},
                        {name: :errstr, is_a: :zstr}]},
      md5sum: {decode: :field_list, fields: [{name: :md5sum, is_a: :zstr}]},
      int8:   {decode: :base, unpack: 'C', size: 1},
      int32:  {decode: :base, unpack: 'L>', size: 4},
      int64:  {decode: :base, unpack: 'Q>', size: 8},
      epoch:  {decode: :base, unpack: 'Q>', size: 8},
      zstr:   {decode: :base, unpack: 'Z*'},
      blist:  {decode: :buffer_list}
    }.freeze

    private_constant :TYPES_DESCR, :ENUM_START

    class << self
      # get description of structure's field, @param struct_name, @param typed_buffer provides field name
      def field_description(struct_name, typed_buffer)
        result = TYPES_DESCR[struct_name][:fields][typed_buffer[:btype] - ENUM_START]
        raise "Unrecognized field for #{struct_name}: #{typed_buffer[:btype]}\n#{typed_buffer[:buffer]}" if result.nil?
        return result
      end

      # decodes the provided buffer as provided type name
      # @return a decoded type.
      # :base : value, :buffer_list : an array of {btype,buffer}, :field_list : a hash, or array
      def parse(buffer, type_name, indent_level=nil)
        indent_level = (indent_level || -1) + 1
        type_descr = TYPES_DESCR[type_name]
        raise "Unexpected type #{type_name}" if type_descr.nil?
        Log.log.trace1{"#{'   .' * indent_level}parse:#{type_name}:#{type_descr[:decode]}:#{buffer[0, 16]}...".red}
        result = nil
        case type_descr[:decode]
        when :base
          num_bytes = type_name.eql?(:zstr) ? buffer.length : type_descr[:size]
          raise 'ERROR:not enough bytes' if buffer.length < num_bytes
          byte_array = buffer.shift(num_bytes)
          byte_array = [byte_array] unless byte_array.is_a?(Array)
          result = byte_array.pack('C*').unpack1(type_descr[:unpack])
          result.force_encoding('UTF-8') if type_name.eql?(:zstr)
          Log.log.trace1{"#{'   .' * indent_level}-> base:#{byte_array} -> #{result}"}
          result = Time.at(result) if type_name.eql?(:epoch)
        when :buffer_list
          result = []
          until buffer.empty?
            btype = parse(buffer, :int8, indent_level)
            length = parse(buffer, :int32, indent_level)
            raise 'ERROR:not enough bytes' if buffer.length < length
            value = buffer.shift(length)
            result.push({btype: btype, buffer: value})
            Log.log.trace1{"#{'   .' * indent_level}:buffer_list[#{result.length - 1}] #{result.last}"}
          end
        when :field_list
          # by default the result is one struct
          result = {}
          # get individual binary fields
          parse(buffer, :blist, indent_level).each do |typed_buffer|
            # what type of field is it ?
            field_info = field_description(type_name, typed_buffer)
            Log.log.trace1{"#{'   .' * indent_level}+ field(special=#{field_info[:special]})=#{field_info[:name]}".green}
            case field_info[:special]
            when nil
              result[field_info[:name]] = parse(typed_buffer[:buffer], field_info[:is_a], indent_level)
            when :return_true
              result[field_info[:name]] = true
            when :sub_struct
              result[field_info[:name]] = parse(typed_buffer[:buffer], :blist, indent_level).map{|r|parse(r[:buffer], field_info[:is_a], indent_level)}
            when :multiple
              result[field_info[:name]] ||= []
              result[field_info[:name]].push(parse(typed_buffer[:buffer], field_info[:is_a], indent_level))
            when :restart_on_first
              fl = result[field_info[:name]] = []
              parse(typed_buffer[:buffer], :blist, indent_level).map do |tb|
                fl.push({}) if tb[:btype].eql?(ENUM_START)
                fi = field_description(field_info[:is_a], tb)
                fl.last[fi[:name]] = parse(tb[:buffer], fi[:is_a], indent_level)
              end
            end
          end
        else Aspera.error_unexpected_value(type_descr[:decode])
        end
        return result
      end
    end
  end
end
