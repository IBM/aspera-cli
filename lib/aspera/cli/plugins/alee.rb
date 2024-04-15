# frozen_string_literal: true

require 'aspera/api/aoc'

module Aspera
  module Cli
    module Plugins
      class Alee < Cli::BasicAuthPlugin
        ACTIONS = %i[entitlement].freeze

        def execute_action
          command = options.get_next_command(ACTIONS)
          case command
          when :entitlement
            entitlement_id = options.get_option(:username, mandatory: true)
            customer_id = options.get_option(:password, mandatory: true)
            api_metering = Api::AoC.metering_api(entitlement_id, customer_id)
            return {type: :single_object, data: api_metering.read('entitlement')[:data]}
          end
        end
      end
    end
  end
end
