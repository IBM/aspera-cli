# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/rest'
require 'aspera/open_application'
require 'securerandom'

module Aspera
  module Fasp
    class AgentConnect < Aspera::Fasp::AgentBase
      # try twice the main init url in sequence
      CONNECT_START_URIS = ['fasp://initialize', 'fasp://initialize', 'aspera-drive://initialize', 'https://test-connect.ibmaspera.com/']
      # delay between each try to start connect
      SLEEP_SEC_BETWEEN_RETRY = 3
      private_constant :CONNECT_START_URIS, :SLEEP_SEC_BETWEEN_RETRY
      def initialize(options)
        super(options)
        @connect_settings = {
          'app_id' => SecureRandom.uuid
        }
        raise 'Using connect requires a graphical environment' if !OpenApplication.default_gui_mode.eql?(:graphical)
        method_index = 0
        begin
          connect_url = Products.connect_uri
          Log.log.debug{"found: #{connect_url}"}
          @connect_api = Rest.new({base_url: "#{connect_url}/v5/connect", headers: {'Origin' => Rest.user_agent}}) # could use v6 also now
          connect_info = @connect_api.read('info/version')[:data]
          Log.log.info('Connect was reached') if method_index > 0
          Log.log.debug{Log.dump(:connect_version, connect_info)}
        rescue StandardError => e # Errno::ECONNREFUSED
          start_url = CONNECT_START_URIS[method_index]
          method_index += 1
          raise StandardError, "Unable to start connect #{method_index} times" if start_url.nil?
          Log.log.warn{"Aspera Connect is not started (#{e}). Trying to start it ##{method_index}..."}
          if !OpenApplication.uri_graphical(start_url)
            OpenApplication.uri_graphical('https://www.ibm.com/aspera/connect/')
            raise StandardError, 'Connect is not installed'
          end
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
      end

      def start_transfer(transfer_spec, token_regenerator: nil)
        if transfer_spec['direction'] == 'send'
          Log.log.warn{"Connect requires upload selection using GUI, ignoring #{transfer_spec['paths']}".red}
          transfer_spec.delete('paths')
          selection = @connect_api.create('windows/select-open-file-dialog/', {
            'aspera_connect_settings' => @connect_settings,
            'title'                   => 'Select Files',
            'suggestedName'           => '',
            'allowMultipleSelection'  => true,
            'allowedFileTypes'        => ''})[:data]
          transfer_spec['paths'] = selection['dataTransfer']['files'].map { |i| {'source' => i['name']}}
        end
        @request_id = SecureRandom.uuid
        # if there is a token, we ask connect client to use well known ssh private keys
        # instead of asking password
        transfer_spec['authentication'] = 'token' if transfer_spec.key?('token')
        connect_transfer_args = {
          'aspera_connect_settings' => @connect_settings.merge({
            'request_id'    => @request_id,
            'allow_dialogs' => true
          }),
          'transfer_specs'          => [{
            'transfer_spec' => transfer_spec
          }]}
        # asynchronous anyway
        res = @connect_api.create('transfers/start', connect_transfer_args)[:data]
        @xfer_id = res['transfer_specs'].first['transfer_spec']['tags'][Fasp::TransferSpec::TAG_RESERVED]['xfer_id']
      end

      def wait_for_transfers_completion
        connect_activity_args = {'aspera_connect_settings' => @connect_settings}
        started = false
        pre_calc = false
        session_id = @xfer_id
        begin
          loop do
            tr_info = @connect_api.create("transfers/info/#{@xfer_id}", connect_activity_args)[:data]
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
    end # AgentConnect
  end
end
