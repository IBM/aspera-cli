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
      SIMPLE_ARGUMENTS = {
        direction:  Aspera::Sync::DIRECTIONS,
        local_dir:  String,
        remote_dir: String
      }.stringify_keys.freeze
      def declare_sync_options
        options.declare(:sync_info, 'Information for sync instance and sessions', types: Hash)
        options.declare(:sync_session, 'Name of session to use for admin commands. default: first one in sync_info')
      end

      def execute_sync_action(&block)
        # options = Aspera::Cli::Manager.new
        raise 'Internal Error: No block given' unless block
        command = options.get_next_command(%i[start admin])
        # try to get 3 arguments as simple arguments
        simple_args = {}
        async_params = nil
        SIMPLE_ARGUMENTS.each do |arg, check|
          value = options.get_next_argument(
            arg,
            type: check.is_a?(Class) ? check : nil,
            expected: check.is_a?(Class) ? :single : check,
            mandatory: false).to_s
          # no arg given at all
          if value.nil?
            # partial args given
            raise "provide zero or 3 arguments: #{SIMPLE_ARGUMENTS.keys.join(',')}" unless simple_args.empty?
            # no args given
            async_params = options.get_option(:sync_info, mandatory: true)
            break
          end
          simple_args[arg] = value
        end
        if async_params.nil?
          async_params = options.get_option(
            :sync_info,
            allowed_types: Hash,
            mandatory: false,
            default: {'sessions' => [{'name' => File.basename(simple_args['local_dir'])}]})
          raise "Bad sync_info: #{async_params}" unless async_params.is_a?(Hash) && async_params['sessions']&.is_a?(Array) && async_params['sessions'].first.is_a?(Hash)
          async_params['sessions'].first.merge!(simple_args)
        end
        Log.dump('async_params', async_params)
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
