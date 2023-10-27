# frozen_string_literal: true

require 'aspera/log'
require 'aspera/command_line_builder'
require 'aspera/temp_file_manager'
require 'aspera/fasp/error'
require 'aspera/cli/formatter'
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
      SUPPORTED_AGENTS = %i[direct node connect trsdk httpgw].freeze
      # Short names of columns in manual
      SUPPORTED_AGENTS_SHORT = SUPPORTED_AGENTS.map{|a|a.to_s[0].to_sym}
      FILE_LIST_OPTIONS = ['--file-list', '--file-pair-list'].freeze
      SUPPORTED_OPTIONS = %i[ascp_args wss].freeze

      private_constant :SUPPORTED_AGENTS, :FILE_LIST_OPTIONS

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
            description_from_yaml = YAML.load_file("#{__FILE__[0..-3]}yaml")
            @param_description_cache = Aspera::CommandLineBuilder.normalize_description(description_from_yaml)
          end
          return @param_description_cache
        end

        # @param to_text [bool] replace HTML entities with text equivalent
        # @return a table suitable to display in manual
        def man_table
          result = []
          description.each do |name, options|
            param = {name: name, type: [options[:accepted_types]].flatten.join(','), description: options[:desc]}
            # add flags for supported agents in doc
            SUPPORTED_AGENTS.each do |a|
              param[a.to_s[0].to_sym] = Cli::Formatter.tick(options[:agents].nil? || options[:agents].include?(a))
            end
            # only keep lines that are usable in supported agents
            next if SUPPORTED_AGENTS_SHORT.inject(true){|m, j|m && param[j].empty?}
            param[:cli] =
              case options[:cli][:type]
              when :envvar then 'env:' + options[:cli][:variable]
              when :opt_without_arg then options[:cli][:switch]
              when :opt_with_arg
                values = if options.key?(:enum)
                  ['enum']
                elsif options[:accepted_types].is_a?(Array)
                  options[:accepted_types]
                elsif !options[:accepted_types].nil?
                  [options[:accepted_types]]
                else
                  raise "error: #{param}"
                end.map{|n|"{#{n}}"}.join('|')
                conv = options[:cli].key?(:convert) ? '(conversion)' : ''
                "#{options[:cli][:switch]} #{conv}#{values}"
              when :special then Cli::Formatter.special('special')
              when :ignore then Cli::Formatter.special('ignored')
              else
                param[:d].eql?(tick_yes) ? '' : 'n/a'
              end
            if options.key?(:enum)
              param[:description] += "\nAllowed values: #{options[:enum].join(', ')}"
            end
            # replace "solidus" HTML entity with its text value
            param[:description] = param[:description].gsub('&sol;', '\\')
            result.push(param)
          end
          return result.sort do |a, b|
            if a[:name].start_with?('EX_').eql?(b[:name].start_with?('EX_'))
              a[:name] <=> b[:name]
            else
              b[:name] <=> a[:name]
            end
          end
        end

        # special encoding methods used in YAML (key: :convert)
        def convert_remove_hyphen(v); v.tr('-', ''); end

        # special encoding methods used in YAML (key: :convert)
        def convert_json64(v); Base64.strict_encode64(JSON.generate(v)); end

        # special encoding methods used in YAML (key: :convert)
        def convert_base64(v); Base64.strict_encode64(v); end

        # file list is provided directly with ascp arguments
        def ts_has_ascp_file_list(ts, ascp_args)
          # it can also be option transfer_info
          ascp_args = ascp_args['ascp_args'] if ascp_args.is_a?(Hash)
          (ts['EX_ascp_args'].is_a?(Array) && ts['EX_ascp_args'].any?{|i|FILE_LIST_OPTIONS.include?(i)}) ||
            (ascp_args.is_a?(Array) && ascp_args.any?{|i|FILE_LIST_OPTIONS.include?(i)}) ||
            ts.key?('EX_file_list') ||
            ts.key?('EX_file_pair_list')
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

      # @param options [Hash] key: :wss: bool, :ascp_args: array of strings
      def initialize(job_spec, options)
        @job_spec = job_spec
        # check necessary options
        raise 'Internal: missing options' unless (SUPPORTED_OPTIONS - options.keys).empty?
        @options = SUPPORTED_OPTIONS.each_with_object({}){|o, h| h[o] = options[o]}
        Log.dump(:options, @options)
        raise 'ascp args must be an Array' unless @options[:ascp_args].is_a?(Array)
        raise 'ascp args must be an Array of String' if @options[:ascp_args].any?{|i|!i.is_a?(String)}
        @builder = Aspera::CommandLineBuilder.new(@job_spec, self.class.description)
      end

      def process_file_list
        # is the file list provided through EX_ parameters?
        ascp_file_list_provided = self.class.ts_has_ascp_file_list(@job_spec, @options[:ascp_args])
        # set if paths is mandatory in ts
        @builder.params_definition['paths'][:mandatory] = !@job_spec.key?('keepalive') && !ascp_file_list_provided
        # get paths in transfer spec (after setting if it is mandatory)
        ts_paths_array = @builder.read_param('paths')
        if ascp_file_list_provided && !ts_paths_array.nil?
          raise 'file list provided both in transfer spec and ascp file list. Remove one of them.'
        end
        # option 1: EX_file_list
        file_list_file = @builder.read_param('EX_file_list')
        if file_list_file.nil?
          # option 2: EX_file_pair_list
          file_list_file = @builder.read_param('EX_file_pair_list')
          if !file_list_file.nil?
            option = '--file-pair-list'
          elsif !ts_paths_array.nil?
            # option 3: in TS, it is an array
            if self.class.file_list_folder.nil?
              # not safe for special characters ? (maybe not, depends on OS)
              Log.log.debug('placing source file list on command line (no file list file)')
              @builder.add_command_line_options(ts_paths_array.map{|i|i['source']})
            else
              raise "All elements of paths must have a 'source' key" unless ts_paths_array.all?{|i|i.key?('source')}
              is_pair_list = ts_paths_array.any?{|i|i.key?('destination')}
              raise "All elements of paths must be consistent with 'destination' key" if is_pair_list && !ts_paths_array.all?{|i|i.key?('destination')}
              # safer option: generate a file list file if there is storage defined for it
              # if there is one destination in paths, then use file-pair-list
              if is_pair_list
                option = '--file-pair-list'
                lines = ts_paths_array.each_with_object([]){|e, m|m.push(e['source'], e['destination'] || e['source']); }
              else
                option = '--file-list'
                lines = ts_paths_array.map{|i|i['source']}
              end
              file_list_file = Aspera::TempFileManager.instance.new_file_path_in_folder(self.class.file_list_folder)
              Log.dump(:file_list, lines)
              File.write(file_list_file, lines.join("\n"), encoding: 'UTF-8')
              Log.log.debug{"#{option}=\n#{File.read(file_list_file)}".red}
            end
          end
        else
          option = '--file-list'
        end
        @builder.add_command_line_options(["#{option}=#{file_list_file}"]) unless option.nil?
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
        if !@job_spec.key?('remote_password') &&
            !@job_spec.key?('ssh_private_key') &&
            !@job_spec.key?('EX_ssh_key_paths')
          raise Fasp::Error, 'required: password or ssh key (value or path)'
        end

        # special cases
        @job_spec.delete('source_root') if @job_spec.key?('source_root') && @job_spec['source_root'].empty?

        # notify multi-session was already used, anyway it was deleted by agent direct
        raise 'internal error' if @builder.read_param('multi_session')

        # use web socket session initiation ?
        if @builder.read_param('wss_enabled') && (@options[:wss] || !@job_spec.key?('fasp_port'))
          # by default use web socket session if available, unless removed by user
          @builder.add_command_line_options(['--ws-connect'])
          # TODO: option to give order ssh,ws (legacy http is implied bu ssh)
          # This will need to be cleaned up in aspera core
          @job_spec['ssh_port'] = @builder.read_param('wss_port')
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
        if @builder.read_param('use_ascp4')
          env_args[:ascp_version] = :ascp4
        else
          env_args[:ascp_version] = :ascp
          # destination will be base64 encoded, put before path arguments
          @builder.add_command_line_options(['--dest64'])
        end
        # get list of files to transfer and build arg for ascp
        process_file_list
        # optional args, at the end to override previous ones (to allow override)
        @builder.add_command_line_options(@builder.read_param('EX_ascp_args'))
        @builder.add_command_line_options(@options[:ascp_args])
        # process destination folder
        destination_folder = @builder.read_param('destination_root') || '/'
        # ascp4 does not support base64 encoding of destination
        destination_folder = Base64.strict_encode64(destination_folder) unless env_args[:ascp_version].eql?(:ascp4)
        # destination MUST be last command line argument to ascp
        @builder.add_command_line_options([destination_folder])

        @builder.add_env_args(env_args[:env], env_args[:args])

        return env_args
      end
    end # Parameters
  end
end
