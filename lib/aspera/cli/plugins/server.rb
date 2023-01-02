# frozen_string_literal: true

require 'aspera/cli/basic_auth_plugin'
require 'aspera/ascmd'
require 'aspera/fasp/transfer_spec'
require 'aspera/ssh'
require 'aspera/nagios'
require 'tempfile'

module Aspera
  module Cli
    module Plugins
      # implement basic remote access with FASP/SSH
      class Server < BasicAuthPlugin
        URI_SCHEMES=%w[ssh https local].freeze
        ASCMD_ALIASES={
          browse: :ls,
          delete: :rm,
          rename: :mv
        }.freeze
        ASCP_ACTIONS=%i[upload download health].freeze

        class LocalExecutor
          def execute(cmd,_input=nil)
            Log.log.debug("Executing: #{cmd}")
            %x(#{cmd.join(' ')})
          end
        end

        def initialize(env)
          super(env)
          options.add_opt_simple(:ssh_keys,'SSH key path list (Array or single)')
          options.add_opt_simple(:ssh_options,'SSH options (Hash)')
          options.set_option(:ssh_keys,[])
          options.set_option(:ssh_options,{})
          options.parse_options!
        end

        def key_symb_to_str_list(source)
          return source.map(&:stringify_keys)
        end

        # @return an object able to execute `ascmd` or nil (WSS)
        # also set transfer spec
        def executor(url,server_transfer_spec)
          server_uri = URI.parse(url)
          Log.log.debug("URI : #{server_uri}, port=#{server_uri.port}, scheme:#{server_uri.scheme}")
          server_transfer_spec['remote_host']=server_uri.hostname
          unless URI_SCHEMES.include?(server_uri.scheme)
            raise "Scheme [#{server_uri.scheme}] not supported, use one of: #{URI_SCHEMES.join(', ')}"
          end
          if server_uri.scheme.eql?('local')
            # Using local execution (mostly for testing)
            return LocalExecutor.new
          end
          if server_uri.scheme.eql?('https')
            if transfer.option_transfer_spec['token'].is_a?(String)
              server_transfer_spec['wss_enabled'] = true
              server_transfer_spec['wss_port'] = server_uri.port
              # Using WSS
              return nil
            end
            Log.log.warn('URL scheme is https but no (Basic) token was provided in transfer spec.')
            Log.log.warn('If you want to access the server, not using WSS for session, then use a URL with scheme "ssh" and proper SSH port')
            assumed_url="ssh://#{server_transfer_spec['remote_host']}:33001"
            Log.log.warn("Assuming proper URL is: #{assumed_url}")
            server_uri = URI.parse(assumed_url)
          end
          # Scheme is SSH
          if options.get_option(:username).nil?
            options.set_option(:username,Aspera::Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER)
            Log.log.info("No username provided: Assuming default transfer user: #{Aspera::Fasp::TransferSpec::ACCESS_KEY_TRANSFER_USER}")
          end
          server_transfer_spec['remote_user'] = options.get_option(:username,is_type: :mandatory)
          ssh_options = options.get_option(:ssh_options)
          raise 'expecting a Hash for ssh_options' unless ssh_options.is_a?(Hash)
          ssh_options = ssh_options.symbolize_keys
          if !server_uri.port.nil?
            ssh_options[:port] = server_uri.port
            server_transfer_spec['ssh_port'] = server_uri.port
          end
          cred_set = false
          password = options.get_option(:password)
          if !password.nil?
            ssh_options[:password] = password
            server_transfer_spec['remote_password'] = password
            cred_set = true
          end
          ssh_keys = options.get_option(:ssh_keys)
          if !ssh_keys.nil?
            raise 'Expecting single value or array for ssh_keys' unless ssh_keys.is_a?(Array) || ssh_keys.is_a?(String)
            ssh_keys = [ssh_keys] if ssh_keys.is_a?(String)
            ssh_keys.map!{|p|File.expand_path(p)}
            Log.log.debug("ssh keys=#{ssh_keys}")
            if !ssh_keys.empty?
              ssh_options[:keys] = ssh_keys
              server_transfer_spec['EX_ssh_key_paths'] = ssh_keys
              ssh_keys.each do |k|
                Log.log.warn("No such key file: #{k}") unless File.exist?(k)
              end
              cred_set = true
            end
          end
          # if user provided transfer spec has a token, we will use bypass keys
          cred_set = true if transfer.option_transfer_spec['token'].is_a?(String)
          raise 'Either password, key , or transfer spec token must be provided' if !cred_set
          return Ssh.new(server_transfer_spec['remote_host'],server_transfer_spec['remote_user'],ssh_options)
        end

        ACTIONS = [ASCP_ACTIONS,Aspera::AsCmd::OPERATIONS,ASCMD_ALIASES.keys].flatten

        def execute_action
          server_transfer_spec={}
          shell_executor = executor(options.get_option(:url,is_type: :mandatory),server_transfer_spec)
          # the set of available commands depends on SSH executor availability (i.e. no WSS)
          available_commands = shell_executor.nil? ? ASCP_ACTIONS : ACTIONS
          # get command and translate aliases
          command = options.get_next_command(available_commands)
          command = ASCMD_ALIASES[command] if ASCMD_ALIASES.has_key?(command)
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
                'paths'         => [{'source' => filepath,'destination' => '.fasping'}]
              })
              statuses = transfer.start(probe_ts,:direct)
              file.unlink
              if TransferAgent.session_status(statuses).eql?(:success)
                nagios.add_ok('transfer','ok')
              else
                nagios.add_critical('transfer',statuses.reject{|i|i.eql?(:success)}.first.to_s)
              end
            else raise 'ERROR'
            end
            return nagios.result
          when :upload
            return Main.result_transfer(transfer.start(server_transfer_spec.merge('direction' => Fasp::TransferSpec::DIRECTION_SEND),:direct))
          when :download
            return Main.result_transfer(transfer.start(server_transfer_spec.merge('direction' => Fasp::TransferSpec::DIRECTION_RECEIVE),:direct))
          when *Aspera::AsCmd::OPERATIONS
            args = options.get_next_argument('ascmd command arguments',expected: :multiple,mandatory: false)
            ascmd = Aspera::AsCmd.new(shell_executor)
            begin
              result = ascmd.send(:execute_single,command,args)
              case command
              when :mkdir,:mv,:cp,:rm then return Main.result_success
              when :ls                then return {type: :object_list,data: key_symb_to_str_list(result),fields: %w[zmode zuid zgid size mtime name]}
              when :df                then return {type: :object_list,data: key_symb_to_str_list(result)}
              when :du,:md5sum,:info  then return {type: :single_object,data: result.stringify_keys}
              end
            rescue Aspera::AsCmd::Error => e
              raise CliBadArgument,e.extended_message
            end
          else raise 'internal error: unexpected action'
          end
        end # execute_action
      end # Server
    end # Plugins
  end # Cli
end # Aspera
