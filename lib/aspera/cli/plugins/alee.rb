# frozen_string_literal: true

require 'aspera/api/alee'
require 'aspera/nagios'
require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      class Alee < BasicAuth
        command(:health,     description: 'Check health of ALEE metering server', handler: :handle_health)
        command(:entitlement, description: 'Show entitlement information',         handler: :handle_entitlement)

        def handle_health
          nagios = Nagios.new
          begin
            api = Api::Alee.new(nil, nil, version: 'ping')
            http = api.read(nil, ret: :resp)
            raise "unexpected response: #{http.body}" unless http.body.eql?('pong')
            nagios.add_ok('api', 'answered ok')
          rescue StandardError => e
            nagios.add_critical('api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        def handle_entitlement
          entitlement_id = options.get_option(:username, mandatory: true)
          customer_id = options.get_option(:password, mandatory: true)
          api_metering = Api::Alee.new(entitlement_id, customer_id)
          Result::SingleObject.new(api_metering.read('entitlement'))
        end
      end
    end
  end
end
