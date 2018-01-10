require 'logger'
require 'asperalm/colors'

module Asperalm
  class Log
    @@logobj=nil
    # levels are :debug,:info,:warn,:error,fatal,:unknown
    def self.levels; Logger::Severity.constants.map{|c| c.downcase.to_sym};end

    def self.logtypes; [:stderr,:stdout,:syslog];end

    def self.log
      self.setlogger(:stderr) if @@logobj.nil?
      return @@logobj
    end

    def self.level=(level)
      log.level=Logger::Severity.const_get(level.to_sym.upcase)
    end

    def self.level
      Logger::Severity.constants.each do |name|
        return name.downcase.to_sym if log.level.eql?(Logger::Severity.const_get(name))
      end
      raise "error"
    end

    def self.setlogger(logtype)
      current_level_num=@@logobj.nil? ? :warn : @@logobj.level
      case logtype
      when :stderr
        @@logobj = Logger.new(STDERR)
      when :stdout
        @@logobj = Logger.new(STDOUT)
      when :syslog
        require 'syslog/logger'
        @@logobj = Syslog::Logger.new("aslmcli")
      else
        raise "unknown log type: #{logtype}"
      end
      @@logobj.level=current_level_num
    end
  end
end
