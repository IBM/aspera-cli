# frozen_string_literal: true

require 'sqlite3'

module Aspera
  module Sync
    # builds command line arg for async and execute it
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

      def overview
        with_db do |db|
          tables = db.execute("SELECT name FROM sqlite_master WHERE type='table';")
          if tables.empty?
            puts 'No tables found in the database.'
          else
            puts 'Tables in the database:'
            tables.each do |table_row|
              table_name = table_row[0]
              puts "  - #{table_name}"
              # Execute a COUNT(*) query to get the number of rows
              row_count = db.get_first_value("SELECT COUNT(*) FROM #{table_name};")
              puts "    #{row_count} rows"
              # Use PRAGMA table_info to get column information for each table
              column_info = db.execute("PRAGMA table_info(#{table_name});")
              puts '    Columns:'
              column_info.each do |column|
                # Column information is returned as an array: [cid, name, type, notnull, dflt_value, pk]
                column_name = column[1]
                column_type = column[2]
                puts "      - #{column_name} (#{column_type})"
              end
            end
          end
        end
      end

      # Get data from table with single row
      def single_table(table_name)
        with_db do |db|
          return db.get_first_row("SELECT * FROM #{table_name} LIMIT 1")
        end
      end

      def meta
        single_table('sync_snapmeta_table')
      end

      def counters
        single_table('sync_snap_counters_table')
      end
    end
  end
end
