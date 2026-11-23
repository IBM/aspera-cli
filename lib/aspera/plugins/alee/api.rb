# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../rest'

module Aspera
  module Plugins
    module Alee
      # Aspera License Entitlement Engine API client
      class Api < Rest::Client
        # Same IBM Aspera SaaS domain as AoC
        SAAS_DOMAIN_PROD = 'ibmaspera.com'

        def initialize(entitlement_id, customer_id, api_domain: SAAS_DOMAIN_PROD, version: 'v1')
          super(
            base_url: "https://api.#{api_domain}/metering/#{version}",
            headers:  {'X-Aspera-Entitlement-Authorization' => Rest.basic_authorization(entitlement_id, customer_id)}
          )
        end
      end
    end
  end
end
