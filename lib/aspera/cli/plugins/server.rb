# frozen_string_literal: true

# cspell:ignore ascmd zmode zuid zgid fasping
require 'aspera/cli/basic_auth_plugin'
require 'aspera/cli/sync_actions'
require 'aspera/transfer/spec'
require 'aspera/ascmd'
require 'aspera/ssh'
require 'aspera/nagios'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'tempfile'
require 'open3'

module Aspera
  module Cli
    module Plugins
      # implement basic remote access with FASP/SSH
      class Server < Cli::BasicAuthPlugin
        include SyncActions
        SSH_SCHEME = 'ssh'
        LOCAL_SCHEME = 'local'
        HTTPS_SCHEME = 'https'
        URI_SCHEMES = [SSH_SCHEME, LOCAL_SCHEME, HTTPS_SCHEME].freeze
        ASCMD_ALIASES = {
          browse: :ls,
          delete: :rm,
          rename: :mv
        }.freeze
        TRANSFER_COMMANDS = %i[sync upload download].freeze

        private_constant :SSH_SCHEME, :URI_SCHEMES, :ASCMD_ALIASES, :TRANSFER_COMMANDS

        class LocalExecutor
          def execute(ascmd_path, line)
            return Environment.secure_capture(exec: ascmd_path, stdin_data: line, binmode: true)
          end
        end

        class << self
          def application_name
            'HSTS Fasp/SSH'
          end

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
              if version.match?(/^SSH-2.0-/)
                return {version: version.gsub(/^SSH-2.0-/, ''), url: base_url}
              end
            rescue StandardError => e
              error = e
              Log.log.debug{"detect error: #{e}"}
            end
            raise error if error
            return nil
          end

          def wizard(object:, private_key_path: nil, pub_key_pem: nil)
            options = object.options
            return {
              preset_value: {
                url:      options.get_option(:url, mandatory: true),
                username: options.get_option(:username, mandatory: true),
                password: options.get_option(:password, mandatory: true)
              },
              test_args:    'files br /'
            }
          end
        end

        def initialize(**env)
          super
          options.declare(:ssh_keys, 'SSH key path list (Array or single)')
          options.declare(:passphrase, 'SSH private key passphrase')
          options.declare(:ssh_options, 'SSH options', types: Hash, default: {})
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
            # simulate SSH environment, else ascp will fail
            ENV['SSH_CLIENT'] = 'local 0 0'
            return server_transfer_spec
          elsif transfer.option_transfer_spec['token'].is_a?(String) && server_uri.scheme.eql?(HTTPS_SCHEME)
            server_transfer_spec['wss_enabled'] = true
            server_transfer_spec['wss_port'] = server_uri.port
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
            ssh_key_list = [ssh_key_list] if ssh_key_list.is_a?(String)
            Aspera.assert_type(ssh_key_list, Array){'ssh_keys'}
            Aspera.assert(ssh_key_list.all?(String))
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
          cred_set = true if transfer.option_transfer_spec['token'].is_a?(String)
          raise 'Either password, key , or transfer spec token must be provided' if !cred_set
          return server_transfer_spec
        end

        def execute_transfer(command, transfer_spec)
          case command
          when :upload, :download
            transfer_spec['direction'] = Transfer::Spec.transfer_type_to_direction(command)
            return Main.result_transfer(transfer.start(transfer_spec))
          when :sync
            # lets ignore the arguments provided by execute_sync_action, we just give the transfer spec
            return execute_sync_action{transfer_spec}
          end
        end

        # actions without ascmd
        BASE_ACTIONS = %i[health].concat(TRANSFER_COMMANDS).freeze
        # all actions
        ACTIONS = [BASE_ACTIONS, AsCmd::OPERATIONS, ASCMD_ALIASES.keys].flatten.freeze

        def execute_action
          server_transfer_spec = options_to_base_transfer_spec
          ascmd_executor = if !@ssh_opts.empty?
            Ssh.new(server_transfer_spec['remote_host'], server_transfer_spec['remote_user'], @ssh_opts)
          elsif server_transfer_spec.key?('wss_enabled')
            nil
          else
            LocalExecutor.new
          end
          # the set of available commands depends on SSH executor availability (i.e. no WSS)
          available_commands = ascmd_executor.nil? ? BASE_ACTIONS : ACTIONS
          # get command and translate aliases
          command = options.get_next_command(available_commands)
          command = ASCMD_ALIASES[command] if ASCMD_ALIASES.key?(command)
          case command
          when :health
            nagios = Nagios.new
            command_nagios = options.get_next_command(%i[transfer])
            case command_nagios
            when :transfer
              file = Tempfile.new('transfer_test')
              filepath = file.path
              file.write('This is a test file for transfer test')
              file.close
              probe_ts = server_transfer_spec.merge({
                'direction'     => 'send',
                'cookie'        => 'aspera.sync', # hide in console
                'resume_policy' => 'none',
                'paths'         => [{'source' => filepath, 'destination' => '.fasping'}]
              })
              statuses = transfer.start(probe_ts)
              file.unlink
              if TransferAgent.session_status(statuses).eql?(:success)
                nagios.add_ok('transfer', 'ok')
              else
                nagios.add_critical('transfer', statuses.reject{ |i| i.eql?(:success)}.first.to_s)
              end
            else Aspera.error_unexpected_value(command_nagios)
            end
            return nagios.result
          when *TRANSFER_COMMANDS
            return execute_transfer(command, server_transfer_spec)
          when *AsCmd::OPERATIONS
            command_arguments = options.get_next_argument('ascmd command arguments', multiple: true, mandatory: false)
            ascmd = AsCmd.new(ascmd_executor)
            begin
              result = ascmd.execute_single(command, command_arguments)
              case command
              when :mkdir, :mv, :cp, :rm
                return Main.result_success
              when :ls
                return Main.result_object_list(result.map(&:stringify_keys), fields: %w[zmode zuid zgid size mtime name])
              when :df
                return Main.result_object_list(result.map(&:stringify_keys))
              when :du, :md5sum, :info
                return Main.result_single_object(result.stringify_keys)
              end
            rescue AsCmd::Error => e
              raise Cli::BadArgument, e.extended_message
            end
          else Aspera.error_unreachable_line
          end
        end
      end
    end
  end
end
