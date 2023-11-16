# frozen_string_literal: true

# cspell:ignore blankslate

require 'aspera/rest_error_analyzer'
require 'blankslate'

Aspera::RestErrorAnalyzer.instance.add_simple_handler(name: 'JSON RPC', path: %w[error message], always: true)

module Aspera
  # a very simple JSON RPC client
  class JsonRpcClient < BlankSlate
    JSON_RPC_VERSION = '2.0'
    reveal :instance_variable_get
    reveal :inspect
    reveal :to_s

    def initialize(api, namespace = nil)
      super()
      @api = api
      @namespace = namespace
      @request_id = 0
    end

    def respond_to_missing?(sym, include_private = false)
      true
    end

    def method_missing(method, *args, &block)
      args = args.first if args.size == 1 && args.first.is_a?(Hash)
      data = @api.create('', {
        jsonrpc: JSON_RPC_VERSION,
        method:  "#{@namespace}#{method}",
        params:  args,
        id:      @request_id += 1
      })[:data]
      raise 'response shall be Hash' unless data.is_a?(Hash)
      raise 'bad version in response' unless data['jsonrpc'] == JSON_RPC_VERSION
      raise 'missing id in response' unless data.key?('id')
      raise 'both error and response' if data.key?('error') && data.key?('result')
      raise 'bad error response' unless
        !data.key?('error') ||
          data['error'].is_a?(Hash) &&
            data['error']['code'].is_a?(Integer) &&
            data['error']['message'].is_a?(String)
      return data['result']
    end
  end
end
