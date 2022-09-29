# frozen_string_literal: true

require 'aspera/log'
require 'aspera/command_line_builder'
require 'aspera/temp_file_manager'
require 'securerandom'
require 'base64'
require 'json'
require 'yaml'
require 'fileutils'
require 'openssl'

module Aspera
  module Fasp
    # translate transfer specification to ascp parameter list
    class Parameters
      # Agents shown in manual for parameters (sub list)
      SUPPORTED_AGENTS = %i[direct node connect].freeze
      # Short names of columns in manual
      SUPPORTED_AGENTS_SHORT = SUPPORTED_AGENTS.map{|a|a.to_s[0].to_sym}

      private_constant :SUPPORTED_AGENTS

      class << self
        # Temp folder for file lists, must contain only file lists
        # because of garbage collection takes any file there
        # this could be refined, as , for instance, on macos, temp folder is already user specific
        @file_list_folder = TempFileManager.instance.new_file_path_global('asession_filelists')
        @param_description_cache = nil
        # @return normalized description of transfer spec parameters, direct from yaml
        def description
          if @param_description_cache.nil?
            # config file in same folder with same name as this source
            description_from_yaml=YAML.load_file("#{__FILE__[0..-3]}yaml")
            @param_description_cache = Aspera::CommandLineBuilder.normalize_description(description_from_yaml)
          end
          return @param_description_cache
        end

        # @return a table suitable to display in manual
        def man_table
          result = []
          description.each do |k,i|
            param = {name: k, type: [i[:accepted_types]].flatten.join(','),description: i[:desc]}
            # add flags for supported agents in doc
            SUPPORTED_AGENTS.each do |a|
              param[a.to_s[0].to_sym] = i[:tragents].nil? || i[:tragents].include?(a) ? 'Y' : ''
            end
            # only keep lines that are usable in supported agents
            next if SUPPORTED_AGENTS_SHORT.inject(true){|m,j|m && param[j].empty?}
            param[:cli] =
              case i[:cltype]
              when :envvar then 'env:' + i[:clvarname]
              when :opt_without_arg then i[:clswitch]
              when :opt_with_arg
                values=if i.has_key?(:enum)
                  ['enum']
                elsif i[:accepted_types].is_a?(Array)
                  i[:accepted_types]
                elsif !i[:accepted_types].nil?
                  [i[:accepted_types]]
                else
                  raise "error: #{param}"
                end.map{|n|"{#{n}}"}.join('|')
                conv=i.has_key?(:clconvert) ? '(conversion)' : ''
                "#{i[:clswitch]} #{conv}#{values}"
              else ''
              end
            if i.has_key?(:enum)
              param[:description] += "\nAllowed values: #{i[:enum].join(', ')}"
            end
            result.push(param)
          end
          return result
        end

        # special encoding methods used in YAML (key: :clconvert)
        def clconv_remove_hyphen(v); v.tr('-',''); end

        # special encoding methods used in YAML (key: :clconvert)
        def clconv_json64(v); Base64.strict_encode64(JSON.generate(v)); end

        # special encoding methods used in YAML (key: :clconvert)
        def clconv_base64(v); Base64.strict_encode64(v); end

        # file list is provided directly with ascp arguments
        def ts_has_ascp_file_list(ts)
          (ts['EX_ascp_args'].is_a?(Array) && ['--file-list','--file-pair-list'].any?{|i|ts['EX_ascp_args'].include?(i)}) ||
          ts.has_key?('EX_file_list') ||
          ts.has_key?('EX_file_pair_list')
        end

        def ts_to_env_args(transfer_spec,options)
          return Parameters.new(transfer_spec,options).ascp_args
        end

        # temp file list files are created here
        def file_list_folder=(v)
          @file_list_folder = v
          return if @file_list_folder.nil?
          FileUtils.mkdir_p(@file_list_folder)
          TempFileManager.instance.cleanup_expired(@file_list_folder)
        end

        # static methods
        attr_reader :file_list_folder
      end # self

      # @param options [Hash] key: :wss: bool
      def initialize(job_spec,options)
        @job_spec = job_spec
        @options = options
        @builder = Aspera::CommandLineBuilder.new(@job_spec,self.class.description)
        Log.log.debug("agent options: #{@options}")
      end

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def ascp_args
        env_args = {
          args:         [],
          env:          {},
          ascp_version: :ascp
        }
        # some ssh credentials are required to avoid interactive password input
        if !@job_spec.has_key?('remote_password') &&
        !@job_spec.has_key?('ssh_private_key') &&
        !@job_spec.has_key?('EX_ssh_key_paths')
          raise Fasp::Error, 'required: password or ssh key (value or path)'
        end

        # special cases
        @job_spec.delete('source_root') if @job_spec.has_key?('source_root') && @job_spec['source_root'].empty?

        # use web socket session initiation ?
        if @builder.process_param('wss_enabled',:get_value) && (@options[:wss] || !@job_spec.has_key?('fasp_port'))
          # by default use web socket session if available, unless removed by user
          @builder.add_command_line_options(['--ws-connect'])
          # TODO: option to give order ssh,ws (legacy http is implied bu ssh)
          # quel bordel:
          @job_spec['ssh_port'] = @builder.process_param('wss_port',:get_value)
          @job_spec.delete('fasp_port')
          @job_spec.delete('EX_ssh_key_paths')
          @job_spec.delete('sshfp')
          # set location for CA bundle to be the one of Ruby, see env var SSL_CERT_FILE / SSL_CERT_DIR
          @job_spec['EX_ssh_key_paths'] = [OpenSSL::X509::DEFAULT_CERT_FILE]
          Log.log.debug('CA certs: EX_ssh_key_paths <- DEFAULT_CERT_FILE from openssl')
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
        # process file lists
        begin
          # is the file list provided through EX_ parameters?
          ascp_file_list_provided = self.class.ts_has_ascp_file_list(@job_spec)
          # set if paths is mandatory in ts
          @builder.params_definition['paths'][:mandatory] = !@job_spec.has_key?('keepalive') && !ascp_file_list_provided
          # get paths in transfer spec (after setting if it is mandatory)
          ts_paths_array = @builder.process_param('paths',:get_value)
          if ascp_file_list_provided && !ts_paths_array.nil?
            raise 'file list provided both in transfer spec and ascp file list. Remove one of them.'
          end
          # option 1: EX_file_list
          file_list_file = @builder.process_param('EX_file_list',:get_value)
          if !file_list_file.nil?
            option = '--file-list'
          else
            # option 2: EX_file_pair_list
            file_list_file = @builder.process_param('EX_file_pair_list',:get_value)
            if !file_list_file.nil?
              option = '--file-pair-list'
            elsif !ts_paths_array.nil?
              # option 3: in TS, it is an array
              if !self.class.file_list_folder.nil?
                # safer option: generate a file list file if there is storage defined for it
                # if there is destination in paths, then use filepairlist
                # TODO: well, we test only the first one, but anyway it shall be consistent
                if ts_paths_array.first.has_key?('destination')
                  option = '--file-pair-list'
                  lines = ts_paths_array.each_with_object([]){|e,m|m.push(e['source'],e['destination']);}
                else
                  option = '--file-list'
                  lines = ts_paths_array.map{|i|i['source']}
                end
                file_list_file = Aspera::TempFileManager.instance.new_file_path_in_folder(self.class.file_list_folder)
                File.write(file_list_file, lines.join("\n"))
                Log.log.debug{"#{option}=\n#{File.read(file_list_file)}".red}
              else
                # not safe for special characters ? (maybe not, depends on OS)
                Log.log.debug('placing source file list on command line (no file list file)')
                @builder.add_command_line_options(ts_paths_array.map{|i|i['source']})
              end
            end
          end
          @builder.add_command_line_options(["#{option}=#{file_list_file}"]) unless option.nil?
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
    end # Parameters
  end
end
