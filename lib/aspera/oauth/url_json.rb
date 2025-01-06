# frozen_string_literal: true

require 'aspera/oauth/base'

module Aspera
  module OAuth
    # This class is used to create a token using a JSON body and a URL
    class UrlJson < Base
      # @param url  URL to send the JSON body
      # @param json JSON body to send
      def initialize(
        url:,
        json:,
        **generic_params
      )
        super(**generic_params, cache_ids: [json[:url_token]])
        @body = json
        @query = url
      end

      def create_token
        @api.call(
          operation:   'POST',
          subpath:     @path_token,
          headers:     {'Accept' => 'application/json'},
          query:       @query.merge(scope: @scope), # scope is here because it may change over time (node)
          body:        @body,
          body_type:   :json
        )
      end
    end
    Factory.instance.register_token_creator(UrlJson)
  end
end
