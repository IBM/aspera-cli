# frozen_string_literal: true

require 'aspera/rest/error_analyzer'
require 'aspera/log'

module Aspera
  module Rest
    # REST error handlers for various Aspera REST APIs
    class AsperaErrors
      class << self
        # handlers should probably be defined by plugins for modularity
        def register_handlers
          Log.log.debug('registering Aspera REST error handlers')
          # Faspex 4: both user_message and internal_message, and code 200
          # example: missing meta data on package creation
          ErrorAnalyzer.instance.add_simple_handler(name: 'Type 1: error:user_message', path: %w[error user_message], always: true)
          ErrorAnalyzer.instance.add_simple_handler(name: 'Type 2: error:description', path: %w[error description])
          ErrorAnalyzer.instance.add_simple_handler(name: 'Type 3: error:internal_message', path: %w[error internal_message])
          ErrorAnalyzer.instance.add_simple_handler(name: 'Type 5', path: ['error_description'])
          ErrorAnalyzer.instance.add_simple_handler(name: 'Type 6', path: ['message'])
          ErrorAnalyzer.instance.add_simple_handler(name: 'Type 6', path: ['failure'], always: true)
          # AoC Automation
          ErrorAnalyzer.instance.add_simple_handler(name: 'AoC Automation', path: ['error'])
          ErrorAnalyzer.instance.add_handler('Type 7: errors[]') do |type, context|
            next unless context[:data].is_a?(Hash) && context[:data]['errors'].is_a?(Hash)
            # special for Shares: false positive ? (update global transfer_settings)
            next if context[:data].key?('min_connect_version')
            context[:data]['errors'].each do |k, v|
              ErrorAnalyzer.add_error(context, type, "#{k}: #{v}")
            end
          end
          # call to upload_setup and download_setup of node api
          ErrorAnalyzer.instance.add_handler('T8:node: *_setup') do |type, context|
            next unless context[:data].is_a?(Hash)
            d_t_s = context[:data]['transfer_specs']
            next unless d_t_s.is_a?(Array)
            d_t_s.each do |res|
              r_err = res.dig(*%w[transfer_spec error]) || res['error']
              next unless r_err.is_a?(Hash)
              ErrorAnalyzer.add_error(context, type, r_err.values.join(': '))
            end
          end
          ErrorAnalyzer.instance.add_simple_handler(name: 'T9:IBM cloud IAM', path: ['errorMessage'])
          ErrorAnalyzer.instance.add_simple_handler(name: 'T10:faspex v4', path: ['user_message'])
          ErrorAnalyzer.instance.add_handler('Orchestrator') do |type, context|
            next if context[:response].code.start_with?('2')
            data = context[:data]
            next unless data.is_a?(Hash)
            work_order = data['work_order']
            next unless work_order.is_a?(Hash)
            ErrorAnalyzer.add_error(context, type, work_order['statusDetails'])
            data['missing_parameters']&.each do |param|
              ErrorAnalyzer.add_error(context, type, "missing parameter: #{param}")
            end
          end
        end
      end
    end
  end
end
