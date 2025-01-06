# frozen_string_literal: true

require 'aspera/oauth/base'

module Aspera
  module OAuth
    # Generic token creator
    class Generic < Base
      def initialize(
        grant_type:,
        response_type: nil,
        apikey: nil,
        receiver_client_ids: nil,
        **base_params
      )
        super(**base_params, cache_ids: [grant_type&.split(':')&.last, apikey, response_type])
        @create_params = {
          grant_type: grant_type
        }
        @create_params[:response_type] = response_type unless response_type.nil?
        @create_params[:apikey] = apikey unless apikey.nil?
        @create_params[:receiver_client_ids] = receiver_client_ids unless receiver_client_ids.nil?
      end

      def create_token
        return create_token_call(optional_scope_client_id.merge(@create_params))
      end
    end
    Factory.instance.register_token_creator(Generic)
  end
end
