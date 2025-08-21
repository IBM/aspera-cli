# frozen_string_literal: true

require 'aspera/transfer/sync'
require 'aspera/transfer/sync_database'
require 'aspera/assert'

module Aspera
  module Cli
    # Module for sync actions
    module SyncActions
      class << self
        def declare_options(options)
          options.declare(:sync_info, 'Information for sync instance and sessions', types: Hash, default: {})
        end
      end

      # Read command line arguments (0 or 3) and converts to sync_info format
      # sync session parameters can be provided on command line instead of sync_info
      def sync_info_from_cli
        async_params = options.get_option(:sync_info, default: {})
        # named arguments, or empty
        arguments = []
        Transfer::Sync::SYNC_PARAMETERS.each do |info|
          value = options.get_next_argument(
            info[:name],
            mandatory: false,
            validation: info[:type],
            accept_list: info[:values])
          break if value.nil?
          arguments.push(value.to_s)
        end
        raise Cli::BadArgument, "Provide 0, 3 or 4 arguments, not #{arguments.length} for: #{Transfer::Sync::SYNC_PARAMETERS.map{ |i| "<#{i[:name]}>"}.join(', ')}" unless [0, 3, 4].include?(arguments.length)
        Log.log.debug{Log.dump('arguments', arguments)}
        return [async_params, arguments]
      end

      # Execute sync action
      # @param &block [nil, Proc] block to generate transfer spec, takes: direction (one of DIRECTIONS), local_dir, remote_dir
      def execute_sync_action(&block)
        command = options.get_next_command(%i[start admin db])
        # try to get 3 arguments as simple arguments
        case command
        when :start
          Transfer::Sync.start(Transfer::Sync.validated_sync_info(*sync_info_from_cli, sync: true), &block)
          return Main.result_success
        when :admin
          command2 = options.get_next_command(%i[status])
          case command2
          when :status
            return Main.result_single_object(Transfer::Sync.admin_status(Transfer::Sync.validated_sync_info(*sync_info_from_cli)))
          else Aspera.error_unexpected_value(command2)
          end
        when :db
          command2 = options.get_next_command(%i[meta counters])
          case command2
          when :meta, :counters
            return Main.result_single_object(Transfer::SyncDatabase.new(Transfer::Sync.session_db_file(Transfer::Sync.validated_sync_info(*sync_info_from_cli))).send(command2))
          else Aspera.error_unexpected_value(command2)
          end
        else Aspera.error_unexpected_value(command)
        end
      end
    end
  end
end
