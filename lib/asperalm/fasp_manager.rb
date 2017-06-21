#!/bin/echo this is a ruby class:
#
# FASP transfer request
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/log'
require 'asperalm/connect'
require 'socket'
require 'rbconfig'
require 'tempfile'
require 'timeout'
require "base64"
require "json"
require 'SecureRandom'

module Asperalm
  # imlement this class to get transfer events
  class FileTransferListener
    def event(data)
      raise 'must be defined'
    end
  end

  # listener for FASP transfers (debug)
  class FaspListenerLogger < FileTransferListener
    def event(data)
      Log.log.debug "#{data}"
    end
  end

  # listener for FASP transfers (debug)
  class FaspListenerProgress < FileTransferListener
    def initialize
      @progress=nil
    end

    def event(data)
      if data['Type'].eql?('NOTIFICATION') and data.has_key?('PreTransferBytes') then
        require 'ruby-progressbar'
        @progress=ProgressBar.create(:title => 'progress', :total => data['PreTransferBytes'].to_i)
      end
      if data['Type'].eql?('STATS') and !@progress.nil? then
        @progress.progress=data['TransferBytes'].to_i
      end
      if data['Type'].eql?('DONE') and ! @progress.nil? then
        @progress.progress=@progress.total
        @progress=nil
      end
    end
  end

  # error raised if transfer fails
  class TransferError < StandardError
  end

  class FaspError < TransferError
    attr_reader :err_code
    def initialize(message,err_code)
      super(message)
      @err_code = err_code
    end
  end

  # Manages FASP based transfers
  class FaspManager
    # a global transfer spec that overrides values in transfer spec provided on start
    @@ts_override_data={}

    # add fields from JSON format
    def self.ts_override_json=(value)
      @@ts_override_data.merge!(JSON.parse(value))
    end

    # returns json format
    def self.ts_override_json
      return JSON.generate(@@ts_override_data)
    end

    # returns ruby data
    def self.ts_override_data
      return @@ts_override_data
    end

    attr_accessor :use_connect_client
    attr_accessor :fasp_proxy_url
    attr_accessor :http_proxy_url
    attr_accessor :tr_node_api

    def initialize
      @mgt_sock=nil
      @ascp_pid=nil
      @use_connect_client=false
      @fasp_proxy_url=nil
      @http_proxy_url=nil
      @tr_node_api=nil
    end

    # todo: support multiple listeners
    def set_listener(listener)
      @listener=listener
      self
    end

    def yes_to_true(value)
      case value
      when 'yes'; return true
      when 'no'; return false
      end
      raise "unsupported value: #{value}"
    end

    # extract transfer information from xml returned by faspex
    # only external users get token in link (see: <faspex>/app/views/delivery/_content.xml.builder)
    def fasp_uri_to_transferspec(fasplink)
      transfer_uri=URI.parse(fasplink)
      transfer_spec={}
      transfer_spec['remote_host']=transfer_uri.host
      transfer_spec['remote_user']=transfer_uri.user
      transfer_spec['ssh_port']=transfer_uri.port
      transfer_spec['paths']=[{"source"=>URI.decode_www_form_component(transfer_uri.path)}]

      URI::decode_www_form(transfer_uri.query).each do |i|
        name=i[0]
        value=i[1]
        case name
        when 'cookie'; transfer_spec['cookie']=value
        when 'token'; transfer_spec['token']=value
        when 'policy'; transfer_spec['rate_policy']=value
        when 'httpport'; transfer_spec['http_fallback_port']=value
        when 'targetrate'; transfer_spec['target_rate_kbps']=value
        when 'minrate'; transfer_spec['min_rate_kbps']=value
        when 'port'; transfer_spec['fasp_port']=value
        when 'enc'; transfer_spec['cipher']=value
        when 'tags64'; transfer_spec['tags64']=value
        when 'bwcap'; transfer_spec['target_rate_cap_kbps']=value
        when 'createpath'; transfer_spec['create_dir']=yes_to_true(value)
        when 'fallback'; transfer_spec['http_fallback']=yes_to_true(value)
        when 'auth'; Log.log.warn("ignoring #{name}=#{value}") # TODO: why ignore ?
        when 'lockpolicy'; transfer_spec['lock_rate_policy']=value
        when 'lockminrate'; transfer_spec['lock_min_rate']=value
        when 'v'; Log.log.warn("ignoring #{name}=#{value}")# TODO: why ignore ?
        else Log.log.error("non managed URI value: #{name} = #{value}".red)
        end
      end
      return transfer_spec
    end

    # start ascp
    # raises FaspError
    # uses ascp management port.
    def execute_ascp(command,arguments,env_vars)
      # open random local TCP port listening
      @mgt_sock = TCPServer.new('127.0.0.1', 0)
      port = @mgt_sock.addr[1]
      Log.log.debug "Port=#{port}"
      # add management port
      arguments.unshift('-M', port.to_s)
      # add fallback cert and key
      http_fallback_index=arguments.index("-y")
      if !http_fallback_index.nil?
        if arguments[http_fallback_index+1].eql?('1') then
          arguments.unshift('-Y', Connect.path(:fallback_key), '-I', Connect.path(:fallback_cert))
        end
      end
      arguments.unshift('--proxy', @fasp_proxy_url) if ! @fasp_proxy_url.nil?
      arguments.unshift('-x', @http_proxy_url) if ! @http_proxy_url.nil?
      Log.log.info "execute #{env_vars.map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{command}\" \"#{arguments.join('" "')}\""
      begin
        @ascp_pid = Process.spawn(env_vars,[command,command],*arguments)
      rescue SystemCallError=> e
        raise TransferError.new(e.message)
      end
      # in parent, wait for connection, max 3 seconds
      Log.log.debug "before accept for pid (#{@ascp_pid})"
      client=nil
      begin
        Timeout.timeout( 3 ) do
          client = @mgt_sock.accept
        end
      rescue Timeout::Error => e
        Process.kill 'INT',@ascp_pid
      end
      Log.log.debug "after accept (#{client})"

      if client.nil? then
        # avoid zombie
        Process.wait @ascp_pid
        raise TransferError.new('timeout waiting mgt port connect')
      end

      # records for one message
      current=nil

      # this is the last full status
      lastStatus=nil

      # read management port
      loop do
        begin
          # check process still present, else receive Errno::ESRCH
          Process.getpgid( @ascp_pid )
        rescue RangeError => e
          break
        rescue Errno::ESRCH => e
          break
        end
        # TODO: timeout here ?
        line = client.gets
        if line.nil? then
          break
        end
        line.chomp!
        Log.log.debug "line=[#{line}]"
        if  line.empty? then
          # end frame
          if !current.nil? then
            if !@listener.nil? then
              @listener.event current
            end
            if 'DONE'.eql?(current['Type']) or 'ERROR'.eql?(current['Type']) then
              lastStatus = current
            end
          else
            Log.log.error "unexpected empty line"
          end
        elsif 'FASPMGR 2'.eql? line then
          # begin frame
          current = Hash.new
        elsif m=line.match('^([^:]+): (.*)$') then
          current[m[1]] = m[2]
        else
          Log.log.error "error parsing[#{line}]"
        end
      end

      # wait for sub process completion
      Process.wait(@ascp_pid)

      if !lastStatus.nil? then
        if 'DONE'.eql?(lastStatus['Type']) then
          return
        end
        Log.log.error "last status is [#{lastStatus}]"
      end

      raise FaspError.new(lastStatus['Description'],lastStatus['Code'].to_i)
    end

    # copy and translate argument+value from transfer spec to env var for ascp
    def ts2env(used_names,transfer_spec,env_vars,ts_name,env_name)
      if transfer_spec.has_key?(ts_name)
        env_vars[env_name] = transfer_spec[ts_name]
        used_names.push(ts_name)
      end
    end

    # copy and translate argument+value from transfer spec to arguments for ascp
    def ts2args_value(used_names,transfer_spec,ascp_args,ts_name,arg_name,&transform)
      if transfer_spec.has_key?(ts_name)
        if !transfer_spec[ts_name].nil?
          value=transfer_spec[ts_name]
          value=transform.call(value) if transform
          ascp_args.push(arg_name,value)
        end
        used_names.push(ts_name)
      end
    end

    # translate boolean transfer spec argument to command line argument
    def ts_bool_param(used_names,transfer_spec,ascp_args,ts_name,&get_arg_list)
      if transfer_spec.has_key?(ts_name)
        ascp_args.push(*get_arg_list.call(transfer_spec[ts_name]))
        used_names.push(ts_name)
      end
    end

    # ignore transfer spec argument
    def ts_ignore_param(used_names,ts_name)
      used_names.push(ts_name)
    end

    # translate transfer spec to env vars and command line arguments to ascp
    # parameters starting with "EX_" (extended) are not standard
    def transfer_spec_to_args_and_env(transfer_spec)
      used_names=[]
      # parameters with env vars
      env_vars = Hash.new
      ts2env(used_names,transfer_spec,env_vars,'password','ASPERA_SCP_PASS')
      ts2env(used_names,transfer_spec,env_vars,'token','ASPERA_SCP_TOKEN')
      ts2env(used_names,transfer_spec,env_vars,'cookie','ASPERA_SCP_COOKIE')
      ts2env(used_names,transfer_spec,env_vars,'EX_ssh_key_value','ASPERA_SCP_KEY')
      ts2env(used_names,transfer_spec,env_vars,'EX_at_rest_password','ASPERA_SCP_FILEPASS')
      ts2env(used_names,transfer_spec,env_vars,'EX_proxy_password','ASPERA_PROXY_PASS')

      # base args
      ascp_args = Array.new

      # some ssh credentials are required
      if !transfer_spec.has_key?('password') and !transfer_spec.has_key?('EX_ssh_key_value') and !transfer_spec.has_key?('EX_ssh_key_paths') then
        raise TransferError.new('required: ssh key (value or path) or password')
      end

      # TODO : -c argument ?, what about "none"
      case transfer_spec['cipher']
      when nil; # nothing to put on command line, encryption by default
      when 'aes-128'; used_names.push('cipher') # nothing to put on command line, encryption by default
      when 'aes128'; used_names.push('cipher') # nothing to put on command line, encryption by default (from faspe link)
      else raise TransferError.new("unsupported cipher: #{transfer_spec['cipher']}")
      end

      case transfer_spec['direction']
      when nil; raise TransferError.new("direction is required")
      when 'receive'; ascp_args.push('--mode','recv'); used_names.push('direction')
      when 'send'; ascp_args.push('--mode','send'); used_names.push('direction')
      else raise TransferError.new("unsupported direction: #{transfer_spec['direction']}")
      end

      if transfer_spec.has_key?('EX_ssh_key_paths')
        transfer_spec['EX_ssh_key_paths'].each do |k|
          ascp_args.push('-i',k); used_names.push('EX_ssh_key_paths')
        end
      end

      ts2args_value(used_names,transfer_spec,ascp_args,'remote_user','--user')
      ts2args_value(used_names,transfer_spec,ascp_args,'remote_host','--host')
      ts2args_value(used_names,transfer_spec,ascp_args,'target_rate_kbps','-l') { |rate| rate.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'min_rate_kbps','-m') { |rate| rate.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'ssh_port','-P') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'fasp_port','-O') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'http_fallback','-y') { |enable| enable ? '1' : '0' }
      ts2args_value(used_names,transfer_spec,ascp_args,'http_fallback_port','-t') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'rate_policy','--policy')
      ts2args_value(used_names,transfer_spec,ascp_args,'source_root','--source-prefix')
      ts2args_value(used_names,transfer_spec,ascp_args,'sshfp','--check-sshfp')

      ts_bool_param(used_names,transfer_spec,ascp_args,'create_dir') { |create_dir| create_dir ? ['-d'] : [] }

      # TODO: manage those parameters
      ts_ignore_param(used_names,'target_rate_cap_kbps')
      ts_ignore_param(used_names,'target_rate_percentage')
      ts_ignore_param(used_names,'min_rate_cap_kbps')
      ts_ignore_param(used_names,'rate_policy_allowed')
      ts_ignore_param(used_names,'fasp_url')
      ts_ignore_param(used_names,'lock_rate_policy')
      ts_ignore_param(used_names,'lock_min_rate')
      ts_ignore_param(used_names,'authentication') # = token
      ts_ignore_param(used_names,'https_fallback_port')
      ts_ignore_param(used_names,'lock_target_rate')
      ts_ignore_param(used_names,'content_protection')
      ts_ignore_param(used_names,'cipher_allowed')

      # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
      ts2args_value(used_names,transfer_spec,ascp_args,'tags','--tags64') { |tags| Base64.strict_encode64(JSON.generate(tags)) }
      ts2args_value(used_names,transfer_spec,ascp_args,'tags64','--tags64') # from faspe link
      #ascp_args.push('--tags64', Base64.strict_encode64(JSON.generate(transfer_spec['tags']))) if transfer_spec.has_key?('tags')

      # optional args
      ascp_args.push(*transfer_spec['EX_ascp_args']) if transfer_spec.has_key?('EX_ascp_args')

      # source list: TODO : check presence, and if pairs
      raise TransferError.new("missing source paths") if !transfer_spec.has_key?('paths')
      ascp_args.push(*transfer_spec['paths'].map { |i| i['source']})
      used_names.push('paths')

      # destination
      raise TransferError.new("missing destination") if !transfer_spec.has_key?('destination_root')
      ascp_args.push(transfer_spec['destination_root'])
      used_names.push('destination_root')

      # warn about non translated arguments
      transfer_spec.each_pair { |key,value|
        if !used_names.include?(key)
          Log.log.error("ignored: #{key} = \"#{value}\"".red)
        end
      }

      return ascp_args,env_vars
    end

    # replaces do_transfer
    # transforms transper_spec into command line arguments and env var, then calls execute_ascp
    def transfer_with_spec(transfer_spec)
      transfer_spec.merge!(self.class.ts_override_data)
      Log.log.debug("ts=#{transfer_spec}")
      if (@use_connect_client) # transfer using connect ...
        Log.log.debug("using connect client")
        connect_url=File.open(Connect.path(:plugin_https_port_file)) {|f| f.gets }.strip
        connect_api=Rest.new("#{connect_url}/v5/connect",{})
        begin
          connect_api.read('info/version')
        rescue Errno::ECONNREFUSED
          BrowserInteraction.open_system_uri('fasp://initialize')
          sleep 2
        end
        if transfer_spec["direction"] == "send"
          Log.log.warn("Upload by connect must be selected using GUI, ignoring #{transfer_spec['paths']}".red)
          transfer_spec.delete('paths')
          res=connect_api.create('windows/select-open-file-dialog/',{"title"=>"Select Files","suggestedName"=>"","allowMultipleSelection"=>true,"allowedFileTypes"=>"","aspera_connect_settings"=>{"app_id"=>$PROGRAM_NAME}})
          transfer_spec['paths']=res[:data]['dataTransfer']['files'].map { |i| {'source'=>i['name']}}
        end
        request_id=SecureRandom.uuid
        transfer_spec['authentication']="token" if transfer_spec.has_key?('token')
        transfer_specs={
          'transfer_specs'=>[{
          'transfer_spec'=>transfer_spec,
          'aspera_connect_settings'=>{
          'allow_dialogs'=>true,
          'app_id'=>$PROGRAM_NAME,
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
        execute_ascp(Connect.path(:ascp),*transfer_spec_to_args_and_env(transfer_spec))
      end
      return nil
    end
  end # FaspManager
end # AsperaLm
