# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../assert'
require_relative './api'
require_relative '../../nagios'
require_relative '../../cli/plugins/basic_auth'

module Aspera
  module Plugins
    module Alee
      class Commands < Cli::Plugins::BasicAuth
        application_name 'Aspera License Entitlement Engine'
        command :health, description: 'Check ALEE metering server health'
        command :entitlement, description: 'Show entitlement information'

        def action_health(**)
          nagios = Nagios.new
          begin
            api = Api.new(nil, nil, version: 'ping')
            http = api.read(nil, ret: :resp)
            Aspera.assert(http.body.eql?('pong')) { "unexpected response: #{http.body}" }
            nagios.add_ok('api', 'answered ok')
          rescue StandardError => e
            nagios.add_critical('api', e.to_s)
          end
          Cli::Result::ObjectList.new(nagios.status_list)
        end

        def action_entitlement(**)
          Cli::Result::SingleObject.new(Api.new(
            options.get_option(:username, mandatory: true),
            options.get_option(:password, mandatory: true)
          ).read('entitlement'))
        end
      end
    end
  end
end
