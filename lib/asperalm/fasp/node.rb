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
      end
      public
      attr_accessor :node_api

      def start_transfer(transfer_spec,options=nil)
        #transfer_spec.keys.select{|i|i.start_with?('EX_')}.each{|i|transfer_spec.delete(i)}
        resp=@node_api.call({:operation=>'POST',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:json_params=>transfer_spec})
        puts "id=#{resp[:data]['id']}"
        @transfer_id=resp[:data]['id']
      end

      def shutdown(wait_for_sessions=false)
        started=false
        # lets emulate management events to display progress bar
        loop do
          trdata=@node_api.call({:operation=>'GET',:subpath=>'ops/transfers/'+@transfer_id,:headers=>{'Accept'=>'application/json'}})[:data]
          case trdata['status']
          when 'completed'
            notify_listeners("emulated",{'Type'=>'DONE'})
            break
          when 'waiting'
            puts 'starting'
          when 'running'
            #puts "running: sessions:#{trdata["sessions"].length}, #{trdata["sessions"].map{|i| i['bytes_transferred']}.join(',')}"
            if !started and trdata["precalc"].is_a?(Hash) and
            trdata["precalc"]["status"].eql?("ready")
              notify_listeners("emulated",{'Type'=>'NOTIFICATION','PreTransferBytes'=>trdata["precalc"]["bytes_expected"]})
              started=true
            else
              notify_listeners("emulated",{'Type'=>'STATS','Bytescont'=>trdata["bytes_transferred"]})
            end
          when 'partially_completed'
            puts 'partial'
          else
            Log.log.warn("trdata -> #{trdata}")
            raise Fasp::Error.new("#{trdata['status']}: #{trdata['error_desc']}")
          end
          sleep 1
        end
      end
    end
  end
end

