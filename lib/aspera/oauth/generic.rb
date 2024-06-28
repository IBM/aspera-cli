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
        super(**base_params)
        @create_params = {
          grant_type: grant_type
        }
        @create_params[:response_type] = response_type if response_type
        @create_params[:apikey] = apikey if apikey
        @create_params[:receiver_client_ids] = receiver_client_ids if receiver_client_ids
        @identifiers.push(
          @create_params[:grant_type]&.split(':')&.last,
          @create_params[:apikey],
          @create_params[:response_type])
      end

      def create_token
        return create_token_call(optional_scope_client_id.merge(@create_params))
      end
    end
    Factory.instance.register_token_creator(Generic)
  end
end
