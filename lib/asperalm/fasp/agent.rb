require 'asperalm/fasp/installation'
require 'asperalm/fasp/resumer'
require 'asperalm/fasp/manager'
require 'securerandom'

module Asperalm
  module Fasp
    # for CLI allows specification of different transfer agents
    # supports 3 modes to start a transfer:
    # - ascp : executes ascp process
    # - node : use the node API
    # - connect : use the connect client
    class Fasp::Agent
      # mode=connect : activate
      attr_accessor :use_connect_client
      # mode=connect : application identifier used in connect API
      attr_accessor :connect_app_id
      # mode=node : activate, set to the REST api object for the node API
      attr_accessor :tr_node_api
      def initialize
        @use_connect_client=false
        @tr_node_api=nil
        @connect_app_id='localapp'
      end

      def start_transfer_connect(transfer_spec)
        raise "Using connect requires a graphical environment" if !OperatingSystem.default_gui_mode.eql?(:graphical)
        trynumber=0
        begin
          Log.log.debug("reading connect port file")
          connect_url=File.open(Installation.instance.path(:plugin_https_port_file)) {|f| f.gets }.strip
          connect_api=Rest.new("#{connect_url}/v5/connect",{})
          connect_api.read('info/version')
        rescue => e # Errno::ECONNREFUSED
          raise CliError,"Unable to start connect after #{trynumber} try" if trynumber > 3
          Log.log.warn("connect is not started, trying to start (#{trynumber}) : #{e}")
          trynumber+=1
          OperatingSystem.open_uri_graphical('fasp://initialize')
          sleep 2
          retry
        end
        if transfer_spec["direction"] == "send"
          Log.log.warn("Connect requires upload selection using GUI, ignoring #{transfer_spec['paths']}".red)
          transfer_spec.delete('paths')
          resdata=connect_api.create('windows/select-open-file-dialog/',{"title"=>"Select Files","suggestedName"=>"","allowMultipleSelection"=>true,"allowedFileTypes"=>"","aspera_connect_settings"=>{"app_id"=>@connect_app_id}})[:data]
          transfer_spec['paths']=resdata['dataTransfer']['files'].map { |i| {'source'=>i['name']}}
        end
        request_id=SecureRandom.uuid
        #transfer_spec['authentication']="token" if transfer_spec.has_key?('token')
        connect_transfer_args={
          'transfer_specs'=>[{
          'transfer_spec'=>transfer_spec,
          'aspera_connect_settings'=>{
          'allow_dialogs'=>true,
          'app_id'=>@connect_app_id,
          'request_id'=>request_id
          }}]}
        connect_api.create('transfers/start',connect_transfer_args)
        connect_activity_args={'aspera_connect_settings'=>{'app_id'=>@connect_app_id}}
        started=false
        loop do
          result=connect_api.create('transfers/activity',connect_activity_args)[:data]
          if result['transfers']
            trdata=result['transfers'].select{|i| i['aspera_connect_settings'] and i['aspera_connect_settings']['request_id'].eql?(request_id)}.first
            case trdata['status']
            when 'completed'
              Manager.instance.notify_listeners("emulated",{'Type'=>'DONE'})
              break
            when 'initiating'
              puts 'starting'
            when 'running'
              #puts "running: sessions:#{trdata["sessions"].length}, #{trdata["sessions"].map{|i| i['bytes_transferred']}.join(',')}"
              if !started and trdata["bytes_expected"] != 0
                Manager.instance.notify_listeners("emulated",{'Type'=>'NOTIFICATION','PreTransferBytes'=>trdata["bytes_expected"]})
                started=true
              else
                Manager.instance.notify_listeners("emulated",{'Type'=>'STATS','Bytescont'=>trdata["bytes_written"]})
              end
            else
              raise Fasp::Error.new("#{trdata['status']}: #{trdata['error_desc']}")
            end
          end
          sleep 1
        end
      end

      def start_transfer_node(transfer_spec)
        resp=@tr_node_api.call({:operation=>'POST',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:json_params=>transfer_spec})
        puts "id=#{resp[:data]['id']}"
        trid=resp[:data]['id']
        started=false
        # lets emulate management events to display progress bar
        loop do
          trdata=@tr_node_api.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})[:data]
          case trdata['status']
          when 'completed'
            Manager.instance.notify_listeners("emulated",{'Type'=>'DONE'})
            break
          when 'waiting'
            puts 'starting'
          when 'running'
            #puts "running: sessions:#{trdata["sessions"].length}, #{trdata["sessions"].map{|i| i['bytes_transferred']}.join(',')}"
            if !started and trdata["precalc"].is_a?(Hash) and
            trdata["precalc"]["status"].eql?("ready")
              Manager.instance.notify_listeners("emulated",{'Type'=>'NOTIFICATION','PreTransferBytes'=>trdata["precalc"]["bytes_expected"]})
              started=true
            else
              Manager.instance.notify_listeners("emulated",{'Type'=>'STATS','Bytescont'=>trdata["bytes_transferred"]})
            end
          else
            raise Fasp::Error.new("#{trdata['status']}: #{trdata['error_desc']}")
          end
          sleep 1
        end
      end

      # calls sub transfer agent
      # fgaspmanager, or connect, or node
      def start_transfer(transfer_spec)
        Log.log.debug("ts=#{transfer_spec}")
        if (@use_connect_client) # transfer using connect ...
          Log.log.debug("using connect client")
          start_transfer_connect(transfer_spec)
        elsif ! @tr_node_api.nil?
          Log.log.debug("using node api")
          start_transfer_node(transfer_spec)
        else
          Log.log.debug("using ascp")
          Fasp::Resumer.instance.start_transfer(transfer_spec)
        end
        return nil
      end # start_transfer
    end # Fasp::Agent
  end # Fasp
end # Asperalm
