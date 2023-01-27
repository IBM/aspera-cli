# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/rest'
require 'aspera/open_application'
require 'securerandom'
require 'tty-spinner'

module Aspera
  module Fasp
    class AgentConnect < Aspera::Fasp::AgentBase
      CONNECT_START_URIS = ['fasp://initialize', 'fasp://initialize', 'aspera-drive://initialize', 'https://test-connect.ibmaspera.com/']
      SLEEP_SEC_BETWEEN_RETRY = 3
      private_constant :CONNECT_START_URIS, :SLEEP_SEC_BETWEEN_RETRY
      def initialize(_options)
        super()
        @connect_settings = {
          'app_id' => SecureRandom.uuid
        }
        raise 'Using connect requires a graphical environment' if !OpenApplication.default_gui_mode.eql?(:graphical)
        method_index = 0
        begin
          connect_url = Installation.instance.connect_uri
          Log.log.debug{"found: #{connect_url}"}
          @connect_api = Rest.new({base_url: "#{connect_url}/v5/connect", headers: {'Origin' => Rest.user_agent}}) # could use v6 also now
          connect_info = @connect_api.read('info/version')[:data]
          Log.log.info('Connect was reached') if method_index > 0
          Log.dump(:connect_version, connect_info)
        rescue StandardError => e # Errno::ECONNREFUSED
          start_url = CONNECT_START_URIS[method_index]
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

      def start_transfer(transfer_spec)
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
        @xfer_id = res['transfer_specs'].first['transfer_spec']['tags']['aspera']['xfer_id']
      end

      def wait_for_transfers_completion
        connect_activity_args = {'aspera_connect_settings' => @connect_settings}
        started = false
        spinner = nil
        begin
          loop do
            tr_info = @connect_api.create("transfers/info/#{@xfer_id}", connect_activity_args)[:data]
            if tr_info['transfer_info'].is_a?(Hash)
              transfer = tr_info['transfer_info']
              if transfer.nil?
                Log.log.warn('no session in Connect')
                break
              end
              # TODO: get session id
              case transfer['status']
              when 'completed'
                notify_end(@connect_settings['app_id'])
                break
              when 'initiating', 'queued'
                if spinner.nil?
                  spinner = TTY::Spinner.new('[:spinner] :title', format: :classic)
                  spinner.start
                end
                spinner.update(title: transfer['status'])
                spinner.spin
              when 'running'
                # puts "running: sessions:#{transfer['sessions'].length}, #{transfer['sessions'].map{|i| i['bytes_transferred']}.join(',')}"
                if !started && (transfer['bytes_expected'] != 0)
                  spinner&.success
                  notify_begin(@connect_settings['app_id'], transfer['bytes_expected'])
                  started = true
                else
                  notify_progress(@connect_settings['app_id'], transfer['bytes_written'])
                end
              when 'failed'
                spinner&.error
                raise Fasp::Error, transfer['error_desc']
              else
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
