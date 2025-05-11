# frozen_string_literal: true

# cspell:ignore precalc
require 'aspera/agent/base'
require 'aspera/transfer/spec'
require 'aspera/api/node'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/oauth'

module Aspera
  module Agent
    # this singleton class is used by the CLI to provide a common interface to start a transfer
    # before using it, the use must set the `node_api` member.
    class Node < Base
      # @param url          [String] the base url of the node api
      # @param username     [String] the username to use for the node api
      # @param password     [String] the password to use for the node api
      # @param root_id      [String] root file id if the node is an access key
      # @param base_options [Hash] options for base class
      def initialize(
        url:,
        username:,
        password:,
        root_id: nil,
        **base_options
      )
        super(**base_options)
        # root id is required for access key
        @root_id = root_id
        rest_params = {base_url: url}
        if OAuth::Factory.bearer?(password)
          Aspera.assert(!@root_id.nil?){'root_id not allowed for access key'}
          rest_params[:headers] = Api::Node.bearer_headers(password, access_key: username)
        else
          rest_params[:auth] = {
            type:     :basic,
            username: username,
            password: password
          }
        end
        @node_api = Rest.new(**rest_params)
        # TODO: currently only supports one transfer. This is bad shortcut. but ok for CLI.
        @transfer_id = nil
      end

      # generic method
      # :reek:UnusedParameters token_regenerator
      def start_transfer(transfer_spec, token_regenerator: nil)
        # add root id if access key
        if !@root_id.nil?
          case transfer_spec['direction']
          when Transfer::Spec::DIRECTION_SEND then transfer_spec['source_root_id'] = @root_id
          when Transfer::Spec::DIRECTION_RECEIVE then transfer_spec['destination_root_id'] = @root_id
          else Aspera.error_unexpected_value(transfer_spec['direction'])
          end
        end
        # add mandatory retry parameter for node api
        ts_tags = transfer_spec['tags']
        if ts_tags.is_a?(Hash) && ts_tags[Transfer::Spec::TAG_RESERVED].is_a?(Hash)
          ts_tags[Transfer::Spec::TAG_RESERVED]['xfer_retry'] ||= 150
        end
        # Optimization in case of sending to the same node
        # TODO: probably remove this, as /etc/hosts shall be used for that
        if !transfer_spec['wss_enabled'] && transfer_spec['remote_host'].eql?(URI.parse(node_api_.base_url).host)
          transfer_spec['remote_host'] = '127.0.0.1'
        end
        resp = node_api_.create('ops/transfers', transfer_spec)
        @transfer_id = resp['id']
        Log.log.debug{"tr_id=#{@transfer_id}"}
        return @transfer_id
      end

      # generic method
      def wait_for_transfers_completion
        # set to true when we know the total size of the transfer
        session_started = false
        bytes_expected = nil
        # lets emulate management events to display progress bar
        loop do
          # status is empty sometimes with status 200...
          transfer_data = node_api_.read("ops/transfers/#{@transfer_id}") || {'status' => 'unknown'} rescue {'status' => 'waiting(api error)'}
          case transfer_data['status']
          when 'waiting', 'partially_completed', 'unknown', 'waiting(read error)'
            notify_progress(:pre_start, session_id: nil, info: transfer_data['status'])
          when 'running'
            if !session_started
              notify_progress(:session_start, session_id: @transfer_id)
              session_started = true
            end
            message = transfer_data['status']
            message = "#{message} (#{transfer_data['error_desc']})" if !transfer_data['error_desc']&.empty?
            notify_progress(:pre_start, session_id: nil, info: message)
            if bytes_expected.nil? &&
                transfer_data['precalc'].is_a?(Hash) &&
                transfer_data['precalc']['status'].eql?('ready')
              bytes_expected = transfer_data['precalc']['bytes_expected']
              notify_progress(:session_size, session_id: @transfer_id, info: bytes_expected)
            end
            notify_progress(:transfer, session_id: @transfer_id, info: transfer_data['bytes_transferred'])
          when 'completed'
            notify_progress(:transfer, session_id: @transfer_id, info: bytes_expected) if bytes_expected
            notify_progress(:end, session_id: @transfer_id)
            break
          when 'failed'
            notify_progress(:end, session_id: @transfer_id)
            # Bug in HSTS ? transfer is marked failed, but there is no reason
            break if transfer_data['error_code'].eql?(0) && transfer_data['error_desc'].empty?
            raise Transfer::Error, "status: #{transfer_data['status']}. code: #{transfer_data['error_code']}. description: #{transfer_data['error_desc']}"
          else Aspera.error_unexpected_value(transfer_data['status']){"transfer_data -> #{transfer_data}"}
          end
          sleep(1.0)
        end
        # TODO: get status of sessions
        return []
      end

      private

      # used internally to ensure node api is set before using.
      def node_api_
        Aspera.assert(!@node_api.nil?){'Before using this object, set the node_api attribute to a Aspera::Rest object'}
        return @node_api
      end
    end
  end
end
