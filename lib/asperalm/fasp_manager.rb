#!/bin/echo this is a ruby class:
#
# FASP transfer request
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'socket'
require 'logger'
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
    def initialize(logger)
      @logger=logger
      @progress=nil
    end

    def event(data)
      @logger.debug "#{data}"
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

  # main class
  class FaspManager
    def initialize(logger)
      @logger=logger
      @mgt_sock=nil
      @ascp_pid=nil
    end

    def set_listener(listener)
      @listener=listener
      self
    end

    # from https://support.asperasoft.com/entries/22895528
    # code name descr msg retryable
    @@fasp_error_codes = [
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

    # arg: FASP errcode
    def self.retryable?(err_code)
      return @@fasp_error_codes[err_code][4] ;
    end

    # start ascp
    # raises TransferError
    # uses ascp management port.
    def execute_ascp(command,arguments,env_vars)
      # open random local TCP port listening
      @mgt_sock = TCPServer.new('127.0.0.1', 0)
      port = @mgt_sock.addr[1]
      @logger.debug "Port=#{port}"
      # add management port
      arguments.unshift '-M', port.to_s
      @logger.info "execute #{env_vars.map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{command}\" \"#{arguments.join('" "')}\""
      begin
        @ascp_pid = Process.spawn(env_vars,[command,command],*arguments)
      rescue SystemCallError=> e
        raise TransferError.new(-1),e.to_s
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
        @logger.debug "line=[#{line}]"
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
            @logger.error "unexpected empty line";
          end
        elsif 'FASPMGR 2'.eql? line then
          # begin frame
          current = Hash.new
        elsif m=line.match('^([^:]+): (.*)$') then
          current[m[1]] = m[2]
        else
          @logger.error "error parsing[#{line}]"
        end
      end

      # wait for sub process completion
      Process.wait(@ascp_pid)

      if !lastStatus.nil? then
        if 'DONE'.eql?(lastStatus['Type']) then
          return
        end
        @logger.error "last status is [#{lastStatus}]";
      end

      raise TransferError.new(lastStatus['Code'].to_i),lastStatus['Description']
    end

    # returns a location for ascp and private key, and if key needs deletion after use
    # {
    #		cmd       => path,
    #		key       => path,
    #		deletekey => bool,
    # };
    def get_ascp_location

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
      @logger.debug "cmd= #{lConnectAscpCmd}"
      @logger.debug "key= #{lConnectAscpId}"
      if File.file?(lConnectAscpCmd) and File.file?(lConnectAscpId ) then
        @logger.debug "Using plugin: [#{lConnectAscpId}]"
        return {
          :cmd       => lConnectAscpCmd,
          :key       => lConnectAscpId,
          :deletekey => false,
        }
      end

      lESAscpCmd = '/usr/bin/ascp'
      @logger.debug "Using system ascp if available"
      if ! File.executable(lESAscpCmd ) then
        @logger.error "no such cmd: [#{lESAscpCmd}]"
        raise "cannot find ascp"
      end

      # private key not found ?
      keyfile=Tempfile.new('aspera_private_key')
      keycontent = "-----BEGIN DSA PRIVATE KEY-----
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
-----END DSA PRIVATE KEY-----
"
      keyfile.puts(keycontent)
      keyfile.close
      lConnectAscpId = keyfile.path

      return {
        :cmd       => lESAscpCmd,
        :key       => lConnectAscpId,
        :deletekey => true,
      }
    end

    # executes a FASP transfer
    # call is blocking
    # returns nil
    # raises TransferError
    # user may start in separate thread if needed
    # TODO: check mandatory params
    # does the following:
    # 1- locate ascp and web ssh key
    # 2- build ascp argument list from Ruby arguments hash
    # 3- restart ascp a number of time upon success
    def do_transfer(transfer_params)

      # prepare location of ascp and key
      use_aspera_key = transfer_params[:use_aspera_key] if transfer_params.has_key?(:use_aspera_key)
      aspera_key = nil
      ascp_path = nil
      delete_key=false

      if (!transfer_params.has_key?(:ssh_key)) or use_aspera_key or (!transfer_params.has_key?(:ascp_path)) then
        # we need to find on system
        begin
          locations = get_ascp_location
          aspera_key = locations[:key]
          ascp_path = locations[:cmd]
          delete_key = locations[:deletekey]
          locations = nil
        rescue Exception  => e
          @logger.error "Exception: #{e}"
          raise TransferError.new(-1),'cannot find ascp'
        end
      end

      # do we use a key ?
      ssh_key = nil
      if use_aspera_key then
        ssh_key = aspera_key
      elsif transfer_params.has_key?(:ssh_key) then
        ssh_key = transfer_params[:ssh_key]
      elsif !transfer_params.has_key?(:password) then
        raise TransferError.new(-1),'required: ssh key or password'
      end

      do_encrypt = transfer_params.has_key?(:encrypt)?transfer_params[:encrypt]:true

      # base args
      ascp_args = Array.new

      ascp_args.push '-T' if !do_encrypt
      ascp_args.push '--mode', transfer_params[:mode].to_s if transfer_params.has_key? :mode
      ascp_args.push '--user', transfer_params[:user] if transfer_params.has_key? :user
      ascp_args.push '--host', transfer_params[:host] if transfer_params.has_key? :host

      # optional key
      ascp_args.unshift '-i', ssh_key if !ssh_key.nil?

      # optional token: in env var (see below), more secure than arg
      #ascp_args.push '-W', transfer_params[:token] if transfer_params.has_key? :token

      # optional tags
      ascp_args.push '--tags64', Base64.strict_encode64(JSON.generate(transfer_params[:tags])) if transfer_params.has_key? :tags
      #ascp_args.push '--tags64', Base64.strict_encode64(JSON.generate(transfer_params[:tags],{:space=>' ',:object_nl=>' '})) if transfer_params.has_key? :tags
      #ascp_args.push '--tags64', Base64.strict_encode64(JSON.generate(transfer_params[:tags],{:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'})) if transfer_params.has_key? :tags
      ascp_args.push '--tags64', transfer_params[:tags64] if transfer_params.has_key? :tags64

      # optional args
      ascp_args.push *transfer_params[:rawArgs] if transfer_params.has_key? :rawArgs

      # source list
      ascp_args.push *transfer_params[:srcList] if transfer_params.has_key? :srcList

      # destination
      ascp_args.push transfer_params[:dest] if transfer_params.has_key? :dest

      # optional parameter: max retry
      lMaxRetry = transfer_params.has_key?(:retries) ? transfer_params[:retries] : 7;

      # initial wait time between two retry
      sleep_seconds  = transfer_params.has_key?(:sleeptime )   ? transfer_params[:sleeptime]   : 2;
      sleep_factor    = transfer_params.has_key?(:sleepfactor ) ? transfer_params[:sleepfactor] : 2;
      sleep_max       = transfer_params.has_key?(:sleepmax )    ? transfer_params[:sleepmax]    : 60;

      # maximum of retry
      lRetryLeft = lMaxRetry;

      # return code
      retstatus=nil

      # parameters with env vars
      env_vars=Hash.new
      env_vars['ASPERA_SCP_PASS'] = transfer_params[:password] if transfer_params.has_key? :password
      env_vars['ASPERA_SCP_KEY'] = transfer_params[:sshKey] if transfer_params.has_key? :sshKey
      env_vars['ASPERA_SCP_TOKEN'] = transfer_params[:token] if transfer_params.has_key? :token
      env_vars['ASPERA_SCP_COOKIE'] = transfer_params[:cookie] if transfer_params.has_key? :cookie
      env_vars['ASPERA_SCP_FILEPASS'] = transfer_params[:file_pass] if transfer_params.has_key? :file_pass
      env_vars['ASPERA_PROXY_PASS'] = transfer_params[:proxy_pass] if transfer_params.has_key? :proxy_pass

      @logger.debug("retries=#{lRetryLeft}")

      # try to send the file until ascp is succesful
      loop do
        @logger.debug('transfer starting');
        begin
          execute_ascp(ascp_path,ascp_args,env_vars)
          @logger.debug( 'transfer ok' );
          break
        rescue TransferError => e
          # failure in ascp
          if e.retryable? then
            # exit if we exceed the max number of retry
            if lRetryLeft <= 0 then
              @logger.error "Maximum number of retry reached."
              raise TransferError.new(-1),"max retry after: [#{status[:message]}]"
              break;
            end
          else
            @logger.error('non-retryable error');
            raise e
            break;
          end
        end

        # take this retry in account
        --lRetryLeft
        @logger.debug( "resuming in  #{sleep_seconds} seconds (retry left:#{lRetryLeft})" );

        # wait a bit before retrying, maybe network condition will be better
        sleep sleep_seconds

        # increase retry period
        sleep_seconds *= sleep_factor
        if sleep_seconds > sleep_max then
          sleep_seconds = sleep_max
        end
      end # loop
      # cleanup if necessary
      File.delete aspera_key if delete_key
      return
    end
  end
end
