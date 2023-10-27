# frozen_string_literal: true

# cspell:words logdir

require 'aspera/command_line_builder'
require 'aspera/fasp/installation'
require 'aspera/log'
require 'json'
require 'base64'
require 'open3'
require 'English'

module Aspera
  # builds command line arg for async
  module Sync
    # sync direction, default is push
    DIRECTIONS = %i[push pull bidi].freeze
    PARAMS_VX_INSTANCE =
      {
        'alt_logdir'          => { cli: { type: :opt_with_arg}, accepted_types: :string},
        'watchd'              => { cli: { type: :opt_with_arg}, accepted_types: :string},
        'apply_local_docroot' => { cli: { type: :opt_without_arg}},
        'quiet'               => { cli: { type: :opt_without_arg}},
        'ws_connect'          => { cli: { type: :opt_without_arg}}
      }.freeze

    # map sync session parameters to transfer spec: sync -> ts, true if same
    PARAMS_VX_SESSION =
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
        'tags'                       => { cli: { type: :opt_with_arg, switch: '--tags64', convert: 'Aspera::Fasp::Parameters.convert_json64'},
                                          accepted_types: :hash, ts: true},
        'tcp_port'                   => { cli: { type: :opt_with_arg}, accepted_types: :int, ts: :ssh_port},
        'rate_policy'                => { cli: { type: :opt_with_arg}, accepted_types: :string},
        'target_rate'                => { cli: { type: :opt_with_arg}, accepted_types: :string},
        'cooloff'                    => { cli: { type: :opt_with_arg}, accepted_types: :int},
        'pending_max'                => { cli: { type: :opt_with_arg}, accepted_types: :int},
        'scan_intensity'             => { cli: { type: :opt_with_arg}, accepted_types: :string},
        'cipher'                     => { cli: { type: :opt_with_arg, convert: 'Aspera::Fasp::Parameters.convert_remove_hyphen'}, accepted_types: :string, ts: true},
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

    Aspera::CommandLineBuilder.normalize_description(PARAMS_VX_INSTANCE)
    Aspera::CommandLineBuilder.normalize_description(PARAMS_VX_SESSION)

    PARAMS_VX_KEYS = %w[instance sessions].freeze

    # new API
    TS_TO_PARAMS_V2 = {
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

    ASYNC_EXECUTABLE = 'async'
    ASYNC_ADMIN_EXECUTABLE = 'asyncadmin'

    private_constant :PARAMS_VX_INSTANCE, :PARAMS_VX_SESSION, :PARAMS_VX_KEYS, :TS_TO_PARAMS_V2, :ASYNC_EXECUTABLE, :ASYNC_ADMIN_EXECUTABLE

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

      # @param sync_params [Hash] sync parameters, old or new format
      # @param block [nil, Proc] block to generate transfer spec, takes: direction (one of DIRECTIONS), local_dir, remote_dir
      def start(sync_params, &block)
        raise 'Internal Error: sync_params parameter must be Hash' unless sync_params.is_a?(Hash)
        env_args = {
          args: [],
          env:  {}
        }
        if sync_params.key?('local')
          # async native JSON format (v2)
          raise StandardError, 'remote must be Hash' unless sync_params['remote'].is_a?(Hash)
          if block
            transfer_spec = yield((sync_params['direction'] || 'push').to_sym, sync_params['local']['path'], sync_params['remote']['path'])
            # async native JSON format
            raise StandardError, 'sync parameter "local" must be Hash' unless sync_params['local'].is_a?(Hash)
            TS_TO_PARAMS_V2.each do |ts_param, sy_path|
              next unless transfer_spec.key?(ts_param)
              sy_dig = sy_path.split('.')
              param = sy_dig.pop
              hash = sy_dig.empty? ? sync_params : sync_params[sy_dig.first]
              hash = sync_params[sy_dig.first] = {} if hash.nil?
              hash[param] = transfer_spec[ts_param]
            end
            sync_params['remote']['connect_mode'] ||= sync_params['remote'].key?('ws_port') ? 'ws' : 'ssh'
            sync_params['remote']['private_key_paths'] ||= Fasp::Installation.instance.bypass_keys if transfer_spec.key?('token')
            update_remote_dir(sync_params['remote'], 'path', transfer_spec)
          end
          env_args[:args] = ["--conf64=#{Base64.strict_encode64(JSON.generate(sync_params))}"]
        elsif sync_params.key?('sessions')
          # ascli JSON format (v1)
          if block
            sync_params['sessions'].each do |session|
              transfer_spec = yield((session['direction'] || 'push').to_sym, session['local_dir'], session['remote_dir'])
              PARAMS_VX_SESSION.each do |async_param, behavior|
                if behavior.key?(:ts)
                  tspec_param = behavior[:ts].is_a?(TrueClass) ? async_param : behavior[:ts].to_s
                  session[async_param] ||= transfer_spec[tspec_param] if transfer_spec.key?(tspec_param)
                end
              end
              session['private_key_paths'] = Fasp::Installation.instance.bypass_keys if transfer_spec.key?('token')
              update_remote_dir(session, 'remote_dir', transfer_spec)
            end
          end
          raise StandardError, "Only 'sessions', and optionally 'instance' keys are allowed" unless
            sync_params.keys.push('instance').uniq.sort.eql?(PARAMS_VX_KEYS)
          raise StandardError, 'sessions key must be Array' unless sync_params['sessions'].is_a?(Array)
          raise StandardError, 'sessions key requires at least one Hash' unless sync_params['sessions'].first.is_a?(Hash)

          if sync_params.key?('instance')
            raise StandardError, 'instance key must be Hash' unless sync_params['instance'].is_a?(Hash)
            instance_builder = Aspera::CommandLineBuilder.new(sync_params['instance'], PARAMS_VX_INSTANCE)
            instance_builder.process_params
            instance_builder.add_env_args(env_args[:env], env_args[:args])
          end

          sync_params['sessions'].each do |session_params|
            raise StandardError, 'sessions must contain hashes' unless session_params.is_a?(Hash)
            raise StandardError, 'session must contain at least name' unless session_params.key?('name')
            session_builder = Aspera::CommandLineBuilder.new(session_params, PARAMS_VX_SESSION)
            session_builder.process_params
            session_builder.add_env_args(env_args[:env], env_args[:args])
          end
        else
          raise 'At least one of `local` or `sessions` must be present in async parameters'
        end
        Log.dump(:sync_params, sync_params)

        Log.log.debug{"execute: #{env_args[:env].map{|k, v| "#{k}=\"#{v}\""}.join(' ')} \"#{ASYNC_EXECUTABLE}\" \"#{env_args[:args].join('" "')}\""}
        res = system(env_args[:env], [ASYNC_EXECUTABLE, ASYNC_EXECUTABLE], *env_args[:args])
        Log.log.debug{"result=#{res}"}
        case res
        when true then return nil
        when false then raise "failed: #{$CHILD_STATUS}"
        when nil then raise "not started: #{$CHILD_STATUS}"
        else raise 'internal error: unspecified case'
        end
      end

      def admin_status(sync_params, session_name)
        command_line = [ASYNC_ADMIN_EXECUTABLE, '--quiet']
        if sync_params.key?('local')
          raise 'Missing session name' if sync_params['name'].nil?
          raise 'Session not found' unless session_name.nil? || session_name.eql?(sync_params['name'])
          command_line.push("--name=#{sync_params['name']}")
          if sync_params.key?('local_db_dir')
            command_line.push("--local-db-dir=#{sync_params['local_db_dir']}")
          elsif sync_params.dig('local', 'path')
            command_line.push("--local-dir=#{sync_params.dig('local', 'path')}")
          else
            raise 'Missing either local_db_dir or local.path'
          end
        elsif sync_params.key?('sessions')
          session = session_name.nil? ? sync_params['sessions'].first : sync_params['sessions'].find{|s|s['name'].eql?(session_name)}
          raise "Session #{session_name} not found in #{sync_params['sessions'].map{|s|s['name']}.join(',')}" if session.nil?
          raise 'Missing session name' if session['name'].nil?
          command_line.push("--name=#{session['name']}")
          if session.key?('local_db_dir')
            command_line.push("--local-db-dir=#{session['local_db_dir']}")
          elsif session.key?('local_dir')
            command_line.push("--local-dir=#{session['local_dir']}")
          else
            raise 'Missing either local_db_dir or local_dir'
          end
        else
          raise 'At least one of `local` or `sessions` must be present in async parameters'
        end
        Log.log.debug{"execute: #{command_line.join(' ')}"}
        stdout, stderr, status = Open3.capture3(*command_line)
        Log.log.debug{"status=#{status}, stderr=#{stderr}"}
        raise "Sync failed: #{status.exitstatus} : #{stderr}" unless status.success?
        return stdout.split("\n").each_with_object({}){|l, m|i = l.split(':', 2); m[i.first.lstrip] = i.last.lstrip} # rubocop:disable Style/Semicolon
      end
    end
  end # end Sync
end # end Aspera
