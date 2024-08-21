# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/rest'
require 'aspera/log'
require 'aspera/json_rpc'
require 'aspera/environment'
require 'securerandom'

module Aspera
  module Agent
    # Aspera Desktop Alpha Client
    class Alpha < Base
      # try twice the main init url in sequence
      START_URIS = ['aspera://', 'aspera://', 'aspera://']
      # delay between each try to start the app
      SLEEP_SEC_BETWEEN_RETRY = 5
      APP_IDENTIFIER = 'com.ibm.software.aspera.desktop'
      APP_NAME = 'Aspera Desktop Alpha Client'
      private_constant :START_URIS, :SLEEP_SEC_BETWEEN_RETRY
      def initialize(**base_options)
        @application_id = SecureRandom.uuid
        @xfer_id = nil
        super(**base_options)
        raise 'Using client requires a graphical environment' if !Environment.default_gui_mode.eql?(:graphical)
        method_index = 0
        begin
          # curl 'http://127.0.0.1:33024/' -X POST -H 'content-type: application/json' --data-raw '{"jsonrpc":"2.0","params":[],"id":999999,"method":"rpc.discover"}'
          # https://playground.open-rpc.org/?schemaUrl=http://127.0.0.1:33024
          @client_app_api = Aspera::JsonRpcClient.new(Aspera::Rest.new(base_url: aspera_client_api_url))
          client_info = @client_app_api.get_info
          Log.log.debug{Log.dump(:client_version, client_info)}
          Log.log.info('Client was reached') if method_index > 0
        rescue Errno::ECONNREFUSED => e
          start_url = START_URIS[method_index]
          method_index += 1
          raise StandardError, "Unable to start #{APP_NAME} #{method_index} times" if start_url.nil?
          Log.log.warn{"#{APP_NAME} is not started (#{e}). Trying to start it ##{method_index}..."}
          if !Environment.open_uri_graphical(start_url)
            Environment.open_uri_graphical('https://www.ibm.com/aspera/connect/')
            raise StandardError, "#{APP_NAME} is not installed"
          end
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
      end

      def sdk_log_file
        File.join(Dir.home, 'Library', 'Logs', APP_IDENTIFIER, 'ibm-aspera-desktop.log')
      end

      def aspera_client_api_url
        log_file = sdk_log_file
        url = nil
        File.open(log_file, 'r') do |file|
          file.each_line do |line|
            line = line.chomp
            if (m = line.match(/JSON-RPC server listening on (.*)/))
              url = "http://#{m[1]}"
            end
          end
        end
        url = 'http://127.0.0.1:33024' if url.nil?
        raise StandardError, "Unable to find the JSON-RPC server URL in #{log_file}" if url.nil?
        return url
      end

      def start_transfer(transfer_spec, token_regenerator: nil)
        @request_id = SecureRandom.uuid
        # if there is a token, we ask the client app to use well known ssh private keys
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
              raise Transfer::Error, transfer['error_desc']
            when 'cancelled'
              notify_progress(type: :end, session_id: @xfer_id)
              raise Transfer::Error, 'Transfer cancelled by user'
            else
              notify_progress(type: :end, session_id: @xfer_id)
              raise Transfer::Error, "unknown status: #{transfer['status']}: #{transfer['error_desc']}"
            end
            sleep(1)
          end
        rescue StandardError => e
          return [e]
        end
        return [:success]
      end
    end
  end
end
