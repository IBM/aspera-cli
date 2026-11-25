# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require 'tempfile'
begin
  require_relative '../lib/aspera/sync/database'
rescue LoadError => e
  warn("Skipping sync database specs: #{e.message}")
  return
end

RSpec.describe(Aspera::Sync::Database) do
  # Create a small sqlite database with one table and one row, with the driver of the platform (as `lib/aspera/sync/database.rb`).
  def create_db(path)
    if defined?(JRUBY_VERSION)
      db = Sequel.connect("jdbc:sqlite:#{path}")
      db.run('CREATE TABLE t(x)')
      db.run('INSERT INTO t VALUES (1)')
      db.disconnect
    else
      db = SQLite3::Database.new(path)
      db.execute('CREATE TABLE t(x)')
      db.execute('INSERT INTO t VALUES (1)')
      db.close
    end
  end

  around do |example|
    file = Tempfile.new(['snap', '.db'])
    file.close
    create_db(file.path)
    @db = described_class.new(file.path)
    example.run
    file.unlink
  end

  it 'reads a query' do
    expect(@db.execute('SELECT x FROM t')).to(eq([{'x' => 1}]))
  end

  it 'opens the database read-only, so a query cannot modify it' do
    expect { @db.execute('UPDATE t SET x = 2') }.to(raise_error(/read.?only/i))
    # the value is unchanged
    expect(@db.execute('SELECT x FROM t')).to(eq([{'x' => 1}]))
  end

  it 'refuses VACUUM INTO (writing the content to a file) even though it only reads the database' do
    Dir.mktmpdir do |dir|
      out = File.join(dir, 'out.db')
      expect { @db.execute("VACUUM INTO '#{out}'") }.to(raise_error(/read.?only/i))
      # the copy is not completed (SQLite may create the empty destination before the read-only check)
      expect(File.size?(out)).to(satisfy { |size| size.nil? || size.zero? })
    end
  end
end
