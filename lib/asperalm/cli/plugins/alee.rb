require 'asperalm/rest'
require 'asperalm/on_cloud'

module Asperalm
  module Cli
    module Plugins
      class Alee < BasicAuthPlugin

        ACTIONS=[ :entitlement ]

        def execute_action
          command=self.options.get_next_command(ACTIONS)
          case command
          when :entitlement
            entitlement_id = self.options.get_option(:username,:mandatory),
            customer_id = self.options.get_option(:password,:mandatory)
            api_metering=OnCloud.metering_api(entitlement_id,customer_id)
            return {:type=>:single_object, :data=>api_metering.read('entitlement')[:data]}
          end
        end
      end # Aspera
    end # Plugins
  end # Cli
end # Asperalm
