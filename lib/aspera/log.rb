require 'aspera/colors'
require 'logger'
require 'pp'
require 'json'
require 'singleton'

module Aspera
  # Singleton object for logging
  class Log

    public
    include Singleton

    attr_reader :logger
    attr_reader :logger_type
    # levels are :debug,:info,:warn,:error,fatal,:unknown
    def self.levels; Logger::Severity.constants.sort{|a,b|Logger::Severity.const_get(a)<=>Logger::Severity.const_get(b)}.map{|c|c.downcase.to_sym};end

    # where logs are sent to
    def self.logtypes; [:stderr,:stdout,:syslog];end

    # get the logger object of singleton
    def self.log; self.instance.logger; end

    # dump object in debug mode
    # @param name string or symbol
    # @param format either pp or json format
    def self.dump(name,object,format=:json)
      result=case format
      when :ruby;PP.pp(object,'')
      when :json;JSON.pretty_generate(object) rescue PP.pp(object,'')
      else raise "wrong parameter, expect pp or json"
      end
      self.log.debug("#{name.to_s.green} (#{format})=\n#{result}")
    end

    # set log level of underlying logger given symbol level
    def level=(new_level)
      @logger.level=Logger::Severity.const_get(new_level.to_sym.upcase)
    end

    # get symbol of debug level of underlying logger
    def level
      Logger::Severity.constants.each do |name|
        return name.downcase.to_sym if @logger.level.eql?(Logger::Severity.const_get(name))
      end
      raise "error"
    end

    # change underlying logger, but keep log level
    def logger_type=(new_logtype)
      current_severity_integer=if @logger.nil?
        if ENV.has_key?('AS_LOG_LEVEL')
          ENV['AS_LOG_LEVEL']
        else
          Logger::Severity::WARN
        end
      else
        @logger.level
      end
      case new_logtype
      when :stderr
        @logger = Logger.new(STDERR)
      when :stdout
        @logger = Logger.new(STDOUT)
      when :syslog
        require 'syslog/logger'
        @logger = Syslog::Logger.new(@program_name)
      else
        raise "unknown log type: #{new_logtype.class} #{new_logtype}"
      end
      @logger.level=current_severity_integer
      @logger_type=new_logtype
    end

    attr_writer :program_name

    private

    def initialize
      @logger=nil
      @program_name='aspera'
      # this sets @logger and @logger_type
      self.logger_type=:stderr
    end

  end
end
