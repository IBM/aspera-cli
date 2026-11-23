# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative '../transfer/error'
require_relative '../../transferd_services_pb'
require 'json'
require 'time'

module Aspera
  module Api
    # Client of a running Transfer Daemon (`transferd`): gRPC calls, no CLI.
    # Requires the optional gem `grpc`.
    class Transferd
      # Sends the API key of the daemon (`authentication` of its configuration) in the metadata `api_key` of each call
      class ApiKeyInterceptor < GRPC::ClientInterceptor
        # @param api_key [String] API key
        def initialize(api_key)
          super()
          @api_key = api_key
        end

        %i[request_response client_streamer server_streamer bidi_streamer].each do |rpc_type|
          define_method(rpc_type) do |metadata: nil, **_rest, &block|
            metadata['api_key'] = @api_key
            block.call
          end
        end
      end

      # Default timeout in seconds of the calls of `transfer_status` and `transfer_cancel` (`agent_params['timeout']`)
      CALL_TIMEOUT_SEC = 10
      # Status of the daemon → status of an asynchronous transfer (as other agents): other statuses are `running`
      ASYNC_STATUS = {
        COMPLETED:      'completed',
        FAILED:         'failed',
        CANCELED:       'cancelled',
        UNKNOWN_STATUS: 'unknown'
      }.freeze
      # Statuses of the daemon after which a transfer does not change
      FINAL_STATUSES = %i[COMPLETED FAILED CANCELED].freeze
      # Time in the daemon is in microseconds, but some versions give milliseconds: values below this are milliseconds
      MIN_USEC_EPOCH = 10**14

      private_constant :ASYNC_STATUS, :MIN_USEC_EPOCH

      class << self
        # Client of a daemon
        # @param url     [String]      Endpoint of the daemon, e.g. `127.0.0.1:55002`
        # @param api_key [String, nil] API key, if the daemon has `authentication` enabled
        # @param ca_file [String, nil] File with the certificate authority of the daemon (PEM), if the daemon has `tls` enabled
        # @return [Transferd::Api::TransferService::Stub] gRPC client
        def create_client(url, api_key: nil, ca_file: nil)
          credentials = ca_file.nil? ? :this_channel_is_insecure : GRPC::Core::ChannelCredentials.new(File.read(ca_file))
          return ::Transferd::Api::TransferService::Stub.new(url, credentials) if api_key.nil?
          ::Transferd::Api::TransferService::Stub.new(url, credentials, interceptors: [ApiKeyInterceptor.new(api_key)])
        end

        # @param agent_params [Hash] `url`: endpoint of the daemon; optional `api_key`, `ca_file`
        # @return [Transferd::Api::TransferService::Stub] Client of the daemon
        def client(agent_params)
          Aspera.assert(agent_params['url'].is_a?(String) && !agent_params['url'].empty?) { 'agent_params: missing url' }
          create_client(agent_params['url'], api_key: agent_params['api_key'], ca_file: agent_params['ca_file'])
        end

        # Re-query a previously started transfer from a running transferd daemon (unary call `QueryTransfer`).
        # The daemon keeps a transfer for some time after its end (`workers.transfer_max_age` of its configuration): then it is `unknown`.
        # @param transfer_id  [String] Identifier of transfer, given by the daemon (`transfer_id`)
        # @param agent_params [Hash]   `url`: endpoint of the daemon, e.g. `127.0.0.1:55002`; optional `timeout`: seconds, `api_key`, `ca_file`
        # @return [Hash] Normalized status: `status` (`running`, `completed`, `failed`, `cancelled`, or `unknown` if the daemon cannot tell),
        #   `bytes_transferred`, and when known: `state` (status of the daemon), `bytes_written` (by the receiver, with the bytes of a resumed transfer),
        #   `files_completed`, `rate_kbps` (average), `target_rate_kbps`,
        #   `elapsed_sec`, `started_at`, `ended_at`, `error_code`, `error`
        def transfer_status(transfer_id, agent_params)
          response = client(agent_params).query_transfer(::Transferd::Api::TransferInfoRequest.new(transferId: transfer_id), deadline: deadline(agent_params))
          # An unknown transfer is not an exception: status is not set, and error has code 404
          error = response.error&.description.to_s
          return {'status' => 'unknown', 'bytes_transferred' => 0, 'error' => error} if response.status.eql?(:UNKNOWN_STATUS) && !error.empty?
          normalize_status(response)
        rescue GRPC::BadStatus => e
          # Daemon not reachable, or timeout: the transfer may still run
          {'status' => 'unknown', 'bytes_transferred' => 0, 'error' => "#{e.class.name.split('::').last}: #{e.details}"}
        end

        # Information on a running daemon (unary call `GetInfo`)
        # @param agent_params [Hash] `url`: endpoint of the daemon; optional `timeout`: seconds, `api_key`, `ca_file`
        # @return [Hash] Version of the API (`apiVersion`) and information on the instance (`info`)
        # @raise [Transfer::Error] The daemon is not reachable, or gave an error
        def info(agent_params)
          response = client(agent_params).get_info(::Transferd::Api::InstanceInfoRequest.new, deadline: deadline(agent_params))
          error = response.error&.description.to_s
          Aspera.assert(error.empty?, type: Transfer::Error) { error }
          JSON.parse(response.to_h.except(:error).to_json)
        rescue GRPC::BadStatus => e
          raise Transfer::Error, "#{e.class.name.split('::').last}: #{e.details}"
        end

        # Stop a transfer (call `StopTransfer`)
        # @param transfer_id  [String] Identifier of transfer, given by the daemon
        # @param agent_params [Hash]   `url`: endpoint of the daemon; optional `timeout`: seconds, `api_key`, `ca_file`
        # @return [Boolean] `true`: stopped
        # @raise [Transfer::Error] The daemon did not stop it: unknown or terminated transfer
        def transfer_cancel(transfer_id, agent_params)
          response = client(agent_params).stop_transfer(::Transferd::Api::StopTransferRequest.new(transferId: [transfer_id]), deadline: deadline(agent_params))
          result = response.stopResult.find { |item| item.transferId.eql?(transfer_id) }
          Aspera.assert(!result.nil?, type: Transfer::Error) { "transfer id=#{transfer_id}: no result of stop" }
          Aspera.assert(result.stopped, type: Transfer::Error) { result.error&.description || "transfer id=#{transfer_id}: not stopped" }
          true
        end

        # @param response [Transferd::Api::QueryTransferResponse, Transferd::Api::TransferResponse] Response of the daemon
        # @return [Hash] Normalized status, see `transfer_status`
        def normalize_status(response)
          info = response.transferInfo
          result = {
            'status'            => ASYNC_STATUS.fetch(response.status, 'running'),
            'state'             => response.status.to_s.downcase,
            'bytes_transferred' => info&.bytesTransferred.to_i
          }
          return result if info.nil?
          result.merge!(
            'bytes_written'    => info.bytesWritten,
            'files_completed'  => info.filesCompleted,
            'rate_kbps'        => info.averageRateKbps,
            'target_rate_kbps' => info.targetRateKbps,
            'elapsed_sec'      => info.elapsedUsec / 1_000_000.0,
            'started_at'       => epoch_time(info.startTimeUsec),
            'ended_at'         => epoch_time(info.endTimeUsec)
          )
          if FINAL_STATUSES.include?(response.status)
            result['ended_at'] ||= Time.now.utc.iso8601
          else
            result.delete('ended_at')
          end
          error = info.errorDescription.to_s.strip
          error = response.error&.description.to_s if error.empty?
          unless error.empty?
            result['error_code'] = info.errorCode
            result['error'] = error
          end
          result.compact
        end

        private

        # @param agent_params [Hash] Optional `timeout`: seconds
        # @return [Time] Deadline of a call
        def deadline(agent_params)
          Time.now + (agent_params['timeout'] || CALL_TIMEOUT_SEC).to_f
        end

        # @param value [Integer] Time since epoch, in microseconds or milliseconds, 0 if not known
        # @return [String, nil] Time in ISO 8601, `nil` if not known
        def epoch_time(value)
          return if value.nil? || value <= 0
          seconds = value >= MIN_USEC_EPOCH ? value / 1_000_000.0 : value / 1000.0
          Time.at(seconds).utc.iso8601
        end
      end
    end
  end
end
