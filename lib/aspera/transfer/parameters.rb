# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
require 'aspera/command_line_builder'
require 'aspera/temp_file_manager'
require 'aspera/transfer/error'
require 'aspera/transfer/spec'
require 'aspera/ascp/installation'
require 'aspera/cli/formatter'
require 'aspera/rest'
require 'securerandom'
require 'base64'
require 'json'
require 'fileutils'
require 'openssl'

module Aspera
  module Transfer
    # translate transfer specification to ascp parameter list
    class Parameters
      # Agents shown in manual for parameters (sub list)
      SUPPORTED_AGENTS = %i[direct node connect trsdk httpgw].freeze
      FILE_LIST_OPTIONS = ['--file-list', '--file-pair-list'].freeze
      # Short names of columns in manual
      SUPPORTED_AGENTS_SHORT = SUPPORTED_AGENTS.map{|agent_sym|agent_sym.to_s[0].to_sym}
      HTTP_FALLBACK_ACTIVATION_VALUES = ['1', 1, true, 'force'].freeze

      private_constant :SUPPORTED_AGENTS, :FILE_LIST_OPTIONS

      class << self
        # Temp folder for file lists, must contain only file lists
        # because of garbage collection takes any file there
        # this could be refined, as , for instance, on macos, temp folder is already user specific
        @file_list_folder = TempFileManager.instance.new_file_path_global('asession_filelists') # cspell:disable-line

        # @param formatter [Cli::Formatter] formatter to use
        # @return a table suitable to display in manual
        def man_table(formatter)
          result = []
          Spec::DESCRIPTION.each do |name, options|
            param = {name: name, type: [options[:accepted_types]].flatten.join(','), description: options[:desc]}
            # add flags for supported agents in doc
            SUPPORTED_AGENTS.each do |agent_sym|
              param[agent_sym.to_s[0].to_sym] = Cli::Formatter.tick(options[:agents].nil? || options[:agents].include?(agent_sym))
            end
            # only keep lines that are usable in supported agents
            next if SUPPORTED_AGENTS_SHORT.inject(true){|memory, agent_short_sym|memory && param[agent_short_sym].empty?}
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
              when :special then formatter.special_format('special')
              when :ignore then formatter.special_format('ignored')
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
          return result.sort_by { |parameter_info| parameter_info[:name] }
        end

        # special encoding methods used in YAML (key: :convert)
        def convert_remove_hyphen(value); value.tr('-', ''); end

        # special encoding methods used in YAML (key: :convert)
        def convert_json64(value); Base64.strict_encode64(JSON.generate(value)); end

        # special encoding methods used in YAML (key: :convert)
        def convert_base64(value); Base64.strict_encode64(value); end

        # file list is provided directly with ascp arguments
        # @param ascp_args [Array,NilClass] ascp arguments
        def ascp_args_file_list?(ascp_args)
          ascp_args&.any?{|i|FILE_LIST_OPTIONS.include?(i)}
        end

        # temp file list files are created here
        def file_list_folder=(value)
          @file_list_folder = value
          return if @file_list_folder.nil?
          FileUtils.mkdir_p(@file_list_folder)
          TempFileManager.instance.cleanup_expired(@file_list_folder)
        end

        # static methods
        attr_reader :file_list_folder
      end

      # @param options [Hash] key: :wss: bool, :ascp_args: array of strings
      def initialize(
        job_spec,
        ascp_args:       nil,
        wss:             true,
        quiet:           true,
        trusted_certs:   nil,
        client_ssh_key:  nil,
        check_ignore_cb: nil
      )
        @job_spec = job_spec
        @ascp_args = ascp_args.nil? ? [] : ascp_args
        @wss = wss
        @quiet = quiet
        @trusted_certs = trusted_certs.nil? ? [] : trusted_certs
        @client_ssh_key = client_ssh_key.nil? ? :rsa : client_ssh_key.to_sym
        @check_ignore_cb = check_ignore_cb
        Aspera.assert_type(@job_spec, Hash)
        Aspera.assert_type(@ascp_args, Array){'ascp_args'}
        Aspera.assert(@ascp_args.all?(String)){'all ascp arguments must be String'}
        Aspera.assert_type(@trusted_certs, Array){'trusted_certs'}
        Aspera.assert_values(@client_ssh_key, Ascp::Installation::CLIENT_SSH_KEY_OPTIONS)
        @builder = CommandLineBuilder.new(@job_spec, Spec::DESCRIPTION)
      end

      # either place source files on command line, or add file list file
      def process_file_list
        # is the file list provided through ascp parameters?
        ascp_file_list_provided = self.class.ascp_args_file_list?(@ascp_args)
        # set if paths is mandatory in ts
        @builder.params_definition['paths'][:mandatory] = !@job_spec.key?('keepalive') && !ascp_file_list_provided # cspell:words keepalive
        # get paths in transfer spec (after setting if it is mandatory)
        ts_paths_array = @builder.read_param('paths')
        file_list_option = nil
        # transfer spec contains paths ?
        if !ts_paths_array.nil?
          Aspera.assert(!ascp_file_list_provided){'file list provided both in transfer spec and ascp file list. Remove one of them.'}
          Aspera.assert(ts_paths_array.all?{|i|i.key?('source')}){"All elements of paths must have a 'source' key"}
          is_pair_list = ts_paths_array.any?{|i|i.key?('destination')}
          raise "All elements of paths must be consistent with 'destination' key" if is_pair_list && !ts_paths_array.all?{|i|i.key?('destination')}
          if self.class.file_list_folder.nil?
            Aspera.assert(!is_pair_list){'file pair list is not supported when file list folder is not set'}
            # not safe for special characters ? (maybe not, depends on OS)
            Log.log.debug('placing source file list on command line (no file list file)')
            @builder.add_command_line_options(ts_paths_array.map{|i|i['source']})
          else
            # safer option: generate a file list file if there is storage defined for it
            if is_pair_list
              file_list_option = '--file-pair-list'
              lines = ts_paths_array.each_with_object([]){|e, m|m.push(e['source'], e['destination']) }
            else
              file_list_option = '--file-list'
              lines = ts_paths_array.map{|i|i['source']}
            end
            file_list_file = TempFileManager.instance.new_file_path_in_folder(self.class.file_list_folder)
            Log.log.debug{Log.dump(:file_list, lines)}
            File.write(file_list_file, lines.join("\n"), encoding: 'UTF-8')
            Log.log.debug{"#{file_list_option}=\n#{File.read(file_list_file)}".red}
          end
        end
        @builder.add_command_line_options(["#{file_list_option}=#{file_list_file}"]) unless file_list_option.nil?
      end

      def remote_certificates
        certificates_to_use = []
        # use web socket secure for session ?
        if @builder.read_param('wss_enabled') && (@wss || !@job_spec.key?('fasp_port'))
          # by default use web socket session if available, unless removed by user
          @builder.add_command_line_options(['--ws-connect'])
          # TODO: option to give order ssh,ws (legacy http is implied by ssh)
          # This will need to be cleaned up in aspera core
          @job_spec['ssh_port'] = @builder.read_param('wss_port')
          @job_spec.delete('fasp_port')
          @job_spec.delete('sshfp')
          # set location for CA bundle to be the one of Ruby, see env var SSL_CERT_FILE / SSL_CERT_DIR
          certificates_to_use.concat(@trusted_certs) if @trusted_certs.is_a?(Array)
          # ignore cert for wss ?
          if @check_ignore_cb&.call(@job_spec['remote_host'], @job_spec['wss_port'])
            wss_cert_file = TempFileManager.instance.new_file_path_global('wss_cert')
            wss_url = "https://#{@job_spec['remote_host']}:#{@job_spec['wss_port']}"
            File.write(wss_cert_file, Rest.remote_certificate_chain(wss_url))
            # place in front, as more priority
            certificates_to_use.unshift(wss_cert_file)
          end
          # when wss is used, only first `-i` is used... Hum...
          certificates_to_use = [certificates_to_use.first] unless certificates_to_use.empty?
        else
          # remove unused parameter (avoid warning)
          @job_spec.delete('wss_port')
          # add SSH bypass keys when authentication is token and no auth is provided
          if @job_spec.key?('token') && !@job_spec.key?('remote_password')
            # @job_spec['remote_password'] = Ascp::Installation.instance.ssh_cert_uuid # not used: no passphrase
            certificates_to_use.concat(Ascp::Installation.instance.aspera_token_ssh_key_paths(@client_ssh_key))
          end
        end
        return certificates_to_use
      end

      # translate transfer spec to env vars and command line arguments for ascp
      def ascp_args
        env_args = {
          args: [],
          env:  {},
          name: :ascp
        }

        # special cases
        @job_spec.delete('source_root') if @job_spec.key?('source_root') && @job_spec['source_root'].empty?

        # notify multi-session was already used, anyway it was deleted by agent direct
        Aspera.assert(!@builder.read_param('multi_session'))

        # add ssh or wss certificates
        # (reverse, to keep order, as we unshift)
        remote_certificates&.reverse_each do |cert|
          env_args[:args].unshift('-i', cert)
        end

        # process parameters as specified in table
        @builder.process_params

        base64_destination = false
        # symbol must be index of Ascp::Installation.paths
        if @builder.read_param('use_ascp4')
          env_args[:name] = :ascp4
        else
          env_args[:name] = :ascp
          base64_destination = true
        end
        # destination will be base64 encoded, put this before source path arguments
        @builder.add_command_line_options(['--dest64']) if base64_destination
        # optional arguments, at the end to override previous ones (to allow override)
        @builder.add_command_line_options(@ascp_args)
        # get list of source files to transfer and build arg for ascp
        process_file_list
        # process destination folder
        destination_folder = @builder.read_param('destination_root') || '/'
        # ascp4 does not support base64 encoding of destination
        destination_folder = Base64.strict_encode64(destination_folder) if base64_destination
        # destination MUST be last command line argument to ascp
        @builder.add_command_line_options([destination_folder])
        @builder.add_env_args(env_args)
        env_args[:args].unshift('-q') if @quiet
        # add fallback cert and key as arguments if needed
        if HTTP_FALLBACK_ACTIVATION_VALUES.include?(@job_spec['http_fallback'])
          env_args[:args].unshift('-Y', Ascp::Installation.instance.path(:fallback_private_key))
          env_args[:args].unshift('-I', Ascp::Installation.instance.path(:fallback_certificate))
        end
        Log.log.debug{"ascp args: #{env_args}"}
        return env_args
      end
    end
  end
end
