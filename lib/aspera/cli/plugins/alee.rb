# frozen_string_literal: true

require 'aspera/api/aoc'
require 'aspera/nagios'

module Aspera
  module Cli
    module Plugins
      class Alee < Cli::BasicAuthPlugin
        ACTIONS = %i[health entitlement].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :health
            nagios = Nagios.new
            begin
              api = Api::Alee.new(nil, nil, version: 'ping')
              result = api.call(operation: 'GET')
              raise "unexpected response: #{result[:http].body}" unless result[:http].body.eql?('pong')
              nagios.add_ok('api', 'answered ok')
            rescue StandardError => e
              nagios.add_critical('api', e.to_s)
            end
            return nagios.result
          when :entitlement
            entitlement_id = options.get_option(:username, mandatory: true)
            customer_id = options.get_option(:password, mandatory: true)
            api_metering = Api::Alee.new(entitlement_id, customer_id)
            return {type: :single_object, data: api_metering.read('entitlement')}
          end
        end
      end
    end
  end
end
