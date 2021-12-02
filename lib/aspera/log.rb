require 'aspera/colors'
require 'logger'
require 'pp'
require 'json'
require 'singleton'

module Aspera
  # Singleton object for logging
  class Log

    include Singleton
    # class methods
    class << self
      # levels are :debug,:info,:warn,:error,fatal,:unknown
      def levels; Logger::Severity.constants.sort{|a,b|Logger::Severity.const_get(a)<=>Logger::Severity.const_get(b)}.map{|c|c.downcase.to_sym};end

      # where logs are sent to
      def logtypes; [:stderr,:stdout,:syslog];end

      # get the logger object of singleton
      alias_method :log, :instance
      #def log; instance;end

      # dump object in debug mode
      # @param name string or symbol
      # @param format either pp or json format
      def dump(name,object,format=:json)
        result=case format
        when :ruby;PP.pp(object,'')
        when :json;JSON.pretty_generate(object) rescue PP.pp(object,'')
        else raise "wrong parameter, expect pp or json"
        end
        self.log.debug("#{name.to_s.green} (#{format})=\n#{result}")
      end
    end

    attr_reader :logger_type
    attr_writer :program_name
    attr_accessor :log_passwords

    # define methods in single that are the same as underlying logger
    Logger::Severity.constants.each do |lev_sym|
      lev_meth=lev_sym.to_s.downcase.to_sym
      define_method(lev_meth) do |message|
        unless @log_passwords
          message=message.gsub(/("[^"]*(password|secret|private_key)[^"]*"=>")([^"]+)(")/){"#{$1}***#{$4}"}
          message=message.gsub(/("[^"]*(secret)[^"]*"=>{)([^}]+)(})/){"#{$1}***#{$4}"}
          message=message.gsub(/((secrets)={)([^}]+)(})/){"#{$1}***#{$4}"}
        end
        @logger.send(lev_meth,message)
      end
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
      # should not happen
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

    private

    def initialize
      @logger=nil
      @program_name='aspera'
      @log_passwords=false
      # this sets @logger and @logger_type (self needed to call method instead of local var)
      self.logger_type=:stderr
      raise "error logger shall be defined" if @logger.nil?
    end

  end
end
