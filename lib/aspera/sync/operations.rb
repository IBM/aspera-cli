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
      # sync direction
      DIRECTIONS = %i[push pull bidi].freeze
      # default direction for sync
      DEFAULT_DIRECTION = :push
      # Read JSON schema and mapping to command line options
      INSTANCE_SCHEMA = CommandLineBuilder.read_schema(__FILE__, 'args')
      SESSION_SCHEMA = INSTANCE_SCHEMA['properties']['sessions']['items']
      INSTANCE_SCHEMA['properties'].delete('sessions')
      CONF_SCHEMA = CommandLineBuilder.read_schema(__FILE__, 'conf')
      CommandLineBuilder.adjust_properties_defaults(INSTANCE_SCHEMA['properties'])
      CommandLineBuilder.adjust_properties_defaults(SESSION_SCHEMA['properties'])
      CommandLineBuilder.adjust_properties_defaults(CONF_SCHEMA['properties'])

      CMDLINE_PARAMS_KEYS = %w[instance sessions].freeze

      # Optional simple command line arguments for sync
      # in Array to keep order as on command line
      # name: just generic name
      # conf: key in option --conf
      # args: key for command line args
      # values: possible values for argument
      # type: type for validation
      SYNC_PARAMETERS = [
        {
          name:   'direction',
          conf:   'direction',
          args:   'direction',
          values: DIRECTIONS
        }, {
          name: 'local folder',
          conf: 'local.path',
          args: 'local_dir',
          type: String
        }, {
          name: 'remote folder',
          conf: 'remote.path',
          args: 'remote_dir',
          type: String
        }
      ].freeze
      ADMIN_PARAMETERS = [
        {
          name: 'local folder',
          conf: 'local.path',
          args: 'local_dir',
          type: String
        }, {
          name:     'name',
          conf:     'name',
          args:     'name',
          type:     String,
          optional: true
        }
      ].freeze

      ASYNC_ADMIN_EXECUTABLE = 'asyncadmin'

      PRIVATE_FOLDER = '.private-asp'
      ASYNC_DB = 'snap.db'

      private_constant :INSTANCE_SCHEMA, :SESSION_SCHEMA, :CMDLINE_PARAMS_KEYS, :ASYNC_ADMIN_EXECUTABLE

      class << self
        # Set `remote_dir` in sync parameters based on transfer spec
        # @param params [Hash] sync parameters, old or new format
        # @param remote_dir_key [String] key to update in above hash
        # @param transfer_spec [Hash] transfer spec
        def update_remote_dir(sync_params, remote_dir_key, transfer_spec)
          if transfer_spec.dig(*%w[tags aspera node file_id])
            # in AoC, use gen4
            sync_params[remote_dir_key] = '/'
          elsif transfer_spec['cookie']&.start_with?('aspera.shares2')
            # TODO : something more generic, independent of Shares
            # in Shares, the actual folder on remote end is not always the same as the name of the share
            remote_key = transfer_spec['direction'].eql?('send') ? 'destination' : 'source'
            actual_remote = transfer_spec['paths']&.first&.[](remote_key)
            sync_params[remote_dir_key] = actual_remote if actual_remote
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
            if remote.key?('token') && !remote.key?('pass')
              certificates_to_use.concat(Ascp::Installation.instance.aspera_token_ssh_key_paths(:rsa))
            end
          end
          return certificates_to_use
        end

        # Get symbol of sync direction, defaulting to :push
        # @param params [Hash] sync parameters, old or new format
        # @return [Symbol] direction symbol, one of :push, :pull, :bidi
        def direction_sym(params)
          (params['direction'] || DEFAULT_DIRECTION).to_sym
        end

        # Start the sync process
        # @param sync_params [Hash] sync parameters, old or new format
        # @param &block [nil, Proc] block to generate transfer spec, takes: direction (one of DIRECTIONS), local_dir, remote_dir
        def start(sync_params)
          Log.log.debug{Log.dump(:sync_params_initial, sync_params)}
          Aspera.assert_type(sync_params, Hash)
          env_args = {
            args: [],
            env:  {}
          }
          if sync_params.key?('local')
            # "conf" format
            Aspera.assert_type(sync_params['local'], Hash){'local'}
            remote = sync_params['remote']
            Aspera.assert_type(remote, Hash){'remote'}
            Aspera.assert_type(remote['path'], String){'remote path'}
            # get transfer spec if possible, and feed back to new structure
            if block_given?
              transfer_spec = yield(direction_sym(sync_params), sync_params['local']['path'], remote['path'])
              tspec_to_sync_info(transfer_spec, sync_params, CONF_SCHEMA)
              update_remote_dir(remote, 'path', transfer_spec)
            end
            remote['connect_mode'] ||= transfer_spec['wss_enabled'] ? 'ws' : 'ssh'
            add_certificates = remote_certificates(remote)
            if !add_certificates.empty?
              remote['private_key_paths'] ||= []
              remote['private_key_paths'].concat(add_certificates)
            end
            # '--exclusive-mgmt-port=12345', '--arg-err-path=-',
            env_args[:args] = ["--conf64=#{Base64.strict_encode64(JSON.generate(sync_params))}"]
            Log.log.debug{Log.dump(:sync_conf, sync_params)}
            agent = Agent::Direct.new
            agent.start_and_monitor_process(session: {}, name: :async, **env_args)
          elsif sync_params.key?('sessions')
            # "args" format
            raise StandardError, "Only 'sessions', and optionally 'instance' keys are allowed" unless
              sync_params.keys.push('instance').uniq.sort.eql?(CMDLINE_PARAMS_KEYS)
            Aspera.assert_type(sync_params['sessions'], Array)
            Aspera.assert_type(sync_params['sessions'].first, Hash)
            if block_given?
              sync_params['sessions'].each do |session|
                Aspera.assert_type(session['local_dir'], String){'local_dir'}
                Aspera.assert_type(session['remote_dir'], String){'remote_dir'}
                transfer_spec = yield(direction_sym(session), session['local_dir'], session['remote_dir'])
                tspec_to_sync_info(transfer_spec, session, SESSION_SCHEMA)
                session['private_key_paths'] = Ascp::Installation.instance.aspera_token_ssh_key_paths(:rsa) if transfer_spec.key?('token')
                update_remote_dir(session, 'remote_dir', transfer_spec)
              end
            end
            if sync_params.key?('instance')
              Aspera.assert_type(sync_params['instance'], Hash)
              instance_builder = CommandLineBuilder.new(sync_params['instance'], INSTANCE_SCHEMA, CommandLineConverter)
              instance_builder.process_params
              instance_builder.add_env_args(env_args)
            end
            sync_params['sessions'].each do |session_params|
              Aspera.assert_type(session_params, Hash)
              Aspera.assert(session_params.key?('name')){'session must contain at least: name'}
              session_builder = CommandLineBuilder.new(session_params, SESSION_SCHEMA, CommandLineConverter)
              session_builder.process_params
              session_builder.add_env_args(env_args)
            end
            Environment.secure_execute(exec: Ascp::Installation.instance.path(:async), **env_args)
          else
            raise 'At least one of `local` or `sessions` must be present in async parameters'
          end
          return nil
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

        # Takes potentially empty params or arguments and ensures viable configuration
        def validated_sync_info(async_params, arguments)
          info_type = if async_params.key?('sessions') || async_params.key?('instance')
            async_params['sessions'] ||= [{}]
            Aspera.assert(async_params['sessions'].length == 1){'Only one session is supported'}
            session = async_params['sessions'].first
            :args
          else
            session = async_params
            :conf
          end
          if !arguments.empty?
            # there must be exactly 3 or 4 args
            # copy arguments to async_params
            arguments.each_with_index do |arg, index|
              key_path = SYNC_PARAMETERS[index][info_type].split('.')
              hash_for_key = session
              if key_path.length > 1
                first = key_path.shift
                hash_for_key[first] ||= {}
                hash_for_key = hash_for_key[first]
              end
              raise "Parameter #{SYNC_PARAMETERS[index][info_type]} is also set in sync_info, remove from sync_info" if hash_for_key.key?(key_path.last)
              hash_for_key[key_path.last] = arg
            end
          end

          # Check if name is already provided
          # else generate one from local/remote paths
          if !session.key?('name')
            session['name'] = Environment.instance.sanitized_filename(
              SYNC_PARAMETERS.filter_map do |arg_info|
                value = session.dig(*arg_info[info_type].split('.'))
                Aspera.assert(!value.nil?){"Missing value for #{arg_info[info_type]} to generate name"}
                value.split(File::SEPARATOR).last(2).join(Environment.instance.safe_filename_character)
              end.compact.join(Environment.instance.safe_filename_character))
          end
          return async_params
        end

        # Takes potentially empty params or arguments and ensures viable configuration for admin
        def validated_admin_info(async_params, arguments)
          info_type = if async_params.key?('sessions') || async_params.key?('instance')
            async_params['sessions'] ||= [{}]
            Aspera.assert(async_params['sessions'].length == 1){'Only one session is supported'}
            session = async_params['sessions'].first
            :args
          else
            session = async_params
            :conf
          end
          if !arguments.empty?
            # there must be exactly 1 or 2 args
            # copy arguments to async_params
            arguments.each_with_index do |arg, index|
              key_path = ADMIN_PARAMETERS[index][info_type].split('.')
              hash_for_key = session
              if key_path.length > 1
                first = key_path.shift
                hash_for_key[first] ||= {}
                hash_for_key = hash_for_key[first]
              end
              raise "Parameter #{SYNC_PARAMETERS[index][info_type]} is also set in sync_info, remove from sync_info" if hash_for_key.key?(key_path.last)
              hash_for_key[key_path.last] = arg
            end
          end
          # if name not provided, check in db folder if there is only one name
          if !session.key?('name')
            local_db_dir = local_db_folder(async_params)
            dbs = list_db_files(local_db_dir)
            raise "#{dbs.length} session found in #{local_db_dir}, please provide a name" unless dbs.length == 1
            session['name'] = dbs.keys.first
          end
          return async_params
        end

        # Run `asyncadmin` to get status of sync session
        # @param sync_params [Hash] sync parameters in conf or args format
        # @return [Hash] parsed output of asyncadmin
        def admin_status(sync_params)
          arguments = ['--quiet']
          if sync_params.key?('local')
            # "conf" format
            arguments.push("--name=#{sync_params['name']}")
            if sync_params.key?('local_db_dir')
              arguments.push("--local-db-dir=#{sync_params['local_db_dir']}")
            elsif sync_params.dig('local', 'path')
              arguments.push("--local-dir=#{sync_params.dig('local', 'path')}")
            else
              raise 'Missing either local_db_dir or local.path'
            end
          elsif sync_params.key?('sessions')
            # "args" format
            session = sync_params['sessions'].first
            arguments.push("--name=#{session['name']}")
            if session.key?('local_db_dir')
              arguments.push("--local-db-dir=#{session['local_db_dir']}")
            elsif session.key?('local_dir')
              arguments.push("--local-dir=#{session['local_dir']}")
            else
              raise 'Missing either local_db_dir or local_dir'
            end
          else
            raise 'At least one of `local` or `sessions` must be present in async parameters'
          end
          stdout = Environment.secure_capture(exec: ASYNC_ADMIN_EXECUTABLE, args: arguments)
          return parse_status(stdout)
        end

        # Find the local database folder based on sync_params
        # @param sync_params [Hash] sync parameters in conf or args format
        # @param exception [Bool] Raise exception in case of problem, else return nil
        # @return [String, nil] path to "local DB dir", i.e. folder that contains folders that contain snap.db
        def local_db_folder(sync_params, exception: true)
          if sync_params.key?('local')
            # "conf" format
            if sync_params.key?('local_db_dir')
              return sync_params['local_db_dir']
            elsif (local_path = sync_params.dig('local', 'path'))
              return local_path
            elsif exception
              raise 'Missing either local_db_dir or local.path'
            end
          elsif sync_params.key?('sessions')
            # "args" format
            session = sync_params['sessions'].first
            if session.key?('local_db_dir')
              return session['local_db_dir']
            elsif session.key?('local_dir')
              return session['local_dir']
            elsif exception
              raise 'Missing either local_db_dir or local_dir'
            end
          elsif exception
            raise 'At least one of `local` or `sessions` must be present in async parameters'
          end
          nil
        end

        def session_name(sync_params)
          if sync_params.key?('local')
            # "conf" format
            return sync_params['name']
          elsif sync_params.key?('sessions')
            # "args" format
            return sync_params['sessions'].first['name']
          else
            raise 'At least one of `local` or `sessions` must be present in async parameters'
          end
        end

        def session_db_file(sync_params)
          db_file = File.join(local_db_folder(sync_params), PRIVATE_FOLDER, session_name(sync_params), ASYNC_DB)
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
        # tag 'x-ts-name' in schema is used to map transfer spec parameters to async sync_info
        # @param transfer_spec [Hash] transfer specification
        # @param sync_info [Hash] synchronization information
        # @param schema [Hash] schema definition
        def tspec_to_sync_info(transfer_spec, sync_info, schema)
          schema['properties'].each do |name, property|
            if property.key?('x-ts-name')
              tspec_param = property['x-ts-name']
              sync_info[name] ||= transfer_spec[tspec_param] if transfer_spec.key?(tspec_param)
            end
            if property['type'].eql?('object') && property.key?('properties')
              sync_info[name] ||= {}
              tspec_to_sync_info(transfer_spec, sync_info[name], property)
            end
          end
        end
      end
    end
  end
end
