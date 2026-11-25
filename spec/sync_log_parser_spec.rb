# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require 'tempfile'
require_relative '../lib/aspera/sync/log_parser'

RSpec.describe(Aspera::Sync::LogParser) do
  # Representative `async` log lines, one notable event per interesting case, plus lines that must be skipped.
  let(:lines) do
    [
      '2026-11-24 20:50:54.008 [d4fc-1] LOG [Sync_reporter] SYNC SESSION START id=s1 name=demo op=bidi snapdb=0 local=/data/L dest=/ peer=host user=xfer',
      '2026-11-24 20:50:55.000 [d4fc-1] LOG [Sync_reporter] SYNC FILE STOP id=s1 name=demo path="/ok.txt" type=file nid=1 mtime=0 size=0 status=SYNCHRONIZED',
      '2026-11-24 20:50:55.500 [d4fc-1] LOG [Sync_reporter] SYNC FILE STOP id=s1 name=demo path="/exists.txt" type=file nid=1 mtime=0 size=0 status=SYNCHRONIZED(exs)',
      '2026-11-24 20:50:56.155 [d4fc-2] ERR Too many management channels requested (max 32).',
      '2026-11-24 20:50:57.000 [d4fc-1] LOG [Sync_reporter] SYNC SESSION STATS id=s1 name=demo scan f/u=0/0 progress t/p=6/0',
      '2026-11-24 20:51:01.275 [d4fc-1] LOG [Sync_reporter] SYNC FILE STOP id=s1 name=demo path="/d.txt" type=file nid=1 mtime=0 size=0 status=CONFLICT',
      "2026-11-24 20:51:01.401 [d4fc-3] ERR [Sync_algo/0] Process_peer_resp_cont_conf: SS_HALF_CONFLICT -> SS_CONFLICT. ui=[#{'x' * 400}]",
      '2026-11-24 20:51:02.000 [d4fc-1] LOG [Sync_reporter] SYNC FILE STOP id=s1 name=demo path="/bad.txt" type=file nid=0 mtime=0 size=0 status=ERROR',
      '2026-11-24 20:51:03.000 [d4fc-4] ERR Unsupported file system event',
      '2026-11-24 20:51:04.000 [d4fc-1] LOG [Sync_reporter] SYNC SESSION IDLE id=s1 name=demo status=success',
      '2026-11-24 20:51:14.984 [d4fc-1] LOG [Sync_reporter] SYNC SESSION STOP id=s1 name=demo status=ok paths=-',
      '2026-11-24 20:51:15.000 [d4fc-1] LOG FASP Manager: not a SYNC line',
      'a line with no timestamp prefix at all'
    ]
  end

  # @yield [path] a readable file containing the fixture lines
  def with_log_file
    file = Tempfile.new(['async', '.log'])
    file.write("#{lines.join("\n")}\n")
    file.close
    yield(file.path)
  ensure
    file&.unlink
  end

  describe '.notable_events' do
    it 'keeps conflicts, errors, unsupported events and session lifecycle, and skips the rest' do
      expected = ['session start', 'error', 'file conflict', 'error', 'file error', 'unsupported-event', 'session idle', 'session stop']
      with_log_file do |path|
        expect(described_class.notable_events([path]).map { |e| e['kind'] }).to(eq(expected))
      end
    end

    it 'extracts session, path and status of a file conflict' do
      with_log_file do |path|
        conflict = described_class.notable_events([path]).find { |e| e['kind'].eql?('file conflict') }
        expect(conflict).to(include('session' => 'demo', 'path' => '/d.txt', 'status' => 'CONFLICT', 'level' => 'LOG'))
      end
    end

    it 'reads op and local path of a session start' do
      with_log_file do |path|
        start = described_class.notable_events([path]).find { |e| e['kind'].eql?('session start') }
        expect(start).to(include('session' => 'demo', 'path' => '/data/L', 'status' => 'bidi'))
      end
    end

    it 'truncates a long detail to the maximum' do
      with_log_file do |path|
        long = described_class.notable_events([path]).find { |e| e['detail']&.include?('SS_CONFLICT') }
        expect(long['detail'].length).to(eq(Aspera::Sync::LogParser::DETAIL_MAX + 1)) # the ellipsis
        expect(long['detail']).to(end_with('…'))
      end
    end

    it 'sorts events across files by time' do
      with_log_file do |path|
        times = described_class.notable_events([path, path]).map { |e| e['time'] }
        expect(times).to(eq(times.sort))
      end
    end

    it 'keeps only async*.log files when given a folder' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'async.log'), "#{lines.join("\n")}\n")
        File.write(File.join(dir, 'other.log'), "#{lines.join("\n")}\n")
        # only the async.log is read: the 8 notable events, not 16
        expect(described_class.notable_events([dir]).size).to(eq(8))
      end
    end
  end

  describe '.default_log_paths' do
    it 'returns an array of existing files' do
      expect(described_class.default_log_paths).to(be_a(Array))
      expect(described_class.default_log_paths.all? { |path| File.file?(path) }).to(be(true))
    end
  end
end
