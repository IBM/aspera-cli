# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'fileutils'
require 'aspera/cli/info'
require 'aspera/products/transferd_service'

RSpec.describe(Aspera::Products::TransferdService) do
  let(:root) { Dir.mktmpdir('transferd_commands') }
  let(:sdk_folder) { File.join(root, 'sdk') }
  let(:answers) { {} }
  let(:runner) { ->(*cmd) { answers.fetch(cmd, ['', true]) } }

  after { FileUtils.rm_rf(root) }

  def host_with(**kwargs)
    described_class::Host.new(root: root, runner: runner, listening: ->(_a, _p) { true }, **kwargs)
  end

  describe '.assert_supported' do
    it 'accepts Linux with systemctl as root' do
      expect { described_class.assert_supported(host_with(os: Aspera::Environment::OS_LINUX, euid: 0, systemctl: true)) }.not_to(raise_error)
    end

    it 'refuses a user who is not root' do
      host = host_with(os: Aspera::Environment::OS_LINUX, euid: 1000, systemctl: true)
      expect { described_class.assert_supported(host) }.to(raise_error(Aspera::Error, /as root/))
    end

    it 'refuses a host without systemctl' do
      host = host_with(os: Aspera::Environment::OS_LINUX, euid: 0, systemctl: false)
      expect { described_class.assert_supported(host) }.to(raise_error(Aspera::Error, /systemctl not found/))
    end

    it 'refuses another platform' do
      host = host_with(os: Aspera::Environment::OS_MACOS, euid: 0, systemctl: true)
      expect { described_class.assert_supported(host) }.to(raise_error(Aspera::Error, /Linux with systemd, this is: osx/))
    end

    it 'checks nothing with dry_run' do
      host = host_with(os: Aspera::Environment::OS_WINDOWS, euid: 1000, systemctl: false)
      expect { described_class.assert_supported(host, dry_run: true) }.not_to(raise_error)
    end
  end

  describe '.schema_version' do
    it 'is the version of transferd that the schema matches' do
      expect(described_class.schema_version).to(match(/\A\d+\.\d+\.\d+\z/))
    end
  end

  describe '.check_version' do
    before do
      FileUtils.mkdir_p(sdk_folder)
      FileUtils.touch(File.join(sdk_folder, 'transferd'))
      allow(Aspera::Log.log).to(receive(:warn))
    end

    def answer_version(version)
      answers[[File.join(sdk_folder, 'transferd'), 'version']] = ["transferd version #{version}\n", true]
    end

    it 'does not warn if the version is the one of the schema' do
      answer_version(described_class.schema_version)
      expect(described_class.check_version(sdk_folder, host: host_with)).to(be_nil)
      expect(Aspera::Log.log).not_to(have_received(:warn))
    end

    it 'warns if the SDK is newer' do
      answer_version('99.0.0')
      expect(described_class.check_version(sdk_folder, host: host_with)).to(include('99.0.0 is newer'))
      expect(Aspera::Log.log).to(have_received(:warn))
    end

    it 'warns if the SDK is older' do
      answer_version('0.0.1')
      expect(described_class.check_version(sdk_folder, host: host_with)).to(include('0.0.1 is older'))
    end

    it 'does nothing if the SDK is not installed' do
      expect(described_class.check_version(File.join(root, 'none'), host: host_with)).to(be_nil)
    end
  end
end

RSpec.describe('config transferd service commands') do
  let(:source_root) { File.expand_path('..', __dir__) }

  def run_cli(*args)
    Dir.mktmpdir do |home|
      cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Aspera::Cli::Info::CMD_NAME), *args, '--version-check-days=0']
      Open3.capture3({'ASCLI_HOME' => home}, *cmd)
    end
  end

  it 'refuses to run for real when not root or not on Linux with systemd' do
    skip('running as root') if Process.euid.zero?
    _stdout, stderr, status = run_cli('config', 'transferd', 'service', 'status')
    expect(status.exitstatus).not_to(eq(0))
    expect(stderr).to(match(/requires (Linux with systemd|systemd)|as root/))
  end

  it 'shows the actions of uninstall with --dry-run=yes on any platform' do
    stdout, stderr, status = run_cli('config', 'transferd', 'service', 'uninstall', '--dry-run=yes')
    expect(status.exitstatus).to(eq(0), stderr)
    expect(stdout + stderr).to(match(/Nothing to do|remove/))
  end

  it 'lists nothing useful but refuses versions without the layout' do
    Dir.mktmpdir do |folder|
      _stdout, stderr, status = run_cli('config', 'transferd', 'service', 'versions', "--sdk-folder=#{folder}")
      expect(status.exitstatus).not_to(eq(0))
      expect(stderr).to(include('must be named current'))
    end
  end

  it 'lists the versions of the layout' do
    Dir.mktmpdir do |prefix|
      FileUtils.mkdir_p(File.join(prefix, '1.1.9'))
      FileUtils.touch(File.join(prefix, '1.1.9', 'transferd'))
      File.symlink('1.1.9', File.join(prefix, 'current'))
      stdout, stderr, status = run_cli('config', 'transferd', 'service', 'versions', "--sdk-folder=#{File.join(prefix, 'current')}", '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(JSON.parse(stdout)).to(eq([{'version' => '1.1.9', 'folder' => File.join(prefix, '1.1.9'), 'current' => true}]))
    end
  end
end
