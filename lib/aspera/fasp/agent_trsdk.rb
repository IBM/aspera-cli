# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/installation'
require 'json'
require 'uri'

module Aspera
  module Fasp
    class AgentTrsdk < Aspera::Fasp::AgentBase
      DEFAULT_OPTIONS = {
        url:      'grpc://127.0.0.1:0',
        external: false,
        keep:     false
      }.freeze
      private_constant :DEFAULT_OPTIONS

      # options come from transfer_info
      def initialize(user_opts={})
        super(user_opts)
        @options = AgentBase.options(default: DEFAULT_OPTIONS, options: user_opts)
        daemon_uri = URI.parse(@options[:url])
        raise Fasp::Error, "invalid url #{@options[:url]}" unless daemon_uri.scheme.eql?('grpc')
        Log.log.debug{Log.dump(:agent_options, @options)}
        # load and create SDK stub
        $LOAD_PATH.unshift(Installation.instance.sdk_ruby_folder)
        require 'transfer_services_pb'
        # it stays
        @daemon_pid = nil
        begin
          @transfer_client = Transfersdk::TransferService::Stub.new("#{daemon_uri.host}:#{daemon_uri.port}", :this_channel_is_insecure)
          get_info_response = @transfer_client.get_info(Transfersdk::InstanceInfoRequest.new)
          Log.log.debug{"daemon info: #{get_info_response}"}
          Log.log.warn{'attached to existing daemon'} unless @options[:external] || @options[:keep]
          at_exit{shutdown}
        rescue GRPC::Unavailable
          raise if @options[:external]
          raise "daemon started with PID #{@daemon_pid}, but connection failed to #{daemon_uri}}" unless @daemon_pid.nil?
          Log.log.warn('no daemon present, starting daemon...') if @options[:external]
          # location of daemon binary
          bin_folder = File.realpath(File.join(Installation.instance.sdk_ruby_folder, '..'))
          # config file and logs are created in same folder
          generated_config_file_path = File.join(bin_folder, 'sdk.conf')
          log_base = File.join(bin_folder, 'transferd')
          # create a config file for daemon
          config = {
            address:      daemon_uri.host,
            port:         daemon_uri.port,
            fasp_runtime: {
              use_embedded: false,
              user_defined: {
                bin: bin_folder,
                etc: bin_folder
              }
            }
          }
          File.write(generated_config_file_path, config.to_json)
          @daemon_pid = Process.spawn(Installation.instance.path(:transferd), '--config', generated_config_file_path, out: "#{log_base}.out", err: "#{log_base}.err")
          begin
            # wait for process to initialize
            Timeout.timeout(2.0) do
              _, status = Process.wait2(@daemon_pid)
              raise "transfer daemon exited with status #{status.exitstatus}. Check files: #{log_base}.out #{log_base}.err"
            end
          rescue Timeout::Error
            nil
          end
          Log.log.debug{"daemon started with pid #{@daemon_pid}"}
          Process.detach(@daemon_pid) if @options[:keep]
          if daemon_uri.port.eql?(0)
            # if port is zero, a dynamic port was created, get it
            File.open("#{log_base}.out", 'r') do |file|
              file.each_line do |line|
                if (m = line.match(/Info: API Server: Listening on ([^:]+):(\d+) /))
                  daemon_uri.port = m[2].to_i
                  # no "break" , need to keep last one
                end
              end
            end
          end
          retry
        end
      end

      def start_transfer(transfer_spec, token_regenerator: nil)
        # create a transfer request
        transfer_request = Transfersdk::TransferRequest.new(
          transferType: Transfersdk::TransferType::FILE_REGULAR, # transfer type (file/stream)
          config: Transfersdk::TransferConfig.new, # transfer configuration
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
        @transfer_client.monitor_transfers(Transfersdk::RegistrationRequest.new(transferId: [@transfer_id])) do |response|
          Log.log.debug{Log.dump(:response, response.to_h)}
          # Log.log.debug{"#{response.sessionInfo.preTransferBytes} #{response.transferInfo.bytesTransferred}"}
          case response.status
          when :RUNNING
            if !session_started
              notify_progress(session_id: @transfer_id, type: :session_start)
              session_started = true
            end
            if bytes_expected.nil? &&
                !response.sessionInfo.preTransferBytes.eql?(0)
              bytes_expected = response.sessionInfo.preTransferBytes
              notify_progress(type: :session_size, session_id: @transfer_id, info: bytes_expected)
            end
            notify_progress(type: :transfer, session_id: @transfer_id, info: response.transferInfo.bytesTransferred)
          when :COMPLETED
            notify_progress(type: :transfer, session_id: @transfer_id, info: bytes_expected) if bytes_expected
            notify_progress(type: :end, session_id: @transfer_id)
            break
          when :FAILED, :CANCELED
            notify_progress(type: :end, session_id: @transfer_id)
            raise Fasp::Error, JSON.parse(response.message)['Description']
          when :QUEUED, :UNKNOWN_STATUS, :PAUSED, :ORPHANED
            notify_progress(session_id: nil, type: :pre_start, info: response.status.to_s.downcase)
          else
            Log.log.error{"unknown status#{response.status}"}
          end
        end
        # TODO: return status
        return []
      end

      def shutdown
        if !@options[:keep] && !@daemon_pid.nil?
          Log.log.debug("stopping daemon #{@daemon_pid}")
          Process.kill('INT', @daemon_pid)
          _, status = Process.wait2(@daemon_pid)
          Log.log.debug("daemon stopped #{status}")
          @daemon_pid = nil
        end
      end
    end
  end
end
