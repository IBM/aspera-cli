# frozen_string_literal: true

# cspell:ignore jsonrpc

require 'aspera/json_rpc/version'
require 'json'

module Aspera
  module JsonRpc
    # JSON-RPC 2.0 server over stdio (Model Context Protocol / MCP transport).
    #
    # Use #register to declare method handlers as blocks.
    #
    # Example:
    #   server = JsonRpc::Server.new
    #   server.register('ping') { |_params, _id| {} }
    #   server.run
    class Server
      # @param input  [IO] readable stream (default $stdin)
      # @param output [IO] writable stream (default $stdout)
      def initialize(input: $stdin, output: $stdout)
        @input    = input
        @output   = output
        @handlers = {}
      end

      # Register a handler block for a named method.
      # @param method_name [String] JSON-RPC method name
      # @yieldparam params [Hash, Array] parsed params from the request
      # @yieldparam id     [Integer, String, nil] request id
      # @yieldreturn [Object] value to send back as the JSON-RPC result
      def register(method_name, &block)
        @handlers[method_name] = block
      end

      # Start the server read loop — blocks until EOF on input.
      def run
        loop do
          line = @input.gets
          break if line.nil? # EOF — client disconnected
          line = line.strip
          next if line.empty?
          handle_raw(line)
        end
      end

      private

      # Parse and dispatch one raw JSON line
      def handle_raw(line)
        request  = JSON.parse(line)
        response = dispatch(request)
        send_message(response) unless response.nil?
      rescue JSON::ParserError => e
        send_message(error_response(nil, -32_700, "Parse error: #{e.message}"))
      rescue => e
        id = defined?(request) && request.is_a?(Hash) ? request['id'] : nil
        send_message(error_response(id, -32_603, "Internal error: #{e.message}"))
      end

      # Route a request to a registered handler or return an error
      def dispatch(req)
        method = req['method']
        id     = req['id']
        params = req['params'] || {}

        # Notifications (no id field) — dispatch but never reply
        notification = !req.key?('id')

        handler = @handlers[method]
        if handler.nil?
          return nil if notification
          return error_response(id, -32_601, "Method not found: #{method}")
        end

        begin
          result = handler.call(params, id)
        rescue => e
          return nil if notification
          return error_response(id, -32_603, e.message)
        end

        return nil if notification
        success_response(id, result)
      end

      def success_response(id, result)
        {jsonrpc: VERSION, id: id, result: result}
      end

      def error_response(id, code, message)
        {jsonrpc: VERSION, id: id, error: {code: code, message: message}}
      end

      def send_message(msg)
        @output.puts(JSON.generate(msg))
        @output.flush
      end
    end
  end
end
