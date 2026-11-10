# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/agent/base'
require 'aspera/products/transferd'
require 'aspera/temp_file_manager'
require 'aspera/transfer/error'
require 'aspera/transfer/spec'
require 'json'
require 'time'
require 'uri'
require 'transferd_services_pb'

module Aspera
  module Agent
    class Transferd < Base
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

      # https://github.com/grpc/grpc/blob/master/doc/naming.md
      # https://grpc.io/docs/guides/custom-name-resolution/
      LOCAL_SOCKET_ADDR = '127.0.0.1'
      PORT_SEP = ':'
      # port zero means select a random available high port
      AUTO_LOCAL_TCP_PORT = "#{PORT_SEP}0"
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

      private_constant :LOCAL_SOCKET_ADDR, :PORT_SEP, :AUTO_LOCAL_TCP_PORT, :ASYNC_STATUS, :MIN_USEC_EPOCH

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

      # @param url   [String]  URL of the transfer manager daemon
      # @param start [Boolean] If `false`, expect that an external daemon is already running
      # @param stop  [Boolean] If `false`, do not shutdown daemon on exit
      # @param api_key [String, nil] API key of an external daemon with `authentication` enabled
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
        Aspera.assert(!(is_local_auto_port && (!@stop || !start)), type: Error) { 'Cannot set options `stop` or `start` to false with port zero' }
        # keep PID for optional shutdown
        @daemon_pid = nil
        @daemon_endpoint = nil
        daemon_endpoint = url
        Log.dump(:daemon_endpoint, daemon_endpoint)
        # retry loop
        begin
          # no address: local bind
          daemon_endpoint = "#{LOCAL_SOCKET_ADDR}#{daemon_endpoint}" if daemon_endpoint.match?(/^#{PORT_SEP}[0-9]+$/o)
          # Create stub: no credentials for a daemon started here, API key and TLS only for an external daemon
          @transfer_client = self.class.create_client(daemon_endpoint, api_key: api_key, ca_file: ca_file)
          # Initiate actual connection
          get_info_response = @transfer_client.get_info(::Transferd::Api::InstanceInfoRequest.new)
          @daemon_endpoint = daemon_endpoint
          Log.log.debug { "Daemon info: #{get_info_response}" }
          Log.log.warn('Attached to existing daemon') unless @daemon_pid || !start || !@stop
          # `shutdown` is registered with `at_exit` only when the daemon is started here:
          # a long-running process (e.g. Orchestrator) that attaches to an external daemon for each transfer would accumulate them
        rescue GRPC::Unavailable => e
          # if transferd is external: do not start it, or other error
          raise if !start || !e.message.include?('failed to connect')
          # we already tried to start a daemon, but it failed
          Aspera.assert(@daemon_pid.nil?) { "Daemon started with PID #{@daemon_pid}, but connection failed to #{daemon_endpoint}" }
          Log.log.warn('no daemon present, starting daemon...') if !start
          # transferd only supports local ip and port
          daemon_uri = URI.parse("ipv4://#{daemon_endpoint}")
          Aspera.assert(daemon_uri.scheme.eql?('ipv4')) { "Invalid scheme daemon URI #{daemon_endpoint}" }
          # create a config file for daemon
          config = {
            address:      daemon_uri.host,
            port:         daemon_uri.port,
            fasp_runtime: {
              use_embedded: false,
              user_defined: {
                bin: Products::Transferd.sdk_directory,
                etc: Products::Transferd.sdk_directory
              }
            }
          }
          # config file and logs are created in same folder
          transferd_base_tmp = TempFileManager.instance.new_file_path_global('transferd')
          Log.log.debug { "transferd base tmp #{transferd_base_tmp}" }
          conf_file = "#{transferd_base_tmp}.conf"
          log_stdout = "#{transferd_base_tmp}.out"
          log_stderr = "#{transferd_base_tmp}.err"
          File.write(conf_file, config.to_json)
          @daemon_pid = Environment.secure_execute(
            Ascp::Installation.instance.path(:transferd), '--config', conf_file,
            mode: :background,
            out: log_stdout,
            err: log_stderr
          )
          begin
            # wait for process to initialize, max 2 seconds
            Timeout.timeout(2.0) do
              # this returns if process dies (within 2 seconds)
              _, status = ::Process.wait2(@daemon_pid)
              raise "Transfer daemon exited with status #{status.exitstatus}. Check files: #{log_stdout} and #{log_stderr}"
            end
          rescue Timeout::Error
            nil
          end
          Log.log.debug { "Daemon started with pid #{@daemon_pid}" }
          ::Process.detach(@daemon_pid) unless @stop
          at_exit { shutdown }
          # update port for next connection attempt (if auto high port was requested)
          daemon_endpoint = "#{LOCAL_SOCKET_ADDR}#{PORT_SEP}#{Products::Transferd.daemon_port_from_log(log_stdout)}" if is_local_auto_port
          # local daemon started, try again
          retry
        end
      end

      # Actual endpoint the daemon is listening on (resolved after connect, e.g. when port 0 was used)
      attr_reader :daemon_endpoint
      # Identifier of the last transfer started, given by the daemon: for `transfer_status` and `transfer_cancel`
      attr_reader :transfer_id
      # gRPC client of the daemon
      attr_reader :transfer_client

      # :reek:UnusedParameters token_regenerator
      def start_transfer(transfer_spec, token_regenerator: nil)
        Transfer::Spec.fix_transferd_resume_policy(transfer_spec)
        # create a transfer request
        transfer_request = ::Transferd::Api::TransferRequest.new(
          transferType: ::Transferd::Api::TransferType::FILE_REGULAR, # transfer type (file/stream)
          config: ::Transferd::Api::TransferConfig.new, # transfer configuration
          transferSpec: transfer_spec.to_json
        ) # transfer definition
        # send start transfer request to the transfer manager daemon
        start_response = @transfer_client.start_transfer(transfer_request)
        Aspera.assert(!start_response.status.eql?(:FAILED), type: Transfer::Error) { start_response.error.description }
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
            raise Transfer::Error, JSON.parse(response.message)['Description']
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
        stop_daemon if @stop
      end

      private

      def stop_daemon
        if !@daemon_pid.nil?
          Log.log.debug("Stopping daemon #{@daemon_pid}")
          ::Process.kill(:KILL, @daemon_pid)
          _, status = ::Process.wait2(@daemon_pid)
          Log.log.debug("daemon stopped #{status}")
          @daemon_pid = nil
        end
      end
    end
  end
end
