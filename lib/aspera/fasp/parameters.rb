require 'aspera/log'
require 'aspera/command_line_builder'
require 'aspera/temp_file_manager'
require 'securerandom'
require 'base64'
require 'json'
require 'securerandom'
require 'fileutils'

module Aspera
  module Fasp
    # translate transfer specification to ascp parameter list
    class Parameters
      private
      # temp folder for file lists, must contain only file lists
      # because of garbage collection takes any file there
      # this could be refined, as , for instance, on macos, temp folder is already user specific
      @@file_list_folder=TempFileManager.instance.new_file_path_global('asession_filelists')
      SEC_IN_DAY=86400
      # assume no transfer last longer than this
      # (garbage collect file list which were not deleted after transfer)
      FILE_LIST_AGE_MAX_SEC=5*SEC_IN_DAY
      PARAM_DEFINITION={
        # parameters with env vars
        'remote_password'         => { :type => :envvar, :variable=>'ASPERA_SCP_PASS'},
        'token'                   => { :type => :envvar, :variable=>'ASPERA_SCP_TOKEN'},
        'cookie'                  => { :type => :envvar, :variable=>'ASPERA_SCP_COOKIE'},
        'ssh_private_key'         => { :type => :envvar, :variable=>'ASPERA_SCP_KEY'},
        'EX_at_rest_password'     => { :type => :envvar, :variable=>'ASPERA_SCP_FILEPASS'},
        'EX_proxy_password'       => { :type => :envvar, :variable=>'ASPERA_PROXY_PASS'},
        'EX_license_text'         => { :type => :envvar, :variable=>'ASPERA_SCP_LICENSE'},
        # bool params
        'create_dir'              => { :type => :opt_without_arg, :option_switch=>'-d'},
        'precalculate_job_size'   => { :type => :opt_without_arg},
        'keepalive'               => { :type => :opt_without_arg},
        'delete_before_transfer'  => { :type => :opt_without_arg}, #TODO: doc readme
        'preserve_access_time'    => { :type => :opt_without_arg}, #TODO: doc
        'preserve_creation_time'  => { :type => :opt_without_arg}, #TODO: doc
        'preserve_times'          => { :type => :opt_without_arg}, #TODO: doc
        'preserve_modification_time'=> { :type => :opt_without_arg}, #TODO: doc
        'remove_empty_directories'=> { :type => :opt_without_arg}, #TODO: doc
        'remove_after_transfer'   => { :type => :opt_without_arg}, #TODO: doc
        'remove_empty_source_directory'=> { :type => :opt_without_arg}, #TODO: doc
        # value params
        'cipher'                  => { :type => :opt_with_arg, :option_switch=>'-c',:accepted_types=>String,:encode=>lambda{|cipher|cipher.tr('-','')}},
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
        'http_fallback'           => { :type => :opt_with_arg, :option_switch=>'-y',:accepted_types=>[String,*Aspera::CommandLineBuilder::BOOLEAN_CLASSES],:translate_values=>{'force'=>'F',true=>1,false=>0}},
        'http_fallback_port'      => { :type => :opt_with_arg, :option_switch=>'-t',:accepted_types=>Integer},
        'source_root'             => { :type => :opt_with_arg, :option_switch=>'--source-prefix64',:accepted_types=>String,:encode=>lambda{|prefix|Base64.strict_encode64(prefix)}},
        'sshfp'                   => { :type => :opt_with_arg, :option_switch=>'--check-sshfp',:accepted_types=>String},
        'symlink_policy'          => { :type => :opt_with_arg, :option_switch=>'--symbolic-links',:accepted_types=>String},
        'overwrite'               => { :type => :opt_with_arg, :accepted_types=>String},
        'exclude_newer_than'      => { :type => :opt_with_arg, :accepted_types=>Integer},
        'exclude_older_than'      => { :type => :opt_with_arg, :accepted_types=>Integer},
        'preserve_acls'           => { :type => :opt_with_arg, :accepted_types=>String},
        'move_after_transfer'     => { :type => :opt_with_arg, :accepted_types=>String},
        'multi_session_threshold' => { :type => :opt_with_arg, :accepted_types=>String},
        # non standard parameters
        'EX_fasp_proxy_url'       => { :type => :opt_with_arg, :option_switch=>'--proxy',:accepted_types=>String},
        'EX_http_proxy_url'       => { :type => :opt_with_arg, :option_switch=>'-x',:accepted_types=>String},
        'EX_ssh_key_paths'        => { :type => :opt_with_arg, :option_switch=>'-i',:accepted_types=>Array},
        'EX_http_transfer_jpeg'   => { :type => :opt_with_arg, :option_switch=>'-j',:accepted_types=>Integer},
        'EX_multi_session_part'   => { :type => :opt_with_arg, :option_switch=>'-C',:accepted_types=>String},
        'EX_no_read'              => { :type => :opt_without_arg, :option_switch=>'--no-read'},
        'EX_no_write'             => { :type => :opt_without_arg, :option_switch=>'--no-write'},
        'EX_apply_local_docroot'  => { :type => :opt_without_arg, :option_switch=>'--apply-local-docroot'},
        # TODO: manage those parameters, some are for connect only ? node api ?
        'target_rate_cap_kbps'    => { :type => :ignore, :accepted_types=>Integer},
        'target_rate_percentage'  => { :type => :ignore, :accepted_types=>String}, # -wf -l<rate>p
        'min_rate_cap_kbps'       => { :type => :ignore, :accepted_types=>Integer},
        'rate_policy_allowed'     => { :type => :ignore, :accepted_types=>String},
        'fasp_url'                => { :type => :ignore, :accepted_types=>String},
        'lock_rate_policy'        => { :type => :ignore, :accepted_types=>Aspera::CommandLineBuilder::BOOLEAN_CLASSES},
        'lock_min_rate'           => { :type => :ignore, :accepted_types=>Aspera::CommandLineBuilder::BOOLEAN_CLASSES},
        'lock_target_rate'        => { :type => :ignore, :accepted_types=>Aspera::CommandLineBuilder::BOOLEAN_CLASSES},
        #'authentication'          => { :type => :ignore, :accepted_types=>String}, # = token
        'https_fallback_port'     => { :type => :ignore, :accepted_types=>Integer}, # same as http fallback, option -t ?
        'content_protection'      => { :type => :ignore, :accepted_types=>String},
        'cipher_allowed'          => { :type => :ignore, :accepted_types=>String},
        'multi_session'           => { :type => :ignore, :accepted_types=>Integer}, # managed
        # optional tags (  additional option to generate: {:space=>' ',:object_nl=>' ',:space_before=>'+',:array_nl=>'1'}  )
        'tags'                    => { :type => :opt_with_arg, :option_switch=>'--tags64',:accepted_types=>Hash,:encode=>lambda{|tags|Base64.strict_encode64(JSON.generate(tags))}},
        # special processing @builder.process_param( called individually
        'use_ascp4'               => { :type => :defer, :accepted_types=>Aspera::CommandLineBuilder::BOOLEAN_CLASSES},
        'paths'                   => { :type => :defer, :accepted_types=>Array},
        'EX_file_list'            => { :type => :defer, :option_switch=>'--file-list', :accepted_types=>String},
        'EX_file_pair_list'       => { :type => :defer, :option_switch=>'--file-pair-list', :accepted_types=>String},
        'EX_ascp_args'            => { :type => :defer, :accepted_types=>Array},
        'destination_root'        => { :type => :defer, :accepted_types=>String},
        'wss_enabled'             => { :type => :defer, :accepted_types=>Aspera::CommandLineBuilder::BOOLEAN_CLASSES},
        'wss_port'                => { :type => :defer, :accepted_types=>Integer},
      }

      private_constant :SEC_IN_DAY,:FILE_LIST_AGE_MAX_SEC,:PARAM_DEFINITION

      def initialize(job_spec,options)
        @job_spec=job_spec
        @builder=Aspera::CommandLineBuilder.new(@job_spec,PARAM_DEFINITION)
        @options=options
      end

      public

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def ascp_args()
        env_args={
          :args=>[],
          :env=>{},
          :ascp_version=>:ascp
        }
        # some ssh credentials are required to avoid interactive password input
        if !@job_spec.has_key?('remote_password') and
        !@job_spec.has_key?('ssh_private_key') and
        !@job_spec.has_key?('EX_ssh_key_paths') then
          raise Fasp::Error.new('required: password or ssh key (value or path)')
        end

        # special cases
        @job_spec.delete('source_root') if @job_spec.has_key?('source_root') and @job_spec['source_root'].empty?

        # use web socket initiation ?
        if @builder.process_param('wss_enabled',:get_value) and @options[:wss]
          # by default use web socket session if available, unless removed by user
          @builder.add_command_line_options(['--ws-connect'])
          # TODO: option to give order ssh,ws (legacy http is implied bu ssh)
          # quel bordel:
          @job_spec['ssh_port']=@builder.process_param('wss_port',:get_value)
          @job_spec.delete('fasp_port')
          @job_spec.delete('EX_ssh_key_paths')
          @job_spec.delete('sshfp')
        else
          # remove unused parameter (avoid warning)
          @job_spec.delete('wss_port')
        end

        # process parameters as specified in table
        @builder.process_params

        # symbol must be index of Installation.paths
        if @builder.process_param('use_ascp4',:get_value)
          env_args[:ascp_version] = :ascp4
        else
          env_args[:ascp_version] = :ascp
          # destination will be base64 encoded, put before path arguments
          @builder.add_command_line_options(['--dest64'])
        end

        PARAM_DEFINITION['paths'][:mandatory]=!@job_spec.has_key?('keepalive')
        paths_array=@builder.process_param('paths',:get_value)
        unless paths_array.nil?
          # use file list if there is storage defined for it.
          if @@file_list_folder.nil?
            # not safe for special characters ? (maybe not, depends on OS)
            Log.log.debug("placing source file list on command line (no file list file)")
            @builder.add_command_line_options(paths_array.map{|i|i['source']})
          else
            file_list_file=@builder.process_param('EX_file_list',:get_value)
            if !file_list_file.nil?
              option='--file-list'
            else
              file_list_file=@builder.process_param('EX_file_pair_list',:get_value)
              if !file_list_file.nil?
                option='--file-pair-list'
              else
                # safer option: file list
                # if there is destination in paths, then use filepairlist
                # TODO: well, we test only the first one, but anyway it shall be consistent
                if paths_array.first.has_key?('destination')
                  option='--file-pair-list'
                  lines=paths_array.inject([]){|m,e|m.push(e['source'],e['destination']);m}
                else
                  option='--file-list'
                  lines=paths_array.map{|i|i['source']}
                end
                file_list_file=Aspera::TempFileManager.instance.new_file_path_in_folder(@@file_list_folder)
                File.open(file_list_file, 'w+'){|f|f.puts(lines)}
                Log.log.debug("#{option}=\n#{File.read(file_list_file)}".red)
              end
            end
            @builder.add_command_line_options(["#{option}=#{file_list_file}"])
          end
        end
        # optional args, at the end to override previous ones (to allow override)
        @builder.add_command_line_options(@builder.process_param('EX_ascp_args',:get_value))
        # process destination folder
        destination_folder = @builder.process_param('destination_root',:get_value) || '/'
        # ascp4 does not support base64 encoding of destination
        destination_folder = Base64.strict_encode64(destination_folder) unless env_args[:ascp_version].eql?(:ascp4)
        # destination MUST be last command line argument to ascp
        @builder.add_command_line_options([destination_folder])

        @builder.add_env_args(env_args[:env],env_args[:args])

        return env_args
      end

      # temp file list files are created here
      def self.file_list_folder=(v)
        @@file_list_folder=v
        unless @@file_list_folder.nil?
          FileUtils.mkdir_p(@@file_list_folder)
          # garbage collect undeleted files
          Dir.entries(@@file_list_folder).each do |name|
            file_path=File.join(@@file_list_folder,name)
            age_sec=(Time.now - File.stat(file_path).mtime).to_i
            # check age of file, delete too old
            if File.file?(file_path) and age_sec > FILE_LIST_AGE_MAX_SEC
              Log.log.debug("garbage collecting #{name}")
              File.delete(file_path)
            end
          end
        end
      end

      # static methods
      class << self
        def file_list_folder; @@file_list_folder;end

        def ts_to_env_args(transfer_spec,options)
          return Parameters.new(transfer_spec,options).ascp_args()
        end
      end
    end # Parameters
  end
end
