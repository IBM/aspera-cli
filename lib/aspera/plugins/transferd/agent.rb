# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../agent/base'
require_relative '../../bundle_registry'
require_relative '../../log'
require_relative '../../transfer/error'
require_relative '../../transfer/spec'
begin
  require_relative 'api'
rescue LoadError => e
  # The optional gem grpc is not a gem of the bundle: the commands `install`, `list` and `service` work without it
  raise unless e.path.eql?('grpc')
  raise Aspera::BundleRegistry::Unavailable, 'agent transferd requires gem grpc: gem install grpc'
end
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
        PORT_SEP = ':'
        # port zero means select a random available high port
        AUTO_LOCAL_TCP_PORT = "#{PORT_SEP}0".freeze
        # Seconds to wait for a daemon started here to answer
        START_TIMEOUT_SEC = 10
        # Seconds between two connection attempts to a daemon started here
        START_RETRY_SEC = 0.2

        # Daemon addresses that run on the local host (loopback or wildcard bind): a daemon there is started or attached to locally
        LOCAL_DAEMON_HOSTS = ['127.0.0.1', 'localhost', '::1', '0.0.0.0', '::'].freeze

        private_constant :PORT_SEP, :AUTO_LOCAL_TCP_PORT, :LOCAL_DAEMON_HOSTS, :START_TIMEOUT_SEC, :START_RETRY_SEC

        class << self
          # A daemon started here, or attached to on the local host, runs on the local host: refused at level `high` (see `Cli::Security`).
          # A daemon on a remote host is provided and controlled by the user: allowed at any level.
          # @param options [Hash] agent parameters (`url` is the daemon endpoint, default: a local daemon)
          # @return [Symbol, nil] `:medium` for a local daemon, `nil` (any level) for a remote one
          def required_security_level(options)
            remote_daemon?(options[:url]) ? nil : :medium
          end

          # @param url [String, nil] daemon endpoint `<address>:<port>` (or `:<port>`, or absent: a local daemon)
          # @return [Boolean] `true` if the daemon is on a remote host
          def remote_daemon?(url)
            return false if url.nil?
            host = url.to_s.sub(%r{\A\w+://}, '')
            host = host[0...host.rindex(':')] if host.include?(':')
            !host.empty? && !LOCAL_DAEMON_HOSTS.include?(host.downcase)
          end

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

        # Connect to the daemon of `url`, and start it if it does not answer (unless `start` is `false`)
        # @param url   [String]  URL of the transfer manager daemon, e.g. `127.0.0.1:55002`, or only its port (address `127.0.0.1`)
        # @param start [Boolean] If `false`, expect that an external daemon is already running
        # @param stop  [Boolean] If `false`, do not shutdown daemon on exit
        # @param api_key [String, nil] API key of the daemon: of an external daemon with `authentication` enabled, or of the daemon started here (else a random one)
        # @param ca_file [String, nil] Certificate authority (PEM file) of an external daemon with `tls` enabled
        # @param base  [Hash]    Base class options
        # @raise [Aspera::Transfer::Error] The daemon started here does not answer within `START_TIMEOUT_SEC`
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
          # no address: local address
          @daemon_endpoint = Api.endpoint(url)
          Log.dump(:daemon_endpoint, @daemon_endpoint)
          begin
            connect(api_key, ca_file)
            Log.log.warn('Attached to existing daemon') if start && @stop
            # `shutdown` is registered with `at_exit` only when the daemon is started here:
            # a long-running process (e.g. Orchestrator) that attaches to an external daemon for each transfer would accumulate them
          rescue GRPC::Unavailable => e
            # if transferd is external: do not start it, or other error
            raise if !start || !e.message.include?('failed to connect')
            start_daemon(api_key, ca_file, auto_port: is_local_auto_port)
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

        private

        # Create the client of the daemon of `@daemon_endpoint`, and get its information: the actual connection
        # @param api_key  [String, nil] API key of the daemon
        # @param ca_file  [String, nil] Certificate authority (PEM file) of the daemon
        # @param deadline [Time, nil]   Time limit of the call, `nil`: none
        # @raise [GRPC::BadStatus] The daemon does not answer
        def connect(api_key, ca_file, deadline: nil)
          # Create stub: API key of the daemon (given, or the one of the daemon started here)
          @transfer_client = Api.create_client(@daemon_endpoint, api_key: api_key, ca_file: ca_file)
          get_info_response = @transfer_client.get_info(::Transferd::Api::InstanceInfoRequest.new, deadline: deadline)
          Log.log.debug { "Daemon info: #{get_info_response}" }
        end

        # Start a daemon on `@daemon_endpoint`, then connect to it: it may need some time before it listens (e.g. first start of its executable)
        # @param api_key   [String, nil] API key given by the user (see `Product.daemon_api_key`)
        # @param ca_file   [String, nil] Certificate authority (PEM file) of the daemon
        # @param auto_port [Boolean]     `true` if started with port zero: the port is read from its log
        # @raise [Aspera::Transfer::Error] The daemon does not answer within `START_TIMEOUT_SEC`
        def start_daemon(api_key, ca_file, auto_port:)
          # Expected for the first execution when the daemon is left running
          Log.log.public_send(@stop ? :warn : :info, 'no daemon present, starting daemon...')
          # transferd only supports local ip and port
          daemon_uri = URI.parse("ipv4://#{@daemon_endpoint}")
          Aspera.assert(!daemon_uri.host.to_s.empty? && !daemon_uri.port.nil?, type: ParameterError) { "Invalid address of daemon: #{@daemon_endpoint}, expecting <ADDRESS>:<PORT> or :<PORT>" }
          @daemon = Product.new(address: daemon_uri.host, port: daemon_uri.port, api_key: api_key, stop: @stop)
          at_exit { shutdown }
          deadline = Time.now + START_TIMEOUT_SEC
          begin
            # Port written in the log once it listens (if auto high port was requested)
            @daemon_endpoint = Api.endpoint("#{PORT_SEP}#{@daemon.port_from_log}") if auto_port
            # API key of the daemon started here
            connect(@daemon.api_key, ca_file, deadline: deadline)
          rescue GRPC::Unavailable, GRPC::DeadlineExceeded, AssertError => e
            reason = e.is_a?(GRPC::BadStatus) ? "#{e.class.name.split('::').last}: #{e.details}" : e.message
            Aspera.assert(Time.now < deadline, type: Aspera::Transfer::Error) do
              "Transfer daemon started with PID #{@daemon.pid} does not answer on #{@daemon_endpoint} after #{START_TIMEOUT_SEC} seconds (#{reason}). " \
                "Check files: #{@daemon.log_files.join(' and ')}"
            end
            Log.log.debug { "Daemon does not answer yet: #{reason}" }
            sleep(START_RETRY_SEC)
            retry
          end
        end
      end
    end
  end
end
