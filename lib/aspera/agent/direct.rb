# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/ascp/installation'
require 'aspera/ascp/management'
require 'aspera/transfer/parameters'
require 'aspera/transfer/error'
require 'aspera/transfer/spec'
require 'aspera/transfer/resumer'
require 'aspera/log'
require 'aspera/assert'
require 'socket'
require 'securerandom'
require 'shellwords'
require 'English'

module Aspera
  module Agent
    # executes a local "ascp", create mgt port
    class Direct < Base
      # ascp started locally, so listen local
      LISTEN_LOCAL_ADDRESS = '127.0.0.1'
      # 0 means: use any available port
      SELECT_AVAILABLE_PORT = 0
      private_constant :LISTEN_LOCAL_ADDRESS, :SELECT_AVAILABLE_PORT

      # Options: same as values in option `transfer_info`
      # @param ascp_args         [Array]   (Params) Optional Additional arguments to ascp
      # @param wss               [Boolean] (Params) `true`: if both SSH and wss in ts: prefer wss
      # @param quiet             [Boolean] (Params) By default no native `ascp` progress bar
      # @param monitor           [Boolean] (Params) Set to `false` to eliminate management port
      # @param trusted_certs     [Array]   (Params) Optional list of files with trusted certificates (stores)
      # @param client_ssh_key    [String]  (Params) Client SSH key option (from CLIENT_SSH_KEY_OPTIONS)
      # @param check_ignore_cb   [Proc]    (Params) Callback with host,port
      # @param spawn_timeout_sec [Integer] Timeout for ascp spawn
      # @param spawn_delay_sec   [Integer] Optional delay to start between sessions
      # @param multi_incr_udp    [Boolean] Optional `true`: increment UDP port for each session
      # @param resume            [Hash]    Optional Resume policy
      # @param management_cb     [Proc]    callback for management events
      # @param base_options      [Hash]    other options for base class
      def initialize(
        ascp_args:         nil,
        wss:               true,
        quiet:             true,
        trusted_certs:     nil,
        client_ssh_key:    nil,
        check_ignore_cb:   nil,
        spawn_timeout_sec: 2,
        spawn_delay_sec:   2,
        multi_incr_udp:    nil,
        resume:            nil,
        monitor:           true,
        management_cb:     nil,
        **base_options
      )
        super(**base_options)
        # Special transfer parameters provided
        @tr_opts = {
          ascp_args:       ascp_args,
          wss:             wss,
          quiet:           quiet,
          trusted_certs:   trusted_certs,
          client_ssh_key:  client_ssh_key,
          check_ignore_cb: check_ignore_cb
        }
        @spawn_timeout_sec = spawn_timeout_sec
        @spawn_delay_sec = spawn_delay_sec
        # default is true on Windows, false on other OSes
        @multi_incr_udp = multi_incr_udp.nil? ? Environment.instance.os.eql?(Environment::OS_WINDOWS) : multi_incr_udp
        @monitor = monitor
        @management_cb = management_cb
        resume = {} if resume.nil?
        Aspera.assert_type(resume, Hash){'resume'}
        @resume_policy = Transfer::Resumer.new(**resume.symbolize_keys)
        # all transfer jobs, key = SecureRandom.uuid, protected by mutex, cond var on change
        @sessions = []
        # mutex protects global data accessed by threads
        @mutex = Mutex.new
        @pre_calc_sent = false
        @pre_calc_last_size = nil
        @command_file = File.join(config_dir || '.', "send_#{$PROCESS_ID}")
      end

      # Start `ascp` transfer(s) (non blocking), single or multi-session
      # Session information added to @sessions
      # @param transfer_spec     [Hash]   Aspera transfer specification
      # @param token_regenerator [Object] Object with method refreshed_transfer_token
      def start_transfer(transfer_spec, token_regenerator: nil)
        # clone transfer spec because we modify it (first level keys)
        transfer_spec = transfer_spec.clone
        # if there are aspera tags
        if transfer_spec.dig('tags', Transfer::Spec::TAG_RESERVED).is_a?(Hash)
          # TODO: what is this for ? only on local ascp ?
          # NOTE: important: transfer id must be unique: generate random id
          # using a non unique id results in discard of tags in AoC, and a package is never finalized
          # all sessions in a multi-session transfer must have the same xfer_id (see admin manual)
          transfer_spec['tags'][Transfer::Spec::TAG_RESERVED]['xfer_id'] ||= SecureRandom.uuid
          Log.log.debug{"xfer id=#{transfer_spec['xfer_id']}"}
          # TODO: useful ? node only ? seems to be a timeout for retry in node
          transfer_spec['tags'][Transfer::Spec::TAG_RESERVED]['xfer_retry'] ||= 3600
        end
        Log.dump(:ts, transfer_spec)
        # Compute this before using transfer spec because it potentially modifies the transfer spec
        # (even if the var is not used in single session)
        multi_session_info = nil
        if transfer_spec.key?('multi_session')
          # Managed by multi-session, so delete from transfer spec
          multi_session_info = {
            count: transfer_spec.delete('multi_session').to_i
          }
          if multi_session_info[:count].negative?
            Log.log.error{"multi_session(#{transfer_spec['multi_session']}) shall be integer >= 0"}
            multi_session_info = nil
          elsif multi_session_info[:count].eql?(0)
            Log.log.debug('multi_session count is zero: no multi session')
            multi_session_info = nil
          elsif @multi_incr_udp # multi_session_info[:count] > 0
            # if option not true: keep default udp port for all sessions
            multi_session_info[:udp_base] = transfer_spec.key?('fasp_port') ? transfer_spec['fasp_port'] : Transfer::Spec::UDP_PORT
            # delete from original transfer spec, as we will increment values
            transfer_spec.delete('fasp_port')
            # override if specified, else use default value
          end
        end

        # generic session information
        session = {
          id:                nil, # SessionId from INIT message in mgt port
          job_id:            SecureRandom.uuid, # job id (regroup sessions)
          ts:                transfer_spec,     # global transfer spec
          thread:            nil,               # Thread object monitoring management port, not nil when pushed to :sessions
          error:             nil,               # exception if failed
          io:                nil,               # management port server socket
          token_regenerator: token_regenerator, # regenerate bearer token with oauth
          # env vars and args for ascp (from transfer spec)
          env_args:          Transfer::Parameters.new(transfer_spec, **@tr_opts).ascp_args
        }

        if multi_session_info.nil?
          Log.log.debug('Starting single session thread')
          # single session for transfer : simple
          session[:thread] = Thread.new{transfer_thread_entry(session)}
          @sessions.push(session)
        else
          Log.log.debug('Starting multi session threads')
          1.upto(multi_session_info[:count]) do |i|
            # do not delay the first session
            sleep(@spawn_delay_sec) unless i.eql?(1)
            # do deep copy (each thread has its own copy because it is modified here below and in thread)
            this_session = session.clone
            this_session[:ts] = this_session[:ts].clone
            env_args = this_session[:env_args] = this_session[:env_args].clone
            args = env_args[:args] = env_args[:args].clone
            # set multi session part
            args.unshift("-C#{i}:#{multi_session_info[:count]}")
            # option: increment (default as per ascp manual) or not (cluster on other side ?)
            args.unshift('-O', (multi_session_info[:udp_base] + i - 1).to_s) if @multi_incr_udp
            # finally start the thread
            this_session[:thread] = Thread.new{transfer_thread_entry(this_session)}
            @sessions.push(this_session)
          end
        end
        return session[:job_id]
      end

      # wait for completion of all jobs started
      # @return list of :success or error message
      def wait_for_transfers_completion
        Log.log.debug('wait_for_transfers_completion')
        # set to non-nil to exit loop
        result = []
        @sessions.each do |session|
          Log.log.debug{"join #{session[:thread]}"}
          session[:thread].join
          result.push(session[:error] || :success)
        end
        notify_progress(:end)
        Log.log.debug('all transfers joined')
        # since all are finished and we return the result, clear statuses
        @sessions.clear
        return result
      end

      # used by asession (to be removed ?)
      def shutdown
        Log.log.debug('fasp local shutdown')
      end

      # @return [Array] list of sessions for a job
      def sessions_by_job(job_id)
        @sessions.select{ |session| session[:job_id].eql?(job_id)}
      end

      # Send command to management port of command (used in `asession).
      # Examples:
      # {'type'=>'START','source'=>_path_,'destination'=>_path_}
      # {'type'=>'DONE'}
      # @param data [Hash]   Command on mgt port
      # @param id   [String] Optional identifier or transfer session
      def send_command(data, id: nil)
        Log.dump(:command, data)
        sessions = id ? @sessions.select{ |session| session[:job_id].eql?(id)} : @sessions
        if sessions.empty?
          Log.log.warn('No transfer session')
          return
        end
        message = Ascp::Management.command_to_stream(data)
        sessions.each do |session|
          session[:io].puts(message)
        end
      end

      private

      # transfer thread entry
      # @param session information
      def transfer_thread_entry(session)
        begin
          # set name for logging
          Thread.current[:name] = 'transfer'
          Log.log.debug{"ENTER (#{Thread.current[:name]})"}
          # start transfer with selected resumer policy
          @resume_policy.execute_with_resume do
            start_and_monitor_process(session: session, **session[:env_args])
          end
          Log.log.debug('transfer ok'.bg_green)
        rescue StandardError => e
          session[:error] = e
          Log.log.error{"Transfer thread error: #{e.class}:\n#{e.message}:\n#{e.backtrace.join("\n")}".red} if Log.instance.level.eql?(:debug)
        end
        Log.log.debug{"EXIT (#{Thread.current[:name]})"}
      end

      public

      # This is the low level method to start the transfer process.
      # Typically started in a thread.
      # Start process with management port.
      # @param session [Hash]   This session information, keys :io and :token_regenerator
      # @param name    [Symbol] Name of executable: :ascp, :ascp4 or :async (comes from ascp_args)
      # @param env     [Hash]   Environment variables (comes from ascp_args)
      # @param args    [Array]  Command line arguments (comes from ascp_args)
      # @return [nil] when process has exited
      # @throw FaspError on error
      def start_and_monitor_process(
        session:,
        name:,
        env:,
        args:
      )
        Aspera.assert_type(session, Hash)
        notify_progress(:sessions_init, info: 'starting')
        begin
          capture_stderr = false
          stderr_r, stderr_w = nil
          spawn_args = {}
          command_pid = nil
          command_arguments = []
          if @monitor
            # we use Socket directly, instead of TCPServer, as it gives access to lower level options
            socket_class = defined?(JRUBY_VERSION) ? ServerSocket : Socket
            mgt_server_socket = socket_class.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
            # open any available (0) local TCP port for use as management port
            mgt_server_socket.bind(Addrinfo.tcp(LISTEN_LOCAL_ADDRESS, SELECT_AVAILABLE_PORT))
            # make port ready to accept connections, before starting ascp
            mgt_server_socket.listen(1)
            # build arguments and add mgt port
            command_arguments = if name.eql?(:async)
              ["--exclusive-mgmt-port=#{mgt_server_socket.local_address.ip_port}"]
            else
              ['-M', mgt_server_socket.local_address.ip_port.to_s]
            end
          end
          command_arguments.concat(args)
          if capture_stderr
            # capture process stderr
            stderr_r, stderr_w = IO.pipe
            spawn_args[err] = stderr_w
          end
          # get location of command executable (ascp, async)
          command_path = Ascp::Installation.instance.path(name)
          command_pid = Environment.secure_spawn(env: env, exec: command_path, args: command_arguments, **spawn_args)
          # close here, but still used in other process (pipe)
          stderr_w&.close
          notify_progress(:sessions_init, info: "waiting for #{name} to start")
          # "ensure" block will wait for process
          return unless @monitor
          # TODO: timeout does not work when Process.spawn is used... until process exits, then it works
          # So we use select to detect that anything happens on the socket (connection)
          Log.log.debug{"before select, timeout: #{@spawn_timeout_sec}"}
          readable, _, _ = IO.select([mgt_server_socket], nil, nil, @spawn_timeout_sec)
          Log.log.debug('after select, before accept')
          Aspera.assert(readable, type: Transfer::Error){'timeout waiting mgt port connect (select not readable)'}
          # There is a connection to accept
          client_socket, _client_addrinfo = mgt_server_socket.accept
          Log.log.debug('after accept')
          management_port_io = client_socket.to_io
          # by default socket is US-ASCII
          # management messages include file names which may be UTF-8
          # TODO: use same value as Encoding.default_external ?
          management_port_io.set_encoding(Encoding::UTF_8)
          session[:io] = management_port_io
          processor = Ascp::Management.new
          # read management port, until socket is closed (gets returns nil)
          while (line = management_port_io.gets)
            event = processor.process_line(line.chomp)
            next unless event
            # event is ready
            Log.dump(:management_port, event, level: :trace1)
            # store session identifier
            session[:id] = event['SessionId'] if event['Type'].eql?('INIT')
            @management_cb&.call(event)
            process_progress(event)
            next unless File.exist?(@command_file)
            begin
              commands = JSON.parse(File.read(@command_file))
              send_command(commands)
            rescue => e
              Log.log.error{e.to_s}
            end
            File.delete(@command_file)
          end
          Log.log.debug('management io closed')
          # check that last status was received before process exit
          last_event = processor.last_event
          raise Transfer::Error, "No management event (#{last_event.class})" unless last_event.is_a?(Hash)
          case last_event['Type']
          when 'DONE'
            Log.log.trace1{'Graceful shutdown, DONE message received'}
          when 'ERROR'
            if /bearer token/i.match?(last_event['Description']) &&
                session[:token_regenerator].respond_to?(:refreshed_transfer_token)
              # regenerate token here, expired, or error on it
              # Note: in multi-session, each session will have a different one.
              Log.log.warn('Regenerating token for transfer')
              env['ASPERA_SCP_TOKEN'] = session[:token_regenerator].refreshed_transfer_token
            end
            raise Transfer::Error.new(last_event['Description'], code: last_event['Code'].to_i)
          else Aspera.error_unexpected_value(last_event['Type'], :error){'last event type'}
          end
        rescue SystemCallError => e
          # Process.spawn failed, or socket error
          raise Transfer::Error, e.message
        rescue Interrupt
          raise Transfer::Error, 'transfer interrupted by user'
        ensure
          mgt_server_socket&.close
          session.delete(:io)
          # if command was successfully started, check its status
          unless command_pid.nil?
            Process.kill(:INT, command_pid) if @monitor && !Environment.instance.os.eql?(Environment::OS_WINDOWS)
            # collect process exit status or wait for termination
            _, status = Process.wait2(command_pid)
            if stderr_r
              # process stderr of ascp
              stderr_flag = false
              stderr_r.each_line do |line|
                Log.log.error{"BEGIN stderr #{name}"} unless stderr_flag
                Log.log.error{line.chomp}
                stderr_flag = true
              end
              Log.log.error{"END stderr #{name}"} if stderr_flag
              stderr_r.close
            end
            # status is nil if an exception occurred before starting command
            if !status&.success?
              message = "#{name} failed (#{status})"
              # raise error only if there was not already an exception (`$ERROR_INFO`)
              raise Transfer::Error, message unless $ERROR_INFO
              # else display this message also, as main exception is already here
              Log.log.error(message)
            end
          end
        end
        nil
      end

      private

      attr_reader :sessions

      # Notify progress to callback
      # @param event [Hash] management port event
      def process_progress(event)
        session_id = event['SessionId']
        case event['Type']
        when 'INIT'
          @pre_calc_sent = false
          @pre_calc_last_size = nil
          notify_progress(:session_start, session_id: session_id)
        when 'NOTIFICATION' # sent from remote
          if event.key?('PreTransferBytes')
            @pre_calc_sent = true
            notify_progress(:session_size, session_id: session_id, info: event['PreTransferBytes'])
          end
        when 'STATS' # during transfer
          @pre_calc_last_size = event['TransferBytes'].to_i + event['StartByte'].to_i
          notify_progress(:transfer, session_id: session_id, info: @pre_calc_last_size)
        when 'DONE', 'ERROR' # end of session
          total_size = event['TransferBytes'].to_i + event['StartByte'].to_i
          notify_progress(:session_size, session_id: session_id, info: total_size) if !@pre_calc_sent && !total_size.zero?
          notify_progress(:transfer, session_id: session_id, info: total_size) if @pre_calc_last_size != total_size
          notify_progress(:session_end, session_id: session_id)
          # cspell:disable
        when 'SESSION'
        when 'ARGSTOP'
        when 'FILEERROR'
          Log.log.error{"#{event['Type']} #{event['Description']}"}
        when 'STOP'
          # cspell:enable
          # stop event when one file is completed
        else
          Log.log.debug{"Unknown event type for progress: #{event['Type']}"}
        end
      end
    end
  end
end
