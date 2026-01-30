# frozen_string_literal: true

require 'aspera/rest_call_error'
require 'aspera/log'
require 'singleton'

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
      add_handler('Type Generic') do |type, call_context|
        if !call_context[:response].code.start_with?('2')
          # add generic information
          RestErrorAnalyzer.add_error(call_context, type, "#{call_context[:request]['host']} #{call_context[:response].code} #{call_context[:response].message}")
        end
      end
    end

    # Use this method to analyze a EST result and raise an exception
    # Analyzes REST call response and raises a RestCallError exception
    # if HTTP result code is not 2XX
    def raise_on_error(req, data, http)
      Log.log.debug{"raise_on_error #{req.method} #{req.path} #{http.code}"}
      call_context = {
        messages: [],
        request:  req,
        response: http,
        data:     data
      }
      # multiple error messages can be found
      # analyze errors from provided handlers
      # note that there can be an error even if code is 2XX
      @error_handlers.each do |handler|
        begin # rubocop:disable Style/RedundantBegin
          # Log.log.debug{"test exception: #{handler[:name]}"}
          handler[:block].call(handler[:name], call_context)
        rescue StandardError => e
          Log.log.error{"ERROR in handler:\n#{e.message}\n#{e.backtrace}"}
        end
      end
      raise RestCallError.new(call_context) unless call_context[:messages].empty?
    end

    # add a new error handler (done at application initialization)
    # @param name : name of error handler (for logs)
    # @param block : processing of response: takes two parameters: name, call_context
    # name is the one provided here
    # call_context is built in method raise_on_error
    def add_handler(name, &block)
      @error_handlers.unshift({name: name, block: block})
    end

    # add a simple error handler
    # check that key exists and is string under specified path (hash)
    # adds other keys as secondary information
    # @param name [String] name of error handler (for logs)
    # @param always [boolean] if true, always add error message, even if response code is 2XX
    # @param path [Array] path to error message in response
    def add_simple_handler(name:, always: false, path:)
      path.freeze
      add_handler(name) do |type, call_context|
        if call_context[:data].is_a?(Hash) && (!call_context[:response].code.start_with?('2') || always)
          # Log.log.debug{"simple_handler: #{type} #{path} #{path.last}"}
          # dig and find hash containing error message
          error_struct = path.length.eql?(1) ? call_context[:data] : call_context[:data].dig(*path[0..-2])
          # Log.log.debug{"found: #{error_struct.class} #{error_struct}"}
          if error_struct.is_a?(Hash) && error_struct[path.last].is_a?(String)
            RestErrorAnalyzer.add_error(call_context, type, error_struct[path.last])
            error_struct.each do |k, v|
              next if k.eql?(path.last)
              RestErrorAnalyzer.add_error(call_context, "#{type}(sub)", "#{k}: #{v}") if [String, Integer].include?(v.class)
            end
          end
        end
      end
    end

    class << self
      # used by handler to add an error description to list of errors
      # for logging and tracing : collect error descriptions (create file to activate)
      # @param call_context a Hash containing the result call_context, provided to handler
      # @param type a string describing type of exception, for logging purpose
      # @param msg one error message  to add to list
      def add_error(call_context, type, msg)
        call_context[:messages].push(msg)
        Log.log.trace1{"Found error: #{type}: #{msg}"}
        log_file = instance.log_file
        # log error for further analysis (file must exist to activate)
        return if log_file.nil? || !File.exist?(log_file)
        File.open(log_file, 'a+') do |f|
          f.write("\n=#{type}=====\n#{call_context[:request].method} #{call_context[:request].path}\n#{call_context[:response].code}\n" \
            "#{JSON.generate(call_context[:data])}\n#{call_context[:messages].join("\n")}")
        end
      end
    end
  end
end
