# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Tests for the daemon started by the agent (Product): API key, configuration file, port, start and stop.
# The gRPC stub and the start of the daemon are doubled: no daemon required. Requires the optional gem grpc.

require 'bundler/setup'
begin
  require_relative '../product'
  require_relative '../agent'
rescue LoadError, Aspera::BundleRegistry::Unavailable => e
  warn("Skipping transferd daemon specs: #{e.message}")
  return
end
require 'tmpdir'
require 'json'

RSpec.describe(Aspera::Plugins::Transferd::Product) do
  let(:tmp_dir) { Dir.mktmpdir('transferd_daemon') }

  describe '.daemon_api_key' do
    it 'uses the key given' do
      expect(described_class.daemon_api_key('<API_KEY>', stop: true)).to(eq('<API_KEY>'))
      expect(described_class.daemon_api_key('<API_KEY>', stop: false)).to(eq('<API_KEY>'))
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

  describe 'Aspera::Products::Transferd.daemon_port_from_log' do
    let(:log_file) { File.join(tmp_dir, 'transferd.out') }

    it 'reads the port of the last line of the API server' do
      File.write(log_file, "Info: API Server: Listening on 127.0.0.1:55002 (x)\nother\nInfo: API Server: Listening on 127.0.0.1:55003 (x)\n")
      expect(Aspera::Products::Transferd.daemon_port_from_log(log_file)).to(eq(55_003))
    end

    it 'gives nil when the log has no port (not listening yet)' do
      File.write(log_file, "other\n")
      expect(Aspera::Products::Transferd.daemon_port_from_log(log_file)).to(be_nil)
    end
  end

  describe 'Aspera::Products::Transferd.daemon_port_from_file' do
    # Folder with characters of a glob pattern: not used as a pattern
    let(:runtime_dir) { File.join(tmp_dir, 'run[1]*').tap { |dir| Dir.mkdir(dir) } }

    it 'reads the port of the file' do
      File.write(File.join(runtime_dir, 'transferd.55005.optport'), '55005')
      expect(Aspera::Products::Transferd.daemon_port_from_file(runtime_dir)).to(eq(55_005))
    end

    it 'gives nil when there is no file, or no folder' do
      File.write(File.join(runtime_dir, 'other'), '55005')
      expect(Aspera::Products::Transferd.daemon_port_from_file(runtime_dir)).to(be_nil)
      expect(Aspera::Products::Transferd.daemon_port_from_file(File.join(tmp_dir, 'missing'))).to(be_nil)
    end

    it 'gives nil while the file is being written (empty)' do
      File.write(File.join(runtime_dir, 'transferd.55005.optport'), '')
      expect(Aspera::Products::Transferd.daemon_port_from_file(runtime_dir)).to(be_nil)
    end

    it 'fails when the file has no port' do
      File.write(File.join(runtime_dir, 'transferd.55005.optport'), 'abc')
      expect { Aspera::Products::Transferd.daemon_port_from_file(runtime_dir) }.to(raise_error(Aspera::AssertError, /No port in file .*transferd\.55005\.optport/))
    end

    it 'fails when there are several files' do
      File.write(File.join(runtime_dir, 'transferd.55005.optport'), '55005')
      File.write(File.join(runtime_dir, 'transferd.55006.optport'), '55006')
      expect { Aspera::Products::Transferd.daemon_port_from_file(runtime_dir) }.to(raise_error(Aspera::AssertError, /Several port files/))
    end
  end

  describe '#initialize' do
    let(:base) { File.join(tmp_dir, 'transferd') }

    before do
      allow(Aspera::Products::Transferd).to(receive(:sdk_directory).and_return(tmp_dir))
      allow(Aspera::Ascp::Installation.instance).to(receive(:path).with(:transferd).and_return(File.join(tmp_dir, 'asperatransferd')))
      allow(Aspera::TempFileManager.instance).to(receive(:new_file_path_global).with('transferd').and_return(base))
      allow(Aspera::Environment).to(receive(:secure_execute).and_return(12_345))
    end

    it 'fails when the daemon exits during its initialization, and deletes the folder of its port file' do
      allow(::Process).to(receive(:wait2).with(12_345).and_return([12_345, instance_double(::Process::Status, exitstatus: 3)]))
      expect { described_class.new(address: '127.0.0.1', port: 0, api_key: '<API_KEY>', stop: true) }
        .to(raise_error(RuntimeError, /exited with status 3\. Check files: #{Regexp.escape(base)}\.out and #{Regexp.escape(base)}\.err/))
      expect(File).not_to(exist("#{base}.run"))
    end

    it 'gives the port of its log (transferd before 1.1.7), and the API key of its configuration' do
      allow(::Process).to(receive(:wait2).with(12_345).and_raise(Timeout::Error))
      daemon = described_class.new(address: '127.0.0.1', port: 0, api_key: '<API_KEY>', stop: true)
      File.write("#{base}.out", "Info: API Server: Listening on 127.0.0.1:55004 (x)\n")
      expect(daemon.listen_port).to(eq(55_004))
      expect(daemon.api_key).to(eq('<API_KEY>'))
      expect(daemon.pid).to(eq(12_345))
      expect(JSON.parse(File.read("#{base}.conf"))).to(include('address' => '127.0.0.1', 'port' => 0, 'authentication' => {'enabled' => true, 'api_key' => '<API_KEY>'}))
    end

    it 'gives the port of its port file, in a folder of its own, deleted when stopped' do
      allow(::Process).to(receive(:wait2).with(12_345).and_raise(Timeout::Error))
      daemon = described_class.new(address: '127.0.0.1', port: 0, api_key: '<API_KEY>', stop: true)
      runtime_dir = "#{base}.run"
      expect(JSON.parse(File.read("#{base}.conf"))).to(include('runtime_dir' => runtime_dir))
      expect(File.stat(runtime_dir).mode & 0o777).to(eq(0o700)) unless Gem.win_platform?
      # Not listening yet: neither file nor log
      File.write("#{base}.out", '')
      expect(daemon.listen_port).to(be_nil)
      # The file, written before the log, has precedence
      File.write(File.join(runtime_dir, 'transferd.55007.optport'), '55007')
      File.write("#{base}.out", "Info: API Server: Listening on 127.0.0.1:55004 (x)\n")
      expect(daemon.listen_port).to(eq(55_007))
      allow(::Process).to(receive(:kill).with(:KILL, 12_345))
      allow(::Process).to(receive(:wait2).with(12_345).and_return([12_345, instance_double(::Process::Status)]))
      daemon.stop
      expect(File).not_to(exist(runtime_dir))
    end

    it 'has no folder for a port file with a port given' do
      allow(::Process).to(receive(:wait2).with(12_345).and_raise(Timeout::Error))
      daemon = described_class.new(address: '127.0.0.1', port: 55_002, api_key: '<API_KEY>', stop: true)
      expect(JSON.parse(File.read("#{base}.conf"))).not_to(have_key('runtime_dir'))
      expect(File).not_to(exist("#{base}.run"))
      expect { daemon.listen_port }.to(raise_error(Aspera::AssertError, /not started with port zero/))
    end
  end
end

RSpec.describe(Aspera::Plugins::Transferd::Agent) do
  let(:api) { Transferd::Api }
  let(:url) { '127.0.0.1:55002' }
  let(:tmp_dir) { Dir.mktmpdir('transferd_daemon') }

  describe '#initialize' do
    # Process that stands for the daemon: killed by `shutdown`
    let(:daemon_pid) { ::Process.spawn('sleep', '60') }
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
      allow(::Process).to(receive(:wait2).with(daemon_pid).and_raise(Timeout::Error))
    end

    after do
      allow(::Process).to(receive(:wait2).and_call_original)
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
        interceptors.first.instance_variable_get(:@api_key).eql?('<API_KEY>') && started.empty? ? offline : daemon
      end
      agents.push(described_class.new(url: ':55002', api_key: '<API_KEY>'))
      expect(started.dig('config', 'authentication')).to(eq('enabled' => true, 'api_key' => '<API_KEY>'))
    end

    it 'refuses an address without port, before starting the daemon' do
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('localhost', :this_channel_is_insecure).and_return(offline))
      expect { described_class.new(url: 'localhost') }.to(raise_error(Aspera::ParameterError, 'Invalid address of daemon: localhost, expecting <ADDRESS>:<PORT> or :<PORT>'))
      expect(started).to(be_empty)
    end

    it 'stops the daemon started here on shutdown' do
      agents.push(described_class.new(url: ':55002'))
      expect(started.dig('config', 'port')).to(eq(55_002))
      allow(::Process).to(receive(:wait2).and_call_original)
      agents.first.shutdown
      expect { ::Process.kill(0, daemon_pid) }.to(raise_error(Errno::ESRCH))
    end

    it 'retries the connection until the daemon started answers (e.g. first start of its executable)' do
      attempts = 0
      allow(daemon).to(receive(:get_info)) do |_request, deadline:|
        expect(deadline).to(be_within(2).of(Time.now + 10))
        attempts += 1
        raise GRPC::Unavailable, 'failed to connect to all addresses' if attempts < 3
        info
      end
      allow(Aspera::Log.log).to(receive(:warn))
      agents.push(described_class.new(url: ':55002'))
      expect(attempts).to(eq(3))
      expect(agents.first.daemon_endpoint).to(eq(url))
      expect(Aspera::Log.log).to(have_received(:warn).with('no daemon present, starting daemon...'))
    end

    it 'fails with the files of its logs when the daemon started does not answer' do
      stub_const('Aspera::Plugins::Transferd::Agent::START_TIMEOUT_SEC', 0.3)
      allow(daemon).to(receive(:get_info).and_raise(GRPC::Unavailable.new('failed to connect to all addresses')))
      allow(Aspera::Log.log).to(receive(:warn))
      base = File.join(tmp_dir, 'transferd')
      # The daemon started is stopped on exit (`at_exit` of the agent)
      expect { described_class.new(url: ':55002') }.to(raise_error(
        Aspera::Transfer::Error,
        /\ATransfer daemon started with PID #{daemon_pid} does not answer on #{url} after 0.3 seconds \(Unavailable: failed to connect to all addresses\)\. Check files: #{Regexp.escape(base)}\.out and #{Regexp.escape(base)}\.err\z/
      ))
    end

    it 'reads the port of the daemon started with port zero in its port file, deleted on shutdown' do
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('127.0.0.1:0', :this_channel_is_insecure).and_return(offline))
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('127.0.0.1:55011', :this_channel_is_insecure, interceptors: anything).and_return(daemon))
      # The daemon writes its port file in its `runtime_dir`
      allow(Aspera::Environment).to(receive(:secure_execute)) do |_exe, _option, conf_file, **_kwargs|
        started['config'] = JSON.parse(File.read(conf_file))
        File.write(File.join(started.dig('config', 'runtime_dir'), 'transferd.55011.optport'), '55011')
        daemon_pid
      end
      allow(Aspera::Log.log).to(receive(:warn))
      agents.push(described_class.new)
      expect(agents.first.daemon_endpoint).to(eq('127.0.0.1:55011'))
      expect(started.dig('config', 'runtime_dir')).to(eq(File.join(tmp_dir, 'transferd.run')))
      allow(::Process).to(receive(:wait2).and_call_original)
      agents.first.shutdown
      expect(File).not_to(exist(File.join(tmp_dir, 'transferd.run')))
    end

    it 'fails at once, without waiting, when the port files of the daemon started with port zero are not valid' do
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('127.0.0.1:0', :this_channel_is_insecure).and_return(offline))
      allow(Aspera::Environment).to(receive(:secure_execute)) do |_exe, _option, conf_file, **_kwargs|
        runtime_dir = JSON.parse(File.read(conf_file))['runtime_dir']
        File.write(File.join(runtime_dir, 'transferd.55011.optport'), '55011')
        File.write(File.join(runtime_dir, 'transferd.55012.optport'), '55012')
        daemon_pid
      end
      allow(Aspera::Log.log).to(receive(:warn))
      started_at = Time.now
      expect { described_class.new }.to(raise_error(Aspera::AssertError, /Several port files/))
      expect(Time.now - started_at).to(be < 1)
    end

    it 'waits for the port of the daemon started with port zero in its log (transferd before 1.1.7)' do
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('127.0.0.1:0', :this_channel_is_insecure).and_return(offline))
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with('127.0.0.1:55010', :this_channel_is_insecure, interceptors: anything).and_return(daemon))
      reads = 0
      allow(Aspera::Products::Transferd).to(receive(:daemon_port_from_log).with(File.join(tmp_dir, 'transferd.out'))) do
        reads += 1
        # Not listening yet on first read
        reads > 1 ? 55_010 : nil
      end
      allow(Aspera::Log.log).to(receive(:warn))
      agents.push(described_class.new)
      expect(reads).to(eq(2))
      expect(agents.first.daemon_endpoint).to(eq('127.0.0.1:55010'))
      expect(started.dig('config', 'port')).to(eq(0))
    end

    it 'starts a daemon left running with an information, not a warning' do
      allow(Transferd::Api::TransferService::Stub).to(receive(:new).with(url, :this_channel_is_insecure, interceptors: anything)) do
        started.empty? ? offline : daemon
      end
      allow(Aspera::Log.log).to(receive_messages(info: nil, warn: nil))
      agents.push(described_class.new(url: '127.0.0.1:55002', stop: false, api_key: '<API_KEY>'))
      expect(Aspera::Log.log).to(have_received(:info).with('no daemon present, starting daemon...'))
      expect(Aspera::Log.log).not_to(have_received(:warn).with('no daemon present, starting daemon...'))
    ensure
      # Left running by the agent
      ::Process.kill(:KILL, daemon_pid)
    end
  end
end
