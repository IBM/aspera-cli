# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/api/alee'
require 'aspera/nagios'
require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      class Alee < BasicAuth
        application_name 'Aspera License Entitlement Engine'
        command(:health, description: 'Check health of ALEE metering server', action: lambda do
          nagios = Nagios.new
          begin
            api = Api::Alee.new(nil, nil, version: 'ping')
            http = api.read(nil, ret: :resp)
            Aspera.assert(http.body.eql?('pong')){"unexpected response: #{http.body}"}
            nagios.add_ok('api', 'answered ok')
          rescue StandardError => e
            nagios.add_critical('api', e.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end)

        command(:entitlement, description: 'Show entitlement information', action: lambda do
          Result::SingleObject.new(Api::Alee.new(
            options.get_option(:username, mandatory: true),
            options.get_option(:password, mandatory: true)
          ).read('entitlement'))
        end)
      end
    end
  end
end
