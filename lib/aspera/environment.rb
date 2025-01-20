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
    USER_INTERFACES = %i[text graphical].freeze

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

    class << self
      def ruby_version
        return RbConfig::CONFIG['RUBY_PROGRAM_VERSION']
      end

      def os
        case RbConfig::CONFIG['host_os']
        when /mswin/, /msys/, /mingw/, /cygwin/, /bccwin/, /wince/, /emc/
          return OS_WINDOWS
        when /darwin/, /mac os/
          return OS_MACOS
        when /linux/
          return OS_LINUX
        when /aix/
          return OS_AIX
        else
          raise "Unknown OS: #{RbConfig::CONFIG['host_os']}"
        end
      end

      def cpu
        case RbConfig::CONFIG['host_cpu']
        when /x86_64/, /x64/
          return CPU_X86_64
        when /powerpc/, /ppc64/
          return CPU_PPC64LE if os.eql?(OS_LINUX)
          return CPU_PPC64
        when /s390/
          return CPU_S390
        when /arm/, /aarch64/
          return CPU_ARM64
        end
        raise "Unknown CPU: #{RbConfig::CONFIG['host_cpu']}"
      end

      # normalized architecture name
      # see constants: OS_* and CPU_*
      def architecture
        return "#{os}-#{cpu}"
      end

      # executable file extension for current OS
      def exe_extension
        return '.exe' if os.eql?(OS_WINDOWS)
        return ''
      end

      # on Windows, the env var %USERPROFILE% provides the path to user's home more reliably than %HOMEDRIVE%%HOMEPATH%
      # so, tell Ruby the right way
      def fix_home
        return unless os.eql?(OS_WINDOWS) && ENV.key?('USERPROFILE') && Dir.exist?(ENV.fetch('USERPROFILE', nil))
        ENV['HOME'] = ENV.fetch('USERPROFILE', nil)
        Log.log.debug{"Windows: set HOME to USERPROFILE: #{Dir.home}"}
      end

      # empty variable binding for secure eval
      def empty_binding
        return Kernel.binding
      end

      # secure execution of Ruby code
      def secure_eval(code, file, line)
        Kernel.send('lave'.reverse, code, empty_binding, file, line)
      end

      def log_spawn(env:, exec:, args:)
        [
          'execute:'.red,
          env.map{|k, v| "#{k}=#{Shellwords.shellescape(v)}"},
          Shellwords.shellescape(exec),
          args.map{|a|Shellwords.shellescape(a)}
        ].flatten.join(' ')
      end

      # start process in background, or raise exception
      # caller can call Process.wait on returned value
      def secure_spawn(exec:, args: [], env: [])
        Log.log.debug {log_spawn(env: env, exec: exec, args: args)}
        # start ascp in separate process
        ascp_pid = Process.spawn(env, [exec, exec], *args, close_others: true)
        Log.log.debug{"pid: #{ascp_pid}"}
        return ascp_pid
      end

      # @param exec [String] path to executable
      # @param args [Array] arguments to executable
      # @param opts [Hash] options to capture3
      # @return stdout of executable or raise expcetion
      def secure_capture(exec:, args: [], **opts)
        Aspera.assert_type(exec, String)
        Aspera.assert_type(args, Array)
        Aspera.assert_type(opts, Hash)
        Log.log.debug {log_spawn(env: {}, exec: exec, args: args)}
        stdout, stderr, status = Open3.capture3(exec, *args, **opts)
        Log.log.debug{"status=#{status}, stderr=#{stderr}"}
        Log.log.trace1{"stdout=#{stdout}"}
        raise "process failed: #{status.exitstatus} : #{stderr}" unless status.success?
        return stdout
      end

      # Write content to a file, with restricted access
      # @param path [String] the file path
      # @param force [Boolean] if true, overwrite the file
      # @param mode [Integer] the file mode (permissions)
      # @block [Proc] return the content to write to the file
      def write_file_restricted(path, force: false, mode: nil)
        Aspera.assert(block_given?, exception_class: Aspera::InternalError)
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

      # @return :text or :graphical depending on the environment
      def default_gui_mode
        # assume not remotely connected on macos and windows
        return :graphical if [Environment::OS_WINDOWS, Environment::OS_MACOS].include?(Environment.os)
        # unix family
        return :graphical if ENV.key?('DISPLAY') && !ENV['DISPLAY'].empty?
        return :text
      end

      # open a URI in a graphical browser
      # command must be non blocking
      def open_uri_graphical(uri)
        case Environment.os
        when Environment::OS_MACOS then return system('open', uri.to_s)
        when Environment::OS_WINDOWS then return system('start', 'explorer', %Q{"#{uri}"})
        when Environment::OS_LINUX   then return system('xdg-open', uri.to_s)
        else
          raise "no graphical open method for #{Environment.os}"
        end
      end

      # open a file in an editor
      def open_editor(file_path)
        if ENV.key?('EDITOR')
          system(ENV['EDITOR'], file_path.to_s)
        elsif Environment.os.eql?(Environment::OS_WINDOWS)
          system('notepad.exe', %Q{"#{file_path}"})
        else
          open_uri_graphical(file_path.to_s)
        end
      end
    end
    attr_accessor :url_method

    def initialize
      @url_method = self.class.default_gui_mode
      @terminal_supports_unicode = nil
    end

    # @return true if we can display Unicode characters
    # https://www.gnu.org/software/libc/manual/html_node/Locale-Categories.html
    # https://pubs.opengroup.org/onlinepubs/7908799/xbd/envvar.html
    def terminal_supports_unicode?
      @terminal_supports_unicode = self.class.terminal? && %w(LC_ALL LC_CTYPE LANG).any?{|var|ENV[var]&.include?('UTF-8')} if @terminal_supports_unicode.nil?
      return @terminal_supports_unicode
    end

    # Allows a user to open a Url
    # if method is "text", then URL is displayed on terminal
    # if method is "graphical", then the URL will be opened with the default browser.
    # this is non blocking
    def open_uri(the_url)
      case @url_method
      when :graphical
        self.class.open_uri_graphical(the_url)
      when :text
        case the_url.to_s
        when /^http/
          puts "USER ACTION: please enter this url in a browser:\n#{the_url.to_s.red}\n"
        else
          puts "USER ACTION: open this:\n#{the_url.to_s.red}\n"
        end
      else
        raise StandardError, "unsupported url open method: #{@url_method}"
      end
    end
  end
end
