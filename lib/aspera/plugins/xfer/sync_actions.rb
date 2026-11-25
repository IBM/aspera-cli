# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../sync/operations'
require_relative '../../assert'
require_relative '../../environment'
require 'pathname'

module Aspera
  module Plugins
    module Xfer
      # Helpers shared by plugins that expose Aspera Sync (async) operations.
      # Provides DSL registration, argument-to-sync-info conversion, and action methods.
      module SyncActions
        # Translate state id (int) to string
        STATE_STR = (['Nil'] +
          (1..18).map { |i| "P(#{i})" } +
          %w[Syncd Error Confl Pconf] +
          (23..24).map { |i| "P(#{i})" }).freeze
        # Positional arguments of sync transfer commands (push/pull/bidi): the positional `path` is the local folder (push, bidi)
        # or the remote path (pull), so it is not declared as a local path here (the local side is checked when the transfer starts).
        PATH_AND_INFO_ARGS = [{name: :path, complete: :folder, access: :none}, {name: :sync_info, type: Hash, mandatory: false, default: {}}].freeze
        # Positional arguments of sync admin commands: the positional `path` is always the local database folder, read to show its state.
        ADMIN_PATH_AND_INFO_ARGS = [{name: :path, complete: :folder, access: :read}, {name: :sync_info, type: Hash, mandatory: false, default: {}}].freeze
        # Argument of `sync logs`: the async log files to analyze, read locally (default: the local async log)
        SYNC_LOG_ARGS = [{
          name:        :paths,
          description: 'async log files (gzip supported), folders, or `-` for standard input (default: the local async log)',
          multiple:    true,
          mandatory:   false,
          complete:    :file,
          access:      :read,
          stdin:       true
        }].freeze
        # When a plugin class includes SyncActions, register the :sql option
        # in that class's DSL registry so Base#initialize auto-declares it,
        # and add the class-level DSL methods of ClassMethods.
        class << self
          def included(base)
            # Raw SQL appended to the queries of the admin commands: executes code (e.g. `VACUUM INTO` writes a file), allowed at level `low` only
            base.option(:sql, description: 'SQL suffix appended to sqlite3 queries for admin subcommands (e.g. WHERE clause)', security: :low)
            base.extend(ClassMethods)
          end
        end

        # Class-level DSL methods added to the plugin class that includes SyncActions.
        module ClassMethods
          # DSL class method: declare the `sync admin` node and its 7 leaf commands.
          # @param parent [Symbol, Array<Symbol>] path relative to current scope, e.g. :admin
          def sync_admin_commands(parent)
            commands_under(parent, description: 'Manage sync database (admin operations)') do
              command(
                :find, description: 'Find sync database files', arguments: [{name: :path, complete: :folder, access: :read}],
                action: lambda do |path:, **|
                  dbs = readable_db_files(path)
                  Cli::Result::ObjectList.new(dbs.keys.map { |n| {name: n, path: dbs[n]} })
                end
              )
              command(
                :status, description: 'Show sync session status', arguments: ADMIN_PATH_AND_INFO_ARGS,
                action: ->(path:, sync_info: {}, **) { Cli::Result::SingleObject.new(Sync::Operations.admin_status(admin_sync_info(path: path, sync_info: sync_info))) }
              )
              command(
                :meta, description: 'Show sync session metadata', arguments: ADMIN_PATH_AND_INFO_ARGS,
                action: lambda do |path:, sync_info: {}, **|
                  require_relative '../../sync/database'
                  Cli::Result::SingleObject.new(db_from_args(path: path, sync_info: sync_info).meta(options.get_option(:sql)))
                end
              )
              command(
                :counters, description: 'Show sync counters', arguments: ADMIN_PATH_AND_INFO_ARGS,
                action: lambda do |path:, sync_info: {}, **|
                  require_relative '../../sync/database'
                  Cli::Result::SingleObject.new(db_from_args(path: path, sync_info: sync_info).counters(options.get_option(:sql)))
                end
              )
              command(:file_info, description: 'Show per-file sync state', arguments: ADMIN_PATH_AND_INFO_ARGS, action: :action_sync_admin_file_info)
              command(
                :overview, description: 'Show sync database overview', arguments: ADMIN_PATH_AND_INFO_ARGS,
                action: lambda do |path:, sync_info: {}, **|
                  require_relative '../../sync/database'
                  Cli::Result::ObjectList.new(db_from_args(path: path, sync_info: sync_info).overview, fields: %w[table name type])
                end
              )
              command(
                :query, description: 'Execute a raw SQL query', arguments: ADMIN_PATH_AND_INFO_ARGS,
                action: lambda do |path:, sync_info: {}, **|
                  require_relative '../../sync/database'
                  Cli::Result.auto(db_from_args(path: path, sync_info: sync_info).execute(options.get_option(:sql, mandatory: true)))
                end
              )
            end
          end

          # DSL class method: declare the `sync logs` command (analysis of async log files).
          # @param name [Symbol, Array<Symbol>] command path relative to current scope, e.g. :logs
          def sync_logs_command(name)
            command(name, description: 'Analyze async log files: conflicts, errors, and session lifecycle', arguments: SYNC_LOG_ARGS, action: :action_sync_logs)
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
            Aspera.assert(sync_info['sessions'].length == 1, 'Only one session is supported', type: Cli::BadArgument)
            session = sync_info['sessions'].first
            dir_key = path_is_remote ? 'remote_dir' : 'local_dir'
            Aspera.assert(!session.key?(dir_key), type: Cli::BadArgument) { "Parameter #{dir_key} shall not be in sync_info" }
            session[dir_key] = path
            if direction
              dir_key = path_is_remote ? 'local_dir' : 'remote_dir'
              Aspera.assert(!session.key?(dir_key), type: Cli::BadArgument) { "Parameter #{dir_key} shall not be in sync_info" }
              session[dir_key] = transfer.destination_folder(path_is_remote ? Aspera::Transfer::Spec::DIRECTION_RECEIVE : Aspera::Transfer::Spec::DIRECTION_SEND)
              local_remote = %w[local remote].map { |i| session["#{i}_dir"] }
            end
          else
            # `conf`
            session = sync_info
            dir_key = path_is_remote ? 'remote' : 'local'
            session[dir_key] ||= {}
            Aspera.assert(!session[dir_key].key?('path'), type: Cli::BadArgument) { "Parameter #{dir_key}.path shall not be in sync_info" }
            session[dir_key]['path'] = path
            if direction
              dir_key = path_is_remote ? 'local' : 'remote'
              session[dir_key] ||= {}
              Aspera.assert(!session[dir_key].key?('path'), type: Cli::BadArgument) { "Parameter #{dir_key}.path shall not be in sync_info" }
              session[dir_key]['path'] = transfer.destination_folder(path_is_remote ? Aspera::Transfer::Spec::DIRECTION_RECEIVE : Aspera::Transfer::Spec::DIRECTION_SEND)
              local_remote = %w[local remote].map { |i| session[i]['path'] }
            end
            # `conf` is quiet by default
            session['quiet'] = false if !session.key?('quiet') && Environment.terminal?
          end
          if direction
            Aspera.assert(!session.key?('direction'), type: Cli::BadArgument) { 'direction shall not be in sync_info' }
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

        # Sync info of an admin command, which reads the database of the session (directly, or by `asyncadmin`).
        # The database is in the folder given by the argument `path`, or by `sync_info` (`local_db_dir`): that folder is checked against the security level,
        # as the argument (`access: :read`), and so is the database file of the session when it is named (a name can contain `..`, a folder can be a symbolic link).
        # @param path      [String] local path, checked against the security level
        # @param sync_info [Hash]   extra sync info (may be empty)
        # @return [Hash] sync info
        def admin_sync_info(path:, sync_info:)
          sync_info = async_info_from_args(path: path, sync_info: sync_info)
          security = Cli::Security.instance
          security.readable_path(Sync::Operations.local_db_folder(sync_info))
          security.readable_path(Sync::Operations.session_db_path(sync_info)) unless Sync::Operations.session_name(sync_info).nil?
          sync_info
        end

        # Database files of the sync sessions in a folder, that can be read at the security level
        # (the folder of the databases, of a session, or a database file can be a symbolic link).
        # @param local_db_dir [String] folder of the databases, checked against the security level
        # @return [Hash{String => String}] name of session => database file
        def readable_db_files(local_db_dir)
          security = Cli::Security.instance
          Sync::Operations.list_db_files(security.readable_path(local_db_dir)).select { |_, file| security.readable_path?(file) }
        end

        # Provide database object from path + sync_info for admin ops
        # @param path      [String] local path
        # @param sync_info [Hash]   extra sync info (may be empty)
        def db_from_args(path:, sync_info: {})
          sync_info = admin_sync_info(path: path, sync_info: sync_info)
          session = sync_info.key?('sessions') ? sync_info['sessions'].first : sync_info
          # if name not provided, check in db folder if there is only one name
          if !session.key?('name')
            local_db_dir = Sync::Operations.local_db_folder(sync_info)
            dbs = readable_db_files(local_db_dir)
            Aspera.assert(dbs.length == 1, type: Cli::BadArgument) { "#{dbs.length} session found in #{local_db_dir}, please provide a name" }
            session['name'] = dbs.keys.first
          end
          Sync::Database.new(Sync::Operations.session_db_file(sync_info))
        end

        def action_sync_admin_file_info(path:, sync_info: {}, **)
          require_relative '../../sync/database'
          result = db_from_args(path: path, sync_info: sync_info).file_info(options.get_option(:sql))
          result.each do |r|
            r['sstate'] = SyncActions::STATE_STR[r['state']] if r['state']
          end
          Cli::Result::ObjectList.new(result, fields: %w[sstate record_id f_meta_path message])
        end

        # Analyze async log files: the notable events (conflicts, errors, session lifecycle).
        # @param paths [Array<String>, nil] log files, folders, or `-`; already checked against the security level (`access: :read`).
        #   When not given, the local async log is read (also checked against the security level).
        def action_sync_logs(paths: nil, **)
          require_relative '../../sync/log_parser'
          files =
            if paths.nil? || paths.empty?
              default = Sync::LogParser.default_log_paths.map { |path| Cli::Security.instance.readable_path(path) }
              Aspera.assert(!default.empty?, type: Cli::BadArgument) { "No async log found at the default location (#{Sync::LogParser.default_location_hint}); give a path" }
              default
            else
              paths
            end
          files.each do |file|
            Aspera.assert(file == Cli::Plugins::Base::STDIN_ARGUMENT || File.exist?(file), type: Cli::BadArgument) { "No such file or folder: #{file}" }
          end
          Cli::Result::ObjectList.new(Sync::LogParser.notable_events(files, readable: Cli::Security.instance.method(:readable_path?)), fields: Sync::LogParser::FIELDS)
        end

        # Execute a sync transfer for a given direction.
        # @param direction [Symbol]    one of Sync::Operations::DIRECTIONS (:push, :pull, :bidi)
        # @param path      [String]    local or remote path (depends on direction)
        # @param sync_info [Hash]      extra sync configuration (may be empty)
        # @param block     [Proc, nil] block to generate transfer spec; receives (direction, local_dir, remote_dir)
        def run_sync_transfer(direction, path:, sync_info: {}, &block)
          # Not a transfer of `TransferAgent`: the sync session runs the local `async` program on a local folder, so it is refused at level `high`,
          # as an agent that runs on the local host (see `Cli::Security` and `TransferAgent`).
          Cli::Security.instance.check_level(:medium, 'sync (local async)')
          transfer.assert_no_dry_run
          Sync::Operations.start(
            async_info_from_args(path: path, sync_info: sync_info, direction: direction),
            transfer.user_transfer_spec,
            agent_options: transfer.sync_agent_options,
            &block
          )
          Cli::Result::Success.new
        end
      end
    end
  end
end
