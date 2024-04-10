# frozen_string_literal: true

require 'aspera/oauth/base'

module Aspera
  module OAuth
    class UrlJson < Base
      def initialize(
        json:,
        url:,
        **generic_params
      )
        super(**generic_params)
        @json_params = json
        @url_params = url
        @identifiers.push(@json_params[:url_token])
      end

      def create_token
        @api.call(
          operation:   'POST',
          subpath:     @path_token,
          headers:     {'Accept' => 'application/json'},
          json_params: @json_params,
          url_params:  @url_params.merge(scope: @scope) # scope is here because it may change over time (node)
        )
      end
    end
    Factory.instance.register_token_creator(UrlJson)
  end
end
