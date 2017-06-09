require 'net/ssh'

module Asperalm
  # Methods for running +ascmd+ commands on a node.
  class AsCmd
    class Result
      attr_accessor :command, :length, :string
      # Returns new instance of Reply.
      def initialize(command, length, string)
        self.command = command
        self.length = length
        self.string = string
      end

      def error?
        command == 4
      end
    end

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
      def initialize(ascmd_error,method,the_args)
        self.command = method.to_s
        self.args = the_args.nil? ? [] : the_args
        AsCmd.parse_bin_response(ascmd_error.string).each do |item|
          case item.command
          when 1; self.rc = AsCmd.parse_bin_int(item.string)
          when 2; self.ascmd_message = item.string
          end
        end
      end

      # Message dispalyed when exception raised.
      # @return [String]
      def message
        "(#{rc}) #{ascmd_message}"
      end

      # All attributes in one string.
      # @return [String]
      def extended_message
        "rc=#{rc} msg='#{ascmd_message}' command='#{command}' args=#{args.map { |e| %('#{e}') }.inspect}"
      end

    end

    def self.run(credentials, method, *args)
      self.new(credentials).send(method, *args)
    end

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
    def self.parse_bin_response(results_string)
      res_list = []
      while results_string && results_string.length > 5
        command = results_string[0].ord
        command_length = parse_bin_int(results_string[1, 4])
        data = results_string[5, command_length]
        res_list << Result.new(command, command_length, data)
        results_string = results_string[(command_length + 5), results_string.length]
      end
      res_list
    end

    # Returns Hash of values derived from banner message that is returned
    # from the invocation of as_cmd.
    def self.parse_res_info(res_list)
      banner_fields = parse_bin_response(res_list.shift.string)
      banner = {}
      banner_fields.each do |field|
        value = field.string.strip
        case field.command
        when 1;  banner[:platform] = value
        when 2;  banner[:version] = value
        when 3;  banner[:language] = value
        when 4;  banner[:territory] = value
        when 5;  banner[:codeset] = value
        when 6;  banner[:lc_ctype] = value
        when 7;  banner[:lc_numeric] = value
        when 8;  banner[:lc_time] = value
        when 9;  banner[:lc_all] = value
        when 10; (banner[:devices] ||= []) << value
        else     raise "Unrecognized banner field: n=[#{field.command}]\n#{field.string}"
        end
      end
      banner
    end

    def self.parse_res_df(res_list)
      df_fields = parse_bin_response(res_list.shift.string)
      devices = {}
      df_fields.each do |field|
        value = field.string.strip
        case field.command
        when 1;  devices[:size] = parse_bin_int(value)
        when 2;  devices[:file_count] = parse_bin_int(value)
        when 3;  devices[:directory_count] = parse_bin_int(value)
        when 4;  devices[:failed_file_count] = parse_bin_int(value)
        when 5;  devices[:failed_directory_count] = parse_bin_int(value)
        when 6..9;  nil # TODO
        else     raise "Unrecognized devices field: #{field.command}\n#{field.string}"
        end
      end
      devices
    end

    def self.parse_res_du(res_list,unused_folder_name)
      du_fields = parse_bin_response(res_list.shift.string)
      disk_usage = {}
      du_fields.each do |field|
        value = field.string.strip
        case field.command
        when 1;  disk_usage[:size] = parse_bin_int(value)
        when 2;  disk_usage[:file_count] = parse_bin_int(value)
        when 3;  disk_usage[:directory_count] = parse_bin_int(value)
        when 4;  disk_usage[:failed_file_count] = parse_bin_int(value)
        when 5;  disk_usage[:failed_directory_count] = parse_bin_int(value)
        else     raise "Unrecognized disk_usage field: #{field.command}\n#{field.string}"
        end
      end
      disk_usage
    end

    def self.parse_res_md5sum(res_list,unused_path)
      du_fields = parse_bin_response(res_list.shift.string)
      result_hash = {}
      du_fields.each do |field|
        value = field.string.strip
        case field.command
        when 1;  result_hash[:md5sum] = value
        else     raise "Unrecognized field: #{field.command}\n#{field.string}"
        end
      end
      result_hash
    end

    #
    # Parses the results of ascms "as_ls <file_or_directory>".  Returns an Array
    # of AsperaRemote::DirectoryItem.
    #
    # Note: the response from an 'ascmd as_ls <file_or_directory>' is either a
    # directory response or a file response depending on what 'file_or_directory' is.
    def self.parse_res_ls(res_list, file_or_directory)
      # Only ever one element in res_list?
      results = res_list.map do |ascmd_result|
        # puts "in parse_bin_ls() #{ascmd_result.string}"
        case ascmd_result.command
        when 1; parse_bin_directory_item(ascmd_result.string)
        when 2; parse_bin_directory(ascmd_result.string)
        when 4; parse_bin_error_and_raise(ascmd_result.string)
        else raise "Error getting directory listing for: '#{file_or_directory}'"
        end
      end.flatten
      results
    end

    # Parses a directory response from ascmd "as_ls <file_or_directory>".
    def self.parse_bin_directory(string)
      results = parse_bin_response(string)
      results.map { |r| parse_bin_directory_item(r.string) }
    end

    # Returns a DirectoryItem instance parsed from a file or directory response.
    def self.parse_bin_directory_item(string)
      hash = {}
      parse_bin_response(string).each do |reply|
        value = reply.string
        case reply.command
        when 1;  hash[:name]    = value[0..-2] #cuts the trailing \000
        when 2;  hash[:size]    = parse_bin_int(value)
        when 3;  hash[:mode]    = parse_bin_int(value)
        when 4;  hash[:type]    = mode_to_type(value.strip)
        when 5;  hash[:uid]     = parse_bin_int(value)
        when 6;  hash[:suid]    = value.strip
        when 7;  hash[:gid]     = parse_bin_int(value)
        when 8;  hash[:sgid]    = value.strip
        when 9;  hash[:ctime]   = parse_bin_time_epoch(value)
        when 10; hash[:sctime]  = parse_bin_time_string(value)
        when 11; hash[:mtime]   = parse_bin_time_epoch(value)
        when 12; hash[:smtime]  = parse_bin_time_string(value)
        when 13; hash[:atime]   = parse_bin_time_epoch(value)
        when 14; hash[:satime]  = parse_bin_time_string(value)
        when 15; hash[:symlink] = value.strip
        when 16; hash[:error]   = parse_bin_int(value)
        when 17; hash[:errstr]  = value.strip
        end
      end
      # Aspera::Directory::Item.new(hash)
      hash
    end

    # Converts the first character of the file mode (see 'man ls') into
    # a type.
    def self.mode_to_type(mode)
      case mode[0,1]
      when 'd'; :directory
      when '-'; :file
      when 'l'; :link
      else      :other
      end
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

    def self.parse_bin_time_string(string)
      Time.parse string rescue nil
    end

    attr_accessor :credentials

    def initialize(credentials)
      self.credentials = credentials
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
    def ascmd_exec(cmd,*args)
      args=[] if args.nil?
      as_cmd='as_'+cmd
      command=as_cmd
      if !args.nil? and !args.empty?
        command=args.map{|v| '"' + v.gsub(/["\\]/n) {|s| '\\' + s } + '"'}.unshift(as_cmd).join(' ')
      end
      response = ''
      Net::SSH.start(credentials[:host], credentials[:user], :password => credentials[:password]) do |ssh|
        chacha=ssh.open_channel do |channel|
          channel.on_data do |chan, data|
            response << data
          end
          # stderr if type = 1
          channel.on_extended_data do |chan, type, data|
            # Happens when windows user hasn't logged in and created home account.
            unless data.include?("Could not chdir to home directory")
              raise "got error running ascmd: #{data}"
            end
          end
          channel.exec("ascmd") do |ch, success|
            command_with_exit = [command,"as_exit\n"].compact.join("\n")
            channel.send_data(command_with_exit)
          end
        end
        chacha.wait
        ssh.loop
      end
      commands = self.class.parse_bin_response(response)
      # first entry is as_info, ignore it
      self.class.parse_res_info(commands)
      if !commands.first.nil? and commands.first.error?
        raise Error.new(commands.first,as_cmd,args)
      end
      parse_method_sym=('parse_res_'+cmd).to_sym
      return nil if !self.class.respond_to?(parse_method_sym)
      return self.class.send(parse_method_sym,commands,*args)
    end
  end
end

if false
  ascmd=Asperalm::AsCmd.new({:host=>"test", :user=>"test", :password => "test"})
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
