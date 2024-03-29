# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/command_line_builder'
require 'aspera/temp_file_manager'
require 'aspera/fasp/error'
require 'aspera/fasp/installation'
require 'aspera/cli/formatter'
require 'aspera/rest'
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
      # options that can be provided to the constructor, and then in @options
      SUPPORTED_OPTIONS = %i[ascp_args wss check_ignore quiet trusted_certs].freeze

      private_constant :SUPPORTED_AGENTS, :FILE_LIST_OPTIONS, :SUPPORTED_OPTIONS

      class << self
        # Temp folder for file lists, must contain only file lists
        # because of garbage collection takes any file there
        # this could be refined, as , for instance, on macos, temp folder is already user specific
        @file_list_folder = TempFileManager.instance.new_file_path_global('asession_filelists') # cspell:disable-line
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
                conversion_tag = options[:cli].key?(:convert) ? '(conversion)' : ''
                "#{options[:cli][:switch]} #{conversion_tag}#{values}"
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
        assert_type(job_spec, Hash)
        assert_type(options, Hash)
        @job_spec = job_spec
        # check necessary options
        missing_options = SUPPORTED_OPTIONS - options.keys
        assert(missing_options.empty?){"missing options: #{missing_options.join(', ')}"}
        @options = SUPPORTED_OPTIONS.each_with_object({}){|o, h| h[o] = options[o]}
        Log.log.debug{Log.dump(:parameters_options, @options)}
        Log.log.debug{Log.dump(:dismiss_options, options.keys - SUPPORTED_OPTIONS)}
        assert_type(@options[:ascp_args], Array){'ascp_args'}
        assert(@options[:ascp_args].all?(String)){'ascp arguments must Strings'}
        @builder = Aspera::CommandLineBuilder.new(@job_spec, self.class.description)
      end

      # either place source files on command line, or add file list file
      def process_file_list
        # is the file list provided through EX_ parameters?
        ascp_file_list_provided = self.class.ts_has_ascp_file_list(@job_spec, @options[:ascp_args])
        # set if paths is mandatory in ts
        @builder.params_definition['paths'][:mandatory] = !@job_spec.key?('keepalive') && !ascp_file_list_provided # cspell:words keepalive
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
              assert(ts_paths_array.all?{|i|i.key?('source')}){"All elements of paths must have a 'source' key"}
              is_pair_list = ts_paths_array.any?{|i|i.key?('destination')}
              raise "All elements of paths must be consistent with 'destination' key" if is_pair_list && !ts_paths_array.all?{|i|i.key?('destination')}
              # safer option: generate a file list file if there is storage defined for it
              # if there is one destination in paths, then use file-pair-list
              if is_pair_list
                option = '--file-pair-list'
                lines = ts_paths_array.each_with_object([]){|e, m|m.push(e['source'], e['destination'] || e['source']) }
              else
                option = '--file-list'
                lines = ts_paths_array.map{|i|i['source']}
              end
              file_list_file = Aspera::TempFileManager.instance.new_file_path_in_folder(self.class.file_list_folder)
              Log.log.debug{Log.dump(:file_list, lines)}
              File.write(file_list_file, lines.join("\n"), encoding: 'UTF-8')
              Log.log.debug{"#{option}=\n#{File.read(file_list_file)}".red}
            end
          end
        else
          option = '--file-list'
        end
        @builder.add_command_line_options(["#{option}=#{file_list_file}"]) unless option.nil?
      end

      def remote_certificates
        certificates_to_use = []
        # use web socket secure for session ?
        if @builder.read_param('wss_enabled') && (@options[:wss] || !@job_spec.key?('fasp_port'))
          # by default use web socket session if available, unless removed by user
          @builder.add_command_line_options(['--ws-connect'])
          # TODO: option to give order ssh,ws (legacy http is implied by ssh)
          # This will need to be cleaned up in aspera core
          @job_spec['ssh_port'] = @builder.read_param('wss_port')
          @job_spec.delete('fasp_port')
          @job_spec.delete('EX_ssh_key_paths')
          @job_spec.delete('sshfp')
          # ignore cert for wss ?
          if @options[:check_ignore]&.call(@job_spec['remote_host'], @job_spec['wss_port'])
            wss_cert_file = TempFileManager.instance.new_file_path_global('wss_cert')
            wss_url = "https://#{@job_spec['remote_host']}:#{@job_spec['wss_port']}"
            File.write(wss_cert_file, Rest.remote_certificates(wss_url))
            certificates_to_use.push(wss_cert_file)
          end
          # set location for CA bundle to be the one of Ruby, see env var SSL_CERT_FILE / SSL_CERT_DIR
          certificates_to_use.concat(@options[:trusted_certs]) if @options[:trusted_certs]
        else
          # remove unused parameter (avoid warning)
          @job_spec.delete('wss_port')
          # add SSH bypass keys when authentication is token and no auth is provided
          if @job_spec.key?('token') && !@job_spec.key?('remote_password')
            # @job_spec['remote_password'] = Installation.instance.ssh_cert_uuid # not used: no passphrase
            certificates_to_use.concat(Installation.instance.aspera_token_ssh_key_paths)
          end
        end
        return certificates_to_use
      end

      # translate transfer spec to env vars and command line arguments for ascp
      # NOTE: parameters starting with "EX_" (extended) are not standard
      def ascp_args
        env_args = {
          args:         [],
          env:          {},
          ascp_version: :ascp
        }

        # special cases
        @job_spec.delete('source_root') if @job_spec.key?('source_root') && @job_spec['source_root'].empty?

        # notify multi-session was already used, anyway it was deleted by agent direct
        assert(!@builder.read_param('multi_session'))

        # add ssh or wss certificates
        remote_certificates.each do |cert|
          Log.log.trace1{"adding certificate: #{cert}"}
          env_args[:args].unshift('-i', cert)
        end

        # process parameters as specified in table
        @builder.process_params

        base64_destination = false
        # symbol must be index of Installation.paths
        if @builder.read_param('use_ascp4')
          env_args[:ascp_version] = :ascp4
        else
          env_args[:ascp_version] = :ascp
          base64_destination = true
        end
        # destination will be base64 encoded, put this before source path arguments
        @builder.add_command_line_options(['--dest64']) if base64_destination
        # optional arguments, at the end to override previous ones (to allow override)
        @builder.add_command_line_options(@builder.read_param('EX_ascp_args'))
        @builder.add_command_line_options(@options[:ascp_args])
        # get list of source files to transfer and build arg for ascp
        process_file_list
        # process destination folder
        destination_folder = @builder.read_param('destination_root') || '/'
        # ascp4 does not support base64 encoding of destination
        destination_folder = Base64.strict_encode64(destination_folder) if base64_destination
        # destination MUST be last command line argument to ascp
        @builder.add_command_line_options([destination_folder])
        @builder.add_env_args(env_args)
        env_args[:args].unshift('-q') if @options[:quiet]
        # add fallback cert and key as arguments if needed
        if ['1', 1, true, 'force'].include?(@job_spec['http_fallback'])
          env_args[:args].unshift('-Y', Installation.instance.path(:fallback_private_key))
          env_args[:args].unshift('-I', Installation.instance.path(:fallback_certificate))
        end
        Log.log.debug{"ascp args: #{env_args}"}
        return env_args
      end
    end # Parameters
  end
end
