# frozen_string_literal: true

# cspell:words logdir bidi watchd cooloff asyncadmin

require 'aspera/ascp/installation'
require 'aspera/agent/direct'
require 'aspera/command_line_converter'
require 'aspera/command_line_builder'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'json'
require 'base64'
require 'open3'
require 'English'

module Aspera
  module Sync
    # builds command line arg for async and execute it
    module Operations
      # Sync direction
      DIRECTIONS = %i[push pull bidi].freeze
      # Default direction for sync
      DEFAULT_DIRECTION = DIRECTIONS.first

      class << self
        # Set `remote_dir` in sync parameters based on transfer spec
        # @param params         [Hash]   Sync parameters, in `conf` or `args` format.
        # @param remote_dir_key [String] Key to update in above hash
        # @param transfer_spec  [Hash]   Transfer spec
        def update_remote_dir(params, remote_dir_key, transfer_spec)
          if transfer_spec.dig(*%w[tags aspera node file_id])
            # in AoC, use gen4
            params[remote_dir_key] = '/'
          elsif transfer_spec['cookie']&.start_with?('aspera.shares2')
            # TODO : something more generic, independent of Shares
            # in Shares, the actual folder on remote end is not always the same as the name of the share
            remote_key = transfer_spec['direction'].eql?('send') ? 'destination' : 'source'
            actual_remote = transfer_spec['paths']&.first&.[](remote_key)
            params[remote_dir_key] = actual_remote if actual_remote
          end
          nil
        end

        # Get certificates to use for remote connection
        # @param remote [Hash] remote connection parameters
        # @return [Array<String>] list of certificate file paths
        def remote_certificates(remote)
          certificates_to_use = []
          # use web socket secure for session ?
          if remote['connect_mode']&.eql?('ws')
            remote.delete('port')
            remote.delete('fingerprint')
            # ignore cert for wss ?
            # if @options[:check_ignore_cb]&.call(remote['host'], remote['ws_port'])
            #   wss_cert_file = TempFileManager.instance.new_file_path_global('wss_cert')
            #   wss_url = "https://#{remote['host']}:#{remote['ws_port']}"
            #   File.write(wss_cert_file, Rest.remote_certificate_chain(wss_url))
            #   certificates_to_use.push(wss_cert_file)
            # end
            # set location for CA bundle to be the one of Ruby, see env var SSL_CERT_FILE / SSL_CERT_DIR
            # certificates_to_use.concat(@options[:trusted_certs]) if @options[:trusted_certs]
          else
            # remove unused parameter (avoid warning)
            remote.delete('ws_port')
            # add SSH bypass keys when authentication is token and no auth is provided
            certificates_to_use.concat(Ascp::Installation.instance.aspera_token_ssh_key_paths(:rsa)) if remote.key?('token') && !remote.key?('pass')
          end
          return certificates_to_use
        end

        # Get symbol of sync direction, defaulting to :push
        # @param params [Hash] Sync parameters, old or new format
        # @return [Symbol] direction symbol, one of :push, :pull, :bidi
        def direction_sym(params)
          (params['direction'] || DEFAULT_DIRECTION).to_sym
        end

        # Start the sync process
        # @param params [Hash] Sync parameters, old or new format
        # @param opt_ts [Hash] Optional transfer spec
        # @param &block [nil, Proc] block to generate transfer spec, takes: direction (one of DIRECTIONS), local_dir, remote_dir
        def start(params, opt_ts = nil)
          Log.dump(:sync_params_initial, params)
          Aspera.assert_type(params, Hash)
          Aspera.assert(PARAM_KEYS.any?{ |k| params.key?(k)}, type: Error){'At least one of `local` or `sessions` must be present in async parameters'}
          env_args = {
            args: [],
            env:  {}
          }
          if params.key?('local')
            # "conf" format
            Aspera.assert_type(params['local'], Hash){'local'}
            remote = params['remote']
            Aspera.assert_type(remote, Hash){'remote'}
            Aspera.assert_type(remote['path'], String){'remote path'}
            # get transfer spec if possible, and feed back to new structure
            if block_given?
              transfer_spec = yield(direction_sym(params), params['local']['path'], remote['path'])
              Log.dump(:auth_ts, transfer_spec)
              transfer_spec.deep_merge!(opt_ts) unless opt_ts.nil?
              tspec_to_sync_info(transfer_spec, params, CONF_SCHEMA)
              update_remote_dir(remote, 'path', transfer_spec)
            end
            remote['connect_mode'] ||= transfer_spec['wss_enabled'] ? 'ws' : 'ssh'
            add_certificates = remote_certificates(remote)
            if !add_certificates.empty?
              remote['private_key_paths'] ||= []
              remote['private_key_paths'].concat(add_certificates)
            end
            # '--exclusive-mgmt-port=12345', '--arg-err-path=-',
            env_args[:args] = ["--conf64=#{Base64.strict_encode64(JSON.generate(params))}"]
            Log.dump(:sync_conf, params)
            agent = Agent::Direct.new
            agent.start_and_monitor_process(session: {}, name: :async, **env_args)
          else
            # "args" format
            raise StandardError, "Only 'sessions', and optionally 'instance' keys are allowed" unless
              params.keys.push('instance').uniq.sort.eql?(CMDLINE_PARAMS_KEYS)
            Aspera.assert_type(params['sessions'], Array)
            Aspera.assert_type(params['sessions'].first, Hash)
            if block_given?
              params['sessions'].each do |session|
                Aspera.assert_type(session['local_dir'], String){'local_dir'}
                Aspera.assert_type(session['remote_dir'], String){'remote_dir'}
                transfer_spec = yield(direction_sym(session), session['local_dir'], session['remote_dir'])
                Log.dump(:auth_ts, transfer_spec)
                transfer_spec.deep_merge!(opt_ts) unless opt_ts.nil?
                tspec_to_sync_info(transfer_spec, session, ARGS_SESSION_SCHEMA)
                session['private_key_paths'] = Ascp::Installation.instance.aspera_token_ssh_key_paths(:rsa) if transfer_spec.key?('token')
                update_remote_dir(session, 'remote_dir', transfer_spec)
              end
            end
            if params.key?('instance')
              Aspera.assert_type(params['instance'], Hash)
              instance_builder = CommandLineBuilder.new(params['instance'], ARGS_INSTANCE_SCHEMA, CommandLineConverter)
              instance_builder.process_params
              instance_builder.add_env_args(env_args)
            end
            params['sessions'].each do |session_params|
              Aspera.assert_type(session_params, Hash)
              Aspera.assert(session_params.key?('name')){'session must contain at least: name'}
              session_builder = CommandLineBuilder.new(session_params, ARGS_SESSION_SCHEMA, CommandLineConverter)
              session_builder.process_params
              session_builder.add_env_args(env_args)
            end
            Environment.secure_execute(exec: Ascp::Installation.instance.path(:async), **env_args)
          end
          return
        end

        # Parse output of asyncadmin
        def parse_status(stdout)
          Log.log.trace1{"stdout=#{stdout}"}
          result = {}
          ids = nil
          stdout.split("\n").each do |line|
            info = line.split(':', 2).map(&:lstrip)
            if info[1].eql?('')
              info[1] = ids = []
            elsif info[1].nil?
              ids.push(info[0])
              next
            end
            result[info[0]] = info[1]
          end
          return result
        end

        # Run `asyncadmin` to get status of sync session
        # @param params [Hash] sync parameters in conf or args format
        # @return [Hash] parsed output of asyncadmin
        def admin_status(params)
          Aspera.assert(PARAM_KEYS.any?{ |k| params.key?(k)}, type: Error){'At least one of `local` or `sessions` must be present in async parameters'}
          arguments = ['--quiet']
          if params.key?('local')
            # "conf" format
            arguments.push("--name=#{params['name']}")
            if params.key?('local_db_dir')
              arguments.push("--local-db-dir=#{params['local_db_dir']}")
            elsif params.dig('local', 'path')
              arguments.push("--local-dir=#{params.dig('local', 'path')}")
            else
              raise Error, 'Missing either local_db_dir or local.path'
            end
          else
            # "args" format
            session = params['sessions'].first
            arguments.push("--name=#{session['name']}")
            if session.key?('local_db_dir')
              arguments.push("--local-db-dir=#{session['local_db_dir']}")
            elsif session.key?('local_dir')
              arguments.push("--local-dir=#{session['local_dir']}")
            else
              raise Error, 'Missing either local_db_dir or local_dir'
            end
          end
          stdout = Environment.secure_capture(exec: ASYNC_ADMIN_EXECUTABLE, args: arguments)
          return parse_status(stdout)
        end

        # Find the local database folder based on params
        # @param params [Hash] sync parameters in conf or args format
        # @return [String, nil] path to "local DB dir", i.e. folder that contains folders that contain snap.db
        def local_db_folder(params)
          Aspera.assert(PARAM_KEYS.any?{ |k| params.key?(k)}, type: Error){'At least one of `local` or `sessions` must be present in async parameters'}
          if params.key?('local')
            # "conf" format
            if params.key?('local_db_dir')
              return params['local_db_dir']
            elsif (local_path = params.dig('local', 'path'))
              return local_path
            elsif exception
              raise Error, 'Missing either local_db_dir or local.path'
            end
          else
            # "args" format
            session = params['sessions'].first
            if session.key?('local_db_dir')
              return session['local_db_dir']
            elsif session.key?('local_dir')
              return session['local_dir']
            elsif exception
              raise Error, 'Missing either local_db_dir or local_dir'
            end
          end
          nil
        end

        def session_name(params)
          Aspera.assert(PARAM_KEYS.any?{ |k| params.key?(k)}, type: Error){'At least one of `local` or `sessions` must be present in async parameters'}
          if params.key?('local')
            # "conf" format
            return params['name']
          else
            # "args" format
            return params['sessions'].first['name']
          end
        end

        def session_db_file(params)
          db_file = File.join(local_db_folder(params), PRIVATE_FOLDER, session_name(params), ASYNC_DB)
          Aspera.assert(File.exist?(db_file)){"Database file #{db_file} does not exist"}
          db_file
        end

        def list_db_files(local_db_dir)
          private = File.join(local_db_dir, PRIVATE_FOLDER)
          Dir.children(private).filter_map do |name|
            db_file = File.join(private, name, ASYNC_DB)
            [name, db_file] if File.exist?(db_file)
          end.to_h
        end

        # private

        # Transfer specification to synchronization information
        # tag `x-ts-name` in schema is used to map transfer spec parameters to async `sync_info`
        # @param transfer_spec [Hash] transfer specification
        # @param sync_info     [Hash] synchronization information
        # @param schema        [Hash] schema definition
        def tspec_to_sync_info(transfer_spec, sync_info, schema)
          Log.dump(:tspec_to_sync_info, transfer_spec)
          schema['properties'].each do |name, property|
            if property.key?('x-ts-name')
              tspec_param = property['x-ts-name']
              if transfer_spec.key?(tspec_param) && !sync_info.key?(name)
                sync_info[name] = property['x-ts-convert'] ? CommandLineConverter.send(property['x-ts-convert'], transfer_spec[tspec_param]) : transfer_spec[tspec_param]
              end
            end
            if property['type'].eql?('object') && property.key?('properties')
              sync_info[name] ||= {}
              tspec_to_sync_info(transfer_spec, sync_info[name], property)
            end
          end
        end
      end
      # Private stuff:
      # Read JSON schema and mapping to command line options
      ARGS_INSTANCE_SCHEMA = CommandLineBuilder.read_schema(__FILE__, 'args')
      ARGS_SESSION_SCHEMA = ARGS_INSTANCE_SCHEMA['properties']['sessions']['items']
      ARGS_INSTANCE_SCHEMA['properties'].delete('sessions')
      CONF_SCHEMA = CommandLineBuilder.read_schema(__FILE__, 'conf')
      CommandLineBuilder.validate_schema(ARGS_INSTANCE_SCHEMA)
      CommandLineBuilder.validate_schema(ARGS_SESSION_SCHEMA)
      CommandLineBuilder.validate_schema(CONF_SCHEMA)
      CMDLINE_PARAMS_KEYS = %w[instance sessions].freeze
      ASYNC_ADMIN_EXECUTABLE = 'asyncadmin'
      PRIVATE_FOLDER = '.private-asp'
      ASYNC_DB = 'snap.db'
      PARAM_KEYS = %w[local sessions].freeze

      private_constant :ARGS_INSTANCE_SCHEMA, :ARGS_SESSION_SCHEMA, :CMDLINE_PARAMS_KEYS, :ASYNC_ADMIN_EXECUTABLE, :PRIVATE_FOLDER, :ASYNC_DB, :PARAM_KEYS
    end
  end
end
