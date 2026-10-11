# frozen_string_literal: true

require 'aspera/oauth/base'
require 'digest'

module Aspera
  module OAuth
    # Token creator using JSON credentials (e.g., username/password or apikey) sent to a login endpoint
    class JsonCredentials < Base
      # @param json           [Hash] Body parameters to send as JSON (e.g. {username:, password:} or {apikey:})
      # @param generic_params [Hash] Generic parameters for OAuth::Base
      def initialize(
        json:,
        **generic_params
      )
        cache_id = json[:username] || Digest::SHA256.hexdigest(json[:apikey] || json.to_s)[0..23]
        super(**generic_params, cache_ids: [cache_id])
        @body = json
      end

      def create_token
        api.call(
          operation:    'POST',
          subpath:      path_token,
          content_type: Mime::JSON,
          body:         @body,
          headers:      {'Accept' => Mime::JSON},
          ret:          :resp
        )
      end
    end
    Factory.instance.register_token_creator(JsonCredentials)
  end
end
