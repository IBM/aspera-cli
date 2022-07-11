# frozen_string_literal: true

require 'aspera/log'
require 'rbconfig'

module Aspera
  # detect OS, architecture, and specific stuff
  class Environment
    OS_WINDOWS = :windows
    OS_X = :osx
    OS_LINUX = :linux
    OS_AIX = :aix
    OS_LIST = [OS_WINDOWS,OS_X,OS_LINUX,OS_AIX].freeze
    CPU_X86_64 = :x86_64
    CPU_PPC64 = :ppc64
    CPU_PPC64LE = :ppc64le
    CPU_S390 = :s390
    CPU_LIST = [CPU_X86_64,CPU_PPC64,CPU_PPC64LE,CPU_S390].freeze

    class << self
      def ruby_version
        return RbConfig::CONFIG['RUBY_PROGRAM_VERSION']
      end

      def os
        case RbConfig::CONFIG['host_os']
        when /mswin/,/msys/,/mingw/,/cygwin/,/bccwin/,/wince/,/emc/
          return OS_WINDOWS
        when /darwin/,/mac os/
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
        when /x86_64/,/x64/
          return CPU_X86_64
        when /powerpc/,/ppc64/
          return CPU_PPC64LE if os.eql?(OS_LINUX)
          return CPU_PPC64
        when /s390/
          return CPU_S390
        when /arm/
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
        return unless os.eql?(OS_WINDOWS) && ENV.has_key?('USERPROFILE') && Dir.exist?(ENV['USERPROFILE'])
        ENV['HOME'] = ENV['USERPROFILE']
        Log.log.debug("Windows: set home to USERPROFILE: #{ENV['HOME']}")
      end

      def empty_binding
        return Kernel.binding
      end

      # secure execution of Ruby code
      def secure_eval(code)
        Kernel.send('lave'.reverse,code,empty_binding, __FILE__, __LINE__)
      end
    end
  end
end
