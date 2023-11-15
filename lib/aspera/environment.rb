# frozen_string_literal: true

# cspell:ignore USERPROFILE HOMEDRIVE HOMEPATH LC_CTYPE msys aarch
require 'aspera/log'
require 'rbconfig'

# cspell:words MEBI mswin bccwin

module Aspera
  # detect OS, architecture, and specific stuff
  class Environment
    OS_WINDOWS = :windows
    OS_X = :osx
    OS_LINUX = :linux
    OS_AIX = :aix
    OS_LIST = [OS_WINDOWS, OS_X, OS_LINUX, OS_AIX].freeze
    CPU_X86_64 = :x86_64
    CPU_PPC64 = :ppc64
    CPU_PPC64LE = :ppc64le
    CPU_S390 = :s390
    CPU_LIST = [CPU_X86_64, CPU_PPC64, CPU_PPC64LE, CPU_S390].freeze

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
          return OS_X
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
          # arm on mac has rosetta 2
          return CPU_X86_64 if os.eql?(OS_X)
        end
        raise "Unknown CPU: #{RbConfig::CONFIG['host_cpu']}"
      end

      def architecture
        return "#{os}-#{cpu}"
      end

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

      def empty_binding
        return Kernel.binding
      end

      # secure execution of Ruby code
      def secure_eval(code, file, line)
        Kernel.send('lave'.reverse, code, empty_binding, file, line)
      end

      # value is provided in block
      def write_file_restricted(path, force: false, mode: nil)
        raise 'coding error, missing content block' unless block_given?
        if force || !File.exist?(path)
          # Windows may give error
          File.unlink(path) rescue nil
          # content provided by block
          File.write(path, yield)
          restrict_file_access(path, mode: mode)
        end
        return path
      end

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

      def terminal?
        $stdout.tty?
      end

      # @return true if we can display Unicode characters
      def use_unicode?
        @use_unicode = terminal? && ENV.values_at('LC_ALL', 'LC_CTYPE', 'LANG').compact.first.include?('UTF-8') if @use_unicode.nil?
        return @use_unicode
      end
    end # self
  end # Environment
end # Aspera
