#!/bin/echo this is a ruby class:
#
# FASP manager for Ruby
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'aspera/fasp/manager'
require 'aspera/fasp/error'
require 'aspera/fasp/parameters'
require 'aspera/fasp/installation'
require 'aspera/fasp/resume_policy'
require 'aspera/log'
require 'socket'
require 'timeout'
require 'securerandom'

module Aspera
  module Fasp
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class Local < Manager
      # options for initialize (same as values in option transfer_info)
      DEFAULT_OPTIONS = {
        :spawn_timeout_sec => 3,
        :spawn_delay_sec   => 2,
        :wss               => false,
        :multi_incr_udp    => true,
        :resume            => {}
      }
      DEFAULT_UDP_PORT=33001
      private_constant :DEFAULT_OPTIONS
      # set to false to keep ascp progress bar display ("true" adds ascp's option -q)
      attr_accessor :quiet

      # start ascp transfer (non blocking), single or multi-session
      # job information added to @jobs
      # @param transfer_spec [Hash] aspera transfer specification
      # @param options [Hash] :resumer, :regenerate_token
      def start_transfer(transfer_spec,options={})
        raise 'option: must be hash (or nil)' unless options.is_a?(Hash)
        job_options = options.clone
        job_options[:resumer] ||= @resume_policy
        job_options[:job_id] ||= SecureRandom.uuid
        # clone transfer spec because we modify it (first level keys)
        transfer_spec=transfer_spec.clone
        # if there is aspera tags
        if transfer_spec['tags'].is_a?(Hash) and transfer_spec['tags']['aspera'].is_a?(Hash)
          # TODO: what is this for ? only on local ascp ?
          # NOTE: important: transfer id must be unique: generate random id
          # using a non unique id results in discard of tags in AoC, and a package is never finalized
          transfer_spec['tags']['aspera']['xfer_id']||=SecureRandom.uuid
          Log.log.debug("xfer id=#{transfer_spec['xfer_id']}")
          # TODO: useful ? node only ?
          transfer_spec['tags']['aspera']['xfer_retry']||=3600
        end
        Log.dump('ts',transfer_spec)

        # add bypass keys when authentication is token and no auth is provided
        if transfer_spec.has_key?('token') and
        !transfer_spec.has_key?('remote_password') and
        !transfer_spec.has_key?('EX_ssh_key_paths')
          # transfer_spec['remote_password'] = Installation.instance.bypass_pass # not used
          transfer_spec['EX_ssh_key_paths'] = Installation.instance.bypass_keys
        end

        # Compute this before using transfer spec because it potentially modifies the transfer spec
        # (even if the var is not used in single session)
        multi_session_info=nil
        if transfer_spec.has_key?('multi_session')
          multi_session_info={
            count: transfer_spec['multi_session'].to_i,
          }
          # Managed by multi-session, so delete from transfer spec
          transfer_spec.delete('multi_session')
          if multi_session_info[:count] < 0
            Log.log.error("multi_session(#{transfer_spec['multi_session']}) shall be integer >= 0")
            multi_session_info = nil
          elsif multi_session_info[:count].eql?(0)
            Log.log.debug("multi_session  count is zero: no multisession")
            multi_session_info = nil
          else # multi_session_info[:count] > 0
            # if option not true: keep default udp port for all sessions
            if @options[:multi_incr_udp]
              # override if specified, else use default value
              multi_session_info[:udp_base]=transfer_spec.has_key?('fasp_port') ? transfer_spec['fasp_port'] : DEFAULT_UDP_PORT
              # delete from original transfer spec, as we will increment values
              transfer_spec.delete('fasp_port')
            end
          end
        end

        # compute known args
        env_args=Parameters.ts_to_env_args(transfer_spec,wss: @options[:wss])

        # add fallback cert and key as arguments if needed
        if ['1','force'].include?(transfer_spec['http_fallback'])
          env_args[:args].unshift('-Y',Installation.instance.path(:fallback_key))
          env_args[:args].unshift('-I',Installation.instance.path(:fallback_cert))
        end

        env_args[:args].unshift('-q') if @quiet

        # transfer job can be multi session
        xfer_job={
          :id            => job_options[:job_id],
          :sessions      => [] # all sessions as below
        }

        # generic session information
        session={
          :thread   => nil,         # Thread object monitoring management port, not nil when pushed to :sessions
          :error    => nil,         # exception if failed
          :io       => nil,         # management port server socket
          :id       => nil,         # SessionId from INIT message in mgt port
          :env_args => env_args,    # env vars and args to ascp (from transfer spec)
          :options  => job_options  # [Hash]
        }

        if multi_session_info.nil?
          Log.log.debug('Starting single session thread')
          # single session for transfer : simple
          session[:thread] = Thread.new(session) {|s|transfer_thread_entry(s)}
          xfer_job[:sessions].push(session)
        else
          Log.log.debug('Starting multi session threads')
          1.upto(multi_session_info[:count]) do |i|
            # do not delay the first session
            sleep(@options[:spawn_delay_sec]) unless i.eql?(1)
            # do deep copy (each thread has its own copy because it is modified here below and in thread)
            this_session=session.clone()
            this_session[:env_args]=this_session[:env_args].clone()
            this_session[:env_args][:args]=this_session[:env_args][:args].clone()
            this_session[:env_args][:args].unshift("-C#{i}:#{multi_session_info[:count]}")
            # option: increment (default as per ascp manual) or not (cluster on other side ?)
            this_session[:env_args][:args].unshift('-O',"#{multi_session_info[:udp_base]+i-1}") if @options[:multi_incr_udp]
            this_session[:thread] = Thread.new(this_session) {|s|transfer_thread_entry(s)}
            xfer_job[:sessions].push(this_session)
          end
        end
        Log.log.debug('started session thread(s)')

        # add job to list of jobs
        @jobs[job_options[:job_id]]=xfer_job
        Log.log.debug("jobs: #{@jobs.keys.count}")

        return job_options[:job_id]
      end # start_transfer

      # wait for completion of all jobs started
      # @return list of :success or error message
      def wait_for_transfers_completion
        Log.log.debug('wait_for_transfers_completion')
        # set to non-nil to exit loop
        result=[]
        @jobs.each do |id,job|
          job[:sessions].each do |session|
            Log.log.debug("join #{session[:thread]}")
            session[:thread].join
            result.push(session[:error] ? session[:error] : :success)
          end
        end
        Log.log.debug('all transfers joined')
        # since all are finished and we return the result, clear statuses
        @jobs.clear
        return result
      end

      # used by asession (to be removed ?)
      def shutdown
        Log.log.debug('fasp local shutdown')
      end

      # This is the low level method to start the "ascp" process
      # currently, relies on command line arguments
      # start ascp with management port.
      # raises FaspError on error
      # if there is a thread info: set and broadcast session id
      # @param env_args a hash containing :args :env :ascp_version
      # @param session this session information
      # could be private method
      def start_transfer_with_args_env(env_args,session)
        raise 'env_args must be Hash' unless env_args.is_a?(Hash)
        raise 'session must be Hash' unless session.is_a?(Hash)
        # by default we assume an exception will be raised (for ensure block)
        exception_raised=true
        begin
          Log.log.debug("env_args=#{env_args.inspect}")
          # get location of ascp executable
          ascp_path=@mutex.synchronize do
            Fasp::Installation.instance.path(env_args[:ascp_version])
          end
          # (optional) check it exists
          raise Fasp::Error.new("no such file: #{ascp_path}") unless File.exist?(ascp_path)
          # open random local TCP port for listening for ascp management
          mgt_sock = TCPServer.new('127.0.0.1',0)
          # clone arguments as we eed to modify with mgt port
          ascp_arguments=env_args[:args].clone
          # add management port
          ascp_arguments.unshift('-M', mgt_sock.addr[1].to_s)
          # start ascp in sub process
          Log.log.debug("execute: #{env_args[:env].map{|k,v| "#{k}=\"#{v}\""}.join(' ')} \"#{ascp_path}\" \"#{ascp_arguments.join('" "')}\"")
          # start process
          ascp_pid = Process.spawn(env_args[:env],[ascp_path,ascp_path],*ascp_arguments)
          # in parent, wait for connection to socket max 3 seconds
          Log.log.debug("before accept for pid (#{ascp_pid})")
          # init management socket
          ascp_mgt_io=nil
          Timeout.timeout(@options[:spawn_timeout_sec]) do
            ascp_mgt_io = mgt_sock.accept
            # management messages include file names which may be utf8
            # by default socket is US-ASCII
            # TODO: use same value as Encoding.default_external
            ascp_mgt_io.set_encoding(Encoding::UTF_8)
          end
          Log.log.debug("after accept (#{ascp_mgt_io})")
          session[:io]=ascp_mgt_io
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
              # empty line is separator to end event information
              raise 'unexpected empty line' if current_event_data.nil?
              current_event_data[Manager::LISTENER_SESSION_ID_B]=ascp_pid
              notify_listeners(current_event_text,current_event_data)
              case current_event_data['Type']
              when 'INIT'
                session[:id]=current_event_data['SessionId']
                Log.log.debug("session id: #{session[:id]}")
              when 'DONE','ERROR'
                # TODO: check if this is always the last event
                last_status_event = current_event_data
              end # event type
            else
              raise "unexpected line:[#{line}]"
            end # case
          end # loop (process mgt port lines)
          # check that last status was received before process exit
          if last_status_event.is_a?(Hash)
            case last_status_event['Type']
            when 'DONE'
              # all went well
              exception_raised=false
            when 'ERROR'
              Log.log.error("code: #{last_status_event['Code']}")
              if last_status_event['Description']  =~ /bearer token/i
                Log.log.error('need to regenerate token'.red)
                if session[:options].is_a?(Hash) and session[:options].has_key?(:regenerate_token)
                  # regenerate token here, expired, or error on it
                  # Note: in multi-session, each session will have a different one.
                  env_args[:env]['ASPERA_SCP_TOKEN']=session[:options][:regenerate_token].call(true)
                end
              end
              raise Fasp::Error.new(last_status_event['Description'],last_status_event['Code'].to_i)
            else # case
              raise "unexpected last event type: #{last_status_event['Type']}"
            end
          else
            exception_raised=false
            Log.log.debug('no status read from ascp mgt port')
          end
        rescue SystemCallError => e
          # Process.spawn
          raise Fasp::Error.new(e.message)
        rescue Timeout::Error => e
          raise Fasp::Error.new('timeout waiting mgt port connect')
        rescue Interrupt => e
          raise Fasp::Error.new('transfer interrupted by user')
        ensure
          # if ascp was successfully started
          unless ascp_pid.nil?
            # "wait" for process to avoid zombie
            Process.wait(ascp_pid)
            status=$?
            ascp_pid=nil
            session.delete(:io)
            if !status.success?
              message="ascp failed with code #{status.exitstatus}"
              if exception_raised
                # just debug, as main exception is already here
                Log.log.debug(message)
              else
                raise Fasp::Error.new(message)
              end
            end
          end
        end # begin-ensure
      end # start_transfer_with_args_env

      # send command of management port to ascp session
      # @param job_id identified transfer process
      # @param session_index index of session (for multi session)
      # @param data command on mgt port, examples:
      # {'type'=>'START','source'=>_path_,'destination'=>_path_}
      # {'type'=>'DONE'}
      def send_command(job_id,session_index,data)
        job=@jobs[job_id]
        raise 'no such job' if job.nil?
        session=job[:sessions][session_index]
        raise 'no such session' if session.nil?
        Log.log.debug("command: #{data}")
        # build command
        command=data.
        keys.
        map{|k|"#{k.capitalize}: #{data[k]}"}.
        unshift('FASPMGR 2').
        push('','').
        join("\n")
        session[:io].puts(command)
      end

      private

      # @param options : keys(symbol): see DEFAULT_OPTIONS
      def initialize(options=nil)
        super()
        # by default no interactive progress bar
        @quiet=true
        # all transfer jobs, key = SecureRandom.uuid, protected by mutex, condvar on change
        @jobs={}
        # mutex protects global data accessed by threads
        @mutex=Mutex.new
        # set default options and override if specified
        @options=DEFAULT_OPTIONS.clone
        if !options.nil?
          raise "expecting Hash (or nil), but have #{options.class}" unless options.is_a?(Hash)
          options.each do |k,v|
            if DEFAULT_OPTIONS.has_key?(k)
              @options[k]=v
            else
              raise "Unknown local agent parameter: #{k}, expect one of #{DEFAULT_OPTIONS.keys.map{|i|i.to_s}.join(",")}"
            end
          end
        end
        Log.log.debug("local options= #{options}")
        @resume_policy=ResumePolicy.new(@options[:resume].symbolize_keys)
      end

      # transfer thread entry
      # @param session information
      def transfer_thread_entry(session)
        begin
          # set name for logging
          Thread.current[:name]='transfer'
          Log.log.debug("ENTER (#{Thread.current[:name]})")
          # start transfer with selected resumer policy
          session[:options][:resumer].process do
            start_transfer_with_args_env(session[:env_args],session)
          end
          Log.log.debug('transfer ok'.bg_green)
        rescue => e
          session[:error]=e
          Log.log.error("Transfer thread error: #{e.class}:\n#{e.message}:\n#{e.backtrace.join("\n")}".red) if Log.instance.level.eql?(:debug)
        end
        Log.log.debug("EXIT (#{Thread.current[:name]})")
      end

    end # Local
  end
end
