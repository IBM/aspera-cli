require 'aspera/fasp/agent_base'
require 'aspera/fasp/transfer_spec'
require 'aspera/log'
require 'tty-spinner'

module Aspera
  module Fasp
    # this singleton class is used by the CLI to provide a common interface to start a transfer
    # before using it, the use must set the `node_api` member.
    class AgentNode < AgentBase
      # option include: root_id if the node is an access key
      attr_writer :options
      def initialize(options)
        raise "node specification must be Hash" unless options.is_a?(Hash)
        [:url,:username,:password].each { |k| raise "missing parameter [#{k}] in node specification: #{options}" unless options.has_key?(k) }
        super()
        # root id is required for access key
        @root_id=options[:root_id]
        rest_params={ base_url: options[:url]}
        if options[:password].match(/^Bearer /)
          rest_params[:headers]={
            'X-Aspera-AccessKey'=>options[:username],
            'Authorization'     =>options[:password]
          }
          raise "root_id is required for access key" if @root_id.nil?
        else
          rest_params[:auth]={
            type:     :basic,
            username: options[:username],
            password: options[:password]
          }
        end
        @node_api=Rest.new(rest_params)
        # TODO: currently only supports one transfer. This is bad shortcut. but ok for CLI.
        @transfer_id=nil
      end

      # used internally to ensure node api is set before using.
      def node_api_
        raise StandardError,'Before using this object, set the node_api attribute to a Aspera::Rest object' if @node_api.nil?
        return @node_api
      end
      # use this to read the node_api end point.
      attr_reader :node_api

      # use this to set the node_api end point before using the class.
      def node_api=(new_value)
        if !@node_api.nil? and !new_value.nil?
          Log.log.warn('overriding existing node api value')
        end
        @node_api=new_value
      end

      # generic method
      def start_transfer(transfer_spec,options=nil)
        # add root id if access key
        if ! @root_id.nil?
          case transfer_spec['direction']
          when Fasp::TransferSpec::DIRECTION_SEND;transfer_spec['source_root_id']=@root_id
          when Fasp::TransferSpec::DIRECTION_RECEIVE;transfer_spec['destination_root_id']=@root_id
          else raise "unexpected direction in ts: #{transfer_spec['direction']}"
          end
        end
        # manage special additional parameter
        if transfer_spec.has_key?('EX_ssh_key_paths') and transfer_spec['EX_ssh_key_paths'].is_a?(Array) and !transfer_spec['EX_ssh_key_paths'].empty?
          # not standard, so place standard field
          if transfer_spec.has_key?('ssh_private_key')
            Log.log.warn('Both ssh_private_key and EX_ssh_key_paths are present, using ssh_private_key')
          else
            Log.log.warn('EX_ssh_key_paths has multiple keys, using first one only') unless transfer_spec['EX_ssh_key_paths'].length.eql?(1)
            transfer_spec['ssh_private_key']=File.read(transfer_spec['EX_ssh_key_paths'].first)
            transfer_spec.delete('EX_ssh_key_paths')
          end
        end
        if transfer_spec['tags'].is_a?(Hash) and transfer_spec['tags']['aspera'].is_a?(Hash)
          transfer_spec['tags']['aspera']['xfer_retry']||=150
        end
        # optimisation in case of sending to the same node
        if transfer_spec['remote_host'].eql?(URI.parse(node_api_.params[:base_url]).host)
          transfer_spec['remote_host']='localhost'
        end
        resp=node_api_.create('ops/transfers',transfer_spec)[:data]
        @transfer_id=resp['id']
        Log.log.debug("tr_id=#{@transfer_id}")
        return @transfer_id
      end

      # generic method
      def wait_for_transfers_completion
        started=false
        spinner=nil
        # lets emulate management events to display progress bar
        loop do
          # status is empty sometimes with status 200...
          trdata=node_api_.read("ops/transfers/#{@transfer_id}")[:data] || {"status"=>"unknown"} rescue {"status"=>"waiting(read error)"}
          case trdata['status']
          when 'completed'
            notify_end(@transfer_id)
            break
          when 'waiting','partially_completed','unknown','waiting(read error)'
            if spinner.nil?
              spinner = TTY::Spinner.new("[:spinner] :title", format: :classic)
              spinner.start
            end
            spinner.update(title: trdata['status'])
            spinner.spin
            #puts trdata
          when 'running'
            #puts "running: sessions:#{trdata["sessions"].length}, #{trdata["sessions"].map{|i| i['bytes_transferred']}.join(',')}"
            if !started and trdata['precalc'].is_a?(Hash) and
            trdata['precalc']['status'].eql?('ready')
              notify_begin(@transfer_id,trdata['precalc']['bytes_expected'])
              started=true
            else
              notify_progress(@transfer_id,trdata['bytes_transferred'])
            end
          else
            Log.log.warn("trdata -> #{trdata}")
            raise Fasp::Error.new("#{trdata['status']}: #{trdata['error_desc']}")
          end
          sleep 1
        end
        #TODO get status of sessions
        return []
      end
    end
  end
end
