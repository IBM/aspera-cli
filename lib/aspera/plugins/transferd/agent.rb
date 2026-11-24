# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../agent/base'
require_relative '../../log'
require_relative '../../transfer/error'
require_relative '../../transfer/spec'
require_relative 'api'
require_relative 'client'
require_relative 'product'
require 'json'
require 'uri'

module Aspera
  module Plugins
    module Transferd
      # Transfers with a Transfer Daemon (`transferd`): an external one, or one started here (`Product`).
      # Calls to a running daemon: `Api`.
      class Agent < Aspera::Agent::Base
        # https://github.com/grpc/grpc/blob/master/doc/naming.md
        # https://grpc.io/docs/guides/custom-name-resolution/
        LOCAL_SOCKET_ADDR = '127.0.0.1'
        PORT_SEP = ':'
        # port zero means select a random available high port
        AUTO_LOCAL_TCP_PORT = "#{PORT_SEP}0".freeze

        private_constant :LOCAL_SOCKET_ADDR, :PORT_SEP, :AUTO_LOCAL_TCP_PORT

        class << self
          # @param stub [Transferd::Api::TransferService::Stub] gRPC client of a daemon
          # @return [Client] Calls to this daemon with plain Ruby arguments
          def wrap_client(stub)
            Client.new(stub)
          end

          # @param name [Symbol] see `Client.empty_message`
          # @return [Google::Protobuf::AbstractMessage] empty gRPC message
          def empty_message(name)
            Client.empty_message(name)
          end

          # Re-query a previously started transfer: see `Api.transfer_status`
          # @param transfer_id  [String] Identifier of transfer, given by the daemon (`transfer_id`)
          # @param agent_params [Hash]   `url`: endpoint of the daemon; optional `timeout`: seconds, `api_key`, `ca_file`
          # @return [Hash] Normalized status
          def transfer_status(transfer_id, agent_params)
            Api.transfer_status(transfer_id, agent_params)
          end

          # Stop a transfer: see `Api.transfer_cancel`
          # @param transfer_id  [String] Identifier of transfer, given by the daemon
          # @param agent_params [Hash]   `url`: endpoint of the daemon; optional `timeout`: seconds, `api_key`, `ca_file`
          # @return [Boolean] `true`: stopped
          # @raise [Aspera::Transfer::Error] The daemon did not stop it: unknown or terminated transfer
          def transfer_cancel(transfer_id, agent_params)
            Api.transfer_cancel(transfer_id, agent_params)
          end
        end

        # @param url   [String]  URL of the transfer manager daemon
        # @param start [Boolean] If `false`, expect that an external daemon is already running
        # @param stop  [Boolean] If `false`, do not shutdown daemon on exit
        # @param api_key [String, nil] API key of the daemon: of an external daemon with `authentication` enabled, or of the daemon started here (else a random one)
        # @param ca_file [String, nil] Certificate authority (PEM file) of an external daemon with `tls` enabled
        # @param base  [Hash]    Base class options
        def initialize(
          url:     AUTO_LOCAL_TCP_PORT,
          start:   true,
          stop:    true,
          api_key: nil,
          ca_file: nil,
          **base
        )
          super(**base)
          @transfer_id = nil
          @stop = stop
          is_local_auto_port = url.eql?(AUTO_LOCAL_TCP_PORT)
          Aspera.assert(!(is_local_auto_port && (!@stop || !start)), type: ParameterError) { 'Cannot set options `stop` or `start` to false with port zero' }
          # daemon started here, kept for optional shutdown
          @daemon = nil
          @daemon_endpoint = nil
          daemon_endpoint = url
          Log.dump(:daemon_endpoint, daemon_endpoint)
          # retry loop
          begin
            # no address: local bind
            daemon_endpoint = "#{LOCAL_SOCKET_ADDR}#{daemon_endpoint}" if daemon_endpoint.match?(/^#{PORT_SEP}[0-9]+$/o)
            # Create stub: API key of the daemon (given, or the one of the daemon started here), TLS only for an external daemon
            @transfer_client = Api.create_client(daemon_endpoint, api_key: api_key, ca_file: ca_file)
            # Initiate actual connection
            get_info_response = @transfer_client.get_info(::Transferd::Api::InstanceInfoRequest.new)
            @daemon_endpoint = daemon_endpoint
            Log.log.debug { "Daemon info: #{get_info_response}" }
            Log.log.warn('Attached to existing daemon') unless @daemon || !start || !@stop
            # `shutdown` is registered with `at_exit` only when the daemon is started here:
            # a long-running process (e.g. Orchestrator) that attaches to an external daemon for each transfer would accumulate them
          rescue GRPC::Unavailable => e
            # if transferd is external: do not start it, or other error
            raise if !start || !e.message.include?('failed to connect')
            # we already tried to start a daemon, but it failed
            Aspera.assert(@daemon.nil?) { "Daemon started with PID #{@daemon.pid}, but connection failed to #{daemon_endpoint}" }
            Log.log.warn('no daemon present, starting daemon...')
            # transferd only supports local ip and port
            daemon_uri = URI.parse("ipv4://#{daemon_endpoint}")
            Aspera.assert(!daemon_uri.host.to_s.empty? && !daemon_uri.port.nil?, type: ParameterError) { "Invalid address of daemon: #{daemon_endpoint}, expecting <ADDRESS>:<PORT> or :<PORT>" }
            @daemon = Product.new(address: daemon_uri.host, port: daemon_uri.port, api_key: api_key, stop: @stop)
            # API key of the daemon started here, for next connection attempt
            api_key = @daemon.api_key
            at_exit { shutdown }
            # update port for next connection attempt (if auto high port was requested)
            daemon_endpoint = "#{LOCAL_SOCKET_ADDR}#{PORT_SEP}#{@daemon.port_from_log}" if is_local_auto_port
            # local daemon started, try again
            retry
          end
        end

        # Actual endpoint the daemon is listening on (resolved after connect, e.g. when port 0 was used)
        attr_reader :daemon_endpoint
        # gRPC client of the daemon
        attr_reader :transfer_client

        # @return [Client] Calls to the daemon with plain Ruby arguments
        def client
          @client ||= Client.new(@transfer_client)
        end

        # @return [Hash] `url`: actual endpoint of the daemon, for `transfer_status` and `transfer_cancel` (`transfer_id` is given by the daemon)
        def async_params
          {'url' => @daemon_endpoint}
        end

        # :reek:UnusedParameters token_regenerator
        def start_transfer(transfer_spec, token_regenerator: nil)
          Aspera::Transfer::Spec.fix_transferd_resume_policy(transfer_spec)
          # create a transfer request
          transfer_request = ::Transferd::Api::TransferRequest.new(
            transferType: ::Transferd::Api::TransferType::FILE_REGULAR, # transfer type (file/stream)
            config: ::Transferd::Api::TransferConfig.new, # transfer configuration
            transferSpec: transfer_spec.to_json
          ) # transfer definition
          # send start transfer request to the transfer manager daemon
          start_response = @transfer_client.start_transfer(transfer_request)
          Aspera.assert(!start_response.status.eql?(:FAILED), type: Aspera::Transfer::Error) { start_response.error.description }
          Log.log.debug { "start transfer response #{start_response}" }
          @transfer_id = start_response.transferId
          Log.log.debug { "transfer started with id #{@transfer_id}" }
        end

        def wait_for_transfers_completion
          # set to true when we know the total size of the transfer
          session_started = false
          bytes_expected = nil
          # monitor transfer status
          @transfer_client.monitor_transfers(::Transferd::Api::RegistrationRequest.new(transferId: [@transfer_id])) do |response|
            Log.dump(:response, response.to_h)
            # Log.log.debug{"#{response.sessionInfo.preTransferBytes} #{response.transferInfo.bytesTransferred}"}
            case response.status
            when :RUNNING
              if !session_started
                notify_progress(:session_start, session_id: @transfer_id)
                session_started = true
              end
              if bytes_expected.nil? &&
                  !response.sessionInfo.preTransferBytes.eql?(0)
                bytes_expected = response.sessionInfo.preTransferBytes
                notify_progress(:session_size, session_id: @transfer_id, info: bytes_expected)
              end
              notify_progress(:transfer, session_id: @transfer_id, info: response.transferInfo.bytesTransferred)
            when :COMPLETED
              notify_progress(:transfer, session_id: @transfer_id, info: bytes_expected) if bytes_expected
              notify_progress(:session_end, session_id: @transfer_id)
              break
            when :FAILED, :CANCELED
              notify_progress(:session_end, session_id: @transfer_id)
              raise Aspera::Transfer::Error, JSON.parse(response.message)['Description']
            when :QUEUED, :UNKNOWN_STATUS, :PAUSED, :ORPHANED
              notify_progress(:sessions_init, info: response.status.to_s.downcase)
            else
              Log.log.error { "unknown status#{response.status}" }
            end
          end
          # TODO: return status
          return []
        end

        def shutdown
          @daemon&.stop if @stop
        end
      end
    end
  end
end
