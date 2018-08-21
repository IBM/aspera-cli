module Asperalm
  # builds command line arg for async
  class Sync
    def initialize(sync_params)
      @sync_params=sync_params
    end

    MANDATORY_KEYS=['instance','sessions']

    def compute_args
      raise StandardError,"parameter must be Hash" unless @sync_params.is_a?(Hash)
      raise StandardError,"parameter hash must have at least 'sessions', and optionally 'instance' keys." unless @sync_params.keys.push('instance').uniq.sort.eql?(MANDATORY_KEYS)
      raise StandardError,"sessions key must be hash" unless @sync_params['sessions'].is_a?(Array)

      all_args=[]
      all_env={}

      if @sync_params.has_key?('instance')
        raise StandardError,"instance key must be hash" unless @sync_params['instance'].is_a?(Hash)
        instance_builder=CommandLineBuilder.new(@sync_params['instance'])
        instance_builder.process_param('alt_logdir',:opt_with_arg,:accepted_types=>[String])
        instance_builder.process_param('apply_local_docroot',:opt_without_arg)
        instance_builder.process_param('watchd',:opt_with_arg,:accepted_types=>[String])
        instance_builder.check_all_used
        instance_env,instance_args=instance_builder.env_args
        all_env.merge!(instance_env)
        all_args.push(*instance_args)
      end

      @sync_params['sessions'].each do |session_params|
        raise StandardError,"sessions must contain hashes" unless session_params.is_a?(Hash)
        puts(">>>[#{session_params}]")
        session_builder=CommandLineBuilder.new(session_params)
        # note: only one env var, but multiple sessions... may be a problem
        session_builder.process_param('name',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('local_dir',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('remote_dir',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('host',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('user',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('private_key_path',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('direction',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('checksum',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('tcp_port',:opt_with_arg,:accepted_types=>[Integer])
        session_builder.process_param('rate_policy',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('target_rate',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('cooloff',:opt_with_arg,:accepted_types=>[Integer])
        session_builder.process_param('pending_max',:opt_with_arg,:accepted_types=>[Integer])
        session_builder.process_param('scan_intensity',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('cipher',:opt_with_arg,:accepted_types=>[String])
        session_builder.process_param('transfer_threads',:opt_with_arg,:accepted_types=>[Integer])
        session_builder.process_param('preserve_time',:opt_without_arg)
        session_builder.process_param('preserve_access_time',:opt_without_arg)
        session_builder.process_param('preserve_modification_time',:opt_without_arg)
        session_builder.process_param('preserve_uid',:opt_without_arg)
        session_builder.process_param('preserve_gid',:opt_without_arg)
        session_builder.process_param('create_dir',:opt_without_arg)
        session_builder.process_param('remote_password',:envvar,:variable=>'ASPERA_SCP_PASS')
        session_builder.process_param('cookie',:envvar,:variable=>'ASPERA_SCP_COOKIE')
        session_builder.process_param('token',:envvar,:variable=>'ASPERA_SCP_TOKEN')
        session_builder.process_param('license',:envvar,:variable=>'ASPERA_SCP_LICENSE')
        session_builder.check_all_used
        session_env,session_args=session_builder.env_args
        all_env.merge!(session_env)
        all_args.push(*session_args)
      end

      return all_args, all_env
    end
  end
end
