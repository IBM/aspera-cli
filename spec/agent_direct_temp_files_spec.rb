# frozen_string_literal: true

# Unit tests for Aspera::Agent::Direct: the temporary files of `ascp` (file list) exist until the end of the transfer,
# also after the end of the command (asynchronous transfer, MCP server), and are deleted then.
# `ascp` is not started: start_and_monitor_process is replaced by a wait.

require 'bundler/setup'
require 'tmpdir'
require 'aspera/agent/direct'
require 'aspera/temp_file_manager'
require 'aspera/transfer/parameters'

RSpec.describe(Aspera::Agent::Direct) do
  let(:manager) { Aspera::TempFileManager.instance }
  let(:agent) { described_class.new(spawn_delay_sec: 0) }
  let(:transfer_spec) do
    {
      'direction' => 'send', 'remote_host' => 'host.example.com', 'remote_user' => 'xfer',
      'paths' => [{'source' => '/src/a.txt'}, {'source' => '/src/b.txt'}]
    }
  end
  # each simulated `ascp` waits for one element
  let(:proceed) { Queue.new }

  around(:each) do |example|
    previous = Aspera::Transfer::Parameters.instance_variable_get(:@file_list_folder)
    Dir.mktmpdir do |dir|
      Aspera::Transfer::Parameters.file_list_folder = dir
      example.run
    ensure
      Aspera::Transfer::Parameters.instance_variable_set(:@file_list_folder, previous)
    end
  end

  before { allow(agent).to(receive(:start_and_monitor_process)) { proceed.pop } }

  after { manager.cleanup }

  # @return [String] path of the file list of the first session of the job
  def file_list_of(job_id)
    agent.sessions_by_job(job_id).first[:exec_spec].temp_files.first
  end

  it 'keeps the file list after the end of the command, until the session ends' do
    job_id = agent.start_transfer(transfer_spec)
    file_list = file_list_of(job_id)
    expect(File.read(file_list)).to(eq("/src/a.txt\n/src/b.txt"))
    # end of the command, as done by the runner
    manager.cleanup
    expect(File.file?(file_list)).to(be(true))
    proceed.push(:done)
    agent.wait_for_transfers_completion
    expect(File.exist?(file_list)).to(be(false))
  end

  it 'deletes the file list when the last session of a multi-session transfer ends' do
    job_id = agent.start_transfer(transfer_spec.merge('multi_session' => 2))
    file_list = file_list_of(job_id)
    threads = agent.sessions_by_job(job_id).map { |session| session[:thread] }
    expect(threads.size).to(eq(2))
    proceed.push(:done)
    # wait for one session to end
    50.times do
      break if threads.any? { |thread| !thread.alive? }
      sleep(0.1)
    end
    expect(threads.count(&:alive?)).to(eq(1))
    expect(File.file?(file_list)).to(be(true))
    proceed.push(:done)
    agent.wait_for_transfers_completion
    expect(File.exist?(file_list)).to(be(false))
  end
end
