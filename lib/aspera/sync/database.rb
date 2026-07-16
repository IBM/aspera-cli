# frozen_string_literal: true

if defined?(JRUBY_VERSION)
  require 'jdbc/sqlite3'
  Jdbc::SQLite3.load_driver
  require 'sequel'
else
  require 'sqlite3'
end

# A wrapper class that provides common API for sqlite in both Ruby and JRuby
class SqLite3Wrapper
  def initialize(db_path)
    @db_path = db_path
  end

  if defined?(JRUBY_VERSION)
    def execute(sql)
      db = Sequel.connect("jdbc:sqlite:#{@db_path}")
      begin
        normalize_rows(db.fetch(sql).all)
      ensure
        db.disconnect
      end
    end
  else
    def execute(sql)
      db = SQLite3::Database.new(@db_path).tap{ |d| d.results_as_hash = true}
      begin
        normalize_rows(db.execute(sql))
      ensure
        db.close
      end
    end
  end

  # The table contains a single row
  def single_table(table_name, sql_suffix = nil)
    execute(["SELECT * FROM #{table_name}", sql_suffix, 'LIMIT 1'].compact.join(' ')).first
  end

  def full_table(table_name, sql_suffix = nil)
    execute(["SELECT * FROM #{table_name}", sql_suffix].compact.join(' '))
  end

  private

  def normalize_rows(rows)
    rows.map{ |r| r.transform_keys(&:to_s)}
  end
end

module Aspera
  module Sync
    # Access `async` sqlite database
    class Database
      def initialize(db_path)
        @db = SqLite3Wrapper.new(db_path)
      end

      def overview
        tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables.flat_map do |table_row|
          table_name = table_row['name']
          @db.execute("PRAGMA table_info(#{table_name});").map do |col|
            {'table' => table_name}.merge(col)
          end
        end
      end

      def meta(sql_suffix = nil)
        @db.single_table('sync_snapmeta_table', sql_suffix)
      end

      def counters(sql_suffix = nil)
        @db.single_table('sync_snap_counters_table', sql_suffix)
      end

      def file_info(sql_suffix = nil)
        @db.full_table('sync_snapdb_table', sql_suffix)
      end

      def execute(sql)
        @db.execute(sql)
      end
    end
  end
end
