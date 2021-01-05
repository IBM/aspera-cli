require 'aspera/log'

module Aspera
  # a simple binary data repository
  class Environment
    OS_WINDOWS = :windows
    OS_X = :osx
    OS_LINUX = :linux
    OS_AIX = :aix
    OS_LIST=[OS_WINDOWS,OS_X,OS_LINUX,OS_AIX]

    def self.os
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
        raise "Unknown: #{RbConfig::CONFIG['host_os']}"
      end
    end
    CPU_X86_64=:x86_64
    CPU_PPC64=:ppc64
    CPU_PPC64LE=:ppc64le
    CPU_S390=:s390
    CPU_LIST=[CPU_X86_64,CPU_PPC64,CPU_PPC64LE,CPU_S390]

    def self.cpu
      case RbConfig::CONFIG['host_cpu']
      when /x86_64/
        return :x86_64
      when /powerpc/
        return :ppc64le if os.eql?(OS_LINUX)
        return :ppc64
      when /s390/
        return :s390
      else # other
        raise "Unknown: #{RbConfig::CONFIG['host_cpu']}"
      end
    end

    def self.architecture
      return "#{os}-#{cpu}"
    end

    def self.exe_extension
      return '.exe' if os.eql?(OS_WINDOWS)
      return ''
    end
  end
end
