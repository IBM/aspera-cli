# frozen_string_literal: true
require 'aspera/command_line_builder'

module Aspera
  # builds command line arg for async
  class Sync
    INSTANCE_PARAMS=
    {
      'alt_logdir'           => { cltype: :opt_with_arg, accepted_types: :string},
      'watchd'               => { cltype: :opt_with_arg, accepted_types: :string},
      'apply_local_docroot'  => { cltype: :opt_without_arg},
      'quiet'                => { cltype: :opt_without_arg}
    }
    SESSION_PARAMS=
    {
      'name'                 => { cltype: :opt_with_arg, accepted_types: :string},
      'local_dir'            => { cltype: :opt_with_arg, accepted_types: :string},
      'remote_dir'           => { cltype: :opt_with_arg, accepted_types: :string},
      'local_db_dir'         => { cltype: :opt_with_arg, accepted_types: :string},
      'remote_db_dir'        => { cltype: :opt_with_arg, accepted_types: :string},
      'host'                 => { cltype: :opt_with_arg, accepted_types: :string},
      'user'                 => { cltype: :opt_with_arg, accepted_types: :string},
      'private_key_path'     => { cltype: :opt_with_arg, accepted_types: :string},
      'direction'            => { cltype: :opt_with_arg, accepted_types: :string},
      'checksum'             => { cltype: :opt_with_arg, accepted_types: :string},
      'tcp_port'             => { cltype: :opt_with_arg, accepted_types: :int},
      'rate_policy'          => { cltype: :opt_with_arg, accepted_types: :string},
      'target_rate'          => { cltype: :opt_with_arg, accepted_types: :string},
      'cooloff'              => { cltype: :opt_with_arg, accepted_types: :int},
      'pending_max'          => { cltype: :opt_with_arg, accepted_types: :int},
      'scan_intensity'       => { cltype: :opt_with_arg, accepted_types: :string},
      'cipher'               => { cltype: :opt_with_arg, accepted_types: :string},
      'transfer_threads'     => { cltype: :opt_with_arg, accepted_types: :int},
      'preserve_time'        => { cltype: :opt_without_arg},
      'preserve_access_time' => { cltype: :opt_without_arg},
      'preserve_modification_time' => { cltype: :opt_without_arg},
      'preserve_uid'         => { cltype: :opt_without_arg},
      'preserve_gid'         => { cltype: :opt_without_arg},
      'create_dir'           => { cltype: :opt_without_arg},
      'reset'                => { cltype: :opt_without_arg},
      # note: only one env var, but multiple sessions... may be a problem
      'remote_password'      => { cltype: :envvar, clvarname: 'ASPERA_SCP_PASS'},
      'cookie'               => { cltype: :envvar, clvarname: 'ASPERA_SCP_COOKIE'},
      'token'                => { cltype: :envvar, clvarname: 'ASPERA_SCP_TOKEN'},
      'license'              => { cltype: :envvar, clvarname: 'ASPERA_SCP_LICENSE'}
    }

    Aspera::CommandLineBuilder.normalize_description(INSTANCE_PARAMS)
    Aspera::CommandLineBuilder.normalize_description(SESSION_PARAMS)

    private_constant :INSTANCE_PARAMS,:SESSION_PARAMS

    def initialize(sync_params)
      @sync_params=sync_params
    end

    MANDATORY_KEYS=['instance','sessions']

    def compute_args
      raise StandardError,'parameter must be Hash' unless @sync_params.is_a?(Hash)
      raise StandardError,"parameter hash must have at least 'sessions', and optionally 'instance' keys." unless @sync_params.keys.push('instance').uniq.sort.eql?(MANDATORY_KEYS)
      raise StandardError,'sessions key must be Array' unless @sync_params['sessions'].is_a?(Array)
      raise StandardError,'sessions key must has at least one element (hash)' unless @sync_params['sessions'].first.is_a?(Hash)

      env_args={
        args: [],
        env: {}
      }

      if @sync_params.has_key?('instance')
        raise StandardError,'instance key must be hash' unless @sync_params['instance'].is_a?(Hash)
        instance_builder=CommandLineBuilder.new(@sync_params['instance'],INSTANCE_PARAMS)
        instance_builder.process_params
        instance_builder.add_env_args(env_args[:env],env_args[:args])
      end

      @sync_params['sessions'].each do |session_params|
        raise StandardError,'sessions must contain hashes' unless session_params.is_a?(Hash)
        raise StandardError,'session must contain at leat name' unless session_params.has_key?('name')
        session_builder=CommandLineBuilder.new(session_params,SESSION_PARAMS)
        session_builder.process_params
        session_builder.add_env_args(env_args[:env],env_args[:args])
      end

      return env_args
    end
  end
end
