require 'asperalm/log'
require 'asperalm/command_line_builder'
require 'securerandom'
require 'base64'
require 'json'

module Asperalm
  module Fasp
    # translate transfer specification to ascp parameter list
    class Parameters
      # temp files are created here, change to go elsewhere
      @@file_list_folder='.'
      def self.file_list_folder; @@file_list_folder;end

      def self.file_list_folder=(v); @@file_list_folder=v;end

      def initialize(job_spec)
        @job_spec=job_spec
        @builder=CommandLineBuilder.new(@job_spec)
      end

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def compute_args
        # some ssh credentials are required to avoid interactive password input
        if !@job_spec.has_key?('remote_password') and
        !@job_spec.has_key?('EX_ssh_key_value') and
        !@job_spec.has_key?('EX_ssh_key_paths') then
          raise Fasp::Error.new('required: ssh key (value or path) or password')
        end

        # parameters with env vars
        @builder.process_param('remote_password',:envvar,:variable=>'ASPERA_SCP_PASS')
        @builder.process_param('token',:envvar,:variable=>'ASPERA_SCP_TOKEN')
        @builder.process_param('cookie',:envvar,:variable=>'ASPERA_SCP_COOKIE')
        @builder.process_param('EX_ssh_key_value',:envvar,:variable=>'ASPERA_SCP_KEY')
        @builder.process_param('EX_at_rest_password',:envvar,:variable=>'ASPERA_SCP_FILEPASS')
        @builder.process_param('EX_proxy_password',:envvar,:variable=>'ASPERA_PROXY_PASS')

        @builder.process_param('create_dir',:opt_without_arg,:option_switch=>'-d')
        @builder.process_param('precalculate_job_size',:opt_without_arg,:option_switch=>'--precalculate-job-size')
        @builder.process_param('EX_quiet',:opt_without_arg,:option_switch=>'-q')

        @builder.process_param('cipher',:opt_with_arg,:option_switch=>'-c',:accepted_types=>[String],:translate_values=>{'aes128'=>'aes128','aes-128'=>'aes128','aes192'=>'aes192','aes-192'=>'aes192','aes256'=>'aes256','aes-256'=>'aes256','none'=>'none'})
        @builder.process_param('resume_policy',:opt_with_arg,:option_switch=>'-k',:accepted_types=>[String],:default=>'sparse_csum',:translate_values=>{'none'=>0,'attrs'=>1,'sparse_csum'=>2,'full_csum'=>3})
        @builder.process_param('direction',:opt_with_arg,:option_switch=>'--mode',:accepted_types=>[String],:translate_values=>{'receive'=>'recv','send'=>'send'})
        @builder.process_param('remote_user',:opt_with_arg,:option_switch=>'--user',:accepted_types=>[String])
        @builder.process_param('remote_host',:opt_with_arg,:option_switch=>'--host',:accepted_types=>[String])
        @builder.process_param('ssh_port',:opt_with_arg,:option_switch=>'-P',:accepted_types=>[Integer])
        @builder.process_param('fasp_port',:opt_with_arg,:option_switch=>'-O',:accepted_types=>[Integer])
        @builder.process_param('dgram_size',:opt_with_arg,:option_switch=>'-Z',:accepted_types=>[Integer])
        @builder.process_param('target_rate_kbps',:opt_with_arg,:option_switch=>'-l',:accepted_types=>[Integer])
        @builder.process_param('min_rate_kbps',:opt_with_arg,:option_switch=>'-m',:accepted_types=>[Integer])
        @builder.process_param('rate_policy',:opt_with_arg,:option_switch=>'--policy',:accepted_types=>[String])
        @builder.process_param('http_fallback',:opt_with_arg,:option_switch=>'-y',:accepted_types=>[String,*CommandLineBuilder::BOOLEAN_CLASSES],:translate_values=>{'force'=>'F',true=>1,false=>0})
        @builder.process_param('http_fallback_port',:opt_with_arg,:option_switch=>'-t',:accepted_types=>[Integer])
        @builder.process_param('source_root',:opt_with_arg,:option_switch=>'--source-prefix64',:accepted_types=>[String],:encode=>lambda{|prefix|Base64.strict_encode64(prefix)})
        @builder.process_param('sshfp',:opt_with_arg,:option_switch=>'--check-sshfp',:accepted_types=>[String])
        @builder.process_param('symlink_policy',:opt_with_arg,:option_switch=>'--symbolic-links',:accepted_types=>[String])
        @builder.process_param('overwrite',:opt_with_arg,:option_switch=>'--overwrite',:accepted_types=>[String])

        @builder.process_param('EX_fallback_key',:opt_with_arg,:option_switch=>'-Y',:accepted_types=>[String])
        @builder.process_param('EX_fallback_cert',:opt_with_arg,:option_switch=>'-I',:accepted_types=>[String])
        @builder.process_param('EX_fasp_proxy_url',:opt_with_arg,:option_switch=>'--proxy',:accepted_types=>[String])
        @builder.process_param('EX_http_proxy_url',:opt_with_arg,:option_switch=>'-x',:accepted_types=>[String])
        @builder.process_param('EX_ssh_key_paths',:opt_with_arg,:option_switch=>'-i',:accepted_types=>[Array])
        @builder.process_param('EX_http_transfer_jpeg',:opt_with_arg,:option_switch=>'-j',:accepted_types=>[Integer])
        @builder.process_param('EX_multi_session_threshold',:opt_with_arg,:option_switch=>'--multi-session-threshold',:accepted_types=>[String])
        @builder.process_param('EX_multi_session_part',:opt_with_arg,:option_switch=>'-C',:accepted_types=>[String])

        # TODO: manage those parameters, some are for connect only ? node api ?
        @builder.process_param('target_rate_cap_kbps',:ignore,:accepted_types=>[Integer])
        @builder.process_param('target_rate_percentage',:ignore,:accepted_types=>[String]) # -wf -l<rate>p
        @builder.process_param('min_rate_cap_kbps',:ignore,:accepted_types=>[Integer])
        @builder.process_param('rate_policy_allowed',:ignore,:accepted_types=>[String])
        @builder.process_param('fasp_url',:ignore,:accepted_types=>[String])
        @builder.process_param('lock_rate_policy',:ignore,:accepted_types=>CommandLineBuilder::BOOLEAN_CLASSES)
        @builder.process_param('lock_min_rate',:ignore,:accepted_types=>CommandLineBuilder::BOOLEAN_CLASSES)
        @builder.process_param('lock_target_rate',:ignore,:accepted_types=>CommandLineBuilder::BOOLEAN_CLASSES)
        @builder.process_param('authentication',:ignore,:accepted_types=>[String]) # = token
        @builder.process_param('https_fallback_port',:ignore,:accepted_types=>[Integer]) # same as http fallback, option -t ?
        @builder.process_param('content_protection',:ignore,:accepted_types=>[String])
        @builder.process_param('cipher_allowed',:ignore,:accepted_types=>[String])
        @builder.process_param('multi_session',:ignore,:accepted_types=>[Integer])
        @builder.process_param('multi_session_threshold',:ignore,:accepted_types=>[Integer])

        # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
        @builder.process_param('tags',:opt_with_arg,:option_switch=>'--tags64',:accepted_types=>[Hash],:encode=>lambda{|tags|Base64.strict_encode64(JSON.generate(tags))})

        # optional args, at the end to override previous ones (to allow override)
        @builder.add_command_line_options(@builder.process_param('EX_ascp_args',:get_value,:accepted_types=>[Array]))

        # destination will be base64 encoded, put before path arguments
        @builder.add_command_line_options(['--dest64'])

        # source list: TODO : use file list or file pair list, avoid command line lists
        @builder.add_command_line_options(@builder.process_param('paths',:get_value,:accepted_types=>[Array],:mandatory=>true).map{|i|i['source']})

        # destination, use base64 encoding, as defined previously
        @builder.add_command_line_options([Base64.strict_encode64(@builder.process_param('destination_root',:get_value,:accepted_types=>[String],:mandatory=>true))])

        # symbol must be index of Installation.paths
        ascp_version=@builder.process_param('use_ascp4',:get_value) ? :ascp4 : :ascp

        @builder.check_all_used

        ascp_env,ascp_args=@builder.env_args

        return {:args=>ascp_args,:env=>ascp_env,:ascp_version=>ascp_version}
      end

    end # Parameters
  end # Fasp
end # Asperalm
