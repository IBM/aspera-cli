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
      public
      attr_writer :node_api

      def node_api
        raise StandardError,"Before using this object, set the node_api attribute to a Asperalm::Rest object" unless @node_api.is_a?(Asperalm::Rest)
        return @node_api
      end

      def start_transfer(transfer_spec,options=nil)
        resp=node_api.create('ops/transfers',transfer_spec)[:data]
        @transfer_id=resp['id']
        Log.log.debug("tr_id=#{@transfer_id}")
      end

      def wait_for_transfers_completion
        started=false
        # lets emulate management events to display progress bar
        loop do
          trdata=node_api.read("ops/transfers/#{@transfer_id}")[:data]
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
