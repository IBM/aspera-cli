# frozen_string_literal: true

require 'sqlite3'

module Aspera
  module Sync
    # Access Sync snapshot DB
    class Database
      def initialize(db_path)
        @db_path = db_path
      end

      # Execute block with database connection
      # @param block [Proc] bloc to be executed within database
      # @raise [SQLite3::Exception] if database access fails
      def with_db
        db = SQLite3::Database.new(@db_path)
        db.results_as_hash = true
        yield db
      ensure
        db&.close
      end

      # Database structure
      def overview
        with_db do |db|
          result = []
          tables = db.execute("SELECT name FROM sqlite_master WHERE type='table';")
          tables.each do |table_row|
            table_name = table_row['name']
            db.execute("PRAGMA table_info(#{table_name});").each do |column_info|
              result.push({'table'=>table_name}.merge(column_info))
            end
          end
          result
        end
      end

      # Get data from table with single row
      def single_table(table_name)
        with_db do |db|
          return db.get_first_row("SELECT * FROM #{table_name} LIMIT 1")
        end
      end

      # Get all objects from table
      def full_table(table_name)
        with_db do |db|
          return db.execute("SELECT * FROM #{table_name}")
        end
      end

      def meta
        single_table('sync_snapmeta_table')
      end

      def counters
        single_table('sync_snap_counters_table')
      end

      def file_info
        full_table('sync_snapdb_table')
      end
    end
  end
end
