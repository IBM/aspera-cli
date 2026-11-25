# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# `config agents jobs list|status|cleanup` and the deprecated alias `config transfer ...`: same commands, no server needed.

require 'spec_helper'
require_relative '../../../cli/info'
require_relative '../../../persistency_folder'
require_relative '../async_transfer_store'
require 'open3'
require 'rbconfig'
require 'socket'
require 'tmpdir'
require 'json'

RSpec.describe('config agents jobs') do
  let(:source_root) { File.expand_path('../../../../..', __dir__) }

  # @param args [Array<String>] Arguments of the command line
  # @param jobs [Array<Hash>]   Jobs saved before the command
  def run_cli(*args, jobs: [])
    Dir.mktmpdir do |home|
      store = Aspera::Plugins::Xfer::AsyncTransferStore.new(Aspera::PersistencyFolder.new(File.join(home, 'persist_store')))
      jobs.each { |job| store.write(job['job_id'], job) }
      cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Aspera::Cli::Info::CMD_NAME), *args, '--version-check-days=0']
      stdout, stderr, status = Open3.capture3({'ASCLI_HOME' => home}, *cmd)
      [stdout, stderr, status]
    end
  end

  it 'lists jobs, with no deprecation warning' do
    stdout, stderr, status = run_cli('config', 'agents', 'jobs', 'list', '--format=json')
    expect(status.exitstatus).to(eq(0), stderr)
    expect(JSON.parse(stdout)).to(eq([]))
    expect(stderr).not_to(include('deprecated'))
  end

  describe 'job of a daemon not running' do
    # Port of no daemon: free after its server is closed
    let(:port) { TCPServer.open('127.0.0.1', 0).then { |server| server.addr[1].tap { server.close } } }
    let(:job) do
      {
        'job_id' => 'job1', 'agent_type' => 'transferd', 'transfer_id' => 'tid', 'agent_params' => {'url' => ":#{port}"},
        'status' => 'running', 'bytes_transferred' => 1024, 'started_at' => '2026-11-23T10:00:00Z', 'ended_at' => nil, 'error' => nil
      }
    end

    before do
      require 'grpc'
    rescue LoadError => e
      skip("requires gem grpc: #{e.message}")
    end

    it 'lists the saved status, with a warning' do
      stdout, stderr, status = run_cli('config', 'agents', 'jobs', 'list', '--format=json', jobs: [job])
      expect(status.exitstatus).to(eq(0), stderr)
      expect(JSON.parse(stdout)).to(eq([job]))
      expect(stderr).to(include('Status not refreshed for job job1: Unavailable: '))
    end

    it 'shows the saved status with the error' do
      stdout, stderr, status = run_cli('config', 'agents', 'jobs', 'status', 'job1', '--format=json', jobs: [job])
      expect(status.exitstatus).to(eq(0), stderr)
      expect(JSON.parse(stdout)).to(include('status' => 'running', 'bytes_transferred' => 1024, 'error' => a_string_starting_with('Unavailable: ')))
    end
  end

  it 'refuses an unknown job' do
    _stdout, stderr, status = run_cli('config', 'agents', 'jobs', 'status', 'bad-job')
    expect(status.exitstatus).not_to(eq(0))
    expect(stderr).to(include('Unknown job_id: bad-job'))
  end

  describe 'deprecated config transfer' do
    it 'still lists jobs, with a deprecation warning' do
      stdout, stderr, status = run_cli('config', 'transfer', 'list', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(JSON.parse(stdout)).to(eq([]))
      expect(stderr).to(include('Command config transfer is deprecated after'))
    end

    it 'runs the same commands' do
      _stdout, stderr, status = run_cli('config', 'transfer', 'status', 'bad-job')
      expect(status.exitstatus).not_to(eq(0))
      expect(stderr).to(include('Unknown job_id: bad-job'))
    end

    it 'shows deprecation in the list of commands' do
      stdout, stderr, status = run_cli('config', 'commands', 'config', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      rows = JSON.parse(stdout)
      expect(rows.find { |r| r['syntax'].start_with?('config transfer ') }['description']).to(include('deprecated after 4.28.0: use agents jobs'))
      expect(rows.map { |r| r['syntax'] }).to(include('config agents jobs list', 'config agents jobs status <job_id>', 'config agents jobs cleanup'))
    end
  end
end
