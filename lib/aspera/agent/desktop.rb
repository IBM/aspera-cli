# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/rest'
require 'aspera/environment'
require 'aspera/json_rpc/client'
require 'aspera/products/desktop'
require 'aspera/transfer/spec'
require 'securerandom'

module Aspera
  module Agent
    # Client: Aspera for Desktop
    class Desktop < Base
      # try twice the main init url in sequence
      START_URIS = ['aspera://', 'aspera://', 'aspera://']
      # delay between each try to start the app
      SLEEP_SEC_BETWEEN_RETRY = 5
      private_constant :START_URIS, :SLEEP_SEC_BETWEEN_RETRY

      class << self
        # Re-query a previously started transfer from the Desktop JSON-RPC daemon.
        # agent_params must contain 'application_id'; the JSON-RPC URL is auto-discovered.
        # @return [Hash] normalized status hash
        def transfer_status(transfer_id, agent_params)
          app_id = agent_params['application_id']
          client = Aspera::JsonRpc::Client.new(Aspera::Rest.new(base_url: desktop_api_url))
          raw = client.get_transfer(app_id: app_id, transfer_id: transfer_id)
          normalize_status(raw['status'], bytes: raw['bytes_written'].to_i, error: raw['error_desc'])
        end

        # Normalize a raw status string into the standard async-transfer hash fields.
        def normalize_status(raw_status, bytes: 0, error: nil)
          result = {'bytes_transferred' => bytes}
          case raw_status
          when 'completed'
            result['status'] = 'completed'
            result['ended_at'] = Time.now.utc.iso8601
          when 'failed'
            result.merge!('status' => 'failed', 'ended_at' => Time.now.utc.iso8601, 'error' => error.to_s)
          when 'cancelled'
            result['status'] = 'cancelled'
            result['ended_at'] = Time.now.utc.iso8601
          else
            result['status'] = 'running'
          end
          result
        end

        # Auto-discover the JSON-RPC URL from the Desktop log file (same logic as instance method).
        def desktop_api_url
          log_file = File.join(Products::Other.find(Products::Desktop.locations).first[:log_root], Products::Desktop::LOG_FILENAME)
          url = 'http://127.0.0.1:33024'
          File.open(log_file, 'r') do |file|
            file.each_line do |line|
              line = line.chomp
              url = "http://#{Regexp.last_match(1)}" if line =~ /JSON-RPC server listening on (.*)/
            end
          end if File.exist?(log_file)
          url
        end
      end

      def initialize(**base_options)
        @application_id = SecureRandom.uuid
        @transfer_id = nil
        super
        Aspera.assert(Environment.instance.graphical?, type: Error){'Using client requires a graphical environment'}
        method_index = 0
        begin
          # curl 'http://127.0.0.1:33024/' -X POST -H 'content-type: application/json' --data-raw '{"jsonrpc":"2.0","params":[],"id":999999,"method":"rpc.discover"}'
          # https://playground.open-rpc.org/?schemaUrl=http://127.0.0.1:33024
          @client_app_api = Aspera::JsonRpc::Client.new(Aspera::Rest.new(base_url: aspera_client_api_url))
          client_info = @client_app_api.get_info
          Log.dump(:client_version, client_info)
          Log.log.debug('Client was reached') if method_index > 0
        rescue Errno::ECONNREFUSED => e
          start_url = START_URIS[method_index]
          method_index += 1
          Aspera.assert(!start_url.nil?){"Unable to start #{Products::Desktop::APP_NAME} #{method_index} times"}
          Log.log.warn{"#{Products::Desktop::APP_NAME} is not started (#{e}). Trying to start it ##{method_index}..."}
          Environment.instance.open_uri_graphical(start_url)
          sleep(SLEEP_SEC_BETWEEN_RETRY)
          retry
        end
      end

      # Returns the application_id so callers can persist it in agent_params.
      attr_reader :application_id

      # :reek:UnusedParameters token_regenerator
      def start_transfer(transfer_spec, token_regenerator: nil)
        Transfer::Spec.fix_transferd_resume_policy(transfer_spec)
        @request_id = SecureRandom.uuid
        # if there is a token, we ask the client app to use well known ssh private keys
        # instead of asking password
        transfer_spec['authentication'] = 'token' if transfer_spec.key?('token')
        result = @client_app_api.start_transfer(app_id: @application_id, desktop_spec: {}, transfer_spec: transfer_spec)
        @transfer_id = result['uuid']
      end

      def wait_for_transfers_completion
        started = false
        pre_calc = false
        begin
          loop do
            transfer = @client_app_api.get_transfer(app_id: @application_id, transfer_id: @transfer_id)
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
            sleep(1)
          end
        rescue StandardError => e
          return [e]
        end
        return [:success]
      end

      private

      # Delegate to the class method (avoids duplication).
      def aspera_client_api_url
        self.class.desktop_api_url
      end
    end
  end
end
