#!/bin/echo this is a ruby class:
#
# FASP transfer request
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/log'
require 'socket'
require 'rbconfig'
require 'tempfile'
require 'timeout'
require "base64"
require "json"

module Asperalm
  # imlement this class to get transfer events
  class FileTransferListener
    def event(data)
      raise 'must be defined'
    end
  end

  # listener for FASP transfers (debug)
  class FaspListenerLogger < FileTransferListener
    def initialize
      @progress=nil
    end

    def event(data)
      Log.log.debug "#{data}"
      if data['Type'].eql?('NOTIFICATION') and data.has_key?('PreTransferBytes') then
        require 'ruby-progressbar'
        @progress=ProgressBar.create(:title => 'progress', :total => data['PreTransferBytes'].to_i)
      end
      if data['Type'].eql?('STATS') and !@progress.nil? then
        #@progress.progress=data['TransferBytes'].to_i
      end
      if data['Type'].eql?('DONE') and ! @progress.nil? then
        @progress.progress=@progress.total
        @progress=nil
      end
    end
  end

  # error raised if transfer fails
  class TransferError < StandardError
    attr_reader :err_code
    def initialize(err_code)
      @err_code = err_code
    end

    def retryable?
      if -1.eql?(@err_code) then
        return false
      end
      return FaspManager.retryable?(@err_code)
    end
  end

  # Manages FASP based transfers
  class FaspManager
    def initialize
      @mgt_sock=nil
      @ascp_pid=nil
      set_ascp_location
      @transfer_retries=7
    end

    def set_listener(listener)
      @listener=listener
      self
    end

    # from https://support.asperasoft.com/entries/22895528
    # columns: code name descr msg retryable
    FASP_ERROR_CODES = [
      [],
      [ 1,  'ERR_FASP_PROTO',         "Generic fasp(tm) protocol error",                "fasp(tm) error",                                                    false ],
      [ 2,  'ERR_ASCP',               "Generic SCP error",                              "ASCP error",                                                        false ],
      [ 3,  'ERR_AMBIGUOUS_TARGET',   "Target incorrectly specified",                   "Ambiguous target",                                                  false ],
      [ 4,  'ERR_NO_SUCH_FILE',       "No such file or directory",                      "No such file or directory",                                         false ],
      [ 5,  'ERR_NO_PERMS',           "Insufficient permission to read or write",       "Insufficient permissions",                                          false ],
      [ 6,  'ERR_NOT_DIR',            "Target is not a directory",                      "Target must be a directory",                                        false ],
      [ 7,  'ERR_IS_DIR',             "File is a directory - expected regular file",    "Expected regular file",                                             false ],
      [ 8,  'ERR_USAGE',              "Incorrect usage of scp command",                 "Incorrect usage of Aspera scp command",                             false ],
      [ 9,  'ERR_LIC_DUP',            "Duplicate license",                              "Duplicate license",                                                 false ],
      [ 10, 'ERR_LIC_RATE_EXCEEDED',  "Rate exceeds the cap imposed by license",        "Rate exceeds cap imposed by license",                               false ],
      [ 11, 'ERR_INTERNAL_ERROR',     "Internal error (unexpected error)",              "Internal error",                                                    false ],
      [ 12, 'ERR_TRANSFER_ERROR',     "Error establishing control connection",          "Error establishing SSH connection (check SSH port and firewall)",   true ],
      [ 13, 'ERR_TRANSFER_TIMEOUT',   "Timeout establishing control connection",        "Timeout establishing SSH connection (check SSH port and firewall)", true ],
      [ 14, 'ERR_CONNECTION_ERROR',   "Error establishing data connection",             "Error establishing UDP connection (check UDP port and firewall)",   true ],
      [ 15, 'ERR_CONNECTION_TIMEOUT', "Timeout establishing data connection",           "Timeout establishing UDP connection (check UDP port and firewall)", true ],
      [ 16, 'ERR_CONNECTION_LOST',    "Connection lost",                                "Connection lost",                                                   true ],
      [ 17, 'ERR_RCVR_SEND_ERROR',    "Receiver fails to send feedback",                "Network failure (receiver can't send feedback)",                    true ],
      [ 18, 'ERR_RCVR_RECV_ERROR',    "Receiver fails to receive data packets",         "Network failure (receiver can't receive UDP data)",                 true ],
      [ 19, 'ERR_AUTH',               "Authentication failure",                         "Authentication failure",                                            false ],
      [ 20, 'ERR_NOTHING',            "Nothing to transfer",                            "Nothing to transfer",                                               false ],
      [ 21, 'ERR_NOT_REGULAR',        "Not a regular file (special file)",              "Not a regular file",                                                false ],
      [ 22, 'ERR_FILE_TABLE_OVR',     "File table overflow",                            "File table overflow",                                               false ],
      [ 23, 'ERR_TOO_MANY_FILES',     "Too many files open",                            "Too many files open",                                               true ],
      [ 24, 'ERR_FILE_TOO_BIG',       "File too big for file system",                   "File too big for filesystem",                                       false ],
      [ 25, 'ERR_NO_SPACE_LEFT',      "No space left on disk",                          "No space left on disk",                                             false ],
      [ 26, 'ERR_READ_ONLY_FS',       "Read only file system",                          "Read only filesystem",                                              false ],
      [ 27, 'ERR_SOME_FILE_ERRS',     "Some individual files failed",                   "One or more files failed",                                          false ],
      [ 28, 'ERR_USER_CANCEL',        "Cancelled by user",                              "Cancelled by user",                                                 false ],
      [ 29, 'ERR_LIC_NOLIC',          "License not found or unable to access",          "Unable to access license info",                                     false ],
      [ 30, 'ERR_LIC_EXPIRED',        "License expired",                                "License expired",                                                   false ],
      [ 31, 'ERR_SOCK_SETUP',         "Unable to setup socket (create, bind, etc ...)", "Unable to set up socket",                                           false ],
      [ 32, 'ERR_OUT_OF_MEMORY',      "Out of memory, unable to allocate",              "Out of memory",                                                     true ],
      [ 33, 'ERR_THREAD_SPAWN',       "Can't spawn thread",                             "Unable to spawn thread",                                            true ],
      [ 34, 'ERR_UNAUTHORIZED',       "Unauthorized by external auth server",           "Unauthorized",                                                      false ],
      [ 35, 'ERR_DISK_READ',          "Error reading source file from disk",            "Disk read error",                                                   true ],
      [ 36, 'ERR_DISK_WRITE',         "Error writing to disk",                          "Disk write error",                                                  true ],
      [ 37, 'ERR_AUTHORIZATION',         "Used interchangeably with <strong>ERR_UNAUTHORIZED</strong>", "Authorization failure",                          true ],
      [ 38, 'ERR_LIC_ILLEGAL',           "Operation not permitted by license",                          "Operation not permitted by license",             false ],
      [ 39, 'ERR_PEER_ABORTED_SESSION',  "Remote peer terminated session",                              "Peer aborted session",                           true ],
      [ 40, 'ERR_DATA_TRANSFER_TIMEOUT', "Transfer stalled, timed out",                                 "Data transfer stalled, timed out",               true ],
      [ 41, 'ERR_BAD_PATH',              "Path violates docroot containment",                           "File location is outside 'docroot' hierarchy",   false ],
      [ 42, 'ERR_ALREADY_EXISTS',        "File or directory already exists",                            "File or directory already exists",               false ],
      [ 43, 'ERR_STAT_FAILS',            "Cannot stat file",                                            "Cannot collect details about file or directory", false ],
      [ 44, 'ERR_PMTU_BRTT_ERROR',       "UDP session initiation fatal error",                          "UDP session initiation fatal error",             true ],
      [ 45, 'ERR_BWMEAS_ERROR',          "Bandwidth measurement fatal error",                           "Bandwidth measurement fatal error",              true ],
      [ 46, 'ERR_VLINK_ERROR',           "Virtual link error",                                          "Virtual link error",                             false ],
      [ 47, 'ERR_CONNECTION_ERROR_HTTP', "Error establishing HTTP connection",       "Error establishing HTTP connection (check HTTP port and firewall)", false ],
      [ 48, 'ERR_FILE_ENCRYPTION_ERROR', "File encryption error, e.g. corrupt file", "File encryption/decryption error, e.g. corrupt file",               false ],
      [ 49, 'ERR_FILE_DECRYPTION_PASS', "File encryption/decryption error, e.g. corrupt file", "File decryption error, bad passphrase", false ],
      [ 50, 'ERR_BAD_CONFIGURATION',    "Aspera.conf contains invalid data and was rejected",  "Invalid configuration",                 false ],
      [ 51, 'ERR_UNDEFINED',            "Should never happen, report to Aspera",               "Undefined error",                       false ],
    ];

    @@ASPERA_SSH_BYPASS_DSA="-----BEGIN DSA PRIVATE KEY-----
MIIBuwIBAAKBgQDkKQHD6m4yIxgjsey6Pny46acZXERsJHy54p/BqXIyYkVOAkEp
KgvT3qTTNmykWWw4ovOP1+Di1c/2FpYcllcTphkWcS8lA7j012mUEecXavXjPPG0
i3t5vtB8xLy33kQ3e9v9/Lwh0xcRfua0d5UfFwopBIAXvJAr3B6raps8+QIVALws
yeqsx3EolCaCVXJf+61ceJppAoGAPoPtEP4yzHG2XtcxCfXab4u9zE6wPz4ePJt0
UTn3fUvnQmJT7i0KVCRr3g2H2OZMWF12y0jUq8QBuZ2so3CHee7W1VmAdbN7Fxc+
cyV9nE6zURqAaPyt2bE+rgM1pP6LQUYxgD3xKdv1ZG+kDIDEf6U3onjcKbmA6ckx
T6GavoACgYEAobapDv5p2foH+cG5K07sIFD9r0RD7uKJnlqjYAXzFc8U76wXKgu6
WXup2ac0Co+RnZp7Hsa9G+E+iJ6poI9pOR08XTdPly4yDULNST4PwlfrbSFT9FVh
zkWfpOvAUc8fkQAhZqv/PE6VhFQ8w03Z8GpqXx7b3NvBR+EfIx368KoCFEyfl0vH
Ta7g6mGwIMXrdTQQ8fZs
-----END DSA PRIVATE KEY-----"

    # arg: FASP errcode
    def self.retryable?(err_code)
      return FASP_ERROR_CODES[err_code][4] ;
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
        when 'port'; transfer_spec['ssh_port']=value
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
        when 'auth'; # TODO: why ignore ?
        when 'lockpolicy'; # TODO: why ignore ?
        when 'lockminrate'; # TODO: why ignore ?
        when 'v'; # TODO: why ignore ?
        else Log.log.error("non managed URI value: #{name} = #{value}".red)
        end
      end
      return transfer_spec
    end

    # start ascp
    # raises TransferError
    # uses ascp management port.
    def execute_ascp(command,arguments,env_vars)
      # open random local TCP port listening
      @mgt_sock = TCPServer.new('127.0.0.1', 0)
      port = @mgt_sock.addr[1]
      Log.log.debug "Port=#{port}"
      # add management port
      arguments.unshift '-M', port.to_s
      Log.log.info "execute #{env_vars.map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{command}\" \"#{arguments.join('" "')}\""
      begin
        @ascp_pid = Process.spawn(env_vars,[command,command],*arguments)
      rescue SystemCallError=> e
        raise TransferError.new(-1),e.to_s
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
        raise TransferError.new(-1),'timeout waiting mgt port connect'
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
            Log.log.error "unexpected empty line";
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
        Log.log.error "last status is [#{lastStatus}]";
      end

      raise TransferError.new(lastStatus['Code'].to_i),lastStatus['Description']
    end

    # returns a location for ascp and private key, and if key needs deletion after use
    # {
    #		cmd       => path,
    #		key       => path,
    #		deletekey => bool,
    # };
    def set_ascp_location

      # ascp command and key file
      lConnectAscpCmd = nil
      lConnectAscpId  = nil

      # TODO: detect Connect Client on all platforms
      case RbConfig::CONFIG['host_os']
      when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
        # also: ENV{TEMP}/.. , or %USERPROFILE%\AppData\Local\
        pluginLocation = ENV['LOCALAPPDATA'] + '/Programs/Aspera/Aspera Connect'
        lConnectAscpCmd = pluginLocation + '/bin/ascp';
        lConnectAscpId  = pluginLocation + '/etc/asperaweb_id_dsa.openssh';
      when /darwin|mac os/
        pluginLocation = Dir.home + '/Applications/Aspera Connect.app/Contents/Resources';
        lConnectAscpCmd = pluginLocation + '/ascp';
        lConnectAscpId  = pluginLocation + '/asperaweb_id_dsa.openssh';
      else     # unix family
        pluginLocation = Dir.home + '/.aspera/connect';
        lConnectAscpCmd = pluginLocation + '/bin/ascp';
        lConnectAscpId  = pluginLocation + '/etc/asperaweb_id_dsa.openssh';
      end
      Log.log.debug "cmd= #{lConnectAscpCmd}"
      Log.log.debug "key= #{lConnectAscpId}"
      if File.file?(lConnectAscpCmd) and File.file?(lConnectAscpId ) then
        Log.log.debug "Using plugin: [#{lConnectAscpId}]"
        @ascp_path= lConnectAscpCmd
        @connect_private_key_path= lConnectAscpId
        return
      end

      lESAscpCmd = '/usr/bin/ascp'
      Log.log.debug "Using system ascp if available"
      if ! File.executable(lESAscpCmd ) then
        Log.log.error "no such cmd: [#{lESAscpCmd}]"
        raise "cannot find ascp on system"
      end

      @ascp_path= lESAscpCmd
    end

    # replaces do_transfer

    def ts2env(used_names,transfer_spec,env_vars,ts_name,env_name)
      if transfer_spec.has_key?(ts_name)
        env_vars[env_name] = transfer_spec[ts_name]
        used_names.push(ts_name)
      end
    end

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

    def ts_bool_param(used_names,transfer_spec,ascp_args,ts_name,&get_arg_list)
      if transfer_spec.has_key?(ts_name)
        ascp_args.push(*get_arg_list.call(transfer_spec[ts_name]))
        used_names.push(ts_name)
      end
    end

    def ts_ignore_param(used_names,ts_name)
      used_names.push(ts_name)
    end

    def transfer_spec_to_args_and_env(transfer_spec)
      used_names=[]
      # parameters with env vars
      env_vars = Hash.new
      ts2env(used_names,transfer_spec,env_vars,'password','ASPERA_SCP_PASS')
      ts2env(used_names,transfer_spec,env_vars,'EX_ssh_key_value','ASPERA_SCP_KEY')
      ts2env(used_names,transfer_spec,env_vars,'token','ASPERA_SCP_TOKEN')
      ts2env(used_names,transfer_spec,env_vars,'cookie','ASPERA_SCP_COOKIE')
      ts2env(used_names,transfer_spec,env_vars,'EX_at_rest_password','ASPERA_SCP_FILEPASS')
      ts2env(used_names,transfer_spec,env_vars,'EX_proxy_password','ASPERA_PROXY_PASS')

      # base args
      ascp_args = Array.new

      if !transfer_spec.has_key?('password') and !transfer_spec.has_key?('EX_ssh_key_value') and !transfer_spec.has_key?('EX_ssh_key_path') then
        raise TransferError.new(-1),'required: ssh key (value or path) or password'
      end

      case transfer_spec['cipher']
      when nil; # nothing to put on command line, encryption by default
      when 'aes-128'; used_names.push('cipher') # nothing to put on command line, encryption by default
      when 'aes128'; used_names.push('cipher') # nothing to put on command line, encryption by default (from faspe link)
      else raise TransferError.new(-1),"unsupported cipher: #{transfer_spec['cipher']}"
      end

      case transfer_spec['direction']
      when nil; raise TransferError.new(-1),"direction is required"
      when 'receive'; ascp_args.push('--mode','recv'); used_names.push('direction')
      when 'send'; ascp_args.push('--mode','send'); used_names.push('direction')
      else raise TransferError.new(-1),"unsupported direction: #{transfer_spec['direction']}"
      end

      ts2args_value(used_names,transfer_spec,ascp_args,'remote_user','--user')
      ts2args_value(used_names,transfer_spec,ascp_args,'remote_host','--host')
      ts2args_value(used_names,transfer_spec,ascp_args,'EX_ssh_key_path','-i')
      ts2args_value(used_names,transfer_spec,ascp_args,'target_rate_kbps','-l') { |rate| rate.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'min_rate_kbps','-m') { |rate| rate.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'ssh_port','-P') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'fasp_port','-O') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'http_fallback','-y') { |enable| enable ? '1' : '0' }
      ts2args_value(used_names,transfer_spec,ascp_args,'http_fallback_port','-t') { |port| port.to_s }
      ts2args_value(used_names,transfer_spec,ascp_args,'rate_policy','--policy')
      ts2args_value(used_names,transfer_spec,ascp_args,'source_root','--source-prefix')

      ts_bool_param(used_names,transfer_spec,ascp_args,'create_dir') { |create_dir| create_dir ? ['-d'] : [] }

      ts_ignore_param(used_names,'target_rate_cap_kbps')
      ts_ignore_param(used_names,'rate_policy_allowed')
      ts_ignore_param(used_names,'fasp_url')
      ts_ignore_param(used_names,'sshfp') # ???
      ts_ignore_param(used_names,'lock_rate_policy')
      ts_ignore_param(used_names,'lock_min_rate')

      # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
      ts2args_value(used_names,transfer_spec,ascp_args,'tags','--tags64') { |tags| Base64.strict_encode64(JSON.generate(tags)) }
      ts2args_value(used_names,transfer_spec,ascp_args,'tags64','--tags64') # from faspe link
      #ascp_args.push('--tags64', Base64.strict_encode64(JSON.generate(transfer_spec['tags']))) if transfer_spec.has_key?('tags')

      # optional args
      ascp_args.push(*transfer_spec['EX_ascp_args']) if transfer_spec.has_key?('EX_ascp_args')

      # source list: TODO : check presence, and if pairs
      raise TransferError.new(-1),"missing source paths" if !transfer_spec.has_key?('paths')
      ascp_args.push(*transfer_spec['paths'].map { |i| i['source']})
      used_names.push('paths')

      # destination
      raise TransferError.new(-1),"missing destination" if !transfer_spec.has_key?('destination_root')
      ascp_args.push(transfer_spec['destination_root'])
      used_names.push('destination_root')

      transfer_spec.keys.each { |key|
        if !used_names.include?(key)
          Log.log.error("did not manage: #{key} = #{transfer_spec[key]}".red)
        end
      }

      return ascp_args,env_vars
    end

    # transforms transper_spec into command line arguments and env var, then calls execute_ascp
    def transfer_with_spec(transfer_spec)
      # if not provided, use standard key
      if !transfer_spec.has_key?('EX_ssh_key_value') and
      !transfer_spec.has_key?('EX_ssh_key_path') and
      transfer_spec.has_key?('token')
        if !@connect_private_key_path.nil?
          transfer_spec['EX_ssh_key_path'] = @connect_private_key_path
        else
          transfer_spec['EX_ssh_key_value'] = @@ASPERA_SSH_BYPASS_DSA
        end
      end

      execute_ascp(@ascp_path,*transfer_spec_to_args_and_env(transfer_spec))

      return nil
    end
  end # FaspManager

  # implements a resumable policy
  class FaspManagerResume < FaspManager
    alias_method :transfer_with_spec_super, :transfer_with_spec
    def transfer_with_spec(transfer_spec)
      max_retry = 7
      sleep_seconds   = 2
      sleep_factor    = 2
      sleep_max       = 60

      # maximum of retry
      lRetryLeft = max_retry
      Log.log.debug("retries=#{lRetryLeft}")

      # try to send the file until ascp is succesful
      loop do
        Log.log.debug('transfer starting');
        begin
          transfer_with_spec_super(transfer_spec)
          Log.log.debug( 'transfer ok' );
          break
        rescue TransferError => e
          # failure in ascp
          if e.retryable? then
            # exit if we exceed the max number of retry
            if lRetryLeft <= 0 then
              Log.log.error "Maximum number of retry reached."
              raise TransferError.new(-1),"max retry after: [#{status[:message]}]"
              break;
            end
          else
            Log.log.error('non-retryable error');
            raise e
            break;
          end
        end

        # take this retry in account
        --lRetryLeft
        Log.log.debug( "resuming in  #{sleep_seconds} seconds (retry left:#{lRetryLeft})" );

        # wait a bit before retrying, maybe network condition will be better
        sleep sleep_seconds

        # increase retry period
        sleep_seconds *= sleep_factor
        if sleep_seconds > sleep_max then
          sleep_seconds = sleep_max
        end
      end # loop
    end
  end

end # AsperaLm
