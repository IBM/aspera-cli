# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/rest'
require 'aspera/open_application'
require 'securerandom'

module Aspera
  module Fasp
    class AgentAspera < Aspera::Fasp::AgentBase
      # try twice the main init url in sequence
      START_URIS = ['aspera://']
      # delay between each try to start connect
      SLEEP_SEC_BETWEEN_RETRY = 3
      private_constant :START_URIS, :SLEEP_SEC_BETWEEN_RETRY
      def initialize(options)
        super(options)
        @client_settings = {
          'app_id' => SecureRandom.uuid
        }
        raise 'Using connect requires a graphical environment' if !OpenApplication.default_gui_mode.eql?(:graphical)
        method_index = 0
        begin
          client_url = aspera_client_api_url
          Log.log.debug{"found: #{client_url}"}
          my_client = Aspera::JsonRpcClient.new(Aspera::Rest.new(base_url: client_url))
          client_info = my_client.get_info
          @application_id = 'aspera_2c45aa46-c43a-4a04-9726-28abc18aefeb'
          # my_transfer_id = '0513fe85-65cf-465b-ad5f-18fd40d8c69f'
          # my_client.get_all_transfers({app_id: @application_id})
          # my_client.get_transfer(app_id: @application_id, transfer_id: my_transfer_id)
          # my_client.start_transfer(app_id: @application_id,transfer_spec: {})
          # my_client.remove_transfer
          # my_client.stop_transfer
          # my_client.modify_transfer
          # my_client.show_directory({app_id: @application_id, transfer_id: my_transfer_id})
          # my_client.get_files_list({app_id: @application_id, transfer_id: my_transfer_id})
          Log.log.info('Connect was reached') if method_index > 0
          Log.log.debug{Log.dump(:client_version, client_info)}
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
        if transfer_spec['direction'] == 'send'
          Log.log.warn{"Connect requires upload selection using GUI, ignoring #{transfer_spec['paths']}".red}
          transfer_spec.delete('paths')
          selection = @client_api.create('windows/select-open-file-dialog/', {
            'aspera_client_settings' => @client_settings,
            'title'                  => 'Select Files',
            'suggestedName'          => '',
            'allowMultipleSelection' => true,
            'allowedFileTypes'       => ''})[:data]
          transfer_spec['paths'] = selection['dataTransfer']['files'].map { |i| {'source' => i['name']}}
        end
        @request_id = SecureRandom.uuid
        # if there is a token, we ask connect client to use well known ssh private keys
        # instead of asking password
        transfer_spec['authentication'] = 'token' if transfer_spec.key?('token')
        client_transfer_args = {
          'aspera_client_settings' => @client_settings.merge({
            'request_id'    => @request_id,
            'allow_dialogs' => true
          }),
          'transfer_specs'         => [{
            'transfer_spec' => transfer_spec
          }]}
        # asynchronous anyway
        res = @client_api.create('transfers/start', client_transfer_args)[:data]
        @xfer_id = res['transfer_specs'].first['transfer_spec']['tags'][Fasp::TransferSpec::TAG_RESERVED]['xfer_id']
      end

      def wait_for_transfers_completion
        client_activity_args = {'aspera_client_settings' => @client_settings}
        started = false
        pre_calc = false
        session_id = @xfer_id
        begin
          loop do
            tr_info = @client_api.create("transfers/info/#{@xfer_id}", client_activity_args)[:data]
            Log.log.trace1{Log.dump(:tr_info, tr_info)}
            if tr_info['transfer_info'].is_a?(Hash)
              transfer = tr_info['transfer_info']
              if transfer.nil?
                Log.log.warn('no session in Connect')
                break
              end
              # TODO: get session id
              case transfer['status']
              when 'initiating', 'queued'
                notify_progress(session_id: nil, type: :pre_start, info: transfer['status'])
              when 'running'
                if !started
                  notify_progress(session_id: session_id, type: :session_start)
                  started = true
                end
                if !pre_calc && (transfer['bytes_expected'] != 0)
                  notify_progress(type: :session_size, session_id: session_id, info: transfer['bytes_expected'])
                  pre_calc = true
                else
                  notify_progress(type: :transfer, session_id: session_id, info: transfer['bytes_written'])
                end
              when 'completed'
                notify_progress(type: :end, session_id: session_id)
                break
              when 'failed'
                notify_progress(type: :end, session_id: session_id)
                raise Fasp::Error, transfer['error_desc']
              when 'cancelled'
                notify_progress(type: :end, session_id: session_id)
                raise Fasp::Error, 'Transfer cancelled by user'
              else
                notify_progress(type: :end, session_id: session_id)
                raise Fasp::Error, "unknown status: #{transfer['status']}: #{transfer['error_desc']}"
              end
            end
            sleep(1)
          end
        rescue StandardError => e
          return [e]
        end
        return [:success]
      end # wait
    end # AgentAspera
  end
end
