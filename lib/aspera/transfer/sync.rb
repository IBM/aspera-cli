# frozen_string_literal: true

# cspell:words logdir bidi watchd cooloff asyncadmin

require 'aspera/command_line_builder'
require 'aspera/ascp/installation'
require 'aspera/agent/direct'
require 'aspera/log'
require 'aspera/assert'
require 'json'
require 'base64'
require 'open3'
require 'English'

module Aspera
  module Transfer
    # builds command line arg for async and execute it
    module Sync
      # sync direction, default is push
      DIRECTIONS = %i[push pull bidi].freeze
      # JSON for async instance command line options
      CMDLINE_PARAMS_INSTANCE =
        {
          'alt_logdir'          => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'watchd'              => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'apply_local_docroot' => { cli: { type: :opt_without_arg}},
          'quiet'               => { cli: { type: :opt_without_arg}},
          'ws_connect'          => { cli: { type: :opt_without_arg}}
        }.freeze

      # map sync session parameters to transfer spec: sync -> ts, true if same
      CMDLINE_PARAMS_SESSION =
        {
          'name'                       => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'local_dir'                  => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'remote_dir'                 => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'local_db_dir'               => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'remote_db_dir'              => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'host'                       => { cli: { type: :opt_with_arg}, accepted_types: :string, ts: :remote_host},
          'user'                       => { cli: { type: :opt_with_arg}, accepted_types: :string, ts: :remote_user},
          'private_key_paths'          => { cli: { type: :opt_with_arg, switch: '--private-key-path'}, accepted_types: :array},
          'direction'                  => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'checksum'                   => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'tags'                       => { cli: { type: :opt_with_arg, switch: '--tags64', convert: 'Aspera::Transfer::Parameters.convert_json64'},
                                            accepted_types: :hash, ts: true},
          'tcp_port'                   => { cli: { type: :opt_with_arg}, accepted_types: :int, ts: :ssh_port},
          'rate_policy'                => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'target_rate'                => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'cooloff'                    => { cli: { type: :opt_with_arg}, accepted_types: :int},
          'pending_max'                => { cli: { type: :opt_with_arg}, accepted_types: :int},
          'scan_intensity'             => { cli: { type: :opt_with_arg}, accepted_types: :string},
          'cipher'                     => { cli: { type: :opt_with_arg, convert: 'Aspera::Transfer::Parameters.convert_remove_hyphen'},
                                            accepted_types: :string, ts: true},
          'transfer_threads'           => { cli: { type: :opt_with_arg}, accepted_types: :int},
          'preserve_time'              => { cli: { type: :opt_without_arg}, ts: :preserve_times},
          'preserve_access_time'       => { cli: { type: :opt_without_arg}, ts: nil},
          'preserve_modification_time' => { cli: { type: :opt_without_arg}, ts: nil},
          'preserve_uid'               => { cli: { type: :opt_without_arg}, ts: :preserve_file_owner_uid},
          'preserve_gid'               => { cli: { type: :opt_without_arg}, ts: :preserve_file_owner_gid},
          'create_dir'                 => { cli: { type: :opt_without_arg}, ts: true},
          'reset'                      => { cli: { type: :opt_without_arg}},
          # NOTE: only one env var, but multiple sessions... could be a problem
          'remote_password'            => { cli: { type: :envvar, variable: 'ASPERA_SCP_PASS'}, ts: true},
          'cookie'                     => { cli: { type: :envvar, variable: 'ASPERA_SCP_COOKIE'}, ts: true},
          'token'                      => { cli: { type: :envvar, variable: 'ASPERA_SCP_TOKEN'}, ts: true},
          'license'                    => { cli: { type: :envvar, variable: 'ASPERA_SCP_LICENSE'}}
        }.freeze

      CommandLineBuilder.normalize_description(CMDLINE_PARAMS_INSTANCE)
      CommandLineBuilder.normalize_description(CMDLINE_PARAMS_SESSION)

      CMDLINE_PARAMS_KEYS = %w[instance sessions].freeze

      # Translation of transfer spec parameters to async v2 API (asyncs)
      TSPEC_TO_ASYNC_CONF = {
        'remote_host'     => 'remote.host',
        'remote_user'     => 'remote.user',
        'remote_password' => 'remote.pass',
        'sshfp'           => 'remote.fingerprint',
        'ssh_port'        => 'remote.port',
        'wss_port'        => 'remote.ws_port',
        'proxy'           => 'remote.proxy',
        'token'           => 'remote.token',
        'tags'            => 'tags'
      }.freeze

      ASYNC_ADMIN_EXECUTABLE = 'asyncadmin'

      private_constant :CMDLINE_PARAMS_INSTANCE, :CMDLINE_PARAMS_SESSION, :CMDLINE_PARAMS_KEYS, :TSPEC_TO_ASYNC_CONF, :ASYNC_ADMIN_EXECUTABLE

      class << self
        # Set remote_dir in sync parameters based on transfer spec
        # @param params [Hash] sync parameters, old or new format
        # @param remote_dir_key [String] key to update in above hash
        # @param transfer_spec [Hash] transfer spec
        def update_remote_dir(sync_params, remote_dir_key, transfer_spec)
          if transfer_spec.dig(*%w[tags aspera node file_id])
            # in AoC, use gen4
            sync_params[remote_dir_key] = '/'
          elsif transfer_spec['cookie']&.start_with?('aspera.shares2')
            # TODO : something more generic, independent of Shares
            # in Shares, the actual folder on remote end is not always the same as the name of the share
            actual_remote = transfer_spec['paths']&.first&.[]('source')
            sync_params[remote_dir_key] = actual_remote if actual_remote
          end
          nil
        end

        def remote_certificates(remote)
          certificates_to_use = []
          # use web socket secure for session ?
          if remote['connect_mode']&.eql?('ws')
            remote.delete('port')
            remote.delete('fingerprint')
            # ignore cert for wss ?
            # if @options[:check_ignore_cb]&.call(remote['host'], remote['ws_port'])
            #   wss_cert_file = TempFileManager.instance.new_file_path_global('wss_cert')
            #   wss_url = "https://#{remote['host']}:#{remote['ws_port']}"
            #   File.write(wss_cert_file, Rest.remote_certificate_chain(wss_url))
            #   certificates_to_use.push(wss_cert_file)
            # end
            # set location for CA bundle to be the one of Ruby, see env var SSL_CERT_FILE / SSL_CERT_DIR
            # certificates_to_use.concat(@options[:trusted_certs]) if @options[:trusted_certs]
          else
            # remove unused parameter (avoid warning)
            remote.delete('ws_port')
            # add SSH bypass keys when authentication is token and no auth is provided
            if remote.key?('token') && !remote.key?('pass')
              certificates_to_use.concat(Ascp::Installation.instance.aspera_token_ssh_key_paths(:rsa))
            end
          end
          return certificates_to_use
        end

        # @param sync_params [Hash] sync parameters, old or new format
        # @param block [nil, Proc] block to generate transfer spec, takes: direction (one of DIRECTIONS), local_dir, remote_dir
        def start(
          sync_params,
          &block
        )
          Log.log.debug{Log.dump(:sync_params_initial, sync_params)}
          Aspera.assert_type(sync_params, Hash)
          env_args = {
            args: [],
            env:  {}
          }
          if sync_params.key?('local')
            # async native JSON format (conf option)
            Aspera.assert_type(sync_params['local'], Hash){'local'}
            remote = sync_params['remote']
            Aspera.assert_type(remote, Hash){'remote'}
            Aspera.assert_type(remote['path'], String){'remote path'}
            # get transfer spec if possible, and feed back to new structure
            if block
              transfer_spec = yield((sync_params['direction'] || 'push').to_sym, sync_params['local']['path'], remote['path'])
              # translate transfer spec to async parameters
              TSPEC_TO_ASYNC_CONF.each do |ts_param, sy_path|
                next unless transfer_spec.key?(ts_param)
                sy_dig = sy_path.split('.')
                param = sy_dig.pop
                hash = sy_dig.empty? ? sync_params : sync_params[sy_dig.first]
                hash = sync_params[sy_dig.first] = {} if hash.nil?
                hash[param] = transfer_spec[ts_param]
              end
              update_remote_dir(remote, 'path', transfer_spec)
            end
            remote['connect_mode'] ||= transfer_spec['wss_enabled'] ? 'ws' : 'ssh'
            add_certificates = remote_certificates(remote)
            if !add_certificates.empty?
              remote['private_key_paths'] ||= []
              remote['private_key_paths'].concat(add_certificates)
            end
            # '--exclusive-mgmt-port=12345', '--arg-err-path=-',
            env_args[:args] = ["--conf64=#{Base64.strict_encode64(JSON.generate(sync_params))}"]
            Log.log.debug{Log.dump(:sync_params_enriched, sync_params)}
            agent = Agent::Direct.new
            agent.start_and_monitor_process(session: {}, name: :async, **env_args)
          elsif sync_params.key?('sessions')
            # ascli JSON format (cmdline)
            raise StandardError, "Only 'sessions', and optionally 'instance' keys are allowed" unless
              sync_params.keys.push('instance').uniq.sort.eql?(CMDLINE_PARAMS_KEYS)
            Aspera.assert_type(sync_params['sessions'], Array)
            Aspera.assert_type(sync_params['sessions'].first, Hash)
            if block
              sync_params['sessions'].each do |session|
                Aspera.assert_type(session['local_dir'], String){'local_dir'}
                Aspera.assert_type(session['remote_dir'], String){'remote_dir'}
                transfer_spec = yield((session['direction'] || 'push').to_sym, session['local_dir'], session['remote_dir'])
                CMDLINE_PARAMS_SESSION.each do |async_param, behavior|
                  if behavior.key?(:ts)
                    tspec_param = behavior[:ts].is_a?(TrueClass) ? async_param : behavior[:ts].to_s
                    session[async_param] ||= transfer_spec[tspec_param] if transfer_spec.key?(tspec_param)
                  end
                end
                session['private_key_paths'] = Ascp::Installation.instance.aspera_token_ssh_key_paths(:rsa) if transfer_spec.key?('token')
                update_remote_dir(session, 'remote_dir', transfer_spec)
              end
            end
            if sync_params.key?('instance')
              Aspera.assert_type(sync_params['instance'], Hash)
              instance_builder = CommandLineBuilder.new(sync_params['instance'], CMDLINE_PARAMS_INSTANCE)
              instance_builder.process_params
              instance_builder.add_env_args(env_args)
            end

            sync_params['sessions'].each do |session_params|
              Aspera.assert_type(session_params, Hash)
              Aspera.assert(session_params.key?('name')){'session must contain at least name'}
              session_builder = CommandLineBuilder.new(session_params, CMDLINE_PARAMS_SESSION)
              session_builder.process_params
              session_builder.add_env_args(env_args)
            end
            Environment.secure_execute(exec: Ascp::Installation.instance.path(:async), **env_args)
          else
            raise 'At least one of `local` or `sessions` must be present in async parameters'
          end
          return nil
        end

        def parse_status(stdout)
          Log.log.trace1{"stdout=#{stdout}"}
          result = {}
          ids = nil
          stdout.split("\n").each do |line|
            info = line.split(':', 2).map(&:lstrip)
            if info[1].eql?('')
              info[1] = ids = []
            elsif info[1].nil?
              ids.push(info[0])
              next
            end
            result[info[0]] = info[1]
          end
          return result
        end

        def admin_status(sync_params, session_name)
          arguments = ['--quiet']
          if sync_params.key?('local')
            Aspera.assert(!sync_params['name'].nil?){'Missing session name'}
            Aspera.assert(session_name.nil? || session_name.eql?(sync_params['name'])){'Session not found'}
            arguments.push("--name=#{sync_params['name']}")
            if sync_params.key?('local_db_dir')
              arguments.push("--local-db-dir=#{sync_params['local_db_dir']}")
            elsif sync_params.dig('local', 'path')
              arguments.push("--local-dir=#{sync_params.dig('local', 'path')}")
            else
              raise 'Missing either local_db_dir or local.path'
            end
          elsif sync_params.key?('sessions')
            session = session_name.nil? ? sync_params['sessions'].first : sync_params['sessions'].find{|s|s['name'].eql?(session_name)}
            raise "Session #{session_name} not found in #{sync_params['sessions'].map{|s|s['name']}.join(',')}" if session.nil?
            raise 'Missing session name' if session['name'].nil?
            arguments.push("--name=#{session['name']}")
            if session.key?('local_db_dir')
              arguments.push("--local-db-dir=#{session['local_db_dir']}")
            elsif session.key?('local_dir')
              arguments.push("--local-dir=#{session['local_dir']}")
            else
              raise 'Missing either local_db_dir or local_dir'
            end
          else
            raise 'At least one of `local` or `sessions` must be present in async parameters'
          end
          stdout = Environment.secure_capture(exec: ASYNC_ADMIN_EXECUTABLE, args: arguments)
          return parse_status(stdout)
        end
      end
    end
  end
end
