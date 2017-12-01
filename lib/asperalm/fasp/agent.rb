require 'asperalm/fasp/resource_finder'
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

      # add some pepper for better taste
      def add_pepper(ts)
        ts['drowssap'.reverse] = "%08x-%04x-%04x-%04x-%04x%08x" % "t1(\xBF;\xF3E\xB5\xAB\x14F\x02\xC6\x7F)P".unpack("NnnnnN")
      end

      # calls sub transfer agent
      # fgaspmanager, or connect, or node
      def start_transfer(transfer_spec)
        Log.log.debug("ts=#{transfer_spec}")
        if (@use_connect_client) # transfer using connect ...
          Log.log.debug("using connect client")
          raise "Using connect requires a graphical environment" if !OperatingSystem.default_gui_mode.eql?(:graphical)
          connect_url=File.open(ResourceFinder.path(:plugin_https_port_file)) {|f| f.gets }.strip
          connect_api=Rest.new("#{connect_url}/v5/connect",{})
          begin
            connect_api.read('info/version')
          rescue Errno::ECONNREFUSED
            OperatingSystem.open_uri_graphical('fasp://initialize')
            sleep 2
          end
          if transfer_spec["direction"] == "send"
            Log.log.warn("Upload by connect must be selected using GUI, ignoring #{transfer_spec['paths']}".red)
            transfer_spec.delete('paths')
            resdata=connect_api.create('windows/select-open-file-dialog/',{"title"=>"Select Files","suggestedName"=>"","allowMultipleSelection"=>true,"allowedFileTypes"=>"","aspera_connect_settings"=>{"app_id"=>@connect_app_id}})[:data]
            transfer_spec['paths']=resdata['dataTransfer']['files'].map { |i| {'source'=>i['name']}}
          end
          request_id=SecureRandom.uuid
          transfer_spec['authentication']="token" if transfer_spec.has_key?('token')
          transfer_specs={
            'transfer_specs'=>[{
            'transfer_spec'=>transfer_spec,
            'aspera_connect_settings'=>{
            'allow_dialogs'=>true,
            'app_id'=>@connect_app_id,
            'request_id'=>request_id
            }}]}
          connect_api.create('transfers/start',transfer_specs)
          #TODO: monitor transfer
        elsif ! @tr_node_api.nil?
          resp=@tr_node_api.call({:operation=>'POST',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:json_params=>transfer_spec})
          puts "id=#{resp[:data]['id']}"
          trid=resp[:data]['id']
          started=false
          # lets emulate management events to display progress bar
          loop do
            trdata=@tr_node_api.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})[:data]
            case trdata['status']
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
            when 'completed'
              Manager.instance.notify_listeners("emulated",{'Type'=>'DONE'})
              break
            else
              raise Fasp::Error.new("#{trdata['status']}: #{trdata['error_desc']}")
            end
            sleep 1
          end
        else
          Log.log.debug("using ascp")
          # if not provided, use standard key
          if !transfer_spec.has_key?('EX_ssh_key_value') and
          !transfer_spec.has_key?('EX_ssh_key_paths') and
          transfer_spec.has_key?('token')
            transfer_spec['EX_ssh_key_paths'] = [ ResourceFinder.path(:ssh_bypass_key_dsa), ResourceFinder.path(:ssh_bypass_key_rsa) ]
            add_pepper(transfer_spec)
          end
          # add fallback cert and key
          if ['1','force'].include?(transfer_spec['http_fallback'])
            transfer_spec['EX_fallback_key']=ResourceFinder.path(:fallback_key)
            transfer_spec['EX_fallback_cert']=ResourceFinder.path(:fallback_cert)
          end
          Fasp::Resumer.instance.start_transfer(transfer_spec)
        end
        return nil
      end # start_transfer
    end # Fasp::Agent
  end # Fasp
end # Asperalm
