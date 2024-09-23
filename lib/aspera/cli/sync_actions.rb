# frozen_string_literal: true

require 'aspera/transfer/sync'
require 'aspera/assert'

module Aspera
  module Cli
    # Module for sync actions
    module SyncActions
      # optional simple command line arguments for sync
      # in Array to keep option order
      # conf: key in option --conf
      # args: key for command line args
      # values: possible values for argument
      # type: type for validation
      SYNC_ARGUMENTS_INFO = [
        {
          conf:   'direction',
          args:   'direction',
          values: Transfer::Sync::DIRECTIONS
        }, {
          conf: 'remote.path',
          args: 'remote_dir',
          type: String
        }, {
          conf: 'local.path',
          args: 'local_dir',
          type: String
        }
      ].freeze
      # name of minimal arguments required, also used to generate a session name
      SYNC_SIMPLE_ARGS = SYNC_ARGUMENTS_INFO.map{|i|i[:conf]}.freeze
      private_constant :SYNC_ARGUMENTS_INFO, :SYNC_SIMPLE_ARGS

      class << self
        def declare_options(options)
          options.declare(:sync_info, 'Information for sync instance and sessions', types: Hash)
        end
      end

      # Read command line arguments (3) and converts to sync_info format
      def sync_args_to_params(async_params)
        # sync session parameters can be provided on command line instead of sync_info
        arguments = {}
        SYNC_ARGUMENTS_INFO.each do |info|
          value = options.get_next_argument(
            info[:conf],
            mandatory: false,
            validation: info[:type],
            accept_list: info[:values])
          break if value.nil?
          arguments[info[:conf]] = value.to_s
        end
        Log.log.debug{Log.dump('arguments', arguments)}
        raise Cli::BadArgument, "Provide 0 or 3 arguments, not #{arguments.keys.length} for: #{SYNC_SIMPLE_ARGS.join(', ')}" unless
          [0, 3].include?(arguments.keys.length)
        if !arguments.empty?
          session_info = async_params
          param_path = :conf
          if async_params.key?('sessions') || async_params.key?('instance')
            async_params['sessions'] ||= [{}]
            Aspera.assert(async_params['sessions'].length == 1){'Only one session is supported with arguments'}
            session_info = async_params['sessions'][0]
            param_path = :args
          end
          SYNC_ARGUMENTS_INFO.each do |info|
            key_path = info[param_path].split('.')
            hash_for_key = session_info
            if key_path.length > 1
              first = key_path.shift
              async_params[first] ||= {}
              hash_for_key = async_params[first]
            end
            raise "Parameter #{info[:conf]} is also set in sync_info, remove from sync_info" if hash_for_key.key?(key_path.last)
            hash_for_key[key_path.last] = arguments[info[:conf]]
          end
          if !session_info.key?('name')
            # if no name is specified, generate one from simple arguments
            session_info['name'] = SYNC_SIMPLE_ARGS.map do |arg_name|
              arguments[arg_name]&.gsub(/[^a-zA-Z0-9]/, '')
            end.compact.reject(&:empty?).join('_')
          end
        end
      end

      def execute_sync_action(&block)
        Aspera.assert(block){'No block given'}
        command = options.get_next_command(%i[start admin])
        # try to get 3 arguments as simple arguments
        case command
        when :start
          # possibilities are:
          async_params = options.get_option(:sync_info, default: {})
          sync_args_to_params(async_params)
          Transfer::Sync.start(async_params, &block)
          return Main.result_success
        when :admin
          command2 = options.get_next_command([:status])
          case command2
          when :status
            sync_session_name = options.get_next_argument('name of sync session', mandatory: false, validation: String)
            async_params = options.get_option(:sync_info, mandatory: true)
            return {type: :single_object, data: Transfer::Sync.admin_status(async_params, sync_session_name)}
          end
        end
      end
    end
  end
end
