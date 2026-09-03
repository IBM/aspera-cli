# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/transfer/spec'
require 'aspera/api/httpgw'
require 'aspera/log'
require 'aspera/assert'
require 'securerandom'

module Aspera
  module Agent
    class Httpgw < Base
      class << self
        # Re-query the status of an httpgw transfer that was started in-process.
        # Only works if the same Ruby process is still alive (e.g. MCP mode).
        # agent_params must contain '_agent_ref' pointing to the live Httpgw instance.
        # @param transfer_id  [String] job_id returned by last_job_id
        # @param agent_params [Hash]   '_agent_ref' is the live agent instance
        # @return [Hash] status hash with at least 'status' key
        def transfer_status(transfer_id, agent_params)
          agent = agent_params['_agent_ref']
          return {'status' => 'unknown', 'note' => 'httpgw agent not available (different process?)'} if agent.nil?
          return {'status' => 'unknown', 'note' => 'no transfer started'} if agent.instance_variable_get(:@transfer_thread).nil?
          if agent.instance_variable_get(:@transfer_thread).alive?
            {'status' => 'running'}
          elsif (err = agent.instance_variable_get(:@transfer_error))
            {'status' => 'failed', 'error' => err.message}
          else
            {'status' => 'completed'}
          end
        end
      end

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
          notify_cb:         ->(*pa, **ka){notify_progress(*pa, **ka)}
        )
        @last_job_id    = nil
        @transfer_thread = nil
        @transfer_error  = nil
      end

      # Start FASP transfer based on transfer spec (hash table).
      # Non-blocking: the actual upload/download runs in a dedicated thread.
      # HTTP download only supports file list.
      # :reek:UnusedParameters token_regenerator
      def start_transfer(transfer_spec, token_regenerator: nil)
        Aspera.assert(!@gw_api.nil?, 'GW URL must be set')
        Aspera.assert_type(transfer_spec['paths'], Array){'paths'}
        Aspera.assert_type(transfer_spec['token'], String){'only token based transfer is supported in GW'}
        Log.dump(:user_spec, transfer_spec)
        transfer_spec['authentication'] ||= 'token'
        @last_job_id    = SecureRandom.uuid
        @transfer_error  = nil
        @transfer_thread = Thread.new{run_transfer(transfer_spec)}
        @last_job_id
      end

      # Wait for the transfer thread to complete.
      # @return [Array] list of :success or error
      def wait_for_transfers_completion
        @transfer_thread&.join
        return [@transfer_error || :success]
      end

      # @return [String, nil] job_id of the last submitted transfer
      def last_job_id
        @last_job_id
      end

      private

      # Execute the actual transfer (runs inside the transfer thread).
      def run_transfer(transfer_spec)
        case transfer_spec['direction']
        when Transfer::Spec::DIRECTION_SEND
          @gw_api.upload(transfer_spec)
        when Transfer::Spec::DIRECTION_RECEIVE
          @gw_api.download(transfer_spec)
        else Aspera.error_unexpected_value(transfer_spec['direction']){'direction'}
        end
      rescue => e
        @transfer_error = e
        Log.log.error{"httpgw transfer thread error: #{e}"}
      end
    end
  end
end
