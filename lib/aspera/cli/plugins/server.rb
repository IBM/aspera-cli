# frozen_string_literal: true

# cspell:ignore ascmd zmode zuid zgid fasping
require 'aspera/cli/plugins/basic_auth'
require 'aspera/cli/sync_actions'
require 'aspera/transfer/spec'
require 'aspera/ascmd'
require 'aspera/ssh'
require 'aspera/nagios'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
module Aspera
  module Cli
    module Plugins
      # Operations on HSTS with SSH/FASP (ascmd/ascp)
      class Server < BasicAuth
        include SyncActions

        SSH_SCHEME = 'ssh'
        LOCAL_SCHEME = 'local'
        HTTPS_SCHEME = 'https'
        URI_SCHEMES = [SSH_SCHEME, LOCAL_SCHEME, HTTPS_SCHEME].freeze

        private_constant :SSH_SCHEME, :URI_SCHEMES

        class LocalExecutor
          def execute(ascmd_path, input:)
            Environment.secure_execute(ascmd_path, mode: :capture, stdin_data: input, binmode: true, exception: false).first
          end
        end

        class << self
          def application_name
            'HSTS Fasp/SSH'
          end

          # @return [Hash,NilClass]
          def detect(address_or_url)
            urls = if address_or_url.match?(%r{^[a-z]{1,6}://})
              [address_or_url]
            else
              [
                "#{SSH_SCHEME}://#{address_or_url}:33001",
                "#{SSH_SCHEME}://#{address_or_url}:22"
              ]
              # wss not practical as it requires a token
            end
            error = nil
            urls.each do |base_url|
              server_uri = URI.parse(base_url)
              Log.log.debug{"URI=#{server_uri}, host=#{server_uri.hostname}, port=#{server_uri.port}, scheme=#{server_uri.scheme}"}
              next unless server_uri.scheme.eql?(SSH_SCHEME)
              socket = TCPSocket.new(server_uri.hostname, server_uri.port)
              socket.puts('SSH-2.0-Ascli_0.0')
              version = socket.gets.chomp
              return {version: version.gsub(/^SSH-2.0-/, ''), url: base_url} if version.match?(/^SSH-2.0-/)
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return
          end
        end

        # @param wizard  [Wizard] The wizard object
        # @param app_url [String] Tested URL
        # @return [Hash] :preset_value, :test_args
        def wizard(wizard, app_url)
          return {
            preset_value: {
              url:      app_url,
              username: options.get_option(:username, mandatory: true),
              password: options.get_option(:password, mandatory: true)
            },
            test_args:    'files browse /'
          }
        end

        def initialize(**_)
          super
          @connection_type = :ssh
          @ascmd_executor = nil
          @server_transfer_spec = nil
          options.declare(:ssh_keys, 'SSH key path list', allowed: Allowed::TYPES_STRING_ARRAY)
          options.declare(:passphrase, 'SSH private key passphrase')
          options.declare(:ssh_options, 'SSH options', allowed: Hash, default: {})
          SyncActions.declare_options(options)
          options.parse_options!
          @ssh_opts = options.get_option(:ssh_options).symbolize_keys
        end

        # Read command line options
        # @return [Hash] transfer specification
        def options_to_base_transfer_spec
          url = options.get_option(:url, mandatory: true)
          server_transfer_spec = {}
          server_uri = URI.parse(url)
          Log.log.debug{"URI=#{server_uri}, host=#{server_uri.hostname}, port=#{server_uri.port}, scheme=#{server_uri.scheme}"}
          server_transfer_spec['remote_host'] = server_uri.hostname
          unless URI_SCHEMES.include?(server_uri.scheme)
            Log.log.warn{"Scheme [#{server_uri.scheme}] not supported in #{url}, use one of: #{URI_SCHEMES.join(', ')}. Defaulting to #{SSH_SCHEME}."}
            server_uri.scheme = SSH_SCHEME
          end
          if server_uri.scheme.eql?(LOCAL_SCHEME)
            # Using local execution (mostly for testing)
            server_transfer_spec['remote_host'] = 'localhost'
            # simulate SSH environment, else ascmd will fail
            ENV['SSH_CLIENT'] = 'local 0 0'
            @connection_type = :local
            return server_transfer_spec
          elsif transfer.user_transfer_spec['token'].is_a?(String) && server_uri.scheme.eql?(HTTPS_SCHEME)
            server_transfer_spec['wss_enabled'] = true
            server_transfer_spec['wss_port'] = server_uri.port
            @connection_type = :wss
            # Using WSS
            return server_transfer_spec
          end
          if !server_uri.scheme.eql?(SSH_SCHEME)
            Log.log.warn('URL scheme is https but no token was provided in transfer spec.')
            Log.log.warn("If you want to access the server, not using WSS for session, then use a URL with scheme \"#{SSH_SCHEME}\" and proper SSH port")
            assumed_url = "#{SSH_SCHEME}://#{server_transfer_spec['remote_host']}:#{Transfer::Spec::SSH_PORT}"
            Log.log.warn{"Assuming proper URL is: #{assumed_url}"}
            server_uri = URI.parse(assumed_url)
          end
          # Scheme is SSH
          if options.get_option(:username).nil?
            options.set_option(:username, Transfer::Spec::ACCESS_KEY_TRANSFER_USER)
            Log.log.info{"No username provided: Assuming default transfer user: #{Transfer::Spec::ACCESS_KEY_TRANSFER_USER}"}
          end
          server_transfer_spec['remote_user'] = options.get_option(:username, mandatory: true)
          if !server_uri.port.nil?
            @ssh_opts[:port] = server_uri.port
            server_transfer_spec['ssh_port'] = server_uri.port
          end
          cred_set = false
          password = options.get_option(:password)
          if !password.nil?
            @ssh_opts[:password] = password
            server_transfer_spec['remote_password'] = password
            cred_set = true
          end
          ssh_key_list = options.get_option(:ssh_keys)
          if !ssh_key_list.nil?
            Aspera.assert_array_all(ssh_key_list, String){'ssh_keys'}
            ssh_key_list.map!{ |p| File.expand_path(p)}
            Log.log.debug{"SSH keys=#{ssh_key_list}"}
            if !ssh_key_list.empty?
              @ssh_opts[:keys] = ssh_key_list
              # PEM as per RFC 7468
              server_transfer_spec['ssh_private_key'] = File.read(ssh_key_list.first).strip
              Log.log.warn{'Using only first SSH key for transfers'} unless ssh_key_list.length.eql?(1)
              cred_set = true
            end
          end
          ssh_passphrase = options.get_option(:passphrase)
          if !ssh_passphrase.nil?
            @ssh_opts[:passphrase] = ssh_passphrase
            server_transfer_spec['ssh_private_key_passphrase'] = ssh_passphrase
          end
          # if user provided transfer spec has a token, we will use bypass keys
          cred_set = true if transfer.user_transfer_spec['token'].is_a?(String)
          Aspera.assert(cred_set, 'Either password, key , or transfer spec token must be provided', type: BadArgument)
          return server_transfer_spec
        end

        def execute_transfer(command, transfer_spec)
          case command
          when :upload, :download
            transfer_spec['direction'] = Transfer::Spec.transfer_type_to_direction(command)
            return Runner.result_transfer(transfer.start(transfer_spec))
          when :sync
            # lets ignore the arguments provided by execute_sync_action, we just give the transfer spec
            return execute_sync_action{transfer_spec}
          end
        end

        # --- DSL ---

        # root_setup runs once before any command argument is consumed, populating
        # @server_transfer_spec and @ascmd_executor so that condition methods work.
        root_setup :setup_server

        command :health,   description: 'Check transfer health'
        command :upload,   description: 'Upload files to server',        transfer_paths: :send
        command :download, description: 'Download files from server',    transfer_paths: :receive
        command :sync,     description: 'Synchronize files with server', transfer_paths: :send

        commands_under(:health) do
          command :transfer, description: 'Check FASP transfer health'
        end

        # AsCmd operations (available only when SSH/local — not WSS)
        command :ls,     description: 'List files on server',            condition: :ascmd_available?, aliases: [:browse]
        command :rm,     description: 'Delete file(s) on server',        condition: :ascmd_available?, aliases: [:delete]
        command :mv,     description: 'Rename/move file(s) on server',   condition: :ascmd_available?, aliases: [:rename]
        command :cp,     description: 'Copy file(s) on server',          condition: :ascmd_available?
        command :mkdir,  description: 'Create directory on server',       condition: :ascmd_available?
        command :df,     description: 'Show disk usage on server',        condition: :ascmd_available?
        command :du,     description: 'Show file sizes on server',        condition: :ascmd_available?
        command :md5sum, description: 'Compute MD5 checksums on server',  condition: :ascmd_available?
        command :info,   description: 'Show server system information',   condition: :ascmd_available?

        # Generate ascmd handlers — convention: handle_<op>
        %i[rm mv cp mkdir].each do |op|
          define_method(:"handle_#{op}") do
            execute_ascmd(op){Result::Success.new}
          end
        end

        %i[du md5sum info].each do |op|
          define_method(:"handle_#{op}") do
            execute_ascmd(op){ |r| Result::SingleObject.new(r.stringify_keys)}
          end
        end

        # --- conditions ---

        def ascmd_available?
          !@ascmd_executor.nil?
        end

        # --- setup ---

        # Build the transfer spec and ascmd executor from CLI options.
        # Stores results in instance variables; returns empty context hash.
        def setup_server
          @server_transfer_spec = options_to_base_transfer_spec
          @ascmd_executor = case @connection_type
          when :local then LocalExecutor.new
          when :wss   then nil
          when :ssh   then Ssh.new(@server_transfer_spec['remote_host'], @server_transfer_spec['remote_user'], @ssh_opts)
          else Aspera.error_unexpected_value(@connection_type){'connection type'}
          end
          {}
        end

        # --- health ---

        def handle_health_transfer
          nagios = Nagios.new
          probe_ts = @server_transfer_spec.merge({
            'direction'     => 'send',
            'cookie'        => 'aspera.sync', # hide in console
            'resume_policy' => 'none',
            'paths'         => [{'source' => 'faux:///pingfile?1k', 'destination' => '.fasping'}]
          })
          statuses = transfer.start(probe_ts)
          if TransferAgent.session_status(statuses).eql?(:success)
            nagios.add_ok('transfer', 'ok')
          else
            nagios.add_critical('transfer', statuses.reject{ |i| i.eql?(:success)}.first.to_s)
          end
          Result::ObjectList.new(nagios.status_list)
        end

        # --- transfer handlers ---

        def handle_upload
          execute_transfer(:upload, @server_transfer_spec)
        end

        def handle_download
          execute_transfer(:download, @server_transfer_spec)
        end

        def handle_sync
          execute_transfer(:sync, @server_transfer_spec)
        end

        # --- ascmd handlers ---

        def handle_ls
          execute_ascmd(:ls) do |result|
            Result::ObjectList.new(result.map(&:stringify_keys), fields: %w[zmode zuid zgid size mtime name])
          end
        end

        def handle_df
          execute_ascmd(:df) do |result|
            Result::ObjectList.new(result.map(&:stringify_keys))
          end
        end

        private

        def execute_ascmd(op)
          command_arguments = options.get_next_argument('ascmd command arguments', multiple: true, mandatory: false)
          ascmd = AsCmd.new(@ascmd_executor)
          begin
            result = ascmd.execute_single(op, command_arguments)
            yield(result)
          rescue AsCmd::Error => e
            raise Cli::BadArgument, e.extended_message
          end
        end
      end
    end
  end
end
