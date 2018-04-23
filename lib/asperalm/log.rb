require 'asperalm/colors'
require 'logger'
require 'pp'

module Asperalm
  class Log
    @@logobj=nil
    # levels are :debug,:info,:warn,:error,fatal,:unknown
    def self.levels; Logger::Severity.constants.map{|c| c.downcase.to_sym};end

    def self.logtypes; [:stderr,:stdout,:syslog];end

    def self.log
      self.logger_type=(:stderr) if @@logobj.nil?
      return @@logobj
    end
    
    def self.dump(name,object)
      log.debug("#{name}=\n#{PP.pp(object,'')}")
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

    def self.logger_type; @@logger_type; end

    def self.logger_type=(logtype)
      current_severity_integer=@@logobj.nil? ? Logger::Severity::WARN : @@logobj.level
      case logtype
      when :stderr
        @@logobj = Logger.new(STDERR)
      when :stdout
        @@logobj = Logger.new(STDOUT)
      when :syslog
        require 'syslog/logger'
        @@logobj = Syslog::Logger.new("aslmcli")
      else
        raise "unknown log type: #{logtype.class} #{logtype}"
      end
      @@logger_type=logtype
      @@logobj.level=current_severity_integer
    end
  end
end
