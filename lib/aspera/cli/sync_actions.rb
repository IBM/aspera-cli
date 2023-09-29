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
        raise 'Internal Error: No block given' unless block
        async_params = options.get_option(:sync_info, mandatory: true)
        command = options.get_next_command(%i[start admin])
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
