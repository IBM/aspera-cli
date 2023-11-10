# frozen_string_literal: true

require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/node'
require 'aspera/log'
require 'aspera/oauth'

module Aspera
  module Fasp
    # this singleton class is used by the CLI to provide a common interface to start a transfer
    # before using it, the use must set the `node_api` member.
    class AgentNode < Aspera::Fasp::AgentBase
      # option include: root_id if the node is an access key
      attr_writer :options

      def initialize(options)
        raise 'node specification must be Hash' unless options.is_a?(Hash)
        super(options)
        %i[url username password].each { |k| raise "missing parameter [#{k}] in node specification: #{options}" unless options.key?(k) }
        # root id is required for access key
        @root_id = options[:root_id]
        rest_params = { base_url: options[:url]}
        if Oauth.bearer?(options[:password])
          raise 'root_id is required for access key' if @root_id.nil?
          rest_params[:headers] = Aspera::Node.bearer_headers(options[:password], access_key: options[:username])
        else
          rest_params[:auth] = {
            type:     :basic,
            username: options[:username],
            password: options[:password]
          }
        end
        @node_api = Rest.new(rest_params)
        # TODO: currently only supports one transfer. This is bad shortcut. but ok for CLI.
        @transfer_id = nil
        Log.dump(:agent_options, @options)
      end

      # used internally to ensure node api is set before using.
      def node_api_
        raise StandardError, 'Before using this object, set the node_api attribute to a Aspera::Rest object' if @node_api.nil?
        return @node_api
      end
      # use this to read the node_api end point.
      attr_reader :node_api

      # use this to set the node_api end point before using the class.
      def node_api=(new_value)
        if !@node_api.nil? && !new_value.nil?
          Log.log.warn('overriding existing node api value')
        end
        @node_api = new_value
      end

      # generic method
      def start_transfer(transfer_spec, token_regenerator: nil)
        # add root id if access key
        if !@root_id.nil?
          case transfer_spec['direction']
          when Fasp::TransferSpec::DIRECTION_SEND then transfer_spec['source_root_id'] = @root_id
          when Fasp::TransferSpec::DIRECTION_RECEIVE then transfer_spec['destination_root_id'] = @root_id
          else raise "unexpected direction in ts: #{transfer_spec['direction']}"
          end
        end
        # manage special additional parameter
        if transfer_spec.key?('EX_ssh_key_paths') && transfer_spec['EX_ssh_key_paths'].is_a?(Array) && !transfer_spec['EX_ssh_key_paths'].empty?
          # not standard, so place standard field
          if transfer_spec.key?('ssh_private_key')
            Log.log.warn('Both ssh_private_key and EX_ssh_key_paths are present, using ssh_private_key')
          else
            Log.log.warn('EX_ssh_key_paths has multiple keys, using first one only') unless transfer_spec['EX_ssh_key_paths'].length.eql?(1)
            transfer_spec['ssh_private_key'] = File.read(transfer_spec['EX_ssh_key_paths'].first)
            transfer_spec.delete('EX_ssh_key_paths')
          end
        end
        # add mandatory retry parameter for node api
        ts_tags = transfer_spec['tags']
        if ts_tags.is_a?(Hash) && ts_tags[Fasp::TransferSpec::TAG_RESERVED].is_a?(Hash)
          ts_tags[Fasp::TransferSpec::TAG_RESERVED]['xfer_retry'] ||= 150
        end
        # Optimization in case of sending to the same node
        # TODO: probably remove this, as /etc/hosts shall be used for that
        if !transfer_spec['wss_enabled'] && transfer_spec['remote_host'].eql?(URI.parse(node_api_.params[:base_url]).host)
          transfer_spec['remote_host'] = '127.0.0.1'
        end
        resp = node_api_.create('ops/transfers', transfer_spec)[:data]
        @transfer_id = resp['id']
        Log.log.debug{"tr_id=#{@transfer_id}"}
        return @transfer_id
      end

      # generic method
      def wait_for_transfers_completion
        # set to true when we know the total size of the transfer
        total_size_sent = false
        session_started = false
        bytes_expected = nil
        # lets emulate management events to display progress bar
        loop do
          # status is empty sometimes with status 200...
          transfer_data = node_api_.read("ops/transfers/#{@transfer_id}")[:data] || {'status' => 'unknown'} rescue {'status' => 'waiting(api error)'}
          case transfer_data['status']
          when 'waiting', 'partially_completed', 'unknown', 'waiting(read error)'
            notify_progress(session_id: nil, type: :pre_start, info: transfer_data['status'])
          when 'running'
            if !session_started
              notify_progress(session_id: @transfer_id, type: :session_start)
              session_started = true
            end
            message = transfer_data['status']
            message = "#{message} (#{transfer_data['error_desc']})" if !transfer_data['error_desc']&.empty?
            notify_progress(session_id: nil, type: :pre_start, info: message)
            if !total_size_sent &&
                transfer_data['precalc'].is_a?(Hash) &&
                transfer_data['precalc']['status'].eql?('ready')
              bytes_expected = transfer_data['precalc']['bytes_expected']
              notify_progress(type: :session_size, session_id: @transfer_id, info: bytes_expected)
              total_size_sent = true
            end
            notify_progress(type: :transfer, session_id: @transfer_id, info: transfer_data['bytes_transferred'])
          when 'completed'
            notify_progress(type: :transfer, session_id: @transfer_id, info: bytes_expected) if bytes_expected
            notify_progress(type: :end, session_id: @transfer_id)
            break
          when 'failed'
            notify_progress(type: :end, session_id: @transfer_id)
            # Bug in HSTS ? transfer is marked failed, but there is no reason
            break if transfer_data['error_code'].eql?(0) && transfer_data['error_desc'].empty?
            raise Fasp::Error, "status: #{transfer_data['status']}. code: #{transfer_data['error_code']}. description: #{transfer_data['error_desc']}"
          else
            Log.log.warn{"transfer_data -> #{transfer_data}"}
            raise Fasp::Error, "status: #{transfer_data['status']}. code: #{transfer_data['error_code']}. description: #{transfer_data['error_desc']}"
          end
          sleep(1.0)
        end
        # TODO: get status of sessions
        return []
      end
    end
  end
end
