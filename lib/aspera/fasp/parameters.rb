require 'aspera/log'
require 'aspera/command_line_builder'
require 'aspera/temp_file_manager'
require 'securerandom'
require 'base64'
require 'json'
require 'yaml'
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
      @@spec=nil
      def self.spec
        return @@spec unless @@spec.nil?
        # config file in same folder with same name as this source
        @@spec=YAML.load_file("#{__FILE__[0..-3]}yaml")
        @@spec.each do |item|
        end
      end

      # special encoding methods used in YAML
      def self.encode_cipher(v)
        v.tr('-','')
      end

      def self.encode_source_root(v)
        Base64.strict_encode64(v)
      end

      def self.encode_tags(v)
        Base64.strict_encode64(JSON.generate(v))
      end

      def initialize(job_spec,options)
        @job_spec=job_spec
        @options=options
        @builder=Aspera::CommandLineBuilder.new(@job_spec,self.class.spec)
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

        # use web socket session initiation ?
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
        @builder.params_definition['paths'][:mandatory]=!@job_spec.has_key?('keepalive')
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
        if !@@file_list_folder.nil?
          FileUtils.mkdir_p(@@file_list_folder)
          TempFileManager.instance.cleanup_expired(@@file_list_folder)
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
