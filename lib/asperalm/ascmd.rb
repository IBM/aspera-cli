module Asperalm
  # Methods for running +ascmd+ commands on a node.
  # equivalent of SDK "command client"
  class AsCmd
    TLV_TYPE_ERROR = 4
    TLV_SIZE_TYPE = 1
    TLV_SIZE_LENGTH = 4
    TLV_SIZE_MIN = TLV_SIZE_TYPE + TLV_SIZE_LENGTH
    # This exception is raised when +ascmd+ returns an error.
    #
    # See the attributes for fine-grained information about the command that raised the error.
    #
    # @example
    #   node.as_ls("/non_existent/directory")   #=> raises: Aspera::Ascmd::Error: (2) No such file or directory
    #
    #   begin
    #     node.as_ls("/non_existent/directory")
    #   rescue => e
    #     puts e.message         #=> "(2) No such file or directory"
    #     puts e.rc              #=> 2
    #     puts e.ascmd_message   #=> "No such file or directory"
    #     puts e.command         #=> "as_ls"
    #     puts e.args            #=> ["/non_existent/directory"]
    #   end
    class Error < StandardError

      # The exit code from +ascmd+.
      # @return [Fixnum]
      attr_accessor :rc

      # The message from +ascmd+.
      # @return [String]
      attr_accessor :ascmd_message

      # The command passed to +ascmd+.
      # @return [String]
      attr_accessor :command

      # The arguments passed to the +ascmd+ command
      # @return [Array of String]
      attr_accessor :args
      # @param [Array] array command array from parsing +ascmd+ response
      def initialize(bin_value,method,the_args)
        self.command = method.to_s
        self.args = the_args.nil? ? [] : the_args
        Parser.parse_tlv_list_from_bin(bin_value).each do |item|
          case item[:type]
          when 1; self.rc = Parser.parse_bin_int(item[:value])
          when 2; self.ascmd_message = item[:value]
          end
        end
      end

      # Message dispalyed when exception raised.
      # @return [String]
      def message
        "ascmd: (#{rc}) #{ascmd_message}"
      end

      # All attributes in one string.
      # @return [String]
      def extended_message
        "ascmd: rc=#{rc} msg='#{ascmd_message}' command='#{command}' args=#{args.map { |e| %('#{e}') }.inspect}"
      end

    end # Error

    # binary answer parsing
    # parse_res take a TypeLengthValue as parameter
    # parse_bin take the binary string
    class Parser
      # Returns an Array of Reply instances built from an ascmd response.
      # The response consists of 1 or more replies, concatenated together,
      # of the form:
      #
      #   <cmd_1><length_1><data_1>...<cmd_n><length_n><data_n>
      #
      # where:
      #
      # * cmd - a hex number indicating the type of response
      # * length - the length of the response
      # * data - the content of the response.
      #
      def self.parse_tlv_list_from_bin(bin_value)
        tlv_list = []
        offset = 0
        while offset < bin_value.length
          raise "bad ascmd result format" if offset > (bin_value.length - TLV_SIZE_MIN)
          type = bin_value[offset].ord
          offset+=TLV_SIZE_TYPE
          length = parse_bin_int(bin_value[offset,TLV_SIZE_LENGTH])
          offset+=TLV_SIZE_LENGTH
          value = bin_value[offset, length]
          offset+=length
          tlv_list << {:type=>type, :length=>length, :value=>value}
        end
        tlv_list
      end

      # parse folder content
      def self.parse_bin_directory(bin_value)
        parse_tlv_list_from_bin(bin_value).map{|r|parse_bin_directory_item(r[:value])}
      end

      # Returns a DirectoryItem instance parsed from a file or directory response.
      def self.parse_bin_directory_item(bin_value)
        final_result = {}
        parse_tlv_list_from_bin(bin_value).each do |tlv|
          case tlv[:type]
          when 1;  final_result[:name]    = tlv[:value][0..-2] #cuts the trailing \000
          when 2;  final_result[:size]    = parse_bin_int(tlv[:value])
          when 3;  final_result[:mode]    = parse_bin_int(tlv[:value])
          when 4;  final_result[:smode]   = tlv[:value].strip
          when 5;  final_result[:uid]     = parse_bin_int(tlv[:value])
          when 6;  final_result[:suid]    = tlv[:value].strip
          when 7;  final_result[:gid]     = parse_bin_int(tlv[:value])
          when 8;  final_result[:sgid]    = tlv[:value].strip
          when 9;  final_result[:ctime]   = parse_bin_time_epoch(tlv[:value])
          when 10; final_result[:sctime]  = parse_bin_time_string(tlv[:value])
          when 11; final_result[:mtime]   = parse_bin_time_epoch(tlv[:value])
          when 12; final_result[:smtime]  = parse_bin_time_string(tlv[:value])
          when 13; final_result[:atime]   = parse_bin_time_epoch(tlv[:value])
          when 14; final_result[:satime]  = parse_bin_time_string(tlv[:value])
          when 15; final_result[:symlink] = tlv[:value].strip
          when 16; final_result[:error]   = parse_bin_int(tlv[:value])
          when 17; final_result[:errstr]  = tlv[:value].strip
          end
        end
        if final_result.has_key?(:smode)
          # Converts the first character of the file mode (see 'man ls') into a type.
          final_result[:type] = case final_result[:smode][0,1]
          when 'd'; :directory
          when '-'; :file
          when 'l'; :link
          else      :other
          end
        end
        final_result
      end

      def self.parse_bin_int(buf)
        val = 0
        if (buf)
          buf.each_byte do |f|
            val = val * 256 + f
          end
        end
        return val
      end

      def self.parse_bin_time_epoch(epoch)
        Time.at(parse_bin_int(epoch)) rescue nil
      end

      def self.parse_bin_time_string(bin_value)
        Time.parse(bin_value) rescue nil
      end

      # Returns Hash of values derived from banner message that is returned
      # from the invocation of as_<cmd>.
      def self.parse_res_info(tlv_list)
        final_result = {}
        parse_tlv_list_from_bin(tlv_list.shift[:value]).each do |tlv|
          case tlv[:type]
          when 1;  final_result[:platform] = tlv[:value].strip
          when 2;  final_result[:version] = tlv[:value].strip
          when 3;  final_result[:language] = tlv[:value].strip
          when 4;  final_result[:territory] = tlv[:value].strip
          when 5;  final_result[:codeset] = tlv[:value].strip
          when 6;  final_result[:lc_ctype] = tlv[:value].strip
          when 7;  final_result[:lc_numeric] = tlv[:value].strip
          when 8;  final_result[:lc_time] = tlv[:value].strip
          when 9;  final_result[:lc_all] = tlv[:value].strip
          when 10; (final_result[:devices] ||= []) << tlv[:value].strip
          else     raise "Unrecognized tlv: n=[#{tlv[:type]}]\n#{tlv[:value]}"
          end
        end
        final_result
      end

      def self.parse_res_df(tlv_list)
        final_result = {}
        parse_tlv_list_from_bin(tlv_list.shift[:value]).each do |tlv|
          case tlv[:type]
          when 1;  final_result[:size] = parse_bin_int(tlv[:value].strip)
          when 2;  final_result[:file_count] = parse_bin_int(tlv[:value].strip)
          when 3;  final_result[:directory_count] = parse_bin_int(tlv[:value].strip)
          when 4;  final_result[:failed_file_count] = parse_bin_int(tlv[:value].strip)
          when 5;  final_result[:failed_directory_count] = parse_bin_int(tlv[:value].strip)
          when 6..9;  nil # TODO: next ?
          else     raise "Unrecognized tlv: #{tlv[:type]}\n#{tlv[:value]}"
          end
        end
        final_result
      end

      def self.parse_res_du(tlv_list,unused_folder_name)
        final_result = {}
        parse_tlv_list_from_bin(tlv_list.shift[:value]).each do |tlv|
          case tlv[:type]
          when 1;  final_result[:size] = parse_bin_int(tlv[:value].strip)
          when 2;  final_result[:file_count] = parse_bin_int(tlv[:value].strip)
          when 3;  final_result[:directory_count] = parse_bin_int(tlv[:value].strip)
          when 4;  final_result[:failed_file_count] = parse_bin_int(tlv[:value].strip)
          when 5;  final_result[:failed_directory_count] = parse_bin_int(tlv[:value].strip)
          else     raise "Unrecognized tlv: #{tlv[:type]}\n#{tlv[:value]}"
          end
        end
        final_result
      end

      def self.parse_res_md5sum(tlv_list,unused_path)
        final_result = {}
        parse_tlv_list_from_bin(tlv_list.shift[:value]).each do |tlv|
          case tlv[:type]
          when 1;  final_result[:md5sum] = tlv[:value].strip
          else     raise "Unrecognized tlv: #{tlv[:type]}\n#{tlv[:value]}"
          end
        end
        final_result
      end

      #
      # Parses the results of ascms "as_ls <file_or_directory>".  Returns an Array
      # of AsperaRemote::DirectoryItem.
      #
      # Note: the response from an 'ascmd as_ls <file_or_directory>' is either a
      # directory response or a file response depending on what 'file_or_directory' is.
      def self.parse_res_ls(tlv_list, file_or_directory)
        tlv=tlv_list.shift
        raise "hic, more elements ?" if !tlv_list.empty?
        # Only ever one element in tlv_list?
        final_result = case tlv[:type]
        when 1; [parse_bin_directory_item(tlv[:value])]
        when 2; parse_bin_directory(tlv[:value])
        when 4; raise Error.new(tlv[:value],'unknown',['unknown'])
        else raise "Error getting directory listing for: '#{file_or_directory}'"
        end
        # final result is a single element array, of either one tlv (file) or several tlv(folder)
        final_result
      end

    end # Parser

    attr_accessor :credentials

    def initialize(ssh_executor)
      @ssh_executor = ssh_executor
    end

    def self.action_list; [:info,:ls,:mkdir,:mv,:rm,:du,:cp,:df,:md5sum]; end

    def cp(source, destination); ascmd_exec('cp',source, destination); end

    def df; ascmd_exec('df'); end

    def du(file_or_directory); ascmd_exec('du',file_or_directory); end

    def info; ascmd_exec('info'); end

    def ls(file_or_directory); ascmd_exec('ls',file_or_directory); end

    def mkdir(directory); ascmd_exec('mkdir',directory); end

    def mv(source, destination); ascmd_exec('mv',source, destination); end

    def rm(file_or_directory); ascmd_exec('rm',file_or_directory); end

    def md5sum(file_or_directory); ascmd_exec('md5sum',file_or_directory); end

    # All +ascmd+ commands go through this method:
    # * run _command_
    # * parses the string response into (unparsed) commands
    # * check for error in the response
    # * return the commands to be parsed by the caller (if needed)
    # @param [String] command the command to run, e.g. <tt>as_ls "/tmp"</tt>
    # @return [Array of Aspera::Ascmd] possibly empty array depending on which +ascmd+ command is run
    def ascmd_exec(cmd_sym,*args)
      # concatenate arguments
      # enclose in double quotes
      # protect backslash and double quotes
      # add "as" command and as_exit
      command_line=(args||[]).map{|v| '"' + v.gsub(/["\\]/n) {|s| '\\' + s } + '"'}.unshift('as_'+cmd_sym.to_s).join(' ')+"\nas_exit\n"
      bin_response=@ssh_executor.exec_session("ascmd",command_line)
      tlv_list = Parser.parse_tlv_list_from_bin(bin_response)
      # first entry is as_info, ignore it
      Parser.parse_res_info(tlv_list)
      # error comes first
      if !tlv_list.first.nil? and tlv_list.first[:type].eql?(TLV_TYPE_ERROR)
        raise Error.new(tlv_list.first[:value],cmd_sym,args)
      end
      # return parsed result if there is a parser
      parse_method_sym=('parse_res_'+cmd_sym.to_s).to_sym
      return nil if !Parser.respond_to?(parse_method_sym)
      return Parser.send(parse_method_sym,tlv_list,*args)
    end
  end
end

if false
  ascmd=Asperalm::AsCmd.new({:host=>ARGV[0], :user=>ARGV[1], :password => ARGV[2]})
  [
    ['info'],
    ['ls','/'],
    ['mkdir','/123'],
    ['mv','/123','/234'],
    ['rm','/234'],
    ['du','/'],
    ['cp','/tmp/123','/tmp/1234'],
    ['df'],
    ['md5sum','/f']
  ].each do |t|
    begin
      puts "testing: #{t}"
      puts ascmd.send(t.shift,*t)
    rescue Asperalm::AsCmd::Error => e
      puts e.extended_message
    end
  end
end
