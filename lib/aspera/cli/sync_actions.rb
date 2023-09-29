# frozen_string_literal: true

# require 'English'
require 'aspera/cli/plugin'
require 'aspera/sync'
# require 'aspera/log'
# require 'open3'

module Aspera
  module Cli
    # Module for sync actions
    module SyncActions
      def declare_sync_options
        options.declare(:sync_info, 'Information for sync instance and sessions', types: Hash)
        options.declare(:sync_session, 'Name of session to use for admin commands. default: first one in sync_info')
      end

      def execute_sync_action(&block)
        # options = Aspera::Cli::Manager.new
        raise 'Internal Error: No block given' unless block
        command = options.get_next_command(%i[start admin])
        sync_direction = options.get_next_argument('sync direction', expected: Aspera::Sync::DIRECTIONS, mandatory: false)
        local_path = options.get_next_argument('local path', type: String, mandatory: false) if sync_direction
        remote_path = options.get_next_argument('remote path', type: String, mandatory: false) if local_path
        async_params = if sync_direction && local_path && remote_path
          additional = options.get_option(:sync_info, allowed_types: Hash, mandatory: false, default: {'sessions' => [{'name' => File.basename(local_path)}]})
          raise "Bad sync_info: #{additional}" unless additional.is_a?(Hash) && additional['sessions']&.is_a?(Array) && additional['sessions'].first.is_a?(Hash)
          additional['sessions'].first.merge!('direction' => sync_direction.to_s, 'local_dir' => local_path, 'remote_dir' => remote_path)
          additional
        else
          raise 'provide zero or 3 arguments: direction, source, destination' if sync_direction && !remote_path
          options.get_option(:sync_info, mandatory: true)
        end
        case command
        when :start
          Aspera::Sync.start(async_params, &block)
          return Main.result_success
        when :admin
          sync_admin = Aspera::SyncAdmin.new(async_params, options.get_option(:sync_session))
          command2 = options.get_next_command([:status])
          case command2
          when :status
            return {type: :single_object, data: sync_admin.status}
          end # command2
        end # command
      end # execute_action
    end # SyncActions
  end # Cli
end # Aspera
