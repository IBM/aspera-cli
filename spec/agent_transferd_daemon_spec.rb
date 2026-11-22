# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tests for the daemon started by Agent::Transferd: API key and configuration file.
# The gRPC stub and the start of the daemon are doubled: no daemon required. Requires the optional gem grpc.

require 'bundler/setup'
begin
  require_relative '../lib/aspera/agent/transferd'
rescue LoadError => e
  warn("Skipping Agent::Transferd daemon specs: #{e.message}")
  return
end
require 'tmpdir'
require 'json'

RSpec.describe(Aspera::Agent::Transferd) do
  let(:api) { Transferd::Api }
  let(:url) { '127.0.0.1:55002' }
  let(:tmp_dir) { Dir.mktmpdir('transferd_daemon') }

  describe '.daemon_api_key' do
    it 'uses the key given' do
      expect(described_class.daemon_api_key('KEY', stop: true)).to(eq('KEY'))
      expect(described_class.daemon_api_key('KEY', stop: false)).to(eq('KEY'))
    end

    it 'generates a different random key for each daemon stopped on exit' do
      keys = Array.new(2) { described_class.daemon_api_key(nil, stop: true) }
      expect(keys).to(all(match(/\A\h{64}\z/)))
      expect(keys.uniq.size).to(eq(2))
    end

    it 'gives no key, with a warning, for a daemon left running' do
      expect(Aspera::Log.log).to(receive(:warn).with(/without authentication/))
      expect(described_class.daemon_api_key(nil, stop: false)).to(be_nil)
    end
  end

  describe '.write_config' do
    it 'creates the file readable only by the user' do
      path = File.join(tmp_dir, 'daemon.conf')
      described_class.write_config(path, {port: 1})
      expect(JSON.parse(File.read(path))).to(eq('port' => 1))
      expect(File.stat(path).mode & 0o777).to(eq(0o600)) unless Gem.win_platform?
    end

    it 'does not write in an existing file or link' do
      target = File.join(tmp_dir, 'target')
      File.write(target, 'unchanged')
      path = File.join(tmp_dir, 'daemon.conf')
      File.symlink(target, path)
      expect { described_class.write_config(path, {port: 1}) }.to(raise_error(Errno::EEXIST))
      expect(File.read(target)).to(eq('unchanged'))
    end
  end

  describe '#initialize' do
    # Process that stands for the daemon: killed by `shutdown`
    let(:daemon_pid) { Process.spawn('sleep', '60') }
    let(:offline) { instance_double(Transferd::Api::TransferService::Stub) }
    let(:daemon) { instance_double(Transferd::Api::TransferService::Stub) }
    let(:info) { api::InstanceInfoResponse.new(apiVersion: 'v1') }
    # Configuration of the daemon, and mode of its file, when it is started
    let(:started) { {} }
    # API keys sent by the clients of the daemon started
    let(:sent_keys) { [] }
    # Agents created, shut down after each example
    let(:agents) { [] }

    before do
      allow(Aspera::Products::Transferd).to(receive(:sdk_directory).and_return(tmp_dir))
      allow(Aspera::Ascp::Installation.instance).to(receive(:path).with(:transferd).and_return(File.join(tmp_dir, 'asperatransferd')))
      allow(Aspera::TempFileManager.instance).to(receive(:new_file_path_global).with('transferd').and_return(File.join(tmp_dir, 'transferd')))
      # First connection: no daemon yet
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with(url, :this_channel_is_insecure).and_return(offline))
      allow(offline).to(receive(:get_info).and_raise(GRPC::Unavailable.new('failed to connect to all addresses')))
      # Connection to the daemon started, with the API key
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with(url, :this_channel_is_insecure, interceptors: anything)) do |*_args, interceptors:|
        sent_keys.concat(interceptors.map { |i| i.instance_variable_get(:@api_key) })
        daemon
      end
      allow(daemon).to(receive(:get_info).and_return(info))
      allow(Aspera::Environment).to(receive(:secure_execute)) do |_exe, _option, conf_file, **_kwargs|
        started['config'] = JSON.parse(File.read(conf_file))
        started['mode'] = File.stat(conf_file).mode & 0o777
        daemon_pid
      end
      # The daemon does not exit within the delay
      allow(Process).to(receive(:wait2).with(daemon_pid).and_raise(Timeout::Error))
    end

    after do
      allow(Process).to(receive(:wait2).and_call_original)
      agents.each(&:shutdown)
    end

    it 'starts the daemon with a random API key, sent in each call' do
      agents.push(described_class.new(url: ':55002'))
      auth = started.dig('config', 'authentication')
      expect(auth).to(include('enabled' => true, 'api_key' => match(/\A\h{64}\z/)))
      expect(started['mode']).to(eq(0o600)) unless Gem.win_platform?
      expect(sent_keys).to(eq([auth['api_key']]))
    end

    it 'starts the daemon with the API key given' do
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with(url, :this_channel_is_insecure, interceptors: anything)) do |*_args, interceptors:|
        # Before the start (no daemon), then after
        interceptors.first.instance_variable_get(:@api_key).eql?('KEY') && started.empty? ? offline : daemon
      end
      agents.push(described_class.new(url: ':55002', api_key: 'KEY'))
      expect(started.dig('config', 'authentication')).to(eq('enabled' => true, 'api_key' => 'KEY'))
    end
  end
end
