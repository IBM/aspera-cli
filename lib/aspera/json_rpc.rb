# frozen_string_literal: true

# cspell:ignore blankslate jsonrpc

require 'aspera/rest_error_analyzer'
require 'aspera/assert'
require 'aspera/json_rpc/version'
require 'blankslate'

Aspera::RestErrorAnalyzer.instance.add_simple_handler(name: 'JSON RPC', path: %w[error message], always: true)

module Aspera
  module JsonRpc
    # JSON-RPC 2.0 client over an Aspera::Rest HTTP endpoint.
    # Methods are dispatched dynamically via method_missing.
    # Example:
    #   client = JsonRpc::Client.new(Rest.new(base_url: 'http://127.0.0.1:33024'))
    #   client.get_info
    #   client.start_transfer(app_id: '…', transfer_spec: {…})
    class Client < BlankSlate
      reveal :instance_variable_get
      reveal :inspect
      reveal :to_s

      # @param api       [Rest]   Aspera REST object pointing at the JSON-RPC endpoint
      # @param namespace [String, nil] optional method prefix, e.g. "myns."
      def initialize(api, namespace = nil)
        super()
        @api        = api
        @namespace  = namespace
        @request_id = 0
      end

      def respond_to_missing?(_sym, _include_private = false)
        true
      end

      # Dispatch any Ruby method call as a JSON-RPC request
      def method_missing(method, *args, &block)
        args = args.first if args.size == 1 && args.first.is_a?(Hash)
        data = @api.create('', {
          jsonrpc: VERSION,
          method:  "#{@namespace}#{method}",
          params:  args,
          id:      @request_id += 1
        })
        Aspera.assert_type(data, Hash){'response'}
        Aspera.assert(data['jsonrpc'] == VERSION, 'bad version in response')
        Aspera.assert(data.key?('id'), 'missing id in response')
        Aspera.assert(!(data.key?('error') && data.key?('result')), 'both error and response')
        Aspera.assert(
          !data.key?('error') ||
          data['error'].is_a?(Hash) &&
          data['error']['code'].is_a?(Integer) &&
          data['error']['message'].is_a?(String),
          'bad error response'
        )
        return data['result']
      end
    end
  end
end
