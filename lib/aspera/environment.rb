# frozen_string_literal: true

# cspell:ignore USERPROFILE HOMEDRIVE HOMEPATH LC_CTYPE msys aarch
require 'aspera/log'
require 'aspera/assert'
require 'rbconfig'
require 'singleton'
require 'English'

# cspell:words MEBI mswin bccwin

module Aspera
  # detect OS, architecture, and specific stuff
  class Environment
    include Singleton

    OS_WINDOWS = :windows
    OS_MACOS = :osx
    OS_LINUX = :linux
    OS_AIX = :aix
    OS_LIST = [OS_WINDOWS, OS_MACOS, OS_LINUX, OS_AIX].freeze

    CPU_X86_64 = :x86_64
    CPU_ARM64 = :arm64
    CPU_PPC64 = :ppc64
    CPU_PPC64LE = :ppc64le
    CPU_S390 = :s390
    CPU_LIST = [CPU_X86_64, CPU_ARM64, CPU_PPC64, CPU_PPC64LE, CPU_S390].freeze

    BITS_PER_BYTE = 8
    MEBI = 1024 * 1024
    BYTES_PER_MEBIBIT = MEBI / BITS_PER_BYTE

    I18N_VARS = %w(LC_ALL LC_CTYPE LANG).freeze

    # "/" is invalid on both Unix and Windows, other are Windows special characters
    # See: https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
    WINDOWS_FILENAME_INVALID_CHARACTERS = '<>:"/\\|?*'
    REPLACE_CHARACTER = '_'

    class << self
      def ruby_version
        return RbConfig::CONFIG['RUBY_PROGRAM_VERSION']
      end

      # empty variable binding for secure eval
      def empty_binding
        return Kernel.binding
      end

      # secure execution of Ruby code
      def secure_eval(code, file, line)
        Kernel.send('lave'.reverse, code, empty_binding, file, line)
      end

      # Generate log line for external program with arguments
      # @param env [Hash, nil]   environment variables
      # @param exec [String]     path to executable
      # @param args [Array, nil] arguments
      # @return [String] log line with environment, program and arguments
      def log_spawn(exec:, args: nil, env: nil)
        [
          'execute:'.red,
          env&.map{ |k, v| "#{k}=#{Shellwords.shellescape(v)}"},
          Shellwords.shellescape(exec),
          args&.map{ |a| Shellwords.shellescape(a)}
        ].compact.flatten.join(' ')
      end

      # Start process in background
      # caller can call Process.wait on returned value
      # @param exec    [String]     path to executable
      # @param args    [Array, nil] arguments for executable
      # @param env     [Hash, nil]  environment variables
      # @param options [Hash, nil]  spawn options
      # @return [String]            PID of process
      # @raise  [Exception]         if problem
      def secure_spawn(exec:, args: nil, env: nil, **options)
        Aspera.assert_type(exec, String)
        Aspera.assert_type(args, Array, NilClass)
        Aspera.assert_type(env, Hash, NilClass)
        Aspera.assert_type(options, Hash, NilClass)
        Log.log.debug{log_spawn(exec: exec, args: args, env: env)}
        # start ascp in separate process
        spawn_args = []
        spawn_args.push(env) unless env.nil?
        spawn_args.push([exec, exec])
        spawn_args.concat(args) unless args.nil?
        opts = {close_others: true}
        opts.merge!(options) unless options.nil?
        ascp_pid = Process.spawn(*spawn_args, **opts)
        Log.log.debug{"pid: #{ascp_pid}"}
        return ascp_pid
      end

      # start process and wait for completion
      # @param env [Hash, nil]   environment variables
      # @param exec [String]     path to executable
      # @param args [Array, nil] arguments
      # @return [String] PID of process
      def secure_execute(exec:, args: nil, env: nil, **system_args)
        Aspera.assert_type(exec, String)
        Aspera.assert_type(args, Array, NilClass)
        Aspera.assert_type(env, Hash, NilClass)
        Log.log.debug{log_spawn(exec: exec, args: args, env: env)}
        # start in separate process
        spawn_args = []
        spawn_args.push(env) unless env.nil?
        # ensure no shell expansion
        spawn_args.push([exec, exec])
        spawn_args.concat(args) unless args.nil?
        kwargs = {exception: true}
        kwargs.merge!(system_args)
        Kernel.system(*spawn_args, **kwargs)
        nil
      end

      # Execute process and capture stdout
      # @param exec [String] path to executable
      # @param args [Array] arguments to executable
      # @param opts [Hash] options to capture3
      # @return stdout of executable or raise exception
      def secure_capture(exec:, args: [], exception: true, **opts)
        Aspera.assert_type(exec, String)
        Aspera.assert_type(args, Array)
        Aspera.assert_type(opts, Hash)
        Log.log.debug{log_spawn(exec: exec, args: args)}
        Log.dump(:opts, opts, level: :trace2)
        Log.dump(:ENV, ENV.to_h, level: :trace1)
        stdout, stderr, status = Open3.capture3(exec, *args, **opts)
        Log.log.debug{"status=#{status}, stderr=#{stderr}"}
        Log.log.trace1{"stdout=#{stdout}"}
        raise "process failed: #{status.exitstatus} (#{stderr})" if !status.success? && exception
        return stdout
      end

      # Write content to a file, with restricted access
      # @param path [String] the file path
      # @param force [Boolean] if true, overwrite the file
      # @param mode [Integer] the file mode (permissions)
      # @block [Proc] return the content to write to the file
      def write_file_restricted(path, force: false, mode: nil)
        Aspera.assert(block_given?, type: Aspera::InternalError)
        if force || !File.exist?(path)
          # Windows may give error
          File.unlink(path) rescue nil
          # content provided by block
          File.write(path, yield)
          restrict_file_access(path, mode: mode)
        end
        return path
      end

      # restrict access to a file or folder to user only
      def restrict_file_access(path, mode: nil)
        if mode.nil?
          # or FileUtils ?
          if File.file?(path)
            mode = 0o600
          elsif File.directory?(path)
            mode = 0o700
          else
            Log.log.debug{"No restriction can be set for #{path}"}
          end
        end
        File.chmod(mode, path) unless mode.nil?
      rescue => e
        Log.log.warn(e.message)
      end

      # @return true if we are in a terminal
      def terminal?
        $stdout.tty?
      end

      # force locale to C so that unicode characters are not used
      def force_terminal_c
        I18N_VARS.each{ |var| ENV[var] = 'C'}
      end

      # @return true if we can display Unicode characters
      # https://www.gnu.org/software/libc/manual/html_node/Locale-Categories.html
      # https://pubs.opengroup.org/onlinepubs/7908799/xbd/envvar.html
      def terminal_supports_unicode?
        terminal? && I18N_VARS.any?{ |var| ENV[var]&.include?('UTF-8')}
      end
    end
    attr_accessor :url_method, :file_illegal_characters
    attr_reader :os, :cpu, :executable_extension, :default_gui_mode

    def initialize
      initialize_fields
    end

    # initialize fields from environment
    def initialize_fields
      @os =
        case RbConfig::CONFIG['host_os']
        when /mswin/, /msys/, /mingw/, /cygwin/, /bccwin/, /wince/, /emc/
          OS_WINDOWS
        when /darwin/, /mac os/
          OS_MACOS
        when /linux/
          OS_LINUX
        when /aix/
          OS_AIX
        else Aspera.error_unexpected_value(RbConfig::CONFIG['host_os']){'host_os'}
        end
      @cpu =
        case RbConfig::CONFIG['host_cpu']
        when /x86_64/, /x64/
          CPU_X86_64
        when /powerpc/, /ppc64/
          @os.eql?(OS_LINUX) ? CPU_PPC64LE : CPU_PPC64
        when /s390/
          CPU_S390
        when /arm/, /aarch64/
          CPU_ARM64
        else Aspera.error_unexpected_value(RbConfig::CONFIG['host_cpu']){'host_cpu'}
        end
      @executable_extension = @os.eql?(OS_WINDOWS) ? 'exe' : nil
      # :text or :graphical depending on the environment
      @default_gui_mode =
        if [Environment::OS_WINDOWS, Environment::OS_MACOS].include?(os) ||
            (ENV.key?('DISPLAY') && !ENV['DISPLAY'].empty?)
          # assume not remotely connected on macos and windows or unix family
          :graphical
        else
          :text
        end
      @url_method = @default_gui_mode
      @file_illegal_characters = REPLACE_CHARACTER + WINDOWS_FILENAME_INVALID_CHARACTERS
      nil
    end

    # Normalized architecture name
    # See constants: OS_* and CPU_*
    def architecture
      "#{@os}-#{@cpu}"
    end

    # executable file extension for current OS
    def exe_file(name)
      return name unless @executable_extension
      return "#{name}#{@executable_extension}"
    end

    # on Windows, the env var %USERPROFILE% provides the path to user's home more reliably than %HOMEDRIVE%%HOMEPATH%
    # so, tell Ruby the right way
    def fix_home
      return unless @os.eql?(OS_WINDOWS) && ENV.key?('USERPROFILE') && Dir.exist?(ENV.fetch('USERPROFILE', nil))
      ENV['HOME'] = ENV.fetch('USERPROFILE', nil)
      Log.log.debug{"Windows: set HOME to USERPROFILE: #{Dir.home}"}
    end

    def graphical?
      @default_gui_mode == :graphical
    end

    # Open a URI in a graphical browser
    # Command must be non blocking
    # @param uri [String] the URI to open
    def open_uri_graphical(uri)
      case @os
      when Environment::OS_MACOS then return self.class.secure_execute(exec: 'open', args: [uri.to_s])
      when Environment::OS_WINDOWS then return self.class.secure_execute(exec: 'start', args: ['explorer', %Q{"#{uri}"}])
      when Environment::OS_LINUX   then return self.class.secure_execute(exec: 'xdg-open', args: [uri.to_s])
      else Assert.error_unexpected_value(os){'no graphical open method'}
      end
    end

    # open a file in an editor
    def open_editor(file_path)
      if ENV.key?('EDITOR')
        self.class.secure_execute(exec: ENV['EDITOR'], args: [file_path.to_s])
      elsif @os.eql?(Environment::OS_WINDOWS)
        self.class.secure_execute(exec: 'notepad.exe', args: [%Q{"#{file_path}"}])
      else
        open_uri_graphical(file_path.to_s)
      end
    end

    # Allows a user to open a URL
    # if method is :text, then URL is displayed on terminal
    # if method is :graphical, then the URL will be opened with the default browser.
    # this is non blocking
    def open_uri(the_url)
      case @url_method
      when :graphical
        open_uri_graphical(the_url)
      when :text
        case the_url.to_s
        when /^http/
          puts "USER ACTION: please enter this URL in a browser:\n#{the_url.to_s.red}\n"
        else
          puts "USER ACTION: open this:\n#{the_url.to_s.red}\n"
        end
      else Aspera.error_unexpected_value(@url_method){'URL open method'}
      end
    end

    # Replacement character for illegal filename characters
    # Can also be used as safe "join" character
    def safe_filename_character
      return REPLACE_CHARACTER if @file_illegal_characters.nil? || @file_illegal_characters.empty?
      @file_illegal_characters[0]
    end

    # Sanitize a filename by replacing illegal characters
    # @param filename [String] the original filename
    # @return [String] A file name safe to use on file system
    def sanitized_filename(filename)
      safe_char = safe_filename_character
      # Windows does not allow file name:
      # - with control characters anywhere
      # - ending with space or dot
      filename = filename
        .gsub(/[\x00-\x1F\x7F]/, safe_char)
        .sub(/[. ]+\z/, safe_char)
      if @file_illegal_characters&.size.to_i >= 2
        # replace all illegal characters with safe_char
        filename = filename.tr(@file_illegal_characters[1..-1], safe_char)
      end
      # ensure only one safe_char is used at a time
      return filename.gsub(/#{Regexp.escape(safe_char)}+/, safe_char).chomp(safe_char)
    end
  end
end
