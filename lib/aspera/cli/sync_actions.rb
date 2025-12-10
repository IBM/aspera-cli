# frozen_string_literal: true

require 'aspera/sync/operations'
require 'aspera/assert'
require 'aspera/environment'
require 'pathname'

module Aspera
  module Cli
    # Manage command line arguments to provide to Sync::Operations and Sync::Database
    module SyncActions
      # Translate state id (int) to string
      STATE_STR = (['Nil'] +
        (1..18).map{ |i| "P(#{i})"} +
        %w[Syncd Error Confl Pconf] +
        (23..24).map{ |i| "P(#{i})"}).freeze
      class << self
        def declare_options(_options)
        end
      end

      # Read 1 or 2 command line arguments and converts to `sync_info` format
      # The resulting sync_info has `args` format only if it contains one of the `sessions` or `instance` keys.
      # It has the `conf` format (default) otherwise.
      # If the `conf` format is detected, then both `local` and `remote` keys are set.
      # @param direction [Symbol,NilClass] One of directions, or `nil` if only for admin command
      # @return [Hash] sync info
      def async_info_from_args(direction: nil)
        path = options.get_next_argument('path')
        sync_info = options.get_next_argument('sync info', mandatory: false, validation: Hash, default: {})
        # is the positional path a remote path ?
        path_is_remote = direction.eql?(:pull)
        if sync_info.key?('sessions') || sync_info.key?('instance')
          # `args`
          sync_info['sessions'] ||= [{}]
          Aspera.assert(sync_info['sessions'].length == 1){'Only one session is supported'}
          session = sync_info['sessions'].first
          dir_key = path_is_remote ? 'remote_dir' : 'local_dir'
          raise "Parameter #{dir_key} shall not be in sync_info" if session.key?(dir_key)
          session[dir_key] = path
          if direction
            dir_key = path_is_remote ? 'local_dir' : 'remote_dir'
            raise "Parameter #{dir_key} shall not be in sync_info" if session.key?(dir_key)
            session[dir_key] = transfer.destination_folder(path_is_remote ? Transfer::Spec::DIRECTION_RECEIVE : Transfer::Spec::DIRECTION_SEND)
            local_remote = %w[local remote].map{ |i| session["#{i}_dir"]}
          end
        else
          # `conf`
          session = sync_info
          dir_key = path_is_remote ? 'remote' : 'local'
          session[dir_key] ||= {}
          raise "Parameter #{dir_key}.path shall not be in sync_info" if session[dir_key].key?('path')
          session[dir_key]['path'] = path
          if direction
            dir_key = path_is_remote ? 'local' : 'remote'
            session[dir_key] ||= {}
            raise "Parameter #{dir_key}.path shall not be in sync_info" if session[dir_key].key?('path')
            session[dir_key]['path'] = transfer.destination_folder(path_is_remote ? Transfer::Spec::DIRECTION_RECEIVE : Transfer::Spec::DIRECTION_SEND)
            local_remote = %w[local remote].map{ |i| session[i]['path']}
          end
          # `conf` is quiet by default
          session['quiet'] = false if !session.key?('quiet') && Environment.terminal?
        end
        if direction
          raise BadArgument, 'direction shall not be in sync_info' if session.key?('direction')
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

      # Provide database object from command line arguments for admin ops
      def db_from_args
        sync_info = async_info_from_args
        session = sync_info.key?('sessions') ? sync_info['sessions'].first : sync_info
        # if name not provided, check in db folder if there is only one name
        if !session.key?('name')
          local_db_dir = Sync::Operations.local_db_folder(sync_info)
          dbs = Sync::Operations.list_db_files(local_db_dir)
          raise "#{dbs.length} session found in #{local_db_dir}, please provide a name" unless dbs.length == 1
          session['name'] = dbs.keys.first
        end
        Sync::Database.new(Sync::Operations.session_db_file(sync_info))
      end

      def execute_sync_admin
        command2 = options.get_next_command(%i[status find meta counters file_info overview])
        require 'aspera/sync/database' unless command2.eql?(:status)
        case command2
        when :status
          return Main.result_single_object(Sync::Operations.admin_status(async_info_from_args))
        when :find
          folder = options.get_next_argument('path')
          dbs = Sync::Operations.list_db_files(folder)
          return Main.result_object_list(dbs.keys.map{ |n| {name: n, path: dbs[n]}})
        when :meta, :counters
          return Main.result_single_object(db_from_args.send(command2))
        when :file_info
          result = db_from_args.send(command2)
          result.each do |r|
            r['sstate'] = SyncActions::STATE_STR[r['state']] if r['state']
          end
          return Main.result_object_list(
            result,
            fields: %w[sstate record_id f_meta_path message]
          )
        when :overview
          return Main.result_object_list(
            db_from_args.overview,
            fields: %w[table name type]
          )
        else Aspera.error_unexpected_value(command2)
        end
      end

      # Execute sync action
      # @param &block [nil, Proc] block to generate transfer spec, takes: `direction` (one of DIRECTIONS), `local_dir`, `remote_dir`
      def execute_sync_action(&block)
        command = options.get_next_command(%i[admin] + Sync::Operations::DIRECTIONS)
        # try to get 3 arguments as simple arguments
        case command
        when *Sync::Operations::DIRECTIONS
          Sync::Operations.start(async_info_from_args(direction: command), transfer.user_transfer_spec, &block)
          return Main.result_success
        when :admin
          return execute_sync_admin
        else Aspera.error_unexpected_value(command)
        end
      end
    end
  end
end
