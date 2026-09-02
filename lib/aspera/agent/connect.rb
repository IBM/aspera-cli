# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/products/connect'
require 'aspera/products/other'
require 'aspera/rest'
require 'aspera/environment'
require 'securerandom'

module Aspera
  module Agent
    class Connect < Base
      # try twice the main init url in sequence
      CONNECT_START_URIS = ['fasp://initialize', 'fasp://initialize', 'aspera-drive://initialize', 'https://test-connect.ibmaspera.com/']
      # delay between each try to start connect
      SLEEP_SEC_BETWEEN_RETRY = 5
      private_constant :CONNECT_START_URIS, :SLEEP_SEC_BETWEEN_RETRY

      class << self
        # Re-query a previously started transfer via the Connect REST API.
        # agent_params must contain 'app_id'; the Connect URL is auto-discovered.
        # @return [Hash] normalized status hash
        def transfer_status(transfer_id, agent_params)
          connect_api = Rest.new(
            base_url: "#{connect_api_url}/v5/connect",
            headers:  {'Origin' => RestParameters.instance.user_agent}
          )
          tr_info = connect_api.create("transfers/info/#{transfer_id}", {'aspera_connect_settings' => {'app_id' => agent_params['app_id']}})
          transfer = tr_info['transfer_info']
          return {'status' => 'running', 'bytes_transferred' => 0} unless transfer.is_a?(Hash)
          normalize_status(transfer)
        end

        # Normalize a Connect transfer_info hash into the standard async-transfer fields.
        def normalize_status(transfer)
          result = {'bytes_transferred' => transfer['bytes_written'].to_i}
          case transfer['status']
          when 'completed'
            result['status'] = 'completed'
            result['ended_at'] = Time.now.utc.iso8601
          when 'failed'
            result.merge!('status' => 'failed', 'ended_at' => Time.now.utc.iso8601, 'error' => transfer['error_desc'].to_s)
          when 'cancelled'
            result['status'] = 'cancelled'
            result['ended_at'] = Time.now.utc.iso8601
          else
            result['status'] = 'running'
          end
          result
        end

        # Auto-discover the Connect API base URL from its local URI file.
        def connect_api_url
          folder = File.join(Products::Other.find(Products::Connect.locations).first[:run_root], 'var', 'run')
          ['', 's'].each do |ext|
            uri_file = File.join(folder, "http#{ext}.uri")
            return File.open(uri_file, &:gets).strip if File.exist?(uri_file)
          end
          raise "no connect uri file found in #{folder}"
        end
      end

      def initialize(**base_options)
        super
        @transfer_id = nil
        @connect_settings = {
          'app_id' => SecureRandom.uuid
        }
        Aspera.assert(Environment.instance.graphical?, type: Error){'Using connect requires a graphical environment'}
        method_index = 0
        begin
          # raise exception if connect not started and file does not exist
          connect_url = self.class.connect_api_url
          Log.log.debug{"found: #{connect_url}"}
          @connect_api = Rest.new(
            base_url: "#{connect_url}/v5/connect", # could use v6 also now
            headers: {'Origin' => RestParameters.instance.user_agent}
          )
          connect_info = @connect_api.read('info/version')
          Log.log.debug('Connect was reached') if method_index > 0
          Log.dump(:connect_version, connect_info)
        rescue StandardError => e # Errno::ECONNREFUSED
          Log.log.debug{"Exception: #{e}"}
          start_url = CONNECT_START_URIS[method_index]
          method_index += 1
          Aspera.assert(!start_url.nil?){"Unable to start connect #{method_index} times"}
          Log.log.warn{"Aspera Connect is not started (#{e}). Trying to start it ##{method_index}..."}
          Environment.instance.open_uri_graphical(start_url)
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
      end

      # Returns the app_id so callers can persist it in agent_params.
      def app_id
        @connect_settings['app_id']
      end

      # :reek:UnusedParameters token_regenerator
      def start_transfer(transfer_spec, token_regenerator: nil)
        if transfer_spec['direction'] == 'send'
          Log.log.warn{"Connect requires upload selection using GUI, ignoring #{transfer_spec['paths']}".red}
          transfer_spec.delete('paths')
          selection = @connect_api.create('windows/select-open-file-dialog/', {
            'aspera_connect_settings' => @connect_settings,
            'title'                   => 'Select Files',
            'suggestedName'           => '',
            'allowMultipleSelection'  => true,
            'allowedFileTypes'        => ''
          })
          transfer_spec['paths'] = selection['dataTransfer']['files'].map{ |i| {'source' => i['name']}}
        end
        # if there is a token, we ask connect client to use well known ssh private keys
        # instead of asking password
        transfer_spec['authentication'] = 'token' if transfer_spec.key?('token')
        connect_transfer_args = {
          'aspera_connect_settings' => @connect_settings.merge({
            'request_id'    => SecureRandom.uuid,
            'allow_dialogs' => true
          }),
          'transfer_specs'          => [{
            'transfer_spec' => transfer_spec
          }]
        }
        # asynchronous anyway
        res = @connect_api.create('transfers/start', connect_transfer_args)
        @transfer_id = res['transfer_specs'].first['transfer_spec']['tags'][Transfer::Spec::TAG_RESERVED]['xfer_id']
      end

      def wait_for_transfers_completion
        connect_activity_args = {'aspera_connect_settings' => @connect_settings}
        started = false
        pre_calc = false
        begin
          loop do
            tr_info = @connect_api.create("transfers/info/#{@transfer_id}", connect_activity_args)
            Log.dump(:tr_info, tr_info, level: :trace1)
            if tr_info['transfer_info'].is_a?(Hash)
              transfer = tr_info['transfer_info']
              if transfer.nil?
                Log.log.warn('no session in Connect')
                break
              end
              # TODO: get session id
              case transfer['status']
              when 'initiating', 'queued'
                notify_progress(:sessions_init, info: transfer['status'])
              when 'running'
                if !started
                  notify_progress(:session_start, session_id: @transfer_id)
                  started = true
                end
                if !pre_calc && (transfer['bytes_expected'] != 0)
                  notify_progress(:session_size, session_id: @transfer_id, info: transfer['bytes_expected'])
                  pre_calc = true
                else
                  notify_progress(:transfer, session_id: @transfer_id, info: transfer['bytes_written'])
                end
              when 'completed'
                notify_progress(:session_end, session_id: @transfer_id)
                notify_progress(:end)
                break
              when 'failed'
                notify_progress(:session_end, session_id: @transfer_id)
                notify_progress(:end)
                raise Transfer::Error, transfer['error_desc']
              when 'cancelled'
                notify_progress(:session_end, session_id: @transfer_id)
                notify_progress(:end)
                raise Transfer::Error, 'Transfer cancelled by user'
              else
                notify_progress(:session_end, session_id: @transfer_id)
                notify_progress(:end)
                raise Transfer::Error, "unknown status: #{transfer['status']}: #{transfer['error_desc']}"
              end
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
