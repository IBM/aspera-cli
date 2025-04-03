# frozen_string_literal: true

require 'aspera/api/aoc.rb'
module Aspera
  module Api
    class Alee < Aspera::Rest
      def initialize(entitlement_id, customer_id, api_domain: AoC::SAAS_DOMAIN_PROD, version: 'v1')
        super(
          base_url: "https://api.#{api_domain}/metering/#{version}",
          headers:  {'X-Aspera-Entitlement-Authorization' => Rest.basic_authorization(entitlement_id, customer_id)}
        )
      end
    end
  end
end
