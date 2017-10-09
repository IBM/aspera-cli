#!/bin/echo this is a ruby class:
#
# FASP manager for Ruby
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'socket'
require 'rbconfig'
require 'tempfile'
require 'timeout'
require 'base64'
require 'json'
require 'securerandom'

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

  # Manages FASP based transfers
  class FaspManager

    # mode=ascp : proxy configuration
    attr_accessor :fasp_proxy_url
    attr_accessor :http_proxy_url
    attr_accessor :ascp_path
    def initialize(logger)
      @logger=logger
      @ascp_path=nil
      @mgt_sock=nil
      @ascp_pid=nil
      @fasp_proxy_url=nil
      @http_proxy_url=nil
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
        when 'lockpolicy'; transfer_spec['lock_rate_policy']=value
        when 'lockminrate'; transfer_spec['lock_min_rate']=value
        when 'auth'; @logger.debug("ignoring #{name}=#{value}") # TODO: why ignore ?
        when 'v'; @logger.debug("ignoring #{name}=#{value}")# TODO: why ignore ?
        when 'protect'; @logger.debug("ignoring #{name}=#{value}")# TODO: why ignore ?
        else @logger.error("non managed URI value: #{name} = #{value}".red)
        end
      end
      return transfer_spec
    end

    # transforms ABigWord into a_big_word
    def snake_case(str)
      str.
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      gsub(/([a-z\d])(usec)$/,'\1_\2').
      downcase
    end

    # start ascp
    # raises FaspError
    # uses ascp management port.
    def start_transfer_from_args_env(arguments,env_vars)
      raise "no ascp path defined" if @ascp_path.nil?
      # open random local TCP port listening
      @mgt_sock = TCPServer.new('127.0.0.1',0 )
      port = @mgt_sock.addr[1]
      @logger.debug "Port=#{port}"
      # add management port
      arguments.unshift('-M', port.to_s)
      arguments.unshift('--proxy', @fasp_proxy_url) if ! @fasp_proxy_url.nil?
      arguments.unshift('-x', @http_proxy_url) if ! @http_proxy_url.nil?
      @logger.info "execute #{env_vars.map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{@ascp_path}\" \"#{arguments.join('" "')}\""
      begin
        @ascp_pid = Process.spawn(env_vars,[@ascp_path,@ascp_path],*arguments)
      rescue SystemCallError=> e
        raise TransferError.new(e.message)
      end
      # in parent, wait for connection, max 3 seconds
      @logger.debug "before accept for pid (#{@ascp_pid})"
      client=nil
      begin
        Timeout.timeout( 3 ) do
          client = @mgt_sock.accept
        end
      rescue Timeout::Error => e
        Process.kill 'INT',@ascp_pid
      end
      @logger.debug "after accept (#{client})"

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
          current[snake_case(m[1])] = m[2]
        else
          @logger.error "error parsing[#{line}]"
        end
      end

      # wait for sub process completion
      Process.wait(@ascp_pid)

      raise "nil last status" if lastStatus.nil?

      if 'DONE'.eql?(lastStatus['type']) then
        return
      else
        raise FaspError.new(lastStatus['description'],lastStatus['code'].to_i)
      end
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
      ts2args_value(used_names,transfer_spec,ascp_args,'http_fallback','-y') { |enable| enable.eql?("force") ? 'F' : enable ? '1' : '0' }
      ts2args_value(used_names,transfer_spec,ascp_args,'http_fallback_port','-t') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'rate_policy','--policy')
      ts2args_value(used_names,transfer_spec,ascp_args,'source_root','--source-prefix64') { |prefix| Base64.strict_encode64(prefix) }
      ts2args_value(used_names,transfer_spec,ascp_args,'sshfp','--check-sshfp')

      ts2args_value(used_names,transfer_spec,ascp_args,'EX_fallback_key','-Y')
      ts2args_value(used_names,transfer_spec,ascp_args,'EX_fallback_cert','-I')

      ts_bool_param(used_names,transfer_spec,ascp_args,'create_dir') { |create_dir| create_dir ? ['-d'] : [] }

      # TODO: manage those parameters, some are for connect only ? not node api ?
      ts_ignore_param(used_names,'target_rate_cap_kbps')
      ts_ignore_param(used_names,'target_rate_percentage') # -wf -l<rate>p
      ts_ignore_param(used_names,'min_rate_cap_kbps')
      ts_ignore_param(used_names,'rate_policy_allowed')
      ts_ignore_param(used_names,'fasp_url')
      ts_ignore_param(used_names,'lock_rate_policy')
      ts_ignore_param(used_names,'lock_min_rate')
      ts_ignore_param(used_names,'lock_target_rate')
      ts_ignore_param(used_names,'authentication') # = token
      ts_ignore_param(used_names,'https_fallback_port') # same as http fallback, option -t ?
      ts_ignore_param(used_names,'content_protection')
      ts_ignore_param(used_names,'cipher_allowed')

      # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
      ts2args_value(used_names,transfer_spec,ascp_args,'tags','--tags64') { |tags| Base64.strict_encode64(JSON.generate(tags)) }
      ts2args_value(used_names,transfer_spec,ascp_args,'tags64','--tags64') # from faspe link
      #ascp_args.push('--tags64', Base64.strict_encode64(JSON.generate(transfer_spec['tags']))) if transfer_spec.has_key?('tags')

      # optional args
      if transfer_spec.has_key?('EX_ascp_args')
        ascp_args.push(*transfer_spec['EX_ascp_args'])
        used_names.push('EX_ascp_args')
      end

      # destination will be base64 encoded
      ascp_args.push('--dest64')

      # source list: TODO : use file list or file pair list, avoid command line lists
      raise TransferError.new("missing source paths") if !transfer_spec.has_key?('paths')
      ascp_args.push(*transfer_spec['paths'].map { |i| i['source']})
      used_names.push('paths')

      # destination
      raise TransferError.new("missing destination") if !transfer_spec.has_key?('destination_root')
      # use base64 encoding
      ascp_args.push(Base64.strict_encode64(transfer_spec['destination_root']))
      used_names.push('destination_root')

      # warn about non translated arguments
      transfer_spec.each_pair { |key,value|
        if !used_names.include?(key)
          @logger.error("unhandled parameter: #{key} = \"#{value}\"".red)
        end
      }

      return ascp_args,env_vars
    end

    # replaces do_transfer
    # transforms transper_spec into command line arguments and env var, then calls start_transfer_from_args_env
    def start_transfer(transfer_spec)
      start_transfer_from_args_env(*transfer_spec_to_args_and_env(transfer_spec))
      return nil
    end # start_transfer
  end # FaspManager
end # AsperaLm
