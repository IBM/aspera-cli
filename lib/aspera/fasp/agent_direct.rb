# frozen_string_literal: true

require 'English'
require 'aspera/fasp/agent_base'
require 'aspera/fasp/error'
require 'aspera/fasp/parameters'
require 'aspera/fasp/installation'
require 'aspera/fasp/resume_policy'
require 'aspera/fasp/transfer_spec'
require 'aspera/fasp/management'
require 'aspera/log'
require 'socket'
require 'timeout'
require 'securerandom'
require 'shellwords'

module Aspera
  module Fasp
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class AgentDirect < Aspera::Fasp::AgentBase
      # options for initialize (same as values in option transfer_info)
      DEFAULT_OPTIONS = {
        spawn_timeout_sec: 3,
        spawn_delay_sec:   2,
        wss:               true, # true: if both SSH and wss in ts: prefer wss
        multi_incr_udp:    true,
        resume:            {},
        ascp_args:         [],
        check_ignore:      nil, # callback with host,port
        quiet:             true, # by default no native ascp progress bar
        trusted_certs:     [] # list of files with trusted certificates (stores)
      }.freeze
      # spellchecker: enable
      private_constant :DEFAULT_OPTIONS

      # start ascp transfer (non blocking), single or multi-session
      # job information added to @jobs
      # @param transfer_spec [Hash] aspera transfer specification
      def start_transfer(transfer_spec, token_regenerator: nil)
        the_job_id = SecureRandom.uuid
        # clone transfer spec because we modify it (first level keys)
        transfer_spec = transfer_spec.clone
        # if there is aspera tags
        if transfer_spec['tags'].is_a?(Hash) && transfer_spec['tags'][Fasp::TransferSpec::TAG_RESERVED].is_a?(Hash)
          # TODO: what is this for ? only on local ascp ?
          # NOTE: important: transfer id must be unique: generate random id
          # using a non unique id results in discard of tags in AoC, and a package is never finalized
          # all sessions in a multi-session transfer must have the same xfer_id (see admin manual)
          transfer_spec['tags'][Fasp::TransferSpec::TAG_RESERVED]['xfer_id'] ||= SecureRandom.uuid
          Log.log.debug{"xfer id=#{transfer_spec['xfer_id']}"}
          # TODO: useful ? node only ?
          transfer_spec['tags'][Fasp::TransferSpec::TAG_RESERVED]['xfer_retry'] ||= 3600
        end
        Log.log.debug{Log.dump('ts', transfer_spec)}

        # Compute this before using transfer spec because it potentially modifies the transfer spec
        # (even if the var is not used in single session)
        multi_session_info = nil
        if transfer_spec.key?('multi_session')
          multi_session_info = {
            count: transfer_spec['multi_session'].to_i
          }
          # Managed by multi-session, so delete from transfer spec
          transfer_spec.delete('multi_session')
          if multi_session_info[:count].negative?
            Log.log.error{"multi_session(#{transfer_spec['multi_session']}) shall be integer >= 0"}
            multi_session_info = nil
          elsif multi_session_info[:count].eql?(0)
            Log.log.debug('multi_session count is zero: no multi session')
            multi_session_info = nil
          elsif @options[:multi_incr_udp] # multi_session_info[:count] > 0
            # if option not true: keep default udp port for all sessions
            multi_session_info[:udp_base] = transfer_spec.key?('fasp_port') ? transfer_spec['fasp_port'] : TransferSpec::UDP_PORT
            # delete from original transfer spec, as we will increment values
            transfer_spec.delete('fasp_port')
            # override if specified, else use default value
          end
        end

        # compute known arguments and environment variables
        env_args = Parameters.new(transfer_spec, @options).ascp_args

        # transfer job can be multi session
        xfer_job = {
          id:       the_job_id,
          sessions: [] # all sessions as below
        }

        # generic session information
        session = {
          thread:            nil,               # Thread object monitoring management port, not nil when pushed to :sessions
          error:             nil,               # exception if failed
          io:                nil,               # management port server socket
          id:                nil,               # SessionId from INIT message in mgt port
          token_regenerator: token_regenerator, # regenerate bearer token with oauth
          env_args:          env_args           # env vars and args to ascp (from transfer spec)
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
            this_session = session.clone
            this_session[:env_args] = this_session[:env_args].clone
            this_session[:env_args][:args] = this_session[:env_args][:args].clone
            this_session[:env_args][:args].unshift("-C#{i}:#{multi_session_info[:count]}")
            # option: increment (default as per ascp manual) or not (cluster on other side ?)
            this_session[:env_args][:args].unshift('-O', (multi_session_info[:udp_base] + i - 1).to_s) if @options[:multi_incr_udp]
            this_session[:thread] = Thread.new(this_session) {|s|transfer_thread_entry(s)}
            xfer_job[:sessions].push(this_session)
          end
        end
        Log.log.debug('started session thread(s)')

        # add job to list of jobs
        @jobs[the_job_id] = xfer_job
        Log.log.debug{"jobs: #{@jobs.keys.count}"}

        return the_job_id
      end # start_transfer

      # wait for completion of all jobs started
      # @return list of :success or error message
      def wait_for_transfers_completion
        Log.log.debug('wait_for_transfers_completion')
        # set to non-nil to exit loop
        result = []
        @jobs.each do |_id, job|
          job[:sessions].each do |session|
            Log.log.debug{"join #{session[:thread]}"}
            session[:thread].join
            result.push(session[:error] || :success)
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

      # begin 'Type' => 'NOTIFICATION', 'PreTransferBytes' => size
      # progress 'Type' => 'STATS', 'Bytescont' => size
      # end 'Type' => 'DONE'

      # @param event management port event
      def process_progress(event)
        session_id = event['SessionId']
        case event['Type']
        when 'INIT'
          @precalc_sent = false
          @precalc_last_size = nil
          notify_progress(session_id: session_id, type: :session_start)
        when 'NOTIFICATION' # sent from remote
          if event.key?('PreTransferBytes')
            @precalc_sent = true
            notify_progress(session_id: session_id, type: :session_size, info: event['PreTransferBytes'])
          end
        when 'STATS' # during transfer
          @precalc_last_size = event['TransferBytes'].to_i + event['StartByte'].to_i
          notify_progress(session_id: session_id, type: :transfer, info: @precalc_last_size)
        when 'DONE', 'ERROR' # end of session
          total_size = event['TransferBytes'].to_i + event['StartByte'].to_i
          if !@precalc_sent
            notify_progress(session_id: session_id, type: :session_size, info: total_size)
          end
          if @precalc_last_size != total_size
            notify_progress(session_id: session_id, type: :transfer, info: total_size)
          end
          notify_progress(session_id: session_id, type: :end)
        when 'SESSION'
        when 'ARGSTOP'
        when 'FILEERROR'
        when 'STOP'
          # stop event when one file is completed
        else
          Log.log.debug{"unknown event type #{event['Type']}"}
        end
      end

      # This is the low level method to start the "ascp" process
      # currently, relies on command line arguments
      # start ascp with management port.
      # raises FaspError on error
      # if there is a thread info: set and broadcast session id
      # @param env_args a hash containing :args :env :ascp_version
      # @param session this session information
      # could be private method
      def start_transfer_with_args_env(env_args, session)
        raise 'env_args must be Hash' unless env_args.is_a?(Hash)
        raise 'session must be Hash' unless session.is_a?(Hash)
        begin
          Log.log.debug{"env_args=#{env_args.inspect}"}
          # get location of ascp executable
          ascp_path = @mutex.synchronize do
            Fasp::Installation.instance.path(env_args[:ascp_version])
          end
          # (optional) check it exists
          raise Fasp::Error, "no such file: #{ascp_path}" unless File.exist?(ascp_path)
          notify_progress(session_id: nil, type: :pre_start, info: 'starting ascp')
          # open an available (0) local TCP port as ascp management
          mgt_sock = TCPServer.new('127.0.0.1', 0)
          # clone arguments as we eed to modify with mgt port
          ascp_arguments = env_args[:args].clone
          # add management port on the selected local port
          ascp_arguments.unshift('-M', mgt_sock.addr[1].to_s)
          # display ascp command line
          Log.log.debug do
            [
              'execute:',
              env_args[:env].map{|k, v| "#{k}=#{Shellwords.shellescape(v)}"},
              Shellwords.shellescape(ascp_path),
              ascp_arguments.map{|a|Shellwords.shellescape(a)}
            ].flatten.join(' ')
          end
          # start ascp in separate process
          ascp_pid = Process.spawn(env_args[:env], [ascp_path, ascp_path], *ascp_arguments)
          # in parent, wait for connection to socket max 3 seconds
          Log.log.debug{"before accept for pid (#{ascp_pid})"}
          # init management socket
          ascp_mgt_io = nil
          notify_progress(session_id: nil, type: :pre_start, info: 'waiting for ascp')
          Timeout.timeout(@options[:spawn_timeout_sec]) do
            ascp_mgt_io = mgt_sock.accept
            # management messages include file names which may be utf8
            # by default socket is US-ASCII
            # TODO: use same value as Encoding.default_external
            ascp_mgt_io.set_encoding(Encoding::UTF_8)
          end
          Log.log.debug{"after accept (#{ascp_mgt_io})"}
          session[:io] = ascp_mgt_io
          processor = Management.new
          # read management port, until socket is closed (gets returns nil)
          while (line = ascp_mgt_io.gets)
            event = processor.process_line(line.chomp)
            next unless event
            # event is ready
            Log.log.debug{Log.dump(:management_port, event)}
            # Log.log.trace1{"event: #{JSON.generate(Management.enhanced_event_format(event))}"}
            process_progress(event)
            Log.log.error((event['Description']).to_s) if event['Type'].eql?('FILEERROR')
          end
          last_event = processor.last_event
          # check that last status was received before process exit
          if last_event.is_a?(Hash)
            case last_event['Type']
            when 'ERROR'
              if /bearer token/i.match?(last_event['Description']) &&
                  session[:token_regenerator].respond_to?(:refreshed_transfer_token)
                # regenerate token here, expired, or error on it
                # Note: in multi-session, each session will have a different one.
                Log.log.warn('Regenerating bearer token')
                env_args[:env]['ASPERA_SCP_TOKEN'] = session[:token_regenerator].refreshed_transfer_token
              end
              raise Fasp::Error.new(last_event['Description'], last_event['Code'].to_i)
            when 'DONE'
              nil
            else
              raise "unexpected last event type: #{last_event['Type']}"
            end # case
          end
        rescue SystemCallError => e
          # Process.spawn
          raise Fasp::Error, e.message
        rescue Timeout::Error
          raise Fasp::Error, 'timeout waiting mgt port connect'
        rescue Interrupt
          raise Fasp::Error, 'transfer interrupted by user'
        ensure
          # if ascp was successfully started
          unless ascp_pid.nil?
            # "wait" for process to avoid zombie
            Process.wait(ascp_pid)
            status = $CHILD_STATUS
            ascp_pid = nil
            session.delete(:io)
            if !status.success?
              message = "ascp failed with code #{status.exitstatus}"
              # raise error only if there was not already an exception
              raise Fasp::Error, message unless $ERROR_INFO
              # else just debug, as main exception is already here
              Log.log.debug(message)
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
      def send_command(job_id, session_index, data)
        job = @jobs[job_id]
        raise 'no such job' if job.nil?
        session = job[:sessions][session_index]
        raise 'no such session' if session.nil?
        Log.log.debug{"command: #{data}"}
        # build command
        command = data
          .keys
          .map{|k|"#{k.capitalize}: #{data[k]}"}
          .unshift(MGT_HEADER)
          .push('', '')
          .join("\n")
        session[:io].puts(command)
      end

      private

      # @param options : keys(symbol): see DEFAULT_OPTIONS
      def initialize(options={})
        super(options)
        # all transfer jobs, key = SecureRandom.uuid, protected by mutex, cond var on change
        @jobs = {}
        # mutex protects global data accessed by threads
        @mutex = Mutex.new
        # set default options and override if specified
        @options = AgentBase.options(default: DEFAULT_OPTIONS, options: options)
        @resume_policy = ResumePolicy.new(@options[:resume].symbolize_keys)
        Log.log.debug{Log.dump(:agent_options, @options)}
      end

      # transfer thread entry
      # @param session information
      def transfer_thread_entry(session)
        begin
          # set name for logging
          Thread.current[:name] = 'transfer'
          Log.log.debug{"ENTER (#{Thread.current[:name]})"}
          # start transfer with selected resumer policy
          @resume_policy.execute_with_resume do
            start_transfer_with_args_env(session[:env_args], session)
          end
          Log.log.debug('transfer ok'.bg_green)
        rescue StandardError => e
          session[:error] = e
          Log.log.error{"Transfer thread error: #{e.class}:\n#{e.message}:\n#{e.backtrace.join("\n")}".red} if Log.instance.level.eql?(:debug)
        end
        Log.log.debug{"EXIT (#{Thread.current[:name]})"}
      end
    end # AgentDirect
  end
end
