require 'asperalm/fasp/manager'
require 'asperalm/log'
require 'singleton'

module Asperalm
  module Fasp
    class Node < Manager
      include Singleton
      private
      def initialize
        super
        @node_api=nil
        # TODO: currently only supports one transfer
        @transfer_id=nil
      end

      def node_api_
        raise StandardError,"Before using this object, set the node_api attribute to a Asperalm::Rest object" if @node_api.nil?
        return @node_api
      end

      public
      attr_reader :node_api

      def node_api=(new_value)
        if !@node_api.nil? and !new_value.nil?
          Log.log.warn("overriding existing node api value")
        end
        @node_api=new_value
      end

      def start_transfer(transfer_spec,options=nil)
        resp=node_api_.create('ops/transfers',transfer_spec)[:data]
        @transfer_id=resp['id']
        Log.log.debug("tr_id=#{@transfer_id}")
      end

      def wait_for_transfers_completion
        started=false
        # lets emulate management events to display progress bar
        loop do
          trdata=node_api_.read("ops/transfers/#{@transfer_id}")[:data]
          case trdata['status']
          when 'completed'
            notify_listeners("emulated",{'Type'=>'DONE'})
            break
          when 'waiting','partially_completed'
            puts trdata['status']
          when 'running'
            #puts "running: sessions:#{trdata["sessions"].length}, #{trdata["sessions"].map{|i| i['bytes_transferred']}.join(',')}"
            if !started and trdata["precalc"].is_a?(Hash) and
            trdata["precalc"]["status"].eql?("ready")
              notify_listeners("emulated",{'Type'=>'NOTIFICATION','PreTransferBytes'=>trdata["precalc"]["bytes_expected"]})
              started=true
            else
              notify_listeners("emulated",{'Type'=>'STATS','Bytescont'=>trdata["bytes_transferred"]})
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
