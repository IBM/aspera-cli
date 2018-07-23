module Asperalm
  class Sync
    def initialize(job_spec)
      @builder=CommandLineBuilder.new(job_spec)
    end

    def compute_args
      @builder.process_param('remote_password',:envvar,:variable=>'ASPERA_SCP_PASS')
      @builder.process_param('cookie',:envvar,:variable=>'ASPERA_SCP_COOKIE')
      @builder.process_param('token',:envvar,:variable=>'ASPERA_SCP_TOKEN')
      @builder.process_param('license',:envvar,:variable=>'ASPERA_SCP_LICENSE')
      @builder.process_param('name',:opt_with_arg,:option_switch=>'--name',:accepted_types=>[String])
      @builder.process_param('local_dir',:opt_with_arg,:option_switch=>'--local-dir',:accepted_types=>[String])
      @builder.process_param('remote_dir',:opt_with_arg,:option_switch=>'--remote-dir',:accepted_types=>[String])
      @builder.process_param('host',:opt_with_arg,:option_switch=>'--host',:accepted_types=>[String])
      @builder.process_param('user',:opt_with_arg,:option_switch=>'--user',:accepted_types=>[String])
      @builder.process_param('private_key_path',:opt_with_arg,:option_switch=>'--private-key-path',:accepted_types=>[String])
      @builder.process_param('direction',:opt_with_arg,:option_switch=>'--direction',:accepted_types=>[String])
      @builder.process_param('checksum',:opt_with_arg,:option_switch=>'--checksum',:accepted_types=>[String])
      @builder.process_param('tcp_port',:opt_with_arg,:option_switch=>'--tcp-port',:accepted_types=>[Integer])
      @builder.process_param('rate_policy',:opt_with_arg,:option_switch=>'--rate-policy',:accepted_types=>[String])
      @builder.process_param('target_rate',:opt_with_arg,:option_switch=>'--target-rate',:accepted_types=>[String])
      @builder.process_param('cooloff',:opt_with_arg,:option_switch=>'--cooloff',:accepted_types=>[Integer])
      @builder.process_param('pending_max',:opt_with_arg,:option_switch=>'--pending-max',:accepted_types=>[Integer])
      @builder.process_param('scan_intensity',:opt_with_arg,:option_switch=>'--scan-intensity',:accepted_types=>[String])
      @builder.process_param('cipher',:opt_with_arg,:option_switch=>'--cipher',:accepted_types=>[String])
      @builder.process_param('transfer_threads',:opt_with_arg,:option_switch=>'--transfer-threads',:accepted_types=>[Integer])
      @builder.process_param('preserve_time',:opt_without_arg,:option_switch=>'--preserve-time')
      @builder.process_param('preserve_access_time',:opt_without_arg,:option_switch=>'--preserve-access-time')
      @builder.process_param('preserve_modification_time',:opt_without_arg,:option_switch=>'--preserve-modification-time')
      @builder.process_param('preserve_uid',:opt_without_arg,:option_switch=>'--preserve-uid')
      @builder.process_param('preserve_gid',:opt_without_arg,:option_switch=>'--preserve-gid')
      @builder.process_param('create_dir',:opt_without_arg,:option_switch=>'--create-dir')
      @builder.check_all_used

      return @builder.result_args, @builder.result_env
      #@builder.result_env
    end
  end
end
