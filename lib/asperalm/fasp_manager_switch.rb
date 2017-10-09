require 'asperalm/connect'

module Asperalm
  # listener for FASP transfers (debug)
  class FaspListenerProgress < FileTransferListener
    def initialize
      @progress=nil
    end

    def event(data)
      if data['type'].eql?('NOTIFICATION') and data.has_key?('pre_transfer_bytes') then
        require 'ruby-progressbar'
        @progress=ProgressBar.create(:title => 'progress', :total => data['pre_transfer_bytes'].to_i)
      end
      if data['type'].eql?('STATS') and !@progress.nil? then
        @progress.progress=data['TransferBytes'].to_i
      end
      if data['type'].eql?('DONE') and ! @progress.nil? then
        @progress.progress=@progress.total
        @progress=nil
      end
    end
  end

  # for CLI allows specification of different transfer agents
  # supports 3 modes to start a transfer:
  # - ascp : executes ascp process
  # - node : use the node API
  # - connect : use the connect client
  class FaspManagerSwitch
    # a global transfer spec that overrides values in transfer spec provided on start
    @@ts_override={}

    # returns ruby data
    def self.ts_override
      return @@ts_override
    end
    # mode=connect : activate
    attr_accessor :use_connect_client
    # mode=connect : application identifier used in connect API
    attr_accessor :connect_app_id
    # mode=node : activate, set to the REST api object for the node API
    attr_accessor :tr_node_api

    def initialize(real_fasp_manager)
      @use_connect_client=false
      @tr_node_api=nil
      @connect_app_id='localapp'
      @real_fasp_manager=real_fasp_manager
    end

    # calls sub transfer agent
    # fgaspmanager, or connect, or node
    def start_transfer(transfer_spec)
      transfer_spec.merge!(self.class.ts_override)
      Log.log.debug("ts=#{transfer_spec}")
      if (@use_connect_client) # transfer using connect ...
        Log.log.debug("using connect client")
        raise "Using connect requires a graphical environment" if !OperatingSystem.default_gui_mode.eql?(:graphical)
        connect_url=File.open(Connect.path(:plugin_https_port_file)) {|f| f.gets }.strip
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
          res=connect_api.create('windows/select-open-file-dialog/',{"title"=>"Select Files","suggestedName"=>"","allowMultipleSelection"=>true,"allowedFileTypes"=>"","aspera_connect_settings"=>{"app_id"=>@connect_app_id}})
          transfer_spec['paths']=res[:data]['dataTransfer']['files'].map { |i| {'source'=>i['name']}}
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
      elsif ! @tr_node_api.nil?
        #transfer_spec['destination_root']='/tmp'
        resp=@tr_node_api.call({:operation=>'POST',:subpath=>'ops/transfers',:headers=>{'Accept'=>'application/json'},:json_params=>transfer_spec})
        puts "id=#{resp[:data]['id']}"
        trid=resp[:data]['id']
        #Log.log.error resp.to_s
        loop do
          res=@tr_node_api.call({:operation=>'GET',:subpath=>'ops/transfers/'+trid,:headers=>{'Accept'=>'application/json'}})
          puts "transfer: #{res[:data]['status']}, sessions:#{res[:data]["sessions"].length}, #{res[:data]["sessions"].map{|i| i['bytes_transferred']}.join(',')}"
          break if ! ( res[:data]['status'].eql?('waiting') or res[:data]['status'].eql?('running'))
          sleep 1
        end
        if ! res[:data]['status'].eql?('completed')
          raise TransferError.new("#{res[:data]['status']}: #{res[:data]['error_desc']}")
        end
        #raise "TODO: wait for transfer completion"
      else
        Log.log.debug("using ascp")
        # if not provided, use standard key
        if !transfer_spec.has_key?('EX_ssh_key_value') and
        !transfer_spec.has_key?('EX_ssh_key_paths') and
        transfer_spec.has_key?('token')
          transfer_spec['EX_ssh_key_paths'] = [ Connect.path(:ssh_bypass_key_dsa), Connect.path(:ssh_bypass_key_rsa) ]
        end
        # add fallback cert and key
        if transfer_spec.has_key?('http_fallback') and ['1','force'].include?(transfer_spec['http_fallback'])
          transfer_spec['EX_fallback_key']=Connect.path(:fallback_key)
          transfer_spec['EX_fallback_cert']=Connect.path(:fallback_cert)
        end
        @real_fasp_manager.start_transfer(transfer_spec)
      end
      return nil
    end # start_transfer
  end # FaspManagerSwitch
end # AsperaLm
