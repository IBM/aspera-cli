# frozen_string_literal: true

require 'aspera/sync/operations'
require 'aspera/assert'
require 'aspera/environment'
require 'pathname'

module Aspera
  module Cli
    # Helpers shared by plugins that expose Aspera Sync (async) operations.
    # Provides DSL registration, argument-to-sync-info conversion, and action methods.
    module SyncActions
      # Translate state id (int) to string
      STATE_STR = (['Nil'] +
        (1..18).map { |i| "P(#{i})" } +
        %w[Syncd Error Confl Pconf] +
        (23..24).map { |i| "P(#{i})" }).freeze
      # Positional arguments shared by sync transfer commands (push/pull/bidi) and sync admin commands.
      PATH_AND_INFO_ARGS = [{name: :path}, {name: :sync_info, type: Hash, mandatory: false, default: {}}].freeze
      # Names of the leaf commands registered under any `sync admin` node.
      ADMIN_COMMANDS = %i[find status meta counters file_info overview query].freeze
      # When a plugin class includes SyncActions, register the :sql option
      # in that class's DSL registry so Base#initialize auto-declares it.
      class << self
        def included(base)
          base.option(:sql, description: 'SQL suffix appended to sqlite3 queries for admin subcommands (e.g. WHERE clause)')
        end

        # DSL helper: register the 7 `sync admin` leaf commands under the given parent path.
        # Called at class-load time from any plugin that includes SyncActions.
        # @param base        [Class]          the plugin class (receiver of DSL methods)
        # @param admin_path  [Symbol, Array<Symbol>]  path relative to current scope, e.g. :admin
        def register_sync_admin_commands(base, admin_path)
          base.commands_under(admin_path) do
            base.command(
              :find, description: 'Find sync database files', arguments: [{name: :path}],
              action: lambda do |path:, **|
                dbs = Sync::Operations.list_db_files(path)
                Result::ObjectList.new(dbs.keys.map { |n| {name: n, path: dbs[n]} })
              end
            )
            base.command(
              :status, description: 'Show sync session status', arguments: PATH_AND_INFO_ARGS,
              action: ->(path:, sync_info: {}, **) { Result::SingleObject.new(Sync::Operations.admin_status(async_info_from_args(path: path, sync_info: sync_info))) }
            )
            base.command(
              :meta, description: 'Show sync session metadata', arguments: PATH_AND_INFO_ARGS,
              action: lambda do |path:, sync_info: {}, **|
                require 'aspera/sync/database'
                Result::SingleObject.new(db_from_args(path: path, sync_info: sync_info).meta(options.get_option(:sql)))
              end
            )
            base.command(
              :counters, description: 'Show sync counters', arguments: PATH_AND_INFO_ARGS,
              action: lambda do |path:, sync_info: {}, **|
                require 'aspera/sync/database'
                Result::SingleObject.new(db_from_args(path: path, sync_info: sync_info).counters(options.get_option(:sql)))
              end
            )
            base.command(:file_info, description: 'Show per-file sync state', arguments: PATH_AND_INFO_ARGS, action: :action_sync_admin_file_info)
            base.command(
              :overview, description: 'Show sync database overview', arguments: PATH_AND_INFO_ARGS,
              action: lambda do |path:, sync_info: {}, **|
                require 'aspera/sync/database'
                Result::ObjectList.new(db_from_args(path: path, sync_info: sync_info).overview, fields: %w[table name type])
              end
            )
            base.command(
              :query, description: 'Execute a raw SQL query', arguments: PATH_AND_INFO_ARGS,
              action: lambda do |path:, sync_info: {}, **|
                require 'aspera/sync/database'
                Result.auto(db_from_args(path: path, sync_info: sync_info).execute(options.get_option(:sql, mandatory: true)))
              end
            )
          end
        end
      end

      # Convert path + sync_info to internal `sync_info` format.
      # The resulting sync_info has `args` format only if it contains one of the `sessions` or `instance` keys.
      # It has the `conf` format (default) otherwise.
      # If the `conf` format is detected, then both `local` and `remote` keys are set.
      # @param path      [String]          local/remote path
      # @param sync_info [Hash]            extra sync info (may be empty)
      # @param direction [Symbol,NilClass] one of DIRECTIONS, or nil for admin commands
      # @return [Hash] sync info
      def async_info_from_args(path:, sync_info: {}, direction: nil)
        # is the positional path a remote path ?
        path_is_remote = direction.eql?(:pull)
        if sync_info.key?('sessions') || sync_info.key?('instance')
          # `args`
          sync_info['sessions'] ||= [{}]
          Aspera.assert(sync_info['sessions'].length == 1, 'Only one session is supported')
          session = sync_info['sessions'].first
          dir_key = path_is_remote ? 'remote_dir' : 'local_dir'
          Aspera.assert(!session.key?(dir_key)) { "Parameter #{dir_key} shall not be in sync_info" }
          session[dir_key] = path
          if direction
            dir_key = path_is_remote ? 'local_dir' : 'remote_dir'
            Aspera.assert(!session.key?(dir_key)) { "Parameter #{dir_key} shall not be in sync_info" }
            session[dir_key] = transfer.destination_folder(path_is_remote ? Transfer::Spec::DIRECTION_RECEIVE : Transfer::Spec::DIRECTION_SEND)
            local_remote = %w[local remote].map { |i| session["#{i}_dir"] }
          end
        else
          # `conf`
          session = sync_info
          dir_key = path_is_remote ? 'remote' : 'local'
          session[dir_key] ||= {}
          Aspera.assert(!session[dir_key].key?('path')) { "Parameter #{dir_key}.path shall not be in sync_info" }
          session[dir_key]['path'] = path
          if direction
            dir_key = path_is_remote ? 'local' : 'remote'
            session[dir_key] ||= {}
            Aspera.assert(!session[dir_key].key?('path')) { "Parameter #{dir_key}.path shall not be in sync_info" }
            session[dir_key]['path'] = transfer.destination_folder(path_is_remote ? Transfer::Spec::DIRECTION_RECEIVE : Transfer::Spec::DIRECTION_SEND)
            local_remote = %w[local remote].map { |i| session[i]['path'] }
          end
          # `conf` is quiet by default
          session['quiet'] = false if !session.key?('quiet') && Environment.terminal?
        end
        if direction
          Aspera.assert(!session.key?('direction'), type: BadArgument) { 'direction shall not be in sync_info' }
          session['direction'] = direction.to_s
          # generate name if not provided by user
          if !session.key?('name')
            safe_char = Environment.instance.safe_filename_character
            # from async man page:
            # -N : can contain only ASCII alphanumeric, hyphen, and underscore characters
            session['name'] = Environment.instance.sanitized_filename(
              ([direction.to_s] + local_remote).map do |value|
                Pathname(value).each_filename.to_a.last(2).join(safe_char)
              end.join(safe_char).gsub(/[^A-Za-z0-9_-]/, safe_char)
            )
          end
        end
        sync_info
      end

      # Provide database object from path + sync_info for admin ops
      # @param path      [String] local path
      # @param sync_info [Hash]   extra sync info (may be empty)
      def db_from_args(path:, sync_info: {})
        sync_info = async_info_from_args(path: path, sync_info: sync_info)
        session = sync_info.key?('sessions') ? sync_info['sessions'].first : sync_info
        # if name not provided, check in db folder if there is only one name
        if !session.key?('name')
          local_db_dir = Sync::Operations.local_db_folder(sync_info)
          dbs = Sync::Operations.list_db_files(local_db_dir)
          Aspera.assert(dbs.length == 1) { "#{dbs.length} session found in #{local_db_dir}, please provide a name" }
          session['name'] = dbs.keys.first
        end
        Sync::Database.new(Sync::Operations.session_db_file(sync_info))
      end

      def action_sync_admin_file_info(path:, sync_info: {}, **)
        require 'aspera/sync/database'
        result = db_from_args(path: path, sync_info: sync_info).file_info(options.get_option(:sql))
        result.each do |r|
          r['sstate'] = SyncActions::STATE_STR[r['state']] if r['state']
        end
        Result::ObjectList.new(result, fields: %w[sstate record_id f_meta_path message])
      end

      # Execute a sync transfer for a given direction.
      # @param direction [Symbol]    one of Sync::Operations::DIRECTIONS (:push, :pull, :bidi)
      # @param path      [String]    local or remote path (depends on direction)
      # @param sync_info [Hash]      extra sync configuration (may be empty)
      # @param block     [Proc, nil] block to generate transfer spec; receives (direction, local_dir, remote_dir)
      def run_sync_transfer(direction, path:, sync_info: {}, &block)
        Sync::Operations.start(async_info_from_args(path: path, sync_info: sync_info, direction: direction), transfer.user_transfer_spec, &block)
        Result::Success.new
      end
    end
  end
end
