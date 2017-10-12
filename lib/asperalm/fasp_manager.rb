#!/bin/echo this is a ruby class:
#
# FASP manager for Ruby
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'socket'
require 'timeout'
require 'json'
require 'logger'
require 'base64'

#require 'rbconfig'
#require 'tempfile'

module Asperalm
  # imlement this class to get transfer events
  class FileTransferListener
    def event(data)
      raise 'must be defined'
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

  class FaspParamUtils
    # no logger available here, so use a generic one
    @@logger=Logger.new(STDERR)
    # returns the value from transfer spec and mark parameter as used
    def self.use_parameter(state,ts_name,mandatory=false)
      raise TransferError.new("mandatory parameter: #{ts_name}") if mandatory and !state[:transfer_spec].has_key?(ts_name)
      state[:used_names].push(ts_name)
      return state[:transfer_spec][ts_name]
    end

    # define ascp parameter in env var from transfer spec
    def self.set_param_env(state,ts_name,env_name)
      value=use_parameter(state,ts_name)
      state[:result][:env][env_name] = value if !value.nil?
    end

    # ts_name : key in transfer spec
    # ascp_option : option on ascp command line
    # transform : transformation function for transfer spec value to option value
    # if transfer_spec value is an array, applies option many times
    def self.set_param_arg(state,ts_name,ascp_option,&transform)
      value=use_parameter(state,ts_name)
      if !value.nil?
        if transform
          newvalue=transform.call(value)
          if newvalue.nil?
            TransferError.new("unsupported #{ts_name}: #{value}")
          else
            value=newvalue
          end
        end
        value=value.to_s if value.is_a?(Integer)
        value=[value] if value.is_a?(String)
        value.each{|v|state[:result][:args].push(ascp_option,v)}
      end
    end

    # translate transfer spec to env vars and command line arguments for ascp
    # NOTE: parameters starting with "EX_" (extended) are not standard
    def self.transfer_spec_to_args_env(transfer_spec)
      # transformation state, input, output, validation
      state={
        :transfer_spec=>transfer_spec,
        :result => {
        :args=>[],
        :env=>{}
        },
        :used_names=>[]
      }

      # some ssh credentials are required to avoid interactive password input
      if !state[:transfer_spec].has_key?('password') and
      !state[:transfer_spec].has_key?('EX_ssh_key_value') and
      !state[:transfer_spec].has_key?('EX_ssh_key_paths') then
        raise TransferError.new('required: ssh key (value or path) or password')
      end

      # parameters with env vars
      set_param_env(state,'password','ASPERA_SCP_PASS')
      set_param_env(state,'token','ASPERA_SCP_TOKEN')
      set_param_env(state,'cookie','ASPERA_SCP_COOKIE')
      set_param_env(state,'EX_ssh_key_value','ASPERA_SCP_KEY')
      set_param_env(state,'EX_at_rest_password','ASPERA_SCP_FILEPASS')
      set_param_env(state,'EX_proxy_password','ASPERA_PROXY_PASS')

      # TODO : -c argument ?, what about "none"
      value=use_parameter(state,'cipher')
      case value
      when nil;# nothing to put on command line, encryption by default
      when 'aes-128','aes128';# nothing to put on command line (or faspe: link), encryption by default
      else raise TransferError.new("unsupported cipher: #{value}")
      end

      value=use_parameter(state,'create_dir')
      case value
      when nil,false# nothing to put on command line, no creation by default
      when true; state[:result][:args].push('-d')
      else raise TransferError.new("unsupported create_dir: #{value}")
      end

      value=use_parameter(state,'EX_quiet')
      case value
      when nil,false# nothing to put on command line, not quiet
      when true; state[:result][:args].push('-q')
      else raise TransferError.new("unsupported EX_quiet: #{value}")
      end

      set_param_arg(state,'direction','--mode'){|v|{'receive'=>'recv','send'=>'send'}[v]}
      set_param_arg(state,'remote_user','--user')
      set_param_arg(state,'remote_host','--host')
      set_param_arg(state,'ssh_port','-P')
      set_param_arg(state,'fasp_port','-O')
      set_param_arg(state,'target_rate_kbps','-l')
      set_param_arg(state,'min_rate_kbps','-m')
      set_param_arg(state,'rate_policy','--policy')
      set_param_arg(state,'http_fallback','-y'){|v|{'force'=>'F',true=>1,false=>0}[v]}
      set_param_arg(state,'http_fallback_port','-t')
      set_param_arg(state,'source_root','--source-prefix64'){|prefix|Base64.strict_encode64(prefix)}
      set_param_arg(state,'sshfp','--check-sshfp')

      set_param_arg(state,'EX_fallback_key','-Y')
      set_param_arg(state,'EX_fallback_cert','-I')
      set_param_arg(state,'EX_fasp_proxy_url','--proxy')
      set_param_arg(state,'EX_http_proxy_url','-x')
      set_param_arg(state,'EX_ssh_key_paths','-i')

      # TODO: manage those parameters, some are for connect only ? node api ?
      use_parameter(state,'target_rate_cap_kbps')
      use_parameter(state,'target_rate_percentage') # -wf -l<rate>p
      use_parameter(state,'min_rate_cap_kbps')
      use_parameter(state,'rate_policy_allowed')
      use_parameter(state,'fasp_url')
      use_parameter(state,'lock_rate_policy')
      use_parameter(state,'lock_min_rate')
      use_parameter(state,'lock_target_rate')
      use_parameter(state,'authentication') # = token
      use_parameter(state,'https_fallback_port') # same as http fallback, option -t ?
      use_parameter(state,'content_protection')
      use_parameter(state,'cipher_allowed')

      # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
      set_param_arg(state,'tags','--tags64'){|tags| Base64.strict_encode64(JSON.generate(tags)) }
      set_param_arg(state,'tags64','--tags64') # from faspe link

      # optional args
      value=use_parameter(state,'EX_ascp_args')
      state[:result][:args].push(*value) if !value.nil?

      # destination will be base64 encoded, put before path arguments
      state[:result][:args].push('--dest64')

      # source list: TODO : use file list or file pair list, avoid command line lists
      value=use_parameter(state,'paths',true)
      state[:result][:args].push(*value.map{|i|i['source']})

      # destination, use base64 encoding, as defined previously
      value=use_parameter(state,'destination_root',true)
      state[:result][:args].push(Base64.strict_encode64(value))

      # warn about non translated arguments
      state[:transfer_spec].each_pair { |key,value|
        if !state[:used_names].include?(key)
          @@logger.error("unhandled parameter: #{key} = \"#{value}\"")
        end
      }

      return state[:result]
    end

    def self.yes_to_true(value)
      case value
      when 'yes'; return true
      when 'no'; return false
      end
      raise "unsupported value: #{value}"
    end

    # translates a "faspe:" URI into transfer spec hash
    def self.fasp_uri_to_transfer_spec(fasplink)
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
        when 'lockpolicy'; transfer_spec['lock_rate_policy']=value
        when 'lockminrate'; transfer_spec['lock_min_rate']=value
        when 'auth'; @@logger.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
        when 'v'; @@logger.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
        when 'protect'; @@logger.debug("ignoring #{name}=#{value}") # TODO: translate into transfer spec ?
        else @@logger.error("non managed URI value: #{name} = #{value}")
        end
      end
      return transfer_spec
    end

    # transforms ABigWord into a_big_word
    def self.snake_case(str)
      str.
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      gsub(/([a-z\d])(usec)$/,'\1_\2').
      downcase
    end
  end # FaspParamUtils

  # Manages FASP based transfers based on ascp command line
  class FaspManager

    attr_accessor :ascp_path
    def initialize(logger,ascp_path=nil)
      @logger=logger
      @ascp_path=ascp_path
      @listeners=[]
    end

    Formats=[:text,:struct,:enhanced]

    #
    def add_listener(listener,format=:struct)
      raise "unsupported format: #{format}" if !Formats.include?(format)
      @listeners.push({:listener=>listener,:format=>format})
      self
    end

    IntegerFields=['Rate','MinRate','Port','Priority','RateCap','MinRateCap','TCPPort','CreatePolicy','TimePolicy','DatagramSize','XoptFlags','VLinkVersion','PeerVLinkVersion','DSPipelineDepth','PeerDSPipelineDepth','ReadBlockSize','WriteBlockSize','ClusterNumNodes','ClusterNodeId','Size','Written','Loss','FileBytes','PreTransferBytes','TransferBytes','PMTU','Elapsedusec','ArgScansAttempted','ArgScansCompleted','PathScansAttempted','FileScansCompleted','TransfersAttempted','TransfersPassed','Delay']

    def enhanced_event_format(event)
      return event.keys.inject({}) do |h,e|
        new_name=FaspParamUtils.snake_case(e)
        value=event[e]
        value=value.to_i if IntegerFields.include?(e)
        h[new_name]=value
        h
      end
    end

    # This is the low level method to start FASP
    # currently, relies on command line arguments
    # start ascp with management port.
    # raises FaspError on error
    def start_transfer_with_args_env(all_params)
      arguments=all_params[:args]
      raise "no ascp path defined" if @ascp_path.nil?
      # open random local TCP port listening
      mgt_sock = TCPServer.new('127.0.0.1',0 )
      mgt_port = mgt_sock.addr[1]
      @logger.debug "Port=#{mgt_port}"
      # add management port
      arguments.unshift('-M', mgt_port.to_s)
      @logger.info "execute #{all_params[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{@ascp_path}\" \"#{arguments.join('" "')}\""
      begin
        ascp_pid = Process.spawn(all_params[:env],[@ascp_path,@ascp_path],*arguments)
      rescue SystemCallError=> e
        raise TransferError.new(e.message)
      end
      # in parent, wait for connection, max 3 seconds
      @logger.debug "before accept for pid (#{ascp_pid})"
      client=nil
      begin
        Timeout.timeout( 3 ) do
          client = mgt_sock.accept
        end
      rescue Timeout::Error => e
        Process.kill 'INT',ascp_pid
      end
      @logger.debug "after accept (#{client})"

      if client.nil? then
        # avoid zombie
        Process.wait ascp_pid
        raise TransferError.new('timeout waiting mgt port connect')
      end

      # records for one message
      current_event_data=nil
      current_event_text=''

      # this is the last full status
      last_event=nil

      # read management port
      loop do
        begin
          # check process still present, else receive Errno::ESRCH
          Process.getpgid( ascp_pid )
        rescue RangeError => e; break
        rescue Errno::ESRCH => e; break
        rescue NotImplementedError; nil # TODO: can we do better on windows ?
        end
        # TODO: timeout here ?
        line = client.gets
        if line.nil? then
          break
        end
        current_event_text=current_event_text+line
        line.chomp!
        @logger.debug "line=[#{line}]"
        if  line.empty? then
          # end frame
          if !current_event_data.nil? then
            if !@listeners.nil? then
              newformat=nil
              @listeners.each do |listener|
                case listener[:format]
                when :text
                  listener[:listener].event(current_event_text)
                when :struct
                  listener[:listener].event(current_event_data)
                when :enhanced
                  newformat=enhanced_event_format(current_event_data) if newformat.nil?
                  listener[:listener].event(newformat)
                else
                  raise :ERROR
                end
              end
            end
            if ['DONE','ERROR'].include?(current_event_data['Type']) then
              last_event = current_event_data
            end
          else
            @logger.error "unexpected empty line"
          end
        elsif 'FASPMGR 2'.eql? line then
          # begin frame
          current_event_data = Hash.new
          current_event_text = ''
        elsif m=line.match('^([^:]+): (.*)$') then
          current_event_data[m[1]] = m[2]
        else
          @logger.error "error parsing[#{line}]"
        end
      end

      # wait for sub process completion
      Process.wait(ascp_pid)

      raise "nil last status" if last_event.nil?

      if 'DONE'.eql?(last_event['Type']) then
        return
      else
        raise FaspError.new(last_event['Description'],last_event['Code'].to_i)
      end
    end

    # start FASP transfer based on transfer spec (hash table)
    def start_transfer(transfer_spec)
      start_transfer_with_args_env(FaspParamUtils.transfer_spec_to_args_env(transfer_spec))
      return nil
    end # start_transfer
  end # FaspManager
end # AsperaLm
