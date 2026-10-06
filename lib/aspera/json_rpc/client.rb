# frozen_string_literal: true

# cspell:ignore jsonrpc

require 'aspera/rest/error_analyzer'
require 'aspera/rest/call_error'
require 'aspera/assert'
require 'aspera/json_rpc/version'

# Error in non-2XX response. Error in 2XX response is raised by the client.
Aspera::Rest::ErrorAnalyzer.instance.add_simple_handler(name: 'JSON RPC', path: %w[error message])

module Aspera
  # JSON-RPC 2.0 over HTTP
  module JsonRpc
    class << self
      # Send a JSON-RPC request
      # @param api    [Rest::Client] Aspera REST object pointing at the JSON-RPC endpoint
      # @param method [String]       JSON-RPC method
      # @param args   [Array]        Arguments of call: a single Hash is sent as named params
      # @param id     [Integer]      Request id
      # @return [Object] `result` of response
      # @raise [Rest::CallError] on JSON-RPC error, or invalid response
      def request(api, method, args, id)
        args = args.first if args.size == 1 && args.first.is_a?(Hash)
        data = api.create('', {
          jsonrpc: VERSION,
          method:  method,
          params:  args,
          id:      id
        })
        Aspera.assert_type(data, Hash, type: Rest::CallError) { 'JSON-RPC response' }
        Aspera.assert(data['jsonrpc'] == VERSION, type: Rest::CallError) { "JSON-RPC: bad version in response: #{data['jsonrpc']}" }
        Aspera.assert(data.key?('result') ^ data.key?('error'), type: Rest::CallError) { 'JSON-RPC: response must have either result or error' }
        # id is null if server could not read it from request
        Aspera.assert(data['id'] == id || (data.key?('error') && data['id'].nil?), type: Rest::CallError) { "JSON-RPC: bad id in response: #{data['id']}, expected #{id}" }
        return data['result'] if data.key?('result')
        error = data['error']
        Aspera.assert(error.is_a?(Hash) && error['code'].is_a?(Integer) && error['message'].is_a?(String), type: Rest::CallError) { "JSON-RPC: bad error in response: #{error}" }
        raise Rest::CallError, "#{error['message']} (code: #{error['code']})"
      end
    end

    # JSON-RPC 2.0 client over an Aspera::Rest::Client HTTP endpoint.
    # Methods are dispatched dynamically via method_missing.
    # Based on BasicObject, so that methods of Object are sent as JSON-RPC requests.
    # Example:
    #   client = JsonRpc::Client.new(Rest::Client.new(base_url: 'http://127.0.0.1:33024'))
    #   client.get_info
    #   client.start_transfer(app_id: '...', transfer_spec: {...})
    class Client < BasicObject
      # @param api       [Rest::Client]   Aspera REST object pointing at the JSON-RPC endpoint
      # @param namespace [String, nil] optional method prefix, e.g. "myns."
      def initialize(api, namespace = nil)
        super()
        @api        = api
        @namespace  = namespace
        @request_id = 0
      end

      # @return [String] Class and URL of JSON-RPC endpoint
      def inspect = "#<#{Client.name} #{@api.base_url}>"

      # @return [String] Same as {#inspect}
      def to_s = inspect

      # Ruby checks it before implicit conversions (`to_ary`, `to_str`, ...): those are not JSON-RPC methods
      # @param _sym             [Symbol]  Method name
      # @param _include_private [Boolean] Also private methods
      # @return [false]
      def respond_to_missing?(_sym, _include_private = false) = false

      # Dispatch any Ruby method call as a JSON-RPC request
      # @param method [Symbol] JSON-RPC method, without namespace
      # @param args   [Array]  Arguments of call: a single Hash is sent as named params, else positional params
      # @return [Object] `result` of response
      # @raise [Rest::CallError] on JSON-RPC error, or invalid response
      def method_missing(method, *args) = JsonRpc.request(@api, "#{@namespace}#{method}", args, @request_id += 1)
    end
  end
end
