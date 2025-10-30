# frozen_string_literal: true

require 'aspera/api/alee'
require 'aspera/nagios'
require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      class Alee < BasicAuth
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
            Main.result_object_list(nagios.status_list)
          when :entitlement
            entitlement_id = options.get_option(:username, mandatory: true)
            customer_id = options.get_option(:password, mandatory: true)
            api_metering = Api::Alee.new(entitlement_id, customer_id)
            return Main.result_single_object(api_metering.read('entitlement'))
          end
        end
      end
    end
  end
end
