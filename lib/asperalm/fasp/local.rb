#!/bin/echo this is a ruby class:
#
# FASP manager for Ruby
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/fasp/manager'
require 'asperalm/fasp/error'
require 'asperalm/fasp/parameters'
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'socket'
require 'timeout'

module Asperalm
  module Fasp
    ACCESS_KEY_TRANSFER_USER='xfer'
    # executes a local "ascp", equivalent of "Fasp Manager"
    class Local < Manager
      attr_accessor :quiet
      # start FASP transfer based on transfer spec (hash table)
      # note that it returns upon completion only (blocking)
      # if the user wants to run in background, just spawn a thread
      # listener methods are called in context of calling thread
      def start_transfer(transfer_spec)
        # TODO: what is this for ? only on local ascp ?
        # NOTE: important: transfer id must be unique: generate random id (using a non unique id results in discard of tags)
        if transfer_spec['tags'].is_a?(Hash) and transfer_spec['tags']['aspera'].is_a?(Hash)
          transfer_spec['tags']['aspera']['xfer_id']=SecureRandom.uuid
          Log.log.debug "xfer id=#{transfer_spec['xfer_id']}"
          # useful ? node only ?
          transfer_spec['tags']['aspera']['xfer_retry']=3600
        end
        Log.log.debug("ts=#{transfer_spec}")
        # suse bypass keys when authentication is token
        if transfer_spec['authentication'].eql?("token")
          # add Aspera private keys for web access, token based authorization
          transfer_spec['EX_ssh_key_paths'] = [ Installation.instance.path(:ssh_bypass_key_dsa), Installation.instance.path(:ssh_bypass_key_rsa) ]
          # mwouais...
          transfer_spec['drowssap_etomer'.reverse] = "%08x-%04x-%04x-%04x-%04x%08x" % "t1(\xBF;\xF3E\xB5\xAB\x14F\x02\xC6\x7F)P".unpack("NnnnnN")
        end
        multi_session=0
        if transfer_spec.has_key?('multi_session')
          multi_session=transfer_spec['multi_session'].to_i
          transfer_spec.delete('multi_session')
        end
        # compute known args
        env_args=Parameters.ts_to_env_args(transfer_spec)

        # add fallback cert and key as arguments if needed
        if ['1','force'].include?(transfer_spec['http_fallback'])
          env_args[:args].unshift('-Y',Installation.instance.path(:fallback_key))
          env_args[:args].unshift('-I',Installation.instance.path(:fallback_cert))
        end

        env_args[:args].unshift('-q') if @quiet

        # transfer job can be multi session
        xfer_job={
          :sessions      => []
        }
        # generic session information
        session={
          :state         => :initial,
          :env_args      => env_args,
          :max_retry     => 7,
          :sleep_seconds => 2,
          :sleep_factor  => 2,
          :sleep_max     => 60
        }
        if multi_session.eql?(0)
          session[:thread] = Thread.new(session) {|s|transfer_thread_entry(s)}
          xfer_job[:sessions].push(session)
        else
          1.upto(multi_session) do |i|
            # do deep copy
            session_n=Marshal.load(Marshal.dump(session))
            session_n[:env_args][:args].unshift("-C#{i}:#{multi_session}")
            # check if this is necessary ? should be handled by server, this is in man page
            session_n[:env_args][:args].unshift("-O","#{33000+i}")
            session_n[:thread] = Thread.new(session_n) {|s|transfer_thread_entry(s)}
            xfer_job[:sessions].push(session_n)
          end
        end
        @jobs.push(xfer_job)
      end # start_transfer

      # terminates monitor thread
      def shutdown(wait_for_sessions=false)
        if wait_for_sessions
          @mutex.synchronize do
            loop do
              running=0
              @jobs.each do |job|
                job[:sessions].each do |session|
                  case session[:state]
                  when :failed; raise StandardError,"at least one session failed"
                  when :success # ignore
                  else running+=1
                  end
                end
              end
              break unless running > 0
              Log.log.debug("wait for completed: running: #{running}")
              @cond_var.wait(@mutex)
            end # loop
          end # mutex
        end
        # tell monitor to stop
        @mutex.synchronize do
          @monitor_run=false
        end
        @cond_var.broadcast
        # wait for thread termination
        @monitor.join
        @monitor=nil
        Log.log.debug("joined monitor")
      end

      # This is the low level method to start FASP
      # currently, relies on command line arguments
      # start ascp with management port.
      # raises FaspError on error
      # if there is a thread info: set and broadcast session id
      # @param env_args a hash containing :args :env :ascp_version
      def start_transfer_with_args_env(env_args,session=nil)
        begin
          Log.log.debug("env_args=#{env_args.inspect}")
          ascp_path=Fasp::Installation.instance.path(env_args[:ascp_version])
          raise Fasp::Error.new("no such file: #{ascp_path}") unless File.exist?(ascp_path)
          ascp_pid=nil
          ascp_arguments=env_args[:args].clone
          # open random local TCP port listening
          mgt_sock = TCPServer.new('127.0.0.1',0 )
          # add management port
          ascp_arguments.unshift('-M', mgt_sock.addr[1].to_s)
          # start ascp in sub process
          Log.log.debug "execute: #{env_args[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{ascp_path}\" \"#{ascp_arguments.join('" "')}\""
          # start process
          ascp_pid = Process.spawn(env_args[:env],[ascp_path,ascp_path],*ascp_arguments)
          # in parent, wait for connection to socket max 3 seconds
          Log.log.debug "before accept for pid (#{ascp_pid})"
          ascp_mgt_io=nil
          Timeout.timeout( 3 ) do
            ascp_mgt_io = mgt_sock.accept
          end
          Log.log.debug "after accept (#{ascp_mgt_io})"

          # exact text for event, with \n
          current_event_text=''
          # parsed event (hash)
          current_event_data=nil

          # this is the last full status
          last_status_event=nil

          # read management port
          loop do
            # TODO: timeout here ?
            line = ascp_mgt_io.gets
            # nil when ascp process exits
            break if line.nil?
            current_event_text=current_event_text+line
            line.chomp!
            Log.log.debug("line=[#{line}]")
            case line
            when 'FASPMGR 2'
              # begin event
              current_event_data = Hash.new
              current_event_text = ''
            when /^([^:]+): (.*)$/
              # event field
              current_event_data[$1] = $2
            when ''
              # end event
              raise "unexpected empty line" if current_event_data.nil?
              notify_listeners(current_event_text,current_event_data)
              # TODO: check if this is always the last event
              case current_event_data['Type']
              when 'DONE','ERROR'
                last_status_event = current_event_data
              when 'INIT'
                unless session.nil?
                  @mutex.synchronize do
                    session[:state]=:started
                    session[:id]=current_event_data['SessionId']
                    Log.log.debug("session id: #{session[:id]}")
                    @cond_var.broadcast
                  end
                end
              end # event type
            else
              raise "unexpected line:[#{line}]"
            end # case
          end # loop
          # check that last status was received before process exit
          raise "INTERNAL: nil last status" if last_status_event.nil?
          case last_status_event['Type']
          when 'DONE'
            return
          when 'ERROR'
            raise Fasp::Error.new(last_status_event['Description'],last_status_event['Code'].to_i)
          else
            raise "INTERNAL ERROR: unexpected last event"
          end
        rescue SystemCallError => e
          # Process.spawn
          raise Fasp::Error.new(e.message)
        rescue Timeout::Error => e
          raise Fasp::Error.new('timeout waiting mgt port connect')
        rescue Interrupt => e
          raise Fasp::Error.new('transfer interrupted by user')
        ensure
          # ensure there is no ascp left running
          unless ascp_pid.nil?
            begin
              Process.kill('INT',ascp_pid)
            rescue
            end
            # avoid zombie
            Process.wait(ascp_pid)
            ascp_pid=nil
          end
        end # begin-ensure
      end # start_transfer_with_args_env

      private

      def initialize
        super
        @quiet=false
        # mutex protects manager data
        @mutex=Mutex.new
        # cond var is waited or broadcast on manager data change
        @cond_var=ConditionVariable.new
        # shared data protected by mutex, CV on change
        @jobs=[]
        # must be set before starting monitor, set to false to stop thread
        @monitor_run=true
        @monitor=Thread.new{monitor_thread_entry}
      end

      # transfer thread entry
      # implements resumable transfer
      def transfer_thread_entry(session)
        # set name for logging
        Thread.current[:name]="transfer"
        session[:state]=:started
        env_args=session[:env_args]
        # maximum of retry
        remaining_tries = session[:max_retry]
        Log.log.debug("retries=#{remaining_tries}")

        begin
          # try to send the file until ascp is succesful
          loop do
            Log.log.debug('transfer starting');
            begin
              start_transfer_with_args_env(env_args,session)
              Log.log.debug( 'transfer ok'.bg_red );
              session[:state]=:success
              break
            rescue Fasp::Error => e
              Log.log.warn("An error occured: #{e.message}" );
              # failure in ascp
              if Error.fasp_error_retryable?(e.err_code) then
                # exit if we exceed the max number of retry
                unless remaining_tries > 0
                  Log.log.error "Maximum number of retry reached"
                  raise Fasp::Error,"max retry after: [#{status[:message]}]"
                end
              else
                # give one chance only to non retryable errors
                unless remaining_tries.eql?(session[:max_retry])
                  Log.log.error('non-retryable error')
                  raise e
                end
              end
            end

            # take this retry in account
            remaining_tries-=1
            Log.log.warn( "resuming in  #{session[:sleep_seconds]} seconds (retry left:#{remaining_tries})" );

            # wait a bit before retrying, maybe network condition will be better
            sleep(session[:sleep_seconds])

            # increase retry period
            session[:sleep_seconds] *= session[:sleep_factor]
            if session[:sleep_seconds] > session[:sleep_max] then
              session[:sleep_seconds] = session[:sleep_max]
            end
          end # loop
        rescue => e
          Log.log.error(e.message)
        ensure
          @mutex.synchronize do
            session[:state]=:failed unless session[:state].eql?(:success)
            @cond_var.broadcast
          end
        end
        Log.log.debug("EXIT (#{Thread.current[:name]})")
      end

      # main thread method for monitor
      def monitor_thread_entry
        Thread.current[:name]="monitor"
        @mutex.synchronize do
          while @monitor_run
            @cond_var.wait(@mutex)
            @jobs.each do |job|
              job[:sessions].each do |session|
                case session[:state]
                when :success,:failed
                  session[:thread].join
                  #@cond_var.broadcast
                when :failure
                end # state
              end # sessions
            end # jobs
          end # monitor run
        end # sync
        Log.log.debug("EXIT (#{Thread.current[:name]})")
      end # monitor_thread_entry
    end # Local
  end
end
