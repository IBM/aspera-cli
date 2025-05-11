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
      def initialize(**base_options)
        super
        @transfer_id = nil
        @connect_settings = {
          'app_id' => SecureRandom.uuid
        }
        raise 'Using connect requires a graphical environment' if !Environment.default_gui_mode.eql?(:graphical)
        method_index = 0
        begin
          connect_url = connect_api_url
          Log.log.debug{"found: #{connect_url}"}
          @connect_api = Rest.new(
            base_url: "#{connect_url}/v5/connect", # could use v6 also now
            headers: {'Origin' => RestParameters.instance.user_agent})
          connect_info = @connect_api.read('info/version')
          Log.log.info('Connect was reached') if method_index > 0
          Log.log.debug{Log.dump(:connect_version, connect_info)}
        rescue StandardError => e # Errno::ECONNREFUSED
          Log.log.debug{"Exception: #{e}"}
          start_url = CONNECT_START_URIS[method_index]
          method_index += 1
          raise StandardError, "Unable to start connect #{method_index} times" if start_url.nil?
          Log.log.warn{"Aspera Connect is not started (#{e}). Trying to start it ##{method_index}..."}
          if !Environment.open_uri_graphical(start_url)
            Environment.open_uri_graphical('https://www.ibm.com/aspera/connect/')
            raise StandardError, 'Connect is not installed'
          end
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
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
            'allowedFileTypes'        => ''})
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
          }]}
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
                notify_progress(:pre_start, session_id: nil, info: transfer['status'])
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
                notify_progress(:end, session_id: @transfer_id)
                break
              when 'failed'
                notify_progress(:end, session_id: @transfer_id)
                raise Transfer::Error, transfer['error_desc']
              when 'cancelled'
                notify_progress(:end, session_id: @transfer_id)
                raise Transfer::Error, 'Transfer cancelled by user'
              else
                notify_progress(:end, session_id: @transfer_id)
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

      private

      # @return the file path of local connect where API's URI can be read
      def connect_api_url
        connect_locations = Products::Other.find(Products::Connect.locations).first
        raise "Product: #{name} not found, please install." if connect_locations.nil?
        folder = File.join(connect_locations[:run_root], 'var', 'run')
        ['', 's'].each do |ext|
          uri_file = File.join(folder, "http#{ext}.uri")
          Log.log.debug{"checking connect port file: #{uri_file}"}
          if File.exist?(uri_file)
            return File.open(uri_file, &:gets).strip
          end
        end
        raise "no connect uri file found in #{folder}"
      end
    end
  end
end
