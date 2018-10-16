module Asperalm
  # builds command line arg for async
  class Sync
    private
    INSTANCE_PARAMS=
    {
      'alt_logdir'           => { :type => :opt_with_arg, :accepted_types=>String},
      'watchd'               => { :type => :opt_with_arg, :accepted_types=>String},
      'apply_local_docroot'  => { :type => :opt_without_arg},
    }
    SESSION_PARAMS=
    {
      'name'                 => { :type => :opt_with_arg, :accepted_types=>String},
      'local_dir'            => { :type => :opt_with_arg, :accepted_types=>String},
      'remote_dir'           => { :type => :opt_with_arg, :accepted_types=>String},
      'local_db_dir'         => { :type => :opt_with_arg, :accepted_types=>String},
      'remote_db_dir'        => { :type => :opt_with_arg, :accepted_types=>String},
      'host'                 => { :type => :opt_with_arg, :accepted_types=>String},
      'user'                 => { :type => :opt_with_arg, :accepted_types=>String},
      'private_key_path'     => { :type => :opt_with_arg, :accepted_types=>String},
      'direction'            => { :type => :opt_with_arg, :accepted_types=>String},
      'checksum'             => { :type => :opt_with_arg, :accepted_types=>String},
      'tcp_port'             => { :type => :opt_with_arg, :accepted_types=>Integer},
      'rate_policy'          => { :type => :opt_with_arg, :accepted_types=>String},
      'target_rate'          => { :type => :opt_with_arg, :accepted_types=>String},
      'cooloff'              => { :type => :opt_with_arg, :accepted_types=>Integer},
      'pending_max'          => { :type => :opt_with_arg, :accepted_types=>Integer},
      'scan_intensity'       => { :type => :opt_with_arg, :accepted_types=>String},
      'cipher'               => { :type => :opt_with_arg, :accepted_types=>String},
      'transfer_threads'     => { :type => :opt_with_arg, :accepted_types=>Integer},
      'preserve_time'        => { :type => :opt_without_arg},
      'preserve_access_time' => { :type => :opt_without_arg},
      'preserve_modification_time' => { :type => :opt_without_arg},
      'preserve_uid'         => { :type => :opt_without_arg},
      'preserve_gid'         => { :type => :opt_without_arg},
      'create_dir'           => { :type => :opt_without_arg},
      'reset'                => { :type => :opt_without_arg},
      # note: only one env var, but multiple sessions... may be a problem
      'remote_password'      => { :type => :envvar, :variable=>'ASPERA_SCP_PASS'},
      'cookie'               => { :type => :envvar, :variable=>'ASPERA_SCP_COOKIE'},
      'token'                => { :type => :envvar, :variable=>'ASPERA_SCP_TOKEN'},
      'license'              => { :type => :envvar, :variable=>'ASPERA_SCP_LICENSE'},
    }
    public

    def initialize(sync_params)
      @sync_params=sync_params
    end

    MANDATORY_KEYS=['instance','sessions']

    def compute_args
      raise StandardError,"parameter must be Hash" unless @sync_params.is_a?(Hash)
      raise StandardError,"parameter hash must have at least 'sessions', and optionally 'instance' keys." unless @sync_params.keys.push('instance').uniq.sort.eql?(MANDATORY_KEYS)
      raise StandardError,"sessions key must be Array" unless @sync_params['sessions'].is_a?(Array)
      raise StandardError,"sessions key must has at least one element (hash)" unless @sync_params['sessions'].first.is_a?(Hash)

      env_args={
        :args=>[],
        :env=>{}
      }

      if @sync_params.has_key?('instance')
        raise StandardError,"instance key must be hash" unless @sync_params['instance'].is_a?(Hash)
        instance_builder=CommandLineBuilder.new(@sync_params['instance'],INSTANCE_PARAMS)
        instance_builder.process_params
        instance_builder.add_env_args(env_args)
      end

      @sync_params['sessions'].each do |session_params|
        raise StandardError,"sessions must contain hashes" unless session_params.is_a?(Hash)
        raise StandardError,"session must contain at leat name" unless session_params.has_key?('name')
        session_builder=CommandLineBuilder.new(session_params,SESSION_PARAMS)
        session_builder.process_params
        session_builder.add_env_args(env_args)
      end

      return env_args
    end
  end
end
