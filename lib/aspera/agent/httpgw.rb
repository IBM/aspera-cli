# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/transfer/spec'
require 'aspera/api/httpgw'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Agent
    class Httpgw < Base
      # start FASP transfer based on transfer spec (hash table)
      # note that it is asynchronous
      # HTTP download only supports file list
      def start_transfer(transfer_spec, token_regenerator: nil)
        raise 'GW URL must be set' if @gw_api.nil?
        Aspera.assert_type(transfer_spec['paths'], Array){'paths'}
        Aspera.assert_type(transfer_spec['token'], String){'only token based transfer is supported in GW'}
        Log.log.debug{Log.dump(:user_spec, transfer_spec)}
        transfer_spec['authentication'] ||= 'token'
        case transfer_spec['direction']
        when Transfer::Spec::DIRECTION_SEND
          @gw_api.upload(transfer_spec)
        when Transfer::Spec::DIRECTION_RECEIVE
          @gw_api.download(transfer_spec)
        else
          raise "unexpected direction: [#{transfer_spec['direction']}]"
        end
      end

      # wait for completion of all jobs started
      # @return list of :success or error message
      def wait_for_transfers_completion
        # well ... transfer was done in "start"
        return [:success]
      end

      # TODO: is that useful?
      # def url=(api_url); end

      private

      def initialize(
        url:,
        api_version: Api::Httpgw::API_V2,
        upload_chunk_size: 64_000,
        synchronous:       false,
        **base_options
      )
        super(**base_options)
        @gw_api = Api::Httpgw.new(
          # remove /v1 from end of user-provided GW url: we need the base url only
          url:               url,
          api_version:       api_version,
          upload_chunk_size: upload_chunk_size,
          synchronous:       synchronous,
          notify_cb:         ->(**event) { notify_progress(**event) }
        )
      end
    end
  end
end
