# frozen_string_literal: true

require 'aspera/sync/operations'
require 'aspera/assert'

module Aspera
  module Cli
    # Manage command line arguments to provide to Sync::Run, Sync::Database and Sync::Operations
    module SyncActions
      # translate state id (int) to string
      STATE_STR = (['Nil'] +
        (1..18).map{ |i| "P(#{i})"} +
        %w[Syncd Error Confl Pconf] +
        (23..24).map{ |i| "P(#{i})"}).freeze
      class << self
        def declare_options(options)
          options.declare(:sync_info, 'Information for sync instance and sessions', types: Hash, default: {})
        end
      end

      # Read command line arguments (0 or 3) and converts to sync_info format
      # sync session parameters can be provided on command line instead of sync_info
      def sync_info_from_cli(parameter_description)
        async_params = options.get_option(:sync_info, default: {})
        # named arguments, or empty
        arguments = []
        parameter_description.each do |info|
          value = options.get_next_argument(
            info[:name],
            mandatory: false,
            validation: info[:type],
            accept_list: info[:values])
          break if value.nil?
          arguments.push(value.to_s)
        end
        Log.log.debug{Log.dump('arguments', arguments)}
        return [async_params, arguments]
      end

      # Execute sync action
      # @param &block [nil, Proc] block to generate transfer spec, takes: direction (one of DIRECTIONS), local_dir, remote_dir
      def execute_sync_action(&block)
        command = options.get_next_command(%i[start admin])
        # try to get 3 arguments as simple arguments
        case command
        when :start
          Sync::Operations.start(Sync::Operations.validated_sync_info(*sync_info_from_cli(Sync::Operations::SYNC_PARAMETERS)), &block)
          return Main.result_success
        when :admin
          command2 = options.get_next_command(%i[status find meta counters file_info overview])
          require 'aspera/sync/database' unless command2.eql?(:status)
          case command2
          when :status
            return Main.result_single_object(Sync::Operations.admin_status(Sync::Operations.validated_admin_info(*sync_info_from_cli(Sync::Operations::ADMIN_PARAMETERS))))
          when :find
            folder = options.get_next_argument('path')
            dbs = Sync::Operations.list_db_files(folder)
            return Main.result_object_list(dbs.keys.map{ |n| {name: n, path: dbs[n]}})
          when :meta, :counters
            return Main.result_single_object(
              Sync::Database.new(
                Sync::Operations.session_db_file(
                  Sync::Operations.validated_admin_info(
                    *sync_info_from_cli(Sync::Operations::ADMIN_PARAMETERS)))).send(command2))
          when :file_info
            result =
              Sync::Database.new(
                Sync::Operations.session_db_file(
                  Sync::Operations.validated_admin_info(
                    *sync_info_from_cli(Sync::Operations::ADMIN_PARAMETERS)))).send(command2)
            result.each do |r|
              r['sstate'] = SyncActions::STATE_STR[r['state']] if r['state']
            end
            return Main.result_object_list(
              result,
              fields: %w[sstate record_id f_meta_path message])
          when :overview
            return Main.result_object_list(
              Sync::Database.new(
                Sync::Operations.session_db_file(
                  Sync::Operations.validated_admin_info(
                    *sync_info_from_cli(Sync::Operations::ADMIN_PARAMETERS)))).overview,
              fields: %w[table name type]
            )
          else Aspera.error_unexpected_value(command2)
          end
        else Aspera.error_unexpected_value(command)
        end
      end
    end
  end
end
