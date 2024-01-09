# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/rest'
require 'aspera/log'
require 'aspera/json_rpc'
require 'aspera/open_application'
require 'securerandom'

module Aspera
  module Fasp
    class AgentAlpha < Aspera::Fasp::AgentBase
      # try twice the main init url in sequence
      START_URIS = ['aspera://']
      # delay between each try to start connect
      SLEEP_SEC_BETWEEN_RETRY = 3
      private_constant :START_URIS, :SLEEP_SEC_BETWEEN_RETRY
      def initialize(options)
        @application_id = SecureRandom.uuid
        super(options)
        raise 'Using client requires a graphical environment' if !OpenApplication.default_gui_mode.eql?(:graphical)
        method_index = 0
        begin
          @client_app_api = Aspera::JsonRpcClient.new(Aspera::Rest.new(base_url: aspera_client_api_url))
          client_info = @client_app_api.get_info
          Log.log.debug{Log.dump(:client_version, client_info)}
          # my_transfer_id = '0513fe85-65cf-465b-ad5f-18fd40d8c69f'
          # @client_app_api.get_all_transfers({app_id: @application_id})
          # @client_app_api.get_transfer(app_id: @application_id, transfer_id: my_transfer_id)
          # @client_app_api.start_transfer(app_id: @application_id,transfer_spec: {})
          # @client_app_api.remove_transfer
          # @client_app_api.stop_transfer
          # @client_app_api.modify_transfer
          # @client_app_api.show_directory({app_id: @application_id, transfer_id: my_transfer_id})
          # @client_app_api.get_files_list({app_id: @application_id, transfer_id: my_transfer_id})
          Log.log.info('Client was reached') if method_index > 0
        rescue StandardError => e # Errno::ECONNREFUSED
          start_url = START_URIS[method_index]
          method_index += 1
          raise StandardError, "Unable to start connect #{method_index} times" if start_url.nil?
          Log.log.warn{"Aspera Connect is not started (#{e}). Trying to start it ##{method_index}..."}
          if !OpenApplication.uri_graphical(start_url)
            OpenApplication.uri_graphical('https://downloads.asperasoft.com/connect2/')
            raise StandardError, 'Connect is not installed'
          end
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
      end

      def aspera_client_api_url
        log_file = File.join(Dir.home, 'Library', 'Logs', 'IBM Aspera', 'ibm-aspera-desktop.log')
        url = nil
        File.open(log_file, 'r') do |file|
          file.each_line do |line|
            line = line.chomp
            if (m = line.match(/JSON-RPC server listening on (.*)/))
              url = "http://#{m[1]}"
            end
          end
        end
        return url
      end

      def start_transfer(transfer_spec, token_regenerator: nil)
        @request_id = SecureRandom.uuid
        # if there is a token, we ask connect client to use well known ssh private keys
        # instead of asking password
        transfer_spec['authentication'] = 'token' if transfer_spec.key?('token')
        result = @client_app_api.start_transfer(app_id: @application_id, desktop_spec: {}, transfer_spec: transfer_spec)
        @xfer_id = result['uuid']
      end

      def wait_for_transfers_completion
        started = false
        pre_calc = false
        begin
          loop do
            transfer = @client_app_api.get_transfer(app_id: @application_id, transfer_id: @xfer_id)
            case transfer['status']
            when 'initiating', 'queued'
              notify_progress(session_id: nil, type: :pre_start, info: transfer['status'])
            when 'running'
              if !started
                notify_progress(session_id: @xfer_id, type: :session_start)
                started = true
              end
              if !pre_calc && (transfer['bytes_expected'] != 0)
                notify_progress(type: :session_size, session_id: @xfer_id, info: transfer['bytes_expected'])
                pre_calc = true
              else
                notify_progress(type: :transfer, session_id: @xfer_id, info: transfer['bytes_written'])
              end
            when 'completed'
              notify_progress(type: :end, session_id: @xfer_id)
              break
            when 'failed'
              notify_progress(type: :end, session_id: @xfer_id)
              raise Fasp::Error, transfer['error_desc']
            when 'cancelled'
              notify_progress(type: :end, session_id: @xfer_id)
              raise Fasp::Error, 'Transfer cancelled by user'
            else
              notify_progress(type: :end, session_id: @xfer_id)
              raise Fasp::Error, "unknown status: #{transfer['status']}: #{transfer['error_desc']}"
            end
            sleep(1)
          end
        rescue StandardError => e
          return [e]
        end
        return [:success]
      end # wait
    end # AgentAlpha
  end
end
