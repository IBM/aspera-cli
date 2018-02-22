require 'asperalm/log'

module Asperalm
  # Methods for running +ascmd+ commands on a node.
  # equivalent of SDK "command client"
  class AsCmd
    # list of supported actions
    def self.action_list; [:ls,:rm,:mv,:du,:info,:mkdir,:cp,:df,:md5sum]; end

    #  @param [Object] provides the "execute" method, taking a command to execute, and stdin to feed to it
    def initialize(command_executor)
      @command_executor = command_executor
    end

    # execute an "as" command on a remote server
    # @param [Symbol] one of [action_list]
    # @param [Array] parameters for "as" command
    # @return result of command, type depends on command (bool, array, hash)
    def execute_single(action_sym,args)
      # concatenate arguments, enclose in double quotes, protect backslash and double quotes, add "as_" command and as_exit
      stdin_input=(args||[]).map{|v| '"' + v.gsub(/["\\]/n) {|s| '\\' + s } + '"'}.unshift('as_'+action_sym.to_s).join(' ')+"\nas_exit\n"
      # execute and get binary output
      bin_response=@command_executor.execute('ascmd',stdin_input)
      # get hash or table
      result=self.class.parse_result(bin_response)
      # raise error as exception
      raise Error.new(result[:errno],result[:errstr],action_sym,args) if result.is_a?(Hash) and result.keys.sort == FIELDS[:error].map{|i|i[:name]}.sort
      # add type field for stats
      if action_sym.eql?(:ls)
        result.each do |file|
          if file.has_key?(:smode)
            # Converts the first character of the file mode (see 'man ls') into a type.
            file[:type] = case file[:smode][0,1]
            when 'd'; :directory
            when '-'; :file
            when 'l'; :link
            else      :other
            end
          end
        end
      end
      return result
    end # execute_single

    # This exception is raised when +ascmd+ returns an error.
    # @example
    #     message         "(2) No such file or directory"
    #     rc              2
    #     ascmd_message   "No such file or directory"
    #     command         :ls
    #     args            ["/non_existent/directory"]
    class Error < StandardError
      attr_reader :rc, :ascmd_message, :command, :args
      # @param code(int), message(str), command(symbol), args(string array)
      def initialize(rc,msg,cmd,args)
        @rc=rc
        @ascmd_message=msg
        @command=cmd
        @args=args
      end

      def message; "ascmd: (#{rc}) #{ascmd_message}"; end

      def extended_message; "ascmd: rc=#{rc} msg=\"#{ascmd_message}\" command=\"#{command}\" args=#{args}"; end
    end # Error

    private

    ENUM_START=1
    # desription of result strutures
    # from ascmdtypes.h, note that enum values start at ENUM_START, not zero (array index)
    FIELDS={
      :response=>[{:name=>:file,:type=>:stat},{:name=>:dir,:type=>:stat,:array=>true},{:name=>:size,:type=>:size},{:name=>:error,:type=>:error},{:name=>:info,:type=>:info},{:name=>:success,:type=>nil,:return_true=>true},{:name=>:exit,:type=>nil},{:name=>:df,:type=>:mnt,:concatlist=>true},{:name=>:md5sum,:type=>:md5sum}],
      :stat=>[{:name=>:name,:type=>:zstr},{:name=>:size,:type=>:int64},{:name=>:mode,:type=>:int32,:check=>nil},{:name=>:zmode,:type=>:zstr},{:name=>:uid,:type=>:int32,:check=>nil},{:name=>:zuid,:type=>:zstr},{:name=>:gid,:type=>:int32,:check=>nil},{:name=>:zgid,:type=>:zstr},{:name=>:ctime,:type=>:epoch},{:name=>:zctime,:type=>:zstr},{:name=>:mtime,:type=>:epoch},{:name=>:zmtime,:type=>:zstr},{:name=>:atime,:type=>:epoch},{:name=>:zatime,:type=>:zstr},{:name=>:symlink,:type=>:zstr},{:name=>:errno,:type=>:int32},{:name=>:errstr,:type=>:zstr}],
      :info=>[{:name=>:platform,:type=>:zstr},{:name=>:version,:type=>:zstr},{:name=>:lang,:type=>:zstr},{:name=>:territory,:type=>:zstr},{:name=>:codeset,:type=>:zstr},{:name=>:lc_ctype,:type=>:zstr},{:name=>:lc_numeric,:type=>:zstr},{:name=>:lc_time,:type=>:zstr},{:name=>:lc_all,:type=>:zstr},{:name=>:dev,:type=>:zstr,:array=>true},{:name=>:browse_caps,:type=>:zstr},{:name=>:protocol,:type=>:zstr}],
      :size=>[{:name=>:size,:type=>:int64},{:name=>:fcount,:type=>:int32},{:name=>:dcount,:type=>:int32},{:name=>:failed_fcount,:type=>:int32},{:name=>:failed_dcount,:type=>:int32}],
      :error=>[{:name=>:errno,:type=>:int32},{:name=>:errstr,:type=>:zstr}],
      :mnt=>[{:name=>:fs,:type=>:zstr},{:name=>:dir,:type=>:zstr},{:name=>:type,:type=>:zstr},{:name=>:total,:type=>:int64},{:name=>:used,:type=>:int64},{:name=>:free,:type=>:int64},{:name=>:fcount,:type=>:int64},{:name=>:errno,:type=>:int32},{:name=>:errstr,:type=>:zstr}],
      :md5sum=>[{:name=>:md5sum,:type=>:zstr}]
    }

    # sizeof(int8)
    TLV_SIZE_TYPE = 1
    # sizeof(int32)
    TLV_SIZE_LENGTH = 4

    def self.parse_result(bin_response)
      result_fields = parse_list(bin_response)
      raise "extecting 2 parts" unless result_fields.length.eql?(2)
      # first entry is as_info, check, but ignore it
      raise "expecting info at start" unless FIELDS[:response][result_fields.first[:type]-ENUM_START][:type].eql?(:info)
      return parse_structure(FIELDS[:response][result_fields.last[:type]-ENUM_START],result_fields.last[:value])
    end

    #
    def self.parse_structure(field_descr,bin_value)
      if field_descr[:array]
        return parse_list(bin_value).map{|r|parse_structure({:name=>field_descr[:name],:type=>field_descr[:type]},r[:value])}
      end
      return true if field_descr[:return_true]
      hash_response = {}
      array_response = []
      fields_info=FIELDS[field_descr[:type]]
      parse_list(bin_value).each do |field|
        field_info=fields_info[field[:type]-ENUM_START]
        raise "Unrecognized field: #{field[:type]}\n#{field[:value]}" if fields_info.nil?
        # if destination != hash_response, then field is a simple list of values
        destination=hash_response
        if field_info[:array]
          # special case: field is a list of values
          hash_response[field_info[:name]]||=[]
          destination={}
        end
        if field_descr[:concatlist] and 1.eql?(field[:type])
          # special case: concatenated list
          # restart a new element at index 1
          hash_response={}
          destination=hash_response
          array_response.push(hash_response)
        end
        # this level has only simple types
        parse_simple(destination,field_info[:name],field_info[:type],field[:value])
        # special case: field is a list of values
        hash_response[field_info[:name]].push(destination[field_info[:name]]) unless destination.eql?(hash_response)
      end
      # special case: concatenated list
      return array_response if field_descr[:concatlist]
      hash_response
    end

    # parse a list of fields
    def self.parse_list(bin_value)
      result = []
      offset = 0
      while (offset+TLV_SIZE_TYPE+TLV_SIZE_LENGTH) <= bin_value.length
        field={}
        offset+=parse_simple(field,:type,:int8,bin_value[offset])
        offset+=parse_simple(field,:length,:int32,bin_value[offset,TLV_SIZE_LENGTH])
        field[:value] = bin_value[offset, field[:length]]
        offset+=field[:length]
        result.push(field)
        Log.log.debug("[#{result.length-1}] #{result.last}")
      end
      raise "extra bytes found: offset=#{offset}, length=#{bin_value.length}" unless offset.eql?(bin_value.length)
      result
    end

    # note we assume same endian as server (native)
    def self.parse_simple(hash,key,type,bin_value)
      size=nil
      hash[key]=case type
      when :int8; size=1;bin_value.unpack('C').first
      when :int32; size=4;bin_value.unpack('L>').first
      when :int64; size=8;bin_value.unpack('Q>').first
      when :zstr; size=bin_value.length;bin_value.unpack('Z*').first
      when :epoch; size=parse_simple(hash,key,:int64,bin_value);Time.at(hash[key]) rescue nil
      else raise "Unexpected type #{type}"
      end
      return size
    end
  end
end

if ENV.has_key?('TESTIT')
  class LocalExecutor
    def execute(cmd,line)
      Asperalm::Log.log.info("[#{line}]")
      #`echo "#{line}"|ssh root@10.25.0.8 #{cmd}`
      `echo "#{line}"|#{cmd}`
    end
  end
  ascmd=Asperalm::AsCmd.new(LocalExecutor.new)
  #Asperalm::Log.level=:debug
  [
    ['info'],
    ['ls','/core.1127'],
    ['ls','/'],
    ['mkdir','/123'],
    ['mv','/123','/234'],
    ['rm','/234'],
    ['du','/Users/xfer'],
    ['cp','/tmp/123','/tmp/1234'],
    ['df','/'],
    ['df'],
    ['md5sum','/dev/null']
  ].each do |t|
    begin
      puts "testing: #{t}"
      puts ascmd.send(:execute_single,t.shift,t)
    rescue Asperalm::AsCmd::Error => e
      puts e.extended_message
    end
  end
end
