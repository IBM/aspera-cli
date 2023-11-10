# frozen_string_literal: true

require 'aspera/colors'
require 'aspera/secret_hider'
require 'aspera/environment'
require 'logger'
require 'pp'
require 'json'
require 'singleton'

# extend Ruby logger with trace levels
class Logger
  TRACE_MAX = 2
  # add custom level to logger severity
  module Severity
    1.upto(TRACE_MAX).each { |level| const_set("TRACE#{level}", - level)}
  end
  # quick access to label
  SEVERITY_LABEL = Severity.constants.each_with_object({}) { |name, hash| hash[Severity.const_get(name)] = name}
  def format_severity(severity)
    SEVERITY_LABEL[severity] || 'ANY'
  end

  def self.make_methods(meth)
    level = ::Logger.const_get(meth.upcase)
    meth = meth.downcase
    Kernel.send('lave'.reverse, <<-EOM, nil, __FILE__, __LINE__ + 1)
      def #{meth}(message = nil, &block)
        add(#{level}, message, &block)
      end

      def #{meth}?
        level <= #{level}
      end

      def #{meth}!
        self.level = #{level}
      end
    EOM
  end
  Logger::Severity.constants.each { |severity| make_methods(severity) }
end

module Aspera
  # Singleton object for logging
  class Log
    include Singleton
    # where logs are sent to
    LOG_TYPES = %i[stderr stdout syslog].freeze
    # class methods
    class << self
      # levels are :debug,:info,:warn,:error,fatal,:unknown
      def levels; Logger::Severity.constants.sort{|a, b|Logger::Severity.const_get(a) <=> Logger::Severity.const_get(b)}.map{|c|c.downcase.to_sym}; end

      # get the logger object of singleton
      def log; instance.logger; end

      # dump object in debug mode
      # @param name string or symbol
      # @param format either pp or json format
      def dump(name, object, format=:json)
        log.debug do
          result =
            case format
            when :json
              JSON.pretty_generate(object) rescue PP.pp(object, +'')
            when :ruby
              PP.pp(object, +'')
            else
              raise 'wrong parameter, expect ruby or json'
            end
          "#{name.to_s.green} (#{format})=\n#{result}"
        end
      end

      # Capture the output of $stderr and log it at debug level
      def capture_stderr
        real_stderr = $stderr
        $stderr = StringIO.new
        yield
        log.debug($stderr.string)
      ensure
        $stderr = real_stderr
      end
    end # class

    attr_reader :logger_type, :logger
    attr_writer :program_name

    # set log level of underlying logger given symbol level
    def level=(new_level)
      @logger.level = Logger::Severity.const_get(new_level.to_sym.upcase)
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
    def logger_type=(new_log_type)
      current_severity_integer = @logger.level unless @logger.nil?
      current_severity_integer = ENV.fetch('AS_LOG_LEVEL', nil) if current_severity_integer.nil? && ENV.key?('AS_LOG_LEVEL')
      current_severity_integer = Logger::Severity::WARN if current_severity_integer.nil?
      case new_log_type
      when :stderr
        @logger = Logger.new($stderr)
      when :stdout
        @logger = Logger.new($stdout)
      when :syslog
        require 'syslog/logger'
        # the syslog class automatically creates methods from the severity names
        # we just need to add the mapping
        Syslog::Logger.const_get(:LEVEL_MAP)[Logger::TRACE1] = Syslog::LOG_DEBUG
        @logger = Syslog::Logger.new(@program_name, Syslog::LOG_LOCAL2)
      else
        raise "unknown log type: #{new_log_type.class} #{new_log_type}"
      end
      @logger.level = current_severity_integer
      @logger_type = new_log_type
      # update formatter with password hiding
      @logger.formatter = SecretHider.log_formatter(@logger.formatter)
    end

    private

    def initialize
      @logger = nil
      @program_name = 'aspera'
      # this sets @logger and @logger_type (self needed to call method instead of local var)
      self.logger_type = :stderr
      raise 'error logger shall be defined' if @logger.nil?
    end
  end
end
