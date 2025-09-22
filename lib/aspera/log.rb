# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/colors'
require 'aspera/secret_hider'
require 'logger'
require 'pp'
require 'json'
require 'singleton'
require 'stringio'

# Ignore warnings
old_verbose = $VERBOSE
$VERBOSE = nil

# Extend Ruby logger with trace levels
class Logger
  # Two additionnal trace levels
  TRACE_MAX = 2
  # Add custom level to logger severity, below debug level
  module Severity
    1.upto(TRACE_MAX).each{ |level| const_set(:"TRACE#{level}", - level)}
  end
  # Quick access to label
  SEVERITY_LABEL = Severity.constants.each_with_object({}){ |name, hash| hash[Severity.const_get(name)] = name}
  def format_severity(severity)
    SEVERITY_LABEL[severity] || 'ANY'
  end

  class << self
    # Define methods for a given log level
    def make_methods(str_level)
      int_level = ::Logger.const_get(str_level.upcase)
      method_base = str_level.downcase
      define_method(method_base, ->(message = nil, &block){add(int_level, message, &block)})
      define_method("#{method_base}?", ->{level <= int_level})
      define_method("#{method_base}!", ->{self.level = int_level})
    end
  end
  # Declare methods for all levels
  Logger::Severity.constants.each{ |severity| make_methods(severity)}
end

# Restore warnings
$VERBOSE = old_verbose

module Aspera
  # Singleton object for logging
  class Log
    include Singleton

    # Where logs are sent to
    LOG_TYPES = %i[stderr stdout syslog].freeze
    STANDARD_FORMATTER = Logger::Formatter.new
    DEFAULT_FORMATTER = ->(s, _d, _p, m){"#{s[0]} #{m}\n"}
    # Class methods
    class << self
      # levels are :debug,:info,:warn,:error,fatal,:unknown
      def levels; Logger::Severity.constants.sort{ |a, b| Logger::Severity.const_get(a) <=> Logger::Severity.const_get(b)}.map{ |c| c.downcase.to_sym}; end

      # get the logger object of singleton
      def log; instance.logger; end

      # Dump object (`Hash`) using specified level
      # @param name string or symbol
      # @param object Hash or nil
      # @param level debug level
      # @param block give computed object
      def dump(name, object = nil, level: :debug)
        return unless instance.logger.send(:"#{level}?")
        object = yield if block_given?
        instance.logger.send(level, obj_dump(name, object))
      end

      def obj_dump(name, object)
        dump_text = case instance.dump_format
        when :json
          JSON.pretty_generate(object) rescue PP.pp(object, +'')
        when :ruby
          PP.pp(object, +'')
        else error_unexpected_value(instance.dump_format){'dump format'}
        end
        "#{name.to_s.green} (#{instance.dump_format})=\n#{dump_text}"
      end

      # Capture the output of $stderr and log it at debug level
      def capture_stderr
        real_stderr = $stderr
        $stderr = StringIO.new
        yield if block_given?
        log.debug($stderr.string)
      ensure
        $stderr = real_stderr
      end
    end

    attr_reader :logger_type, :logger
    attr_accessor :dump_format

    def program_name=(value)
      @program_name = value
      self.logger_type = @logger_type
    end

    # Set log level of underlying logger given symbol level
    def level=(new_level)
      @logger.level = Logger::Severity.const_get(new_level.to_sym.upcase)
    end

    def formatter=(formatter)
      # Update formatter with password hiding
      @logger.formatter = SecretHider.instance.log_formatter(formatter)
    end

    def formatter
      @logger.formatter
    end

    # Get symbol of debug level of underlying logger
    def level
      Logger::Severity.constants.each do |name|
        return name.downcase.to_sym if @logger.level.eql?(Logger::Severity.const_get(name))
      end
      Aspera.error_unexpected_value(@logger.level){'log level'}
    end

    # Change underlying logger, but keep log level
    def logger_type=(new_log_type)
      current_severity_integer = @logger.level unless @logger.nil?
      current_severity_integer = ENV.fetch('AS_LOG_LEVEL', nil) if current_severity_integer.nil? && ENV.key?('AS_LOG_LEVEL')
      current_severity_integer = Logger::Severity::WARN if current_severity_integer.nil?
      case new_log_type
      when :stderr
        @logger = Logger.new($stderr, progname: @program_name, formatter: DEFAULT_FORMATTER)
      when :stdout
        @logger = Logger.new($stdout, progname: @program_name, formatter: DEFAULT_FORMATTER)
      when :syslog
        require 'syslog/logger'
        # the syslog class automatically creates methods from the severity names
        # we just need to add the mapping (but syslog lowest is DEBUG)
        1.upto(Logger::TRACE_MAX).each do |level|
          Syslog::Logger.const_get(:LEVEL_MAP)[Logger.const_get("TRACE#{level}")] = Syslog::LOG_DEBUG
        end
        Logger::Severity.constants.each do |severity|
          Syslog::Logger.make_methods(severity.downcase)
        end
        # Use `local2` facility, like other Aspera components
        @logger = Syslog::Logger.new(@program_name, Syslog::LOG_LOCAL2)
      else error_unexpected_value(new_log_type){"log type (#{LOG_TYPES.join(', ')})"}
      end
      @logger.level = current_severity_integer
      @logger_type = new_log_type
      # add secret hider to default logger
      self.formatter = @logger.formatter
    end

    private

    def initialize
      @logger = nil
      @program_name = 'aspera'
      @dump_format = :json
      @logger_type = :stderr
      # This sets @logger and @logger_type (self needed to call method instead of local var)
      self.logger_type = @logger_type
    end
  end
end
