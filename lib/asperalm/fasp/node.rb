require 'asperalm/fasp/manager'
require 'asperalm/log'
require 'singleton'
require 'tty-spinner'

module Asperalm
  module Fasp
    # this singleton class is used by the CLI to provide a common interface to start a transfer
    # before using it, the use must set the `node_api` member.
    class Node < Manager
      include Singleton
      private
      def initialize
        super
        @node_api=nil
        # TODO: currently only supports one transfer. This is bad shortcut. but ok for CLI.
        @transfer_id=nil
      end

      # used internally to ensure node api is set before using.
      def node_api_
        raise StandardError,'Before using this object, set the node_api attribute to a Asperalm::Rest object' if @node_api.nil?
        return @node_api
      end

      public
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
            notify_listeners('emulated',{'Type'=>'DONE'})
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
              notify_listeners('emulated',{'Type'=>'NOTIFICATION','PreTransferBytes'=>trdata['precalc']['bytes_expected']})
              started=true
            else
              notify_listeners('emulated',{'Type'=>'STATS','Bytescont'=>trdata['bytes_transferred']})
            end
          else
            Log.log.warn("trdata -> #{trdata}")
            raise Fasp::Error.new("#{trdata['status']}: #{trdata['error_desc']}")
          end
          sleep 1
        end
        return [] #TODO
      end
    end
  end
end
