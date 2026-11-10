# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'json'
require 'aspera/cli/info'

RSpec.describe('transferd service CLI') do
  let(:source_root) { File.expand_path('..', __dir__) }

  def run_cli(*args)
    Dir.mktmpdir do |home|
      cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Aspera::Cli::Info::CMD_NAME), *args, '--version-check-days=0']
      stdout, stderr, status = Open3.capture3({'ASCLI_HOME' => home}, *cmd)
      [stdout, stderr, status]
    end
  end

  describe 'service spec' do
    it 'outputs the transfer daemon configuration schema in table format' do
      stdout, stderr, status = run_cli('transferd', 'service', 'spec')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(stdout).to(include('address'))
      expect(stdout).to(include('port'))
      expect(stdout).to(include('authentication'))
      expect(stdout).to(include('fasp_runtime'))
      expect(stdout).to(include('tls'))
      expect(stdout).to(include('workers'))
    end

    it 'outputs the schema in JSON format' do
      stdout, stderr, status = run_cli('transferd', 'service', 'spec', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      data = JSON.parse(stdout)
      expect(data).to(be_an(Array))
      names = data.map { |r| r['name'] }
      expect(names).to(include('address', 'port', 'authentication', 'fasp_runtime', 'tls', 'workers'))
    end
  end

  describe 'service configure' do
    it 'runs with --dry-run=yes and shows configuration steps' do
      stdout, stderr, status = run_cli('transferd', 'service', 'configure', '--dry-run=yes', '@json:{"service":{"user":"aspweb"},"config":{"port":55002}}')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(stdout + stderr).to(include('write /etc/transferd/transferd.json'))
      expect(stdout + stderr).to(include('write /etc/systemd/system/aspera-transferd.service'))
      expect(stdout + stderr).to(include('User=aspweb'))
    end

    it 'refuses unknown top-level keys in CONFIG' do
      _stdout, stderr, status = run_cli('transferd', 'service', 'configure', '--dry-run=yes', '@json:{"invalid_key":"val"}')
      expect(status.exitstatus).not_to(eq(0))
      expect(stderr).to(include('disallowed additional property'))
    end

    it 'refuses unknown service options in CONFIG' do
      _stdout, stderr, status = run_cli('transferd', 'service', 'configure', '--dry-run=yes', '@json:{"service":{"invalid_service_opt":"val"}}')
      expect(status.exitstatus).not_to(eq(0))
      expect(stderr).to(include('disallowed additional property'))
    end
  end

  describe 'deprecated config transferd' do
    it 'still runs service commands, with a deprecation warning' do
      stdout, stderr, status = run_cli('config', 'transferd', 'service', 'uninstall', '--dry-run=yes')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(stdout + stderr).to(include('Nothing to do'))
      expect(stderr).to(include('Command config transferd is deprecated after'))
    end

    it 'still shows the schema' do
      stdout, stderr, status = run_cli('config', 'transferd', 'service', 'spec', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(JSON.parse(stdout).map { |r| r['name'] }).to(include('address', 'port'))
    end

    it 'shows deprecation in the help of config transferd' do
      stdout, stderr, status = run_cli('config', 'transferd', '--help')
      expect(status.exitstatus).to(eq(0), stderr)
      expect(stdout + stderr).to(include('deprecated after'))
    end
  end

  describe 'install' do
    it 'is a command of plugin transferd with an optional version' do
      stdout, stderr, status = run_cli('config', 'commands', 'transferd', '--format=json')
      expect(status.exitstatus).to(eq(0), stderr)
      syntaxes = JSON.parse(stdout).map { |r| r['syntax'] }
      expect(syntaxes).to(include('transferd install [<version>]', 'transferd list'))
    end
  end
end
