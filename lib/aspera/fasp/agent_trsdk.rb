# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/installation'
require 'json'

module Aspera
  module Fasp
    class AgentTrsdk < AgentBase
      DEFAULT_OPTIONS = {
        address: '127.0.0.1',
        port:    55_002
      }.freeze
      private_constant :DEFAULT_OPTIONS

      # options come from transfer_info
      def initialize(user_opts)
        raise "expecting Hash (or nil), but have #{user_opts.class}" unless user_opts.nil? || user_opts.is_a?(Hash)
        # set default options and override if specified
        options = DEFAULT_OPTIONS.clone
        user_opts&.each do |k,v|
          raise "Unknown local agent parameter: #{k}, expect one of #{DEFAULT_OPTIONS.keys.map(&:to_s).join(',')}" unless DEFAULT_OPTIONS.has_key?(k)
          options[k] = v
        end
        Log.log.debug("options= #{options}")
        super()
        # load and create SDK stub
        $LOAD_PATH.unshift(Installation.instance.sdk_ruby_folder)
        require 'transfer_services_pb'
        @transfer_client = Transfersdk::TransferService::Stub.new("#{options[:address]}:#{options[:port]}",:this_channel_is_insecure)
        begin
          get_info_response = @transfer_client.get_info(Transfersdk::InstanceInfoRequest.new)
          Log.log.debug("daemon info: #{get_info_response}")
        rescue GRPC::Unavailable
          Log.log.warn('no daemon present, starting daemon...')
          # location of daemon binary
          bin_folder = File.realpath(File.join(Installation.instance.sdk_ruby_folder,'..'))
          # config file and logs are created in same folder
          conf_file = File.join(bin_folder,'sdk.conf')
          log_base = File.join(bin_folder,'transferd')
          # create a config file for daemon
          config = {
            address:      options[:address],
            port:         options[:port],
            fasp_runtime: {
            use_embedded: false,
            user_defined: {
            bin: bin_folder,
            etc: bin_folder
            }
            }
          }
          File.write(conf_file,config.to_json)
          trd_pid = Process.spawn(Installation.instance.path(:transferd),'--config', conf_file, out: "#{log_base}.out", err: "#{log_base}.err")
          Process.detach(trd_pid)
          sleep(2.0)
          retry
        end
      end

      def start_transfer(transfer_spec,_options=nil)
        # create a transfer request
        transfer_request = Transfersdk::TransferRequest.new(
        transferType: Transfersdk::TransferType::FILE_REGULAR, # transfer type (file/stream)
        config: Transfersdk::TransferConfig.new, # transfer configuration
        transferSpec: transfer_spec.to_json) # transfer definition
        # send start transfer request to the transfer manager daemon
        start_transfer_response = @transfer_client.start_transfer(transfer_request)
        Log.log.debug("start transfer response #{start_transfer_response}")
        @transfer_id = start_transfer_response.transferId
        Log.log.debug("transfer started with id #{@transfer_id}")
      end

      def wait_for_transfers_completion
        started = false
        # monitor transfer status
        @transfer_client.monitor_transfers(Transfersdk::RegistrationRequest.new(transferId: [@transfer_id])) do |response|
          Log.dump(:response, response.to_h)
          #Log.log.debug("#{response.sessionInfo.preTransferBytes} #{response.transferInfo.bytesTransferred}")
          case response.status
          when :RUNNING
            if !started && !response.sessionInfo.preTransferBytes.eql?(0)
              notify_begin(@transfer_id,response.sessionInfo.preTransferBytes)
              started = true
            elsif started
              notify_progress(@transfer_id,response.transferInfo.bytesTransferred)
            end
          when :FAILED, :COMPLETED, :CANCELED
            notify_end(@transfer_id)
            raise Fasp::Error, JSON.parse(response.message)['Description'] unless :COMPLETED.eql?(response.status)
            break
          when :QUEUED,:UNKNOWN_STATUS,:PAUSED,:ORPHANED
            # ignore
          else
            Log.log.error("unknown status#{response.status}")
          end
        end
        # TODO return status
        return []
      end
    end
  end
end
