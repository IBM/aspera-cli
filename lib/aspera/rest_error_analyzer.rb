# frozen_string_literal: true

require 'aspera/rest_call_error'
require 'aspera/log'
require 'singleton'
require 'net/http'

module Aspera
  # analyze error codes returned by REST calls and raise ruby exception
  class RestErrorAnalyzer
    include Singleton

    attr_accessor :log_file

    # the singleton object is registered with application specific handlers
    def initialize
      # list of handlers
      @error_handlers = []
      @log_file = nil
      add_handler('Type Generic') do |type, context|
        if !context[:response].code.start_with?('2')
          # add generic information
          RestErrorAnalyzer.add_error(context, type, "#{context[:request]['host']} #{context[:response].code} #{context[:response].message}")
        end
      end
    end

    # Use this method to analyze a EST result and raise an exception
    # Analyzes REST call response and raises a RestCallError exception
    # if HTTP result code is not 2XX
    # @param req  [Net::HTTPRequest]
    # @param data [Object]
    # @param http [Net::HTTPResponse]
    def raise_on_error(req, data, http)
      Log.log.debug{"raise_on_error #{req.method} #{req.path} #{http.code}"}
      context = {
        messages: [],
        request:  req,
        response: http,
        data:     data
      }
      # multiple error messages can be found
      # analyze errors from provided handlers
      # note that there can be an error even if code is 2XX
      @error_handlers.each do |handler|
        handler[:block].call(handler[:name], context)
      rescue StandardError => e
        Log.log.error{"ERROR in handler:\n#{e.message}\n#{e.backtrace}"}
      end
      raise RestCallError, context unless context[:messages].empty?
    end

    # Add a new error handler (done at application initialization)
    # @param name  [String] name of error handler (for logs)
    # @param block [Proc]   processing of response: takes two parameters: `name`, `context`
    # name is the one provided here
    # context is built in method raise_on_error
    def add_handler(name, &block)
      @error_handlers.unshift({name: name, block: block})
      nil
    end

    # Add a simple error handler
    # Check that key exists and is string under specified path (hash)
    # Adds other keys as secondary information
    # @param name   [String]  name of error handler (for logs)
    # @param always [Boolean] if true, always add error message, even if response code is 2XX
    # @param path   [Array]   path to error message in response
    def add_simple_handler(name:, always: false, path:)
      path.freeze
      add_handler(name) do |type, context|
        if context[:data].is_a?(Hash) && (!context[:response].code.start_with?('2') || always)
          # Log.log.debug{"simple_handler: #{type} #{path} #{path.last}"}
          # dig and find hash containing error message
          error_struct = path.length.eql?(1) ? context[:data] : context[:data].dig(*path[0..-2])
          # Log.log.debug{"found: #{error_struct.class} #{error_struct}"}
          if error_struct.is_a?(Hash) && error_struct[path.last].is_a?(String)
            RestErrorAnalyzer.add_error(context, type, error_struct[path.last])
            error_struct.each do |k, v|
              next if k.eql?(path.last)
              RestErrorAnalyzer.add_error(context, "#{type}(sub)", "#{k}: #{v}") if [String, Integer].include?(v.class)
            end
          end
        end
      end
    end

    class << self
      # Used by handler to add an error description to list of errors
      # For logging and tracing : collect error descriptions (create file to activate)
      # @param context [Hash]   the result context, provided to handler
      # @param type    [String] type of exception, for logging purpose
      # @param message [String] one error message  to add to list
      def add_error(context, type, message)
        context[:messages].push(message)
        Log.log.trace1{"Found error: #{type}: #{message}"}
        log_file = instance.log_file
        # log error for further analysis (file must exist to activate)
        return if log_file.nil? || !File.exist?(log_file)
        File.open(log_file, 'a+') do |f|
          f.write("\n=#{type}=====\n#{context[:request].method} #{context[:request].path}\n#{context[:response].code}\n" \
            "#{JSON.generate(context[:data])}\n#{context[:messages].join("\n")}")
        end
      end
    end
  end
end
