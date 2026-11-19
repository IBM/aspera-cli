# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Ascp::LogLocations: location of the `ascp` log files of the local system.

require_relative '../lib/aspera/ascp/log_locations'
require 'bundler/setup'
require 'tmpdir'
require 'fileutils'
require 'zlib'

RSpec.describe(Aspera::Ascp::LogLocations) do
  let(:ascp_line) { "2026-09-24 09:45:52.311 [518a-5406707] LOG Initializing FASP version 4.4.8.2592, license max rate=(unlimited)\n" }
  let(:other_line) { "2026-09-24 09:45:52.311 INFO daemon started\n" }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def write(path, content, mtime: nil)
    path = File.join(@dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    File.utime(mtime, mtime, path) if mtime
    path
  end

  # Product installed in `<dir>/<name>`, with `ascp` in `bin`
  def product(name, log_root: nil, conf_log: nil)
    app_root = File.join(@dir, name)
    ascp = write("#{name}/bin/ascp", '')
    write("#{name}/etc/aspera.conf", "<CONF version=\"2\"><default><logging><directory>#{conf_log}</directory></logging></default></CONF>") if conf_log
    {name: name, app_root: app_root, ascp_path: ascp, log_root: log_root}
  end

  def paths(rows)
    rows.map { |row| row['path'].delete_prefix("#{@dir}/") }
  end

  before { allow(ENV).to(receive(:fetch).and_call_original) && allow(ENV).to(receive(:fetch).with('PATH', '').and_return('')) }

  it 'finds ascp log files in the log folder of a product, most recent first, without other log files' do
    write('logs/aspera-scp-transfer.0.log', ascp_line, mtime: Time.at(1_000))
    write('logs/aspera-scp-transfer.1.log', ascp_line, mtime: Time.at(2_000))
    write('logs/ascp4.0.log.gz', Zlib.gzip(ascp_line))
    write('logs/transferd.log', ascp_line)
    rows = described_class.find([product('desk', log_root: File.join(@dir, 'logs'))], defaults: [])
    expect(paths(rows)).to(eq(%w[logs/ascp4.0.log.gz logs/aspera-scp-transfer.1.log logs/aspera-scp-transfer.0.log]))
    expect(rows.first).to(include('source' => 'desk', 'size' => File.size(File.join(@dir, 'logs/ascp4.0.log.gz'))))
  end

  it 'keeps only one of a file and its hard link, and of a folder given twice' do
    current = write('logs/aspera-scp-transfer.0.log', ascp_line)
    File.link(current, File.join(@dir, 'logs/aspera-scp-transfer.log'))
    folder = File.join(@dir, 'logs')
    rows = described_class.find([product('a', log_root: folder)], defaults: [[folder, 'default']])
    expect(rows.length).to(eq(1))
    expect(rows.first['source']).to(eq('default'))
  end

  it 'finds the folder of <logging><directory> of aspera.conf and the var/log folder of the product' do
    write('conf_logs/aspera-scp-transfer.0.log', ascp_line)
    write('hsts/var/log/aspera-scp-transfer.0.log', ascp_line)
    rows = described_class.find([product('hsts', conf_log: File.join(@dir, 'conf_logs'))], defaults: [])
    expect(paths(rows)).to(contain_exactly('conf_logs/aspera-scp-transfer.0.log', 'hsts/var/log/aspera-scp-transfer.0.log'))
  end

  it 'keeps syslog files and their rotations only if they contain ascp lines' do
    write('messages', "#{other_line}Oct 25 00:02:20 host ascp[1369]: LOG FASP Session Start\n")
    write('messages-20261101.gz', Zlib.gzip(other_line))
    write('syslog', other_line)
    rows = described_class.find([], defaults: [[File.join(@dir, 'messages'), 'syslog'], [File.join(@dir, 'syslog'), 'syslog']])
    expect(paths(rows)).to(eq(%w[messages]))
  end

  it 'finds ascp of PATH that is not an installed product' do
    write('other/var/log/aspera-scp-transfer.0.log', ascp_line)
    write('other/bin/ascp', '')
    allow(ENV).to(receive(:fetch).with('PATH', '').and_return(File.join(@dir, 'other', 'bin')))
    rows = described_class.find([], defaults: [])
    expect(rows.map { |row| row['source'] }).to(eq([described_class::PATH_SOURCE]))
  end

  it 'ignores missing locations' do
    expect(described_class.find([], defaults: [[File.join(@dir, 'none'), 'x'], [File.join(@dir, 'none.log'), 'y']])).to(be_empty)
  end

  describe '.ascp_log_location' do
    def os(value)
      allow(Aspera::Environment.instance).to(receive(:os).and_return(value))
    end

    it 'gives <default><logging><directory> of aspera.conf first' do
      os(Aspera::Environment::OS_LINUX)
      conf = write('etc/aspera.conf', '<CONF version="2"><default><logging><directory>/logs</directory></logging></default></CONF>')
      expect(described_class.ascp_log_location('/x/ascp', conf_file: conf)).to(eq('/logs'))
    end

    it 'gives syslog on Linux' do
      os(Aspera::Environment::OS_LINUX)
      expect(described_class.ascp_log_location('/x/ascp', conf_file: File.join(@dir, 'none.conf'))).to(eq(described_class::SYSLOG))
    end

    it 'gives ~/Library/Logs/Aspera on macOS' do
      os(Aspera::Environment::OS_MACOS)
      expect(described_class.ascp_log_location('/x/ascp')).to(eq(File.join(Dir.home, 'Library', 'Logs', 'Aspera')))
    end

    it 'gives var/log of the root on Windows if it exists, else the folder of ascp' do
      os(Aspera::Environment::OS_WINDOWS)
      ascp = write('sdk/ascp.exe', '')
      root = File.join(@dir, 'sdk')
      expect(described_class.ascp_log_location(ascp, root: root)).to(eq(root))
      FileUtils.mkdir_p(File.join(root, 'var', 'log'))
      expect(described_class.ascp_log_location(ascp, root: root)).to(eq(File.join(root, 'var', 'log')))
    end
  end
end
