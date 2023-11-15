# frozen_string_literal: true

# cspell:ignore blankslate

require 'aspera/rest_error_analyzer'
require 'aspera/log'
require 'blankslate'
require 'json'
require 'aspera/rest'

RestErrorAnalyzer.instance.add_simple_handler(name: 'JSON RPC', path: %w[error message], always: true)

class JsonRpcClient < BlankSlate
  JSON_RPC_VERSION = '2.0'
  reveal :instance_variable_get
  reveal :inspect
  reveal :to_s

  def initialize(api, namespace = nil)
    super
    @api = api
    @namespace = namespace
  end

  def method_missing(method, *args, &block)
    args = args.first if args.size == 1 && args.first.is_a?(Hash)
    data = @api.create('', {
      'jsonrpc' => JSON_RPC_VERSION,
      'method'  => "#{@namespace}#{method}",
      'params'  => args,
      'id'      => rand(10**12)
    })[:data]

    raise 'response shall be Hash' unless data.is_a?(Hash)
    raise 'bad version in response' unless data['jsonrpc'] == JSON_RPC_VERSION
    raise 'missing id in response' unless data.key?('id')
    raise 'both error and response' if data.key?('error') && data.key?('result')

    if data.key?('error')
      if !data['error'].is_a?(Hash) || !data['error'].key?('code') || !data['error'].key?('message')
        raise 'bad response'
      end

      if !data['error']['code'].is_a?(Integer) || !data['error']['message'].is_a?(String)
        raise 'bad response'
      end
    end

    return data['result']
  end

  def respond_to_missing?(sym, include_private = false)
    true
  end
end

log_file = '/Users/laurent/Library/Logs/IBM Aspera/ibm-aspera-desktop.log'



essai = JsonRpcClient.new(Rest.new('https://api.asperafiles.com/api/v1/jsonrpc', 'asperafiles'))