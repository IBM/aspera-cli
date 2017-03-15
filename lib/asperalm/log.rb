require 'logger'
require 'asperalm/colors'

module Asperalm
  class Log
    @@LEVELS=[:debug,:info,:warn,:error,:fatal,:unknown]
    @@LOGTYPES= [:syslog,:stdout]
    @@logobj=nil

    def self.levels; @@LEVELS;end

    def self.logtypes; @@LOGTYPES;end

    def self.log
      if @@logobj.nil? then
        @@logobj=Logger.new(STDERR)
        self.level=:warn
        @@logobj.debug("setting defaults")
      end
      return @@logobj
    end

    def self.level=(level)
      log.level=@@LEVELS.index(level)
    end

    def self.level
      @@LEVELS[log.level]
    end

    def self.setlogger(logtype)
      case logtype
      when :stdout
        @@logobj = Logger.new(STDOUT)
      when :syslog
        require 'syslog/logger'
        @@logobj = Logger::Syslog.new("as_cli")
      else
        raise "unknown log type: #{logtype}"
      end
    end
  end
end
