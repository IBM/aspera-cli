# frozen_string_literal: true

require 'aspera/rest_error_analyzer'
require 'aspera/log'

module Aspera
  # REST error handlers for various Aspera REST APIs
  class RestErrorsAspera
    class << self
      # handlers should probably be defined by plugins for modularity
      def register_handlers
        Log.log.debug('registering Aspera REST error handlers')
        # Faspex 4: both user_message and internal_message, and code 200
        # example: missing meta data on package creation
        RestErrorAnalyzer.instance.add_simple_handler(name: 'Type 1: error:user_message', path: %w[error user_message], always: true)
        RestErrorAnalyzer.instance.add_simple_handler(name: 'Type 2: error:description', path: %w[error description])
        RestErrorAnalyzer.instance.add_simple_handler(name: 'Type 3: error:internal_message', path: %w[error internal_message])
        RestErrorAnalyzer.instance.add_simple_handler(name: 'Type 5', path: ['error_description'])
        RestErrorAnalyzer.instance.add_simple_handler(name: 'Type 6', path: ['message'])
        # AoC Automation
        RestErrorAnalyzer.instance.add_simple_handler(name: 'AoC Automation', path: ['error'])
        RestErrorAnalyzer.instance.add_handler('Type 7: errors[]') do |type, call_context|
          next unless call_context[:data].is_a?(Hash) && call_context[:data]['errors'].is_a?(Hash)
          # special for Shares: false positive ? (update global transfer_settings)
          next if call_context[:data].key?('min_connect_version')
          call_context[:data]['errors'].each do |k, v|
            RestErrorAnalyzer.add_error(call_context, type, "#{k}: #{v}")
          end
        end
        # call to upload_setup and download_setup of node api
        RestErrorAnalyzer.instance.add_handler('T8:node: *_setup') do |type, call_context|
          next unless call_context[:data].is_a?(Hash)
          d_t_s = call_context[:data]['transfer_specs']
          next unless d_t_s.is_a?(Array)
          d_t_s.each do |res|
            r_err = res.dig(*%w[transfer_spec error]) || res['error']
            next unless r_err.is_a?(Hash)
            RestErrorAnalyzer.add_error(call_context, type, "#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}")
          end
        end
        RestErrorAnalyzer.instance.add_simple_handler(name: 'T9:IBM cloud IAM', path: ['errorMessage'])
        RestErrorAnalyzer.instance.add_simple_handler(name: 'T10:faspex v4', path: ['user_message'])
        RestErrorAnalyzer.instance.add_handler('bss graphql') do |type, call_context|
          next unless call_context[:data].is_a?(Hash)
          d_t_s = call_context[:data]['errors']
          next unless d_t_s.is_a?(Array)
          d_t_s.each do |res|
            r_err = res['message']
            next unless r_err.is_a?(String)
            RestErrorAnalyzer.add_error(call_context, type, r_err)
          end
        end
        RestErrorAnalyzer.instance.add_handler('Orchestrator') do |type, call_context|
          next if call_context[:response].code.start_with?('2')
          data = call_context[:data]
          next unless data.is_a?(Hash)
          work_order = data['work_order']
          next unless work_order.is_a?(Hash)
          RestErrorAnalyzer.add_error(call_context, type, work_order['statusDetails'])
          data['missing_parameters']&.each do |param|
            RestErrorAnalyzer.add_error(call_context, type, "missing parameter: #{param}")
          end
        end
      end # register_handlers
    end
  end
end
