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
      # Temp folder for file lists, must contain only file lists
      # because of garbage collection takes any file there
      # this could be refined, as , for instance, on macos, temp folder is already user specific
      @@file_list_folder=TempFileManager.instance.new_file_path_global('asession_filelists')
      @@param_description_cache=nil
      # @return normaiwed description of transfer spec parameters
      def self.description
        return @@param_description_cache unless @@param_description_cache.nil?
        # config file in same folder with same name as this source
        @@param_description_cache=YAML.load_file("#{__FILE__[0..-3]}yaml")
        Aspera::CommandLineBuilder.normalize_description(@@param_description_cache)
      end

      # Agents shown in manual
      SUPPORTED_AGENTS=[:direct,:node,:connect]
      # Short names of columns in manual
      SUPPORTED_AGENTS_SHORT=SUPPORTED_AGENTS.map{|a|a.to_s[0].to_sym}

      # @return a table suitable to display a manual
      def self.man_table
        result=[]
        description.keys.map do |k|
          i=description[k]
          param={name: k, type: [i[:accepted_types]].flatten.join(','),description: i[:desc]}
          SUPPORTED_AGENTS.each do |a|
            param[a.to_s[0].to_sym]=i[:context].nil? || i[:context].include?(a) ? 'Y' : ''
          end
          # only keep lines that are usable in supported agents
          next if SUPPORTED_AGENTS_SHORT.inject(true){|m,i|m and param[i].empty?}
          param[:cli]=case i[:cltype]
          when :envvar; 'env:'+i[:clvarname]
          when :opt_without_arg,:opt_with_arg; i[:option_switch]
          else ''
          end
          if i.has_key?(:enum)
            param[:description] << "\nAllowed values: #{i[:enum].join(', ')}"
          end
          result.push(param)
        end
        return result
      end

      # special encoding methods used in YAML (key: :encode)
      def self.encode_cipher(v)
        v.tr('-','')
      end

      # special encoding methods used in YAML (key: :encode)
      def self.encode_source_root(v)
        Base64.strict_encode64(v)
      end

      # special encoding methods used in YAML (key: :encode)
      def self.encode_tags(v)
        Base64.strict_encode64(JSON.generate(v))
      end

      def self.ts_has_file_list(ts)
        ts.has_key?('EX_ascp_args') and ts['EX_ascp_args'].is_a?(Array) and ['--file-list','--file-pair-list'].any?{|i|ts['EX_ascp_args'].include?(i)}
      end

      def initialize(job_spec,options)
        @job_spec=job_spec
        @options=options
        @builder=Aspera::CommandLineBuilder.new(@job_spec,self.class.description)
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
        # paths is mandatory, unless ...
        file_list_provided=self.class.ts_has_file_list(@job_spec)
        @builder.params_definition['paths'][:mandatory]=!@job_spec.has_key?('keepalive') and !file_list_provided
        paths_array=@builder.process_param('paths',:get_value)
        if file_list_provided and ! paths_array.nil?
          Log.log.warn("file list provided both in transfer spec and ascp file list. Keeping file list only.")
          paths_array=nil
        end
        if ! paths_array.nil?
          # it's an array
          raise "paths is empty in transfer spec" if paths_array.empty?
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
