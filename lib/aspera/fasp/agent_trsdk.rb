require 'aspera/fasp/agent_base'
require 'aspera/fasp/installation'
require 'json'

module Aspera
  module Fasp
    class AgentTrsdk < AgentBase
      SDK_GRPC_ADDR = '127.0.0.1'
      SDK_GRPC_PORT = 55002
      def initialize(options)
        super()
        $LOAD_PATH.unshift(Installation.instance.sdk_ruby_folder)
        bin_folder=File.realpath(File.join(Installation.instance.sdk_ruby_folder,'..'))
        require 'transfer_services_pb'
        @transfer_client = Transfersdk::TransferService::Stub.new("#{SDK_GRPC_ADDR}:#{SDK_GRPC_PORT}",:this_channel_is_insecure)
        begin
          get_info_response = @transfer_client.get_info(Transfersdk::InstanceInfoRequest.new)
          Log.log.debug("daemon info: #{get_info_response}")
        rescue GRPC::Unavailable => e
          Log.log.warn("no daemon, starting...")
          config = {
            address: SDK_GRPC_ADDR,
            port: SDK_GRPC_PORT,
            fasp_runtime: {
            use_embedded: false,
            user_defined: {
            bin: bin_folder,
            etc: bin_folder,
            }
            }
          }
          conf_file = File.join(bin_folder,'sdk.conf')
          log_base = File.join(bin_folder,'transferd')
          File.write(conf_file,config.to_json)
          daemon=Installation.instance.path(:transferd)
          trd_pid = Process.spawn([daemon,daemon],'--config' , conf_file, out: "#{log_base}.out", err: "#{log_base}.err")
          Process.detach(trd_pid)
          sleep(2.0)
          retry
        end
      end

      #            filters: [
      #              Transfersdk::RegistrationFilter.new(
      #              operator: Transfersdk::RegistrationFilterOperator::OR,
      #              eventType: [Transfersdk::TransferEvent::FILE_STOP],
      #              direction: 'Receive'),
      #              Transfersdk::RegistrationFilter.new(
      #              operator: Transfersdk::RegistrationFilterOperator::AND,
      #              transferStatus: [Transfersdk::TransferStatus::COMPLETED]
      #              )
      #            ]
      def start_transfer(transfer_spec,options=nil)
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
        started=false
        # monitor transfer status
        @transfer_client.monitor_transfers(Transfersdk::RegistrationRequest.new(transferId: [@transfer_id])) do |response|
          Log.log.debug("transfer info #{response}")
          # check transfer status in response, and exit if it's done
          case response.status
          when :QUEUED,:UNKNOWN_STATUS,:PAUSED,:ORPHANED
          when :RUNNING
            if !started and !response.sessionInfo.preTransferBytes.eql?(0)
              notify_begin(@transfer_id,response.sessionInfo.preTransferBytes)
              started=true
            else
              notify_progress(@transfer_id,response.transferInfo.bytesTransferred)
            end
          when :FAILED, :COMPLETED, :CANCELED
            notify_end(@transfer_id)
            break
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
