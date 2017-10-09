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
    # copy and translate argument+value from transfer spec to env var for ascp
    def self.ts2env(state,ts_name,env_name)
      if state[:transfer_spec].has_key?(ts_name)
        state[:result][:env][env_name] = state[:transfer_spec][ts_name]
        state[:used_names].push(ts_name)
      end
    end

    # copy and translate argument+value from transfer spec to arguments for ascp
    def self.ts2args_value(state,ts_name,arg_name,&transform)
      if state[:transfer_spec].has_key?(ts_name)
        if !state[:transfer_spec][ts_name].nil?
          value=state[:transfer_spec][ts_name]
          value=transform.call(value) if transform
          state[:result][:args].push(arg_name,value)
        end
        state[:used_names].push(ts_name)
      end
    end

    # translate boolean transfer spec argument to command line argument
    def self.ts_bool_param(state,ts_name,&get_arg_list)
      if state[:transfer_spec].has_key?(ts_name)
        state[:result][:args].push(*get_arg_list.call(state[:transfer_spec][ts_name]))
        state[:used_names].push(ts_name)
      end
    end

    # ignore transfer spec argument
    def self.ts_ignore_param(state,ts_name)
      state[:used_names].push(ts_name)
    end

    # translate transfer spec to env vars and command line arguments for ascp
    # NOTE: parameters starting with "EX_" (extended) are not standard
    def self.transfer_spec_to_args_env(transfer_spec)
      state={
        :transfer_spec=>transfer_spec,
        :result => {
        :args=>[],
        :env=>{}
        },
        :used_names=>[]
      }

      # parameters with env vars
      ts2env(state,'password','ASPERA_SCP_PASS')
      ts2env(state,'token','ASPERA_SCP_TOKEN')
      ts2env(state,'cookie','ASPERA_SCP_COOKIE')
      ts2env(state,'EX_ssh_key_value','ASPERA_SCP_KEY')
      ts2env(state,'EX_at_rest_password','ASPERA_SCP_FILEPASS')
      ts2env(state,'EX_proxy_password','ASPERA_PROXY_PASS')

      # some ssh credentials are required
      if !state[:transfer_spec].has_key?('password') and !state[:transfer_spec].has_key?('EX_ssh_key_value') and !state[:transfer_spec].has_key?('EX_ssh_key_paths') then
        raise TransferError.new('required: ssh key (value or path) or password')
      end

      # TODO : -c argument ?, what about "none"
      case state[:transfer_spec]['cipher']
      when nil; # nothing to put on command line, encryption by default
      when 'aes-128'; state[:used_names].push('cipher') # nothing to put on command line, encryption by default
      when 'aes128'; state[:used_names].push('cipher') # nothing to put on command line, encryption by default (from faspe link)
      else raise TransferError.new("unsupported cipher: #{state[:transfer_spec]['cipher']}")
      end

      case state[:transfer_spec]['direction']
      when nil; raise TransferError.new("direction is required")
      when 'receive'; state[:result][:args].push('--mode','recv'); state[:used_names].push('direction')
      when 'send'; state[:result][:args].push('--mode','send'); state[:used_names].push('direction')
      else raise TransferError.new("unsupported direction: #{state[:transfer_spec]['direction']}")
      end

      if state[:transfer_spec].has_key?('EX_ssh_key_paths')
        state[:transfer_spec]['EX_ssh_key_paths'].each do |k|
          state[:result][:args].push('-i',k); state[:used_names].push('EX_ssh_key_paths')
        end
      end

      ts2args_value(state,'remote_user','--user')
      ts2args_value(state,'remote_host','--host')
      ts2args_value(state,'target_rate_kbps','-l') { |rate| rate.to_s }
      ts2args_value(state,'min_rate_kbps','-m') { |rate| rate.to_s }
      ts2args_value(state,'ssh_port','-P') { |port| port.to_s }
      ts2args_value(state,'fasp_port','-O') { |port| port.to_s }
      ts2args_value(state,'http_fallback','-y') { |enable| enable.eql?("force") ? 'F' : enable ? '1' : '0' }
      ts2args_value(state,'http_fallback_port','-t') { |port| port.to_s }
      ts2args_value(state,'rate_policy','--policy')
      ts2args_value(state,'source_root','--source-prefix64') { |prefix| Base64.strict_encode64(prefix) }
      ts2args_value(state,'sshfp','--check-sshfp')

      ts2args_value(state,'EX_fallback_key','-Y')
      ts2args_value(state,'EX_fallback_cert','-I')
      ts2args_value(state,'EX_fasp_proxy_url','--proxy')
      ts2args_value(state,'EX_http_proxy_url','-x')

      ts_bool_param(state,'create_dir') { |create_dir| create_dir ? ['-d'] : [] }

      # TODO: manage those parameters, some are for connect only ? not node api ?
      ts_ignore_param(state,'target_rate_cap_kbps')
      ts_ignore_param(state,'target_rate_percentage') # -wf -l<rate>p
      ts_ignore_param(state,'min_rate_cap_kbps')
      ts_ignore_param(state,'rate_policy_allowed')
      ts_ignore_param(state,'fasp_url')
      ts_ignore_param(state,'lock_rate_policy')
      ts_ignore_param(state,'lock_min_rate')
      ts_ignore_param(state,'lock_target_rate')
      ts_ignore_param(state,'authentication') # = token
      ts_ignore_param(state,'https_fallback_port') # same as http fallback, option -t ?
      ts_ignore_param(state,'content_protection')
      ts_ignore_param(state,'cipher_allowed')

      # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
      ts2args_value(state,'tags','--tags64') { |tags| Base64.strict_encode64(JSON.generate(tags)) }
      ts2args_value(state,'tags64','--tags64') # from faspe link

      # optional args
      if state[:transfer_spec].has_key?('EX_ascp_args')
        state[:result][:args].push(*state[:transfer_spec]['EX_ascp_args'])
        state[:used_names].push('EX_ascp_args')
      end

      # destination will be base64 encoded, put before path arguments
      state[:result][:args].push('--dest64')

      # source list: TODO : use file list or file pair list, avoid command line lists
      raise TransferError.new("missing source paths") if !state[:transfer_spec].has_key?('paths')
      state[:result][:args].push(*state[:transfer_spec]['paths'].map { |i| i['source']})
      state[:used_names].push('paths')

      # destination
      raise TransferError.new("missing destination") if !state[:transfer_spec].has_key?('destination_root')
      # use base64 encoding
      state[:result][:args].push(Base64.strict_encode64(state[:transfer_spec]['destination_root']))
      state[:used_names].push('destination_root')

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
    end

    # todo: support multiple listeners
    def set_listener(listener)
      @listener=listener
      self
    end

    # start ascp
    # raises FaspError
    # uses ascp management port.
    def start_transfer_with_args_env(all_params)
      arguments=all_params[:args]
      raise "no ascp path defined" if @ascp_path.nil?
      # open random local TCP port listening
      mgt_sock = TCPServer.new('127.0.0.1',0 )
      port = mgt_sock.addr[1]
      @logger.debug "Port=#{port}"
      # add management port
      arguments.unshift('-M', port.to_s)
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
      current=nil

      # this is the last full status
      lastStatus=nil

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
        line.chomp!
        @logger.debug "line=[#{line}]"
        if  line.empty? then
          # end frame
          if !current.nil? then
            if !@listener.nil? then
              @listener.event(current)
            end
            if 'DONE'.eql?(current['type']) or 'ERROR'.eql?(current['type']) then
              lastStatus = current
            end
          else
            @logger.error "unexpected empty line"
          end
        elsif 'FASPMGR 2'.eql? line then
          # begin frame
          current = Hash.new
        elsif m=line.match('^([^:]+): (.*)$') then
          current[FaspParamUtils.snake_case(m[1])] = m[2]
        else
          @logger.error "error parsing[#{line}]"
        end
      end

      # wait for sub process completion
      Process.wait(ascp_pid)

      raise "nil last status" if lastStatus.nil?

      if 'DONE'.eql?(lastStatus['type']) then
        return
      else
        raise FaspError.new(lastStatus['description'],lastStatus['code'].to_i)
      end
    end

    # replaces do_transfer
    # transforms transper_spec into command line arguments and env var, then calls start_transfer_with_args_env
    def start_transfer(transfer_spec)
      start_transfer_with_args_env(FaspParamUtils.transfer_spec_to_args_env(transfer_spec))
      return nil
    end # start_transfer
  end # FaspManager
end # AsperaLm
