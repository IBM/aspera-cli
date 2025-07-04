# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/agent/base'
require 'aspera/products/transferd'
require 'aspera/temp_file_manager'
require 'json'
require 'uri'
require 'transferd_services_pb'

module Aspera
  module Agent
    class Transferd < Base
      # https://github.com/grpc/grpc/blob/master/doc/naming.md
      # https://grpc.io/docs/guides/custom-name-resolution/
      LOCAL_SOCKET_ADDR = '127.0.0.1'
      PORT_SEP = ':'
      # port zero means select a random available high port
      AUTO_LOCAL_TCP_PORT = "#{PORT_SEP}0"

      private_constant :LOCAL_SOCKET_ADDR, :PORT_SEP, :AUTO_LOCAL_TCP_PORT

      # @param url   [String] URL of the transfer manager daemon
      # @param start [Bool]   if false, expect that an external daemon is already running
      # @param stop  [Bool]   if false, do not shutdown daemon on exit
      # @param base  [Hash]   base class options
      def initialize(
        url:   AUTO_LOCAL_TCP_PORT,
        start: true,
        stop:  true,
        **base
      )
        super(**base)
        @transfer_id = nil
        @stop = stop
        is_local_auto_port = url.eql?(AUTO_LOCAL_TCP_PORT)
        raise 'Cannot set options `stop` or `start` to false with port zero' if is_local_auto_port && (!@stop || !start)
        # keep PID for optional shutdown
        @daemon_pid = nil
        daemon_endpoint = url
        Log.log.debug{Log.dump(:daemon_endpoint, daemon_endpoint)}
        # retry loop
        begin
          # no address: local bind
          daemon_endpoint = "#{LOCAL_SOCKET_ADDR}#{daemon_endpoint}" if daemon_endpoint.match?(/^#{PORT_SEP}[0-9]+$/o)
          # Create stub (without credentials)
          @transfer_client = ::Transferd::Api::TransferService::Stub.new(daemon_endpoint, :this_channel_is_insecure)
          # Initiate actual connection
          get_info_response = @transfer_client.get_info(::Transferd::Api::InstanceInfoRequest.new)
          Log.log.debug{"Daemon info: #{get_info_response}"}
          Log.log.warn('Attached to existing daemon') unless @daemon_pid || !start || !@stop
          at_exit{shutdown}
        rescue GRPC::Unavailable => e
          # if transferd is external: do not start it, or other error
          raise if !start || !e.message.include?('failed to connect')
          # we already tried to start a daemon, but it failed
          Aspera.assert(@daemon_pid.nil?){"Daemon started with PID #{@daemon_pid}, but connection failed to #{daemon_endpoint}}"}
          Log.log.warn('no daemon present, starting daemon...') if !start
          # transferd only supports local ip and port
          daemon_uri = URI.parse("ipv4://#{daemon_endpoint}")
          Aspera.assert(daemon_uri.scheme.eql?('ipv4')){"Invalid scheme daemon URI #{daemon_endpoint}"}
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
          Log.log.debug{"transferd base tmp #{transferd_base_tmp}"}
          conf_file = "#{transferd_base_tmp}.conf"
          log_stdout = "#{transferd_base_tmp}.out"
          log_stderr = "#{transferd_base_tmp}.err"
          File.write(conf_file, config.to_json)
          @daemon_pid = Environment.secure_spawn(
            exec: Ascp::Installation.instance.path(:transferd),
            args: ['--config', conf_file],
            out: log_stdout,
            err: log_stderr)
          begin
            # wait for process to initialize, max 2 seconds
            Timeout.timeout(2.0) do
              # this returns if process dies (within 2 seconds)
              _, status = Process.wait2(@daemon_pid)
              raise "Transfer daemon exited with status #{status.exitstatus}. Check files: #{log_stdout} and #{log_stderr}"
            end
          rescue Timeout::Error
            nil
          end
          Log.log.debug{"Daemon started with pid #{@daemon_pid}"}
          Process.detach(@daemon_pid) unless @stop
          at_exit{shutdown}
          # update port for next connection attempt (if auto high port was requested)
          daemon_endpoint = "#{LOCAL_SOCKET_ADDR}#{PORT_SEP}#{Products::Transferd.daemon_port_from_log(log_stdout)}" if is_local_auto_port
          # local daemon started, try again
          retry
        end
      end

      # :reek:UnusedParameters token_regenerator
      def start_transfer(transfer_spec, token_regenerator: nil)
        # create a transfer request
        transfer_request = ::Transferd::Api::TransferRequest.new(
          transferType: ::Transferd::Api::TransferType::FILE_REGULAR, # transfer type (file/stream)
          config: ::Transferd::Api::TransferConfig.new, # transfer configuration
          transferSpec: transfer_spec.to_json) # transfer definition
        # send start transfer request to the transfer manager daemon
        start_transfer_response = @transfer_client.start_transfer(transfer_request)
        Log.log.debug{"start transfer response #{start_transfer_response}"}
        @transfer_id = start_transfer_response.transferId
        Log.log.debug{"transfer started with id #{@transfer_id}"}
      end

      def wait_for_transfers_completion
        # set to true when we know the total size of the transfer
        session_started = false
        bytes_expected = nil
        # monitor transfer status
        @transfer_client.monitor_transfers(::Transferd::Api::RegistrationRequest.new(transferId: [@transfer_id])) do |response|
          Log.log.debug{Log.dump(:response, response.to_h)}
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
            notify_progress(:end, session_id: @transfer_id)
            break
          when :FAILED, :CANCELED
            notify_progress(:end, session_id: @transfer_id)
            raise Transfer::Error, JSON.parse(response.message)['Description']
          when :QUEUED, :UNKNOWN_STATUS, :PAUSED, :ORPHANED
            notify_progress(:pre_start, session_id: nil, info: response.status.to_s.downcase)
          else
            Log.log.error{"unknown status#{response.status}"}
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
          Process.kill(:INT, @daemon_pid)
          _, status = Process.wait2(@daemon_pid)
          Log.log.debug("daemon stopped #{status}")
          @daemon_pid = nil
        end
      end
    end
  end
end
