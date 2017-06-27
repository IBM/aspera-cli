require 'logger'
require 'asperalm/colors'

module Asperalm
  class Log
    @@LEVELS=[:debug,:info,:warn,:error,:fatal,:other_struct]
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
      raise "error" if @@logobj.nil?
      return @@logobj
    end

    def self.level=(level)
      log.level=@@LEVELS.index(level)
    end

    def self.level
      @@LEVELS[log.level]
    end

    def self.setlogger(logtype)
      current_level_num=@@logobj.nil? ? :warn : @@logobj.level
      case logtype
      when :stdout
        @@logobj = Logger.new(STDOUT)
      when :syslog
        require 'syslog/logger'
        @@logobj = Logger::Syslog.new("as_cli")
      else
        raise "unknown log type: #{logtype}"
      end
      @@logobj.level=current_level_num
    end
  end
end
