# frozen_string_literal: true

require 'aspera/agent/base'
require 'aspera/ascp/installation'
require 'aspera/ascp/management'
require 'aspera/transfer/parameters'
require 'aspera/transfer/error'
require 'aspera/transfer/spec'
require 'aspera/resumer'
require 'aspera/log'
require 'aspera/assert'
require 'socket'
require 'securerandom'
require 'shellwords'
require 'English'

module Aspera
  module Agent
    # executes a local "ascp", connects mgt port, equivalent of "Fasp Manager"
    class Direct < Base
      LISTEN_LOCAL_ADDRESS = '127.0.0.1'
      # 0 means: select an available port
      SELECT_AVAILABLE_PORT = 0
      # spellchecker: enable
      private_constant :LISTEN_LOCAL_ADDRESS, :SELECT_AVAILABLE_PORT

      # method of Base
      # start ascp transfer(s) (non blocking), single or multi-session
      # session information added to @sessions
      # @param transfer_spec [Hash] aspera transfer specification
      # @param token_regenerator [Object] object with method refreshed_transfer_token
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
          ts:                transfer_spec,     # transfer spec
          thread:            nil,               # Thread object monitoring management port, not nil when pushed to :sessions
          error:             nil,               # exception if failed
          io:                nil,               # management port server socket
          token_regenerator: token_regenerator, # regenerate bearer token with oauth
          # env vars and args to ascp (from transfer spec)
          env_args:          Transfer::Parameters.new(transfer_spec, **@tr_opts).ascp_args
        }

        if multi_session_info.nil?
          Log.log.debug('Starting single session thread')
          # single session for transfer : simple
          session[:thread] = Thread.new(session) {|session_info|transfer_thread_entry(session_info)}
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
            this_session[:thread] = Thread.new(this_session) {|session_info|transfer_thread_entry(session_info)}
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
        @sessions.select{|session_info| session_info[:job_id].eql?(job_id)}
      end

      # This is the low level method to start the transfer process
      # Start process with management port.
      # returns
      # raises FaspError on error
      # @param session this session information, keys :io and :token_regenerator
      # @param env  [Hash]   environment variables
      # @param name [Symbol] name of executable: :ascp, :ascp4 or :async
      # @param args [Array]  command line arguments
      # @return [nil] when process has exited
      def start_and_monitor_process(
        session:,
        env:,
        name:,
        args:
      )
        Aspera.assert_type(session, Hash)
        notify_progress(session_id: nil, type: :pre_start, info: 'starting')
        begin
          command_pid = nil
          # we use Socket directly, instead of TCPServer, as it gives access to lower level options
          socket_class = RUBY_ENGINE.eql?('jruby') ? ServerSocket : Socket
          mgt_server_socket = socket_class.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
          # open any available (0) local TCP port for use as management port
          mgt_server_socket.bind(Addrinfo.tcp(LISTEN_LOCAL_ADDRESS, SELECT_AVAILABLE_PORT))
          # build arguments and add mgt port
          command_arguments = if name.eql?(:async)
            ["--exclusive-mgmt-port=#{mgt_server_socket.local_address.ip_port}"]
          else
            ['-M', mgt_server_socket.local_address.ip_port.to_s]
          end
          command_arguments.concat(args)
          # get location of command executable (ascp, async)
          command_path = Ascp::Installation.instance.path(name)
          command_pid = Environment.secure_spawn(env: env, exec: command_path, args: command_arguments)
          notify_progress(session_id: nil, type: :pre_start, info: "waiting for #{name} to start")
          mgt_server_socket.listen(1)
          # TODO: timeout does not work when Process.spawn is used... until process exits, then it works
          Log.log.debug{"before select, timeout: #{@spawn_timeout_sec}"}
          readable, _, _ = IO.select([mgt_server_socket], nil, nil, @spawn_timeout_sec)
          Log.log.debug('after select, before accept')
          Aspera.assert(readable, exception_class: Transfer::Error){'timeout waiting mgt port connect (select not readable)'}
          # There is a connection to accept
          client_socket, _client_addrinfo = mgt_server_socket.accept
          Log.log.debug('after accept')
          management_port_io = client_socket.to_io
          # management messages include file names which may be utf8
          # by default socket is US-ASCII
          # TODO: use same value as Encoding.default_external
          management_port_io.set_encoding(Encoding::UTF_8)
          session[:io] = management_port_io
          processor = Ascp::Management.new
          # read management port, until socket is closed (gets returns nil)
          while (line = management_port_io.gets)
            event = processor.process_line(line.chomp)
            next unless event
            # event is ready
            Log.log.trace1{Log.dump(:management_port, event)}
            @management_cb&.call(event)
            process_progress(event)
            Log.log.error((event['Description']).to_s) if event['Type'].eql?('FILEERROR') # cspell:disable-line
          end
          Log.log.debug('management io closed')
          last_event = processor.last_event
          # check that last status was received before process exit
          if last_event.is_a?(Hash)
            case last_event['Type']
            when 'ERROR'
              if /bearer token/i.match?(last_event['Description']) &&
                  session[:token_regenerator].respond_to?(:refreshed_transfer_token)
                # regenerate token here, expired, or error on it
                # Note: in multi-session, each session will have a different one.
                Log.log.warn('Regenerating token for transfer')
                env['ASPERA_SCP_TOKEN'] = session[:token_regenerator].refreshed_transfer_token
              end
              raise Transfer::Error.new(last_event['Description'], last_event['Code'].to_i)
            when 'DONE'
              nil
            else
              raise "unexpected last event type: #{last_event['Type']}"
            end
          end
        rescue SystemCallError => e
          # Process.spawn failed, or socket error
          raise Transfer::Error, e.message
        rescue Interrupt
          raise Transfer::Error, 'transfer interrupted by user'
        ensure
          mgt_server_socket.close
          # if command was successfully started, check its status
          unless command_pid.nil?
            # "wait" for process to avoid zombie
            Process.wait(command_pid)
            status = $CHILD_STATUS
            # command_pid = nil
            session.delete(:io)
            # status is nil if an exception occurred before starting command
            if !status&.success?
              message = status.nil? ? "#{name} not started" : "#{name} failed (#{status})"
              # raise error only if there was not already an exception (ERROR_INFO)
              raise Transfer::Error, message unless $ERROR_INFO
              # else display this message also, as main exception is already here
              Log.log.error(message)
            end
          end
        end
        nil
      end

      private

      # notify progress to callback
      # @param event management port event
      def process_progress(event)
        session_id = event['SessionId']
        case event['Type']
        when 'INIT'
          @pre_calc_sent = false
          @pre_calc_last_size = nil
          notify_progress(session_id: session_id, type: :session_start)
        when 'NOTIFICATION' # sent from remote
          if event.key?('PreTransferBytes')
            @pre_calc_sent = true
            notify_progress(session_id: session_id, type: :session_size, info: event['PreTransferBytes'])
          end
        when 'STATS' # during transfer
          @pre_calc_last_size = event['TransferBytes'].to_i + event['StartByte'].to_i
          notify_progress(session_id: session_id, type: :transfer, info: @pre_calc_last_size)
        when 'DONE', 'ERROR' # end of session
          total_size = event['TransferBytes'].to_i + event['StartByte'].to_i
          if !@pre_calc_sent && !total_size.zero?
            notify_progress(session_id: session_id, type: :session_size, info: total_size)
          end
          if @pre_calc_last_size != total_size
            notify_progress(session_id: session_id, type: :transfer, info: total_size)
          end
          notify_progress(session_id: session_id, type: :end)
          # cspell:disable
        when 'SESSION'
        when 'ARGSTOP'
        when 'FILEERROR'
        when 'STOP'
          # cspell:enable
          # stop event when one file is completed
        else
          Log.log.debug{"unknown event type #{event['Type']}"}
        end
      end

      # @return [Hash] session information
      def session_by_id(id)
        matches = @sessions.select{|session_info| session_info[:id].eql?(id)}
        raise 'no such session' if matches.empty?
        raise 'more than one session' if matches.length > 1
        return matches.first
      end

      # send command to management port of command (used in `asession)
      # @param job_id identified transfer process
      # @param session_index index of session (for multi session)
      # @param data command on mgt port, examples:
      # {'type'=>'START','source'=>_path_,'destination'=>_path_}
      # {'type'=>'DONE'}
      def send_command(job_id, data)
        session = session_by_id(job_id)
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
      attr_reader :sessions

      # options for initialize (same as values in option transfer_info)
      # @param ascp_args [Array] additional arguments to ascp
      # @param wss [Boolean] true: if both SSH and wss in ts: prefer wss
      # @param quiet [Boolean] by default no native ascp progress bar
      # @param trusted_certs [Array,NilClass] list of files with trusted certificates (stores)
      # @param client_ssh_key [String] client ssh key option (from CLIENT_SSH_KEY_OPTIONS)
      # @param check_ignore_cb [Proc] callback with host,port
      # @param spawn_timeout_sec [Integer] timeout for ascp spawn
      # @param spawn_delay_sec [Integer] optional delay to start between sessions
      # @param multi_incr_udp [Boolean,NilClass] true: increment udp port for each session
      # @param resume [Hash,NilClass] resume policy
      # @param management_cb [Proc] callback for management events
      # @param base_options [Hash] other options for base class
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
        management_cb:     nil,
        **base_options
      )
        super(**base_options)
        # special transfer parameters
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
        # default is true on windows, false on other platforms
        @multi_incr_udp = multi_incr_udp.nil? ? Environment.os.eql?(Environment::OS_WINDOWS) : multi_incr_udp
        @management_cb = management_cb
        @resume_policy = Resumer.new(resume.nil? ? {} : resume.symbolize_keys)
        # all transfer jobs, key = SecureRandom.uuid, protected by mutex, cond var on change
        @sessions = []
        # mutex protects global data accessed by threads
        @mutex = Mutex.new
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
            start_and_monitor_process(session: session, **session[:env_args])
          end
          Log.log.debug('transfer ok'.bg_green)
        rescue StandardError => e
          session[:error] = e
          Log.log.error{"Transfer thread error: #{e.class}:\n#{e.message}:\n#{e.backtrace.join("\n")}".red} if Log.instance.level.eql?(:debug)
        end
        Log.log.debug{"EXIT (#{Thread.current[:name]})"}
      end
    end
  end
end
