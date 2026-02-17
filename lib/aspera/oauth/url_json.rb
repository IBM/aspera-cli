# frozen_string_literal: true

require 'aspera/oauth/base'

module Aspera
  module OAuth
    # This class is used to create a token using a JSON body and a URL
    class UrlJson < Base
      # @param url  [Hash] Query parameters to send
      # @param json [Hash] Body parameters to send as JSON
      # @param generic_params [Hash] Generic parameters for OAuth::Base
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
        api.call(
          operation:    'POST',
          subpath:      path_token,
          query:        @query.merge(scope: params[:scope]), # scope is here because it may change over time (node)
          content_type: Mime::JSON,
          body:         @body,
          headers:      {'Accept' => Mime::JSON},
          ret:          :resp
        )
      end
    end
    Factory.instance.register_token_creator(UrlJson)
  end
end
