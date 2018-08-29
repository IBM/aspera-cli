require 'asperalm/log'
require 'asperalm/command_line_builder'
require 'securerandom'
require 'base64'
require 'json'
require 'securerandom'

module Asperalm
  module Fasp
    # translate transfer specification to ascp parameter list
    class Parameters
      private
      @@file_list_folder=nil
      @@FILE_LIST_AGE_MAX=2*86400
      PARAM_DEFINITION={
        # parameters with env vars
        'remote_password'         => { :type => :envvar, :variable=>'ASPERA_SCP_PASS'},
        'token'                   => { :type => :envvar, :variable=>'ASPERA_SCP_TOKEN'},
        'cookie'                  => { :type => :envvar, :variable=>'ASPERA_SCP_COOKIE'},
        'EX_ssh_key_value'        => { :type => :envvar, :variable=>'ASPERA_SCP_KEY'},
        'EX_at_rest_password'     => { :type => :envvar, :variable=>'ASPERA_SCP_FILEPASS'},
        'EX_proxy_password'       => { :type => :envvar, :variable=>'ASPERA_PROXY_PASS'},
        # bool params
        'create_dir'              => { :type => :opt_without_arg, :option_switch=>'-d'},
        'precalculate_job_size'   => { :type => :opt_without_arg, :option_switch=>'--precalculate-job-size'},
        'EX_quiet'                => { :type => :opt_without_arg, :option_switch=>'-q'},
        # value params
        'cipher'                  => { :type => :opt_with_arg, :option_switch=>'-c',:accepted_types=>String,:translate_values=>{'aes128'=>'aes128','aes-128'=>'aes128','aes192'=>'aes192','aes-192'=>'aes192','aes256'=>'aes256','aes-256'=>'aes256','none'=>'none'}},
        'resume_policy'           => { :type => :opt_with_arg, :option_switch=>'-k',:accepted_types=>String,:default=>'sparse_csum',:translate_values=>{'none'=>0,'attrs'=>1,'sparse_csum'=>2,'full_csum'=>3}},
        'direction'               => { :type => :opt_with_arg, :option_switch=>'--mode',:accepted_types=>String,:translate_values=>{'receive'=>'recv','send'=>'send'}},
        'remote_user'             => { :type => :opt_with_arg, :option_switch=>'--user',:accepted_types=>String},
        'remote_host'             => { :type => :opt_with_arg, :option_switch=>'--host',:accepted_types=>String},
        'ssh_port'                => { :type => :opt_with_arg, :option_switch=>'-P',:accepted_types=>Integer},
        'fasp_port'               => { :type => :opt_with_arg, :option_switch=>'-O',:accepted_types=>Integer},
        'dgram_size'              => { :type => :opt_with_arg, :option_switch=>'-Z',:accepted_types=>Integer},
        'target_rate_kbps'        => { :type => :opt_with_arg, :option_switch=>'-l',:accepted_types=>Integer},
        'min_rate_kbps'           => { :type => :opt_with_arg, :option_switch=>'-m',:accepted_types=>Integer},
        'rate_policy'             => { :type => :opt_with_arg, :option_switch=>'--policy',:accepted_types=>String},
        'http_fallback'           => { :type => :opt_with_arg, :option_switch=>'-y',:accepted_types=>[String,*CommandLineBuilder::BOOLEAN_CLASSES],:translate_values=>{'force'=>'F',true=>1,false=>0}},
        'http_fallback_port'      => { :type => :opt_with_arg, :option_switch=>'-t',:accepted_types=>Integer},
        'source_root'             => { :type => :opt_with_arg, :option_switch=>'--source-prefix64',:accepted_types=>String,:encode=>lambda{|prefix|Base64.strict_encode64(prefix)}},
        'sshfp'                   => { :type => :opt_with_arg, :option_switch=>'--check-sshfp',:accepted_types=>String},
        'symlink_policy'          => { :type => :opt_with_arg, :option_switch=>'--symbolic-links',:accepted_types=>String},
        'overwrite'               => { :type => :opt_with_arg, :accepted_types=>String},
        # non standard parameters
        'EX_fallback_key'         => { :type => :opt_with_arg, :option_switch=>'-Y',:accepted_types=>String},
        'EX_fallback_cert'        => { :type => :opt_with_arg, :option_switch=>'-I',:accepted_types=>String},
        'EX_fasp_proxy_url'       => { :type => :opt_with_arg, :option_switch=>'--proxy',:accepted_types=>String},
        'EX_http_proxy_url'       => { :type => :opt_with_arg, :option_switch=>'-x',:accepted_types=>String},
        'EX_ssh_key_paths'        => { :type => :opt_with_arg, :option_switch=>'-i',:accepted_types=>Array},
        'EX_http_transfer_jpeg'   => { :type => :opt_with_arg, :option_switch=>'-j',:accepted_types=>Integer},
        'EX_multi_session_threshold' => { :type => :opt_with_arg, :option_switch=>'--multi-session-threshold',:accepted_types=>String},
        'EX_multi_session_part'   => { :type => :opt_with_arg, :option_switch=>'-C',:accepted_types=>String},
        # TODO: manage those parameters, some are for connect only ? node api ?
        'target_rate_cap_kbps'    => { :type => :ignore, :accepted_types=>Integer},
        'target_rate_percentage'  => { :type => :ignore, :accepted_types=>String}, # -wf -l<rate>p
        'min_rate_cap_kbps'       => { :type => :ignore, :accepted_types=>Integer},
        'rate_policy_allowed'     => { :type => :ignore, :accepted_types=>String},
        'fasp_url'                => { :type => :ignore, :accepted_types=>String},
        'lock_rate_policy'        => { :type => :ignore, :accepted_types=>CommandLineBuilder::BOOLEAN_CLASSES},
        'lock_min_rate'           => { :type => :ignore, :accepted_types=>CommandLineBuilder::BOOLEAN_CLASSES},
        'lock_target_rate'        => { :type => :ignore, :accepted_types=>CommandLineBuilder::BOOLEAN_CLASSES},
        'authentication'          => { :type => :ignore, :accepted_types=>String}, # = token
        'https_fallback_port'     => { :type => :ignore, :accepted_types=>Integer}, # same as http fallback, option -t ?
        'content_protection'      => { :type => :ignore, :accepted_types=>String},
        'cipher_allowed'          => { :type => :ignore, :accepted_types=>String},
        'multi_session'           => { :type => :ignore, :accepted_types=>Integer},
        'multi_session_threshold' => { :type => :ignore, :accepted_types=>Integer},
        # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
        'tags'                    => { :type => :opt_with_arg, :option_switch=>'--tags64',:accepted_types=>Hash,:encode=>lambda{|tags|Base64.strict_encode64(JSON.generate(tags))}},
      }

      def initialize(job_spec)
        @job_spec=job_spec
        @builder=CommandLineBuilder.new(@job_spec,PARAM_DEFINITION)
      end

      public

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def compute_args
        env_args={
          :args=>[],
          :env=>{},
          :ascp_version=>:ascp,
          :finalize=>lambda{nil}
        }
        # some ssh credentials are required to avoid interactive password input
        if !@job_spec.has_key?('remote_password') and
        !@job_spec.has_key?('EX_ssh_key_value') and
        !@job_spec.has_key?('EX_ssh_key_paths') then
          raise Fasp::Error.new('required: ssh key (value or path) or password')
        end

        @builder.process_params

        # symbol must be index of Installation.paths
        env_args[:ascp_version]=@builder.process_param('use_ascp4',:get_value) ? :ascp4 : :ascp

        # optional args, at the end to override previous ones (to allow override)
        @builder.add_command_line_options(@builder.process_param('EX_ascp_args',:get_value,:accepted_types=>Array))

        # destination will be base64 encoded, put before path arguments
        @builder.add_command_line_options(['--dest64'])

        # use file list if there is storage defined for it.
        src_dst_list=@builder.process_param('paths',:get_value,:accepted_types=>Array,:mandatory=>true)
        if @@file_list_folder.nil?
          # not safe for special characters ? (maybe not, depends on OS)
          Log.log.debug("placing source file list on command line (no file list file)")
          @builder.add_command_line_options(src_dst_list.map{|i|i['source']})
        else
          # safer option: file list
          # if there is destination in paths, then use filepairlist
          if src_dst_list.first.has_key?('destination')
            option='--file-pair-list'
            lines=src_dst_list.inject([]){|m,e|m.push(e['source'],e['destination']);m}
          else
            option='--file-list'
            lines=src_dst_list.map{|i|i['source']}
          end
          file_list_file=File.join(@@file_list_folder,SecureRandom.uuid)
          File.open(file_list_file, "w+"){|f|f.puts(lines)}
          @builder.add_command_line_options(["#{option}=#{file_list_file}"])
          # add finalization method to delete file after use
          env_args[:finalize]=lambda{FileUtils.rm_f(file_list_file)}
        end

        # destination, use base64 encoding  (as defined previously: --dest64)
        @builder.add_command_line_options([Base64.strict_encode64(@builder.process_param('destination_root',:get_value,:accepted_types=>String,:mandatory=>true))])

        @builder.add_env_args(env_args)

        return env_args
      end

      # temp files are created here  (if value is not nil)
      # garbage collect undeleted files
      def self.file_list_folder=(v)
        @@file_list_folder=v
        FileUtils.mkdir_p(@@file_list_folder)
        Dir.entries(@@file_list_folder) do |name|
          # TODO: check age of file, delete if older
          Log.log.error(">>#{name}")
          @@FILE_LIST_AGE_MAX
        end
      end

      def self.file_list_folder; @@file_list_folder;end

      def self.ts_to_env_args(transfer_spec)
        return Parameters.new(transfer_spec).compute_args
      end

    end # Parameters
  end # Fasp
end # Asperalm
