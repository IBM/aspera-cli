require 'aspera/colors'
require 'logger'
require 'pp'
require 'json'
require 'singleton'

module Aspera
  # Singleton object for logging
  class Log
    # display string for hidden secrets
    HIDDEN_PASSWORD='***'.freeze
    private_constant :HIDDEN_PASSWORD
    include Singleton
    # class methods
    class << self
      # levels are :debug,:info,:warn,:error,fatal,:unknown
      def levels; Logger::Severity.constants.sort{|a,b|Logger::Severity.const_get(a)<=>Logger::Severity.const_get(b)}.map{|c|c.downcase.to_sym};end

      # where logs are sent to
      def logtypes; [:stderr,:stdout,:syslog];end

      # get the logger object of singleton
      def log; instance.logger;end

      # dump object in debug mode
      # @param name string or symbol
      # @param format either pp or json format
      def dump(name,object,format=:json)
        self.log.debug() do
          result=case format
          when :json
            JSON.pretty_generate(object) rescue PP.pp(object,'')
          when :ruby
            PP.pp(object,'')
          else
            raise "wrong parameter, expect pp or json"
          end
          "#{name.to_s.green} (#{format})=\n#{result}"
        end
      end
    end # class

    attr_reader :logger_type
    attr_reader :logger
    attr_writer :program_name
    attr_accessor :log_passwords

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
      raise "INTERNAL ERROR: unexpected level #{@logger.level}"
    end

    # change underlying logger, but keep log level
    def logger_type=(new_logtype)
      current_severity_integer=@logger.level unless @logger.nil?
      current_severity_integer=ENV['AS_LOG_LEVEL'] if current_severity_integer.nil? and ENV.has_key?('AS_LOG_LEVEL')
      current_severity_integer=Logger::Severity::WARN if current_severity_integer.nil?
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
      original_formatter = @logger.formatter || Logger::Formatter.new
      # update formatter with password hiding, note that @log_passwords may be set AFTER this init is done, so it's done at runtime
      @logger.formatter=lambda do |severity, datetime, progname, msg|
        unless @log_passwords
          msg=msg.gsub(/(["':][^"]*(password|secret|private_key)[^"]*["']?[=>: ]+")([^"]+)(")/){"#{$1}#{HIDDEN_PASSWORD}#{$4}"}
          msg=msg.gsub(/("[^"]*(secret)[^"]*"=>{)([^}]+)(})/){"#{$1}#{HIDDEN_PASSWORD}#{$4}"}
          msg=msg.gsub(/((secrets)={)([^}]+)(})/){"#{$1}#{HIDDEN_PASSWORD}#{$4}"}
          msg=msg.gsub(/--+BEGIN[A-Z ]+KEY--+.+--+END[A-Z ]+KEY--+/m){HIDDEN_PASSWORD}
        end
        original_formatter.call(severity, datetime, progname, msg)
      end
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
