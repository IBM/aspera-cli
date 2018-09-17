#!/bin/echo this is a ruby class:
#
# FASP manager for Ruby
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/fasp/manager/base'
require 'asperalm/fasp/error'
require 'asperalm/fasp/parameters'
require 'asperalm/fasp/installation'
require 'asperalm/log'
require 'socket'
require 'timeout'

module Asperalm
  module Fasp
    module Manager
      ACCESS_KEY_TRANSFER_USER='xfer'
      # executes a local "ascp", equivalent of "Fasp Manager"
      class Local < Base
        def start_transfer(transfer_spec)
          # resume parameters, could be modified by options (TODO)
          max_retry     = 7
          sleep_seconds = 2
          sleep_factor  = 2
          sleep_max     = 60

          # maximum of retry
          lRetryLeft = max_retry
          Log.log.debug("retries=#{lRetryLeft}")

          # try to send the file until ascp is succesful
          loop do
            Log.log.debug('transfer starting');
            begin
              start_transfer_once(transfer_spec)
              Log.log.debug( 'transfer ok'.bg_red );
              break
            rescue Fasp::Error => e
              Log.log.warn( "An error occured: #{e.message}" );
              # failure in ascp
              if fasp_error_retryable?(e.err_code) then
                # exit if we exceed the max number of retry
                unless lRetryLeft > 0
                  Log.log.error "Maximum number of retry reached"
                  raise Fasp::Error,"max retry after: [#{status[:message]}]"
                end
              else
                # give one chance only to non retryable errors
                unless lRetryLeft.eql?(max_retry)
                  Log.log.error('non-retryable error')
                  raise e
                end
              end
            end

            # take this retry in account
            lRetryLeft-=1
            Log.log.warn( "resuming in  #{sleep_seconds} seconds (retry left:#{lRetryLeft})" );

            # wait a bit before retrying, maybe network condition will be better
            sleep(sleep_seconds)

            # increase retry period
            sleep_seconds *= sleep_factor
            if sleep_seconds > sleep_max then
              sleep_seconds = sleep_max
            end
          end # loop
        end

        # start FASP transfer based on transfer spec (hash table)
        # note that it returns upon completion only (blocking)
        # if the user wants to run in background, just spawn a thread
        # listener methods are called in context of calling thread
        def start_transfer_once(transfer_spec)
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
          # add fallback cert and key
          if ['1','force'].include?(transfer_spec['http_fallback'])
            transfer_spec['EX_fallback_key']=Installation.instance.path(:fallback_key)
            transfer_spec['EX_fallback_cert']=Installation.instance.path(:fallback_cert)
          end
          env_args=Parameters.ts_to_env_args(transfer_spec)

          thread_info={:state=>:create,:ts=>transfer_spec}
          thread_info[:thread] = Thread.new(thread_info) {|ti| Thread.current[:name]="transfer";Thread.current[:ti]=ti;start_transfer_with_args_env(env_args)  }
          @sessions_mutex.synchronize do
            # check failure here
            until thread_info.has_key?(:id)
              Log.log.debug("waiting for id..")
              @sessions_cv.wait(@sessions_mutex)
            end
            raise "error" if thread_info[:id].nil?
            Log.log.debug("id:#{thread_info[:id]}")
            @sessions_info[thread_info[:id]]=thread_info
          end
          #return thread_info[:id]
          #return nil
          wait_for_all_completed(true)
        end # start_transfer

        # call to terminate threads
        def shutdown
          @sessions_mutex.synchronize do
            @monitor_run=false
            @sessions_cv.broadcast
          end
          @monitor.join
          @monitor=nil
          Log.log.debug("joined monitor")
        end

        def wait_for_all_completed(do_finalize=false)
          loop do
            @sessions_mutex.synchronize do
              return if @sessions_info.empty?
              Log.log.debug("wait for completed: not empty: #{@sessions_info.keys}")
              @sessions_cv.wait(@sessions_mutex)
            end
          end
          shutdown if do_finalize
        end

        private

        def initialize
          super
          # mutex and condition variable for inter thread communication
          @sessions_mutex=Mutex.new
          @sessions_cv=ConditionVariable.new
          # shared data protected by mutex, CV on change
          @sessions_info={}
          # must be set before starting monitor, set to false to stop thread
          @monitor_run=true
          @monitor=Thread.new{Thread.current[:name]="monitor";thread_main_monitor}
        end

        # main thread method for monitor
        def thread_main_monitor
          @sessions_mutex.synchronize do
            while @monitor_run
              Log.log.debug("wait")
              @sessions_cv.wait(@sessions_mutex)
              Log.log.debug("waked")
              @sessions_info.each do |k,v|
                if v[:state].eql?(:finished)
                  Log.log.debug("thread finished: #{k}")
                  v[:thread].join
                  Log.log.debug("joined")
                  @sessions_info.delete(k)
                  Log.log.debug("notify changed")
                  @sessions_cv.broadcast
                  Log.log.debug("deleted")
                end
              end
            end  # while
          end # sync
          Log.log.debug("EXIT")
        end

        # main thread method for transfer
        def thread_main_transfer(ti)

          @sessions_mutex.synchronize do
            # Thread 'a' now needs the resource
            Log.log.debug("wait for id")
            sleep 1
            ti[:id]=123
            ti[:state]=:started
            @sessions_cv.broadcast
          end
          4.times do
            Log.log.debug("working...")
            sleep 1
          end
          @sessions_mutex.synchronize do
            # Thread 'a' now needs the resource
            ti[:state]=:finished
            @sessions_cv.broadcast
          end
          Log.log.debug("EXIT")
        end

        # This is the low level method to start FASP
        # currently, relies on command line arguments
        # start ascp with management port.
        # raises FaspError on error
        # @param env_args a hash containing :args :env :ascp_version :finalize
        def start_transfer_with_args_env(env_args)
          begin
            thread_info=Thread.current[:ti]
            raise "missing thread info" if thread_info.nil?
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
              Log.log.debug "line=[#{line}]"
              case line
              when 'FASPMGR 2'
                # begin frame
                current_event_data = Hash.new
                current_event_text = ''
              when /^([^:]+): (.*)$/
                # payload
                current_event_data[$1] = $2
              when ''
                # end frame
                raise "unexpected empty line" if current_event_data.nil?
                notify_listeners(current_event_text,current_event_data)
                # TODO: check if this is always the last event
                case current_event_data['Type']
                when 'DONE','ERROR'
                  last_status_event = current_event_data
                when 'INIT'
                  @sessions_mutex.synchronize do
                    thread_info[:id]=current_event_data['SessionId']
                    Log.log.warn("session: #{thread_info[:id]}")
                    thread_info[:state]=:started
                    @sessions_cv.broadcast
                  end
                end
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
          rescue SystemCallError=> e
            # Process.spawn
            raise Fasp::Error.new(e.message)
          rescue Timeout::Error => e
            raise Fasp::Error.new('timeout waiting mgt port connect')
          rescue Interrupt => e
            raise Fasp::Error.new('transfer interrupted by user')
          ensure
            # delete file lists
            env_args[:finalize].call()
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
            thread_info=Thread.current[:ti]
            @sessions_mutex.synchronize do
              # Thread 'a' now needs the resource
              thread_info[:state]=:finished
              @sessions_cv.broadcast
            end
          end # begin
        end # start_transfer_with_args_env
      end # Local
    end # Agent
  end # Fasp
end # AsperaLm
