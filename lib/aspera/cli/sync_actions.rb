# frozen_string_literal: true

require 'aspera/transfer/sync'
require 'aspera/assert'

module Aspera
  module Cli
    # Module for sync actions
    module SyncActions
      SIMPLE_ARGUMENTS_SYNC = {
        direction:  Transfer::Sync::DIRECTIONS,
        local_dir:  String,
        remote_dir: String
      }.stringify_keys.freeze

      class << self
        def declare_options(options)
          options.declare(:sync_info, 'Information for sync instance and sessions', types: Hash)
        end
      end

      def execute_sync_action(&block)
        Aspera.assert(block){'No block given'}
        command = options.get_next_command(%i[start admin])
        # try to get 3 arguments as simple arguments
        case command
        when :start
          simple_session_args = {}
          SIMPLE_ARGUMENTS_SYNC.each do |arg, check|
            value = options.get_next_argument(
              arg,
              type: check.is_a?(Class) ? check : nil,
              expected: check.is_a?(Class) ? :single : check,
              mandatory: false)
            break if value.nil?
            simple_session_args[arg] = value.to_s
          end
          async_params = nil
          if simple_session_args.empty?
            async_params = options.get_option(:sync_info, mandatory: true)
          else
            raise Cli::BadArgument,
              "Provide zero or 3 arguments: #{SIMPLE_ARGUMENTS_SYNC.keys.join(',')}" unless simple_session_args.keys.sort == SIMPLE_ARGUMENTS_SYNC.keys.sort
            async_params = options.get_option(
              :sync_info,
              mandatory: false,
              default: {'sessions' => [{'name' => File.basename(simple_session_args['local_dir'])}]})
            Aspera.assert_type(async_params, Hash){'sync_info'}
            Aspera.assert_type(async_params['sessions'], Array){'sync_info[sessions]'}
            Aspera.assert_type(async_params['sessions'].first, Hash){'sync_info[sessions][0]'}
            async_params['sessions'].first.merge!(simple_session_args)
          end
          Log.log.debug{Log.dump('async_params', async_params)}
          Transfer::Sync.start(async_params, &block)
          return Main.result_success
        when :admin
          command2 = options.get_next_command([:status])
          case command2
          when :status
            sync_session_name = options.get_next_argument('name of sync session', mandatory: false, type: String)
            async_params = options.get_option(:sync_info, mandatory: true)
            return {type: :single_object, data: Transfer::Sync.admin_status(async_params, sync_session_name)}
          end # command2
        end # command
      end # execute_action
    end # SyncActions
  end # Cli
end # Aspera
