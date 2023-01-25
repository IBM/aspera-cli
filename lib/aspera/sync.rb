# frozen_string_literal: true

require 'aspera/command_line_builder'
require 'aspera/fasp/installation'

module Aspera
  # builds command line arg for async
  class Sync
    INSTANCE_PARAMS =
      {
        'alt_logdir'          => { cltype: :opt_with_arg, accepted_types: :string},
        'watchd'              => { cltype: :opt_with_arg, accepted_types: :string},
        'apply_local_docroot' => { cltype: :opt_without_arg},
        'quiet'               => { cltype: :opt_without_arg},
        'ws_connect'          => { cltype: :opt_without_arg}
      }.freeze

    # map sync session parameters to transfer spec: sync -> ts, true if same
    SESSION_PARAMS =
      {
        'name'                       => { cltype: :opt_with_arg, accepted_types: :string},
        'local_dir'                  => { cltype: :opt_with_arg, accepted_types: :string},
        'remote_dir'                 => { cltype: :opt_with_arg, accepted_types: :string},
        'local_db_dir'               => { cltype: :opt_with_arg, accepted_types: :string},
        'remote_db_dir'              => { cltype: :opt_with_arg, accepted_types: :string},
        'host'                       => { cltype: :opt_with_arg, accepted_types: :string, ts: :remote_host},
        'user'                       => { cltype: :opt_with_arg, accepted_types: :string, ts: :remote_user},
        'private_key_paths'          => { cltype: :opt_with_arg, accepted_types: :array, clswitch: '--private-key-path'},
        'direction'                  => { cltype: :opt_with_arg, accepted_types: :string},
        'checksum'                   => { cltype: :opt_with_arg, accepted_types: :string},
        'tags'                       => { cltype: :opt_with_arg, accepted_types: :hash, ts: true,
                                          clswitch: '--tags64', clconvert: 'Aspera::Fasp::Parameters.clconv_json64'},
        'tcp_port'                   => { cltype: :opt_with_arg, accepted_types: :int, ts: :ssh_port},
        'rate_policy'                => { cltype: :opt_with_arg, accepted_types: :string},
        'target_rate'                => { cltype: :opt_with_arg, accepted_types: :string},
        'cooloff'                    => { cltype: :opt_with_arg, accepted_types: :int},
        'pending_max'                => { cltype: :opt_with_arg, accepted_types: :int},
        'scan_intensity'             => { cltype: :opt_with_arg, accepted_types: :string},
        'cipher'                     => { cltype: :opt_with_arg, accepted_types: :string, ts: true},
        'transfer_threads'           => { cltype: :opt_with_arg, accepted_types: :int},
        'preserve_time'              => { cltype: :opt_without_arg, ts: :preserve_times},
        'preserve_access_time'       => { cltype: :opt_without_arg, ts: nil},
        'preserve_modification_time' => { cltype: :opt_without_arg, ts: nil},
        'preserve_uid'               => { cltype: :opt_without_arg, ts: :preserve_file_owner_uid},
        'preserve_gid'               => { cltype: :opt_without_arg, ts: :preserve_file_owner_gid},
        'create_dir'                 => { cltype: :opt_without_arg, ts: true},
        'reset'                      => { cltype: :opt_without_arg},
        # NOTE: only one env var, but multiple sessions... could be a problem
        'remote_password'            => { cltype: :envvar, clvarname: 'ASPERA_SCP_PASS', ts: true},
        'cookie'                     => { cltype: :envvar, clvarname: 'ASPERA_SCP_COOKIE', ts: true},
        'token'                      => { cltype: :envvar, clvarname: 'ASPERA_SCP_TOKEN', ts: true},
        'license'                    => { cltype: :envvar, clvarname: 'ASPERA_SCP_LICENSE'}
      }.freeze

    Aspera::CommandLineBuilder.normalize_description(INSTANCE_PARAMS)
    Aspera::CommandLineBuilder.normalize_description(SESSION_PARAMS)

    ALLOWED_KEYS = %w[instance sessions].freeze

    ASYNC_EXECUTABLE = 'async'

    private_constant :INSTANCE_PARAMS, :SESSION_PARAMS, :ALLOWED_KEYS, :ASYNC_EXECUTABLE

    class << self
      def update_parameters_with_transfer_spec(params, transfer_spec)
        params['sessions'].each do |session|
          SESSION_PARAMS.each do |async_param, behaviour|
            if behaviour.key?(:ts)
              tspec_param = behaviour[:ts].is_a?(TrueClass) ? async_param : behaviour[:ts].to_s
              session[async_param] ||= transfer_spec[tspec_param] if transfer_spec.key?(tspec_param)
            end
          end
          session['private_key_paths'] = Fasp::Installation.instance.bypass_keys if transfer_spec.key?('token')
          session['remote_dir'] = '/' if transfer_spec.dig(*%w[tags aspera node file_id])
        end
        Log.dump(:sync, params)
      end
    end

    attr_reader :env_args

    def initialize(sync_params)
      raise StandardError, 'parameter must be Hash' unless sync_params.is_a?(Hash)
      raise StandardError, "parameter hash must have at least 'sessions', and optionally 'instance' keys." unless
        sync_params.keys.push('instance').uniq.sort.eql?(ALLOWED_KEYS)
      raise StandardError, 'sessions key must be Array' unless sync_params['sessions'].is_a?(Array)
      raise StandardError, 'sessions key requires at least one Hash' unless sync_params['sessions'].first.is_a?(Hash)
      @env_args = {
        args: [],
        env:  {}
      }

      if sync_params.key?('instance')
        raise StandardError, 'instance key must be Hash' unless sync_params['instance'].is_a?(Hash)
        instance_builder = CommandLineBuilder.new(sync_params['instance'], INSTANCE_PARAMS)
        instance_builder.process_params
        instance_builder.add_env_args(@env_args[:env], @env_args[:args])
      end

      sync_params['sessions'].each do |session_params|
        raise StandardError, 'sessions must contain hashes' unless session_params.is_a?(Hash)
        raise StandardError, 'session must contain at leat name' unless session_params.key?('name')
        session_builder = CommandLineBuilder.new(session_params, SESSION_PARAMS)
        session_builder.process_params
        session_builder.add_env_args(@env_args[:env], @env_args[:args])
      end
    end

    def start
      Log.log.debug{"execute: #{@env_args[:env].map{|k, v| "#{k}=\"#{v}\""}.join(' ')} \"#{ASYNC_EXECUTABLE}\" \"#{@env_args[:args].join('" "')}\""}
      res = system(@env_args[:env], [ASYNC_EXECUTABLE, ASYNC_EXECUTABLE], *@env_args[:args])
      Log.log.debug{"result=#{res}"}
      case res
      when true then return nil
      when false then raise "failed: #{$CHILD_STATUS}"
      when nil then raise "not started: #{$CHILD_STATUS}"
      else raise 'internal error: unspecified case'
      end
    end
  end

  class SyncAdmin
    ASYNC_ADMIN_EXECUTABLE = 'asyncadmin'
    private_constant :ASYNC_ADMIN_EXECUTABLE
    def initialize(sessions, session_name)
      @cmdline = [ASYNC_ADMIN_EXECUTABLE, '--quiet']
      session = session_name.nil? ? sessions['sessions'].first : sessions['sessions'].find{|s|s['name'].eql?(session_name)}
      raise 'Session not found' if session.nil?
      raise 'Missing session name' if session['name'].nil?
      @cmdline.push('--name=' + session['name'])
      if session.key?('local_db_dir')
        @cmdline.push('--local-db-dir=' + session['local_db_dir'])
      elsif session.key?('local_dir')
        @cmdline.push('--local-dir=' + session['local_dir'])
      else
        raise 'Missing either local_db_dir or local_dir'
      end
    end

    def status
      stdout, stderr, status = Open3.capture3(*@cmdline)
      Log.log.debug{"status=#{status}, stderr=#{stderr}"}
      raise "Sync failed: #{status.exitstatus} : #{stderr}" unless status.success?
      return stdout.split("\n").each_with_object({}){|l, m|i = l.split(/:  */); m[i.first.lstrip] = i.last.lstrip} # rubocop:disable Style/Semicolon
    end
  end
end
