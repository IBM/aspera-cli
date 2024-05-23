# frozen_string_literal: true

require 'aspera/oauth/base'

module Aspera
  module OAuth
    class UrlJson < Base
      def initialize(
        url:,
        json:,
        **generic_params
      )
        super(**generic_params)
        @body = json
        @query = url
        @identifiers.push(@body[:url_token])
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
