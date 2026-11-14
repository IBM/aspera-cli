# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/products/transferd_service'
require 'tmpdir'
require 'etc'
require 'fileutils'
require 'json'

RSpec.describe(Aspera::Products::TransferdService) do
  let(:root) { Dir.mktmpdir('transferd_service') }
  let(:sdk_folder) { File.join(root, 'sdk') }
  let(:commands) { [] }
  let(:listening_calls) { [] }
  let(:runner_answers) { {} }
  let(:runner) do
    lambda do |*cmd|
      commands.push(cmd)
      answer = runner_answers.find { |prefix, _| cmd.first(prefix.size).eql?(prefix) }
      answer ? answer.last : ['', true]
    end
  end
  let(:listening) { ->(address, port) { listening_calls.push([address, port]) && true } }
  let(:host) { described_class::Host.new(root: root, runner: runner, listening: listening, timeout: 1) }
  let(:current_user) { Etc.getpwuid(Process.uid).name }
  let(:user_config) { {'service' => {'user' => current_user}, 'config' => {'port' => 55002, 'authentication' => {'enabled' => true}}} }
  let(:config_file) { File.join(root, 'etc/transferd/transferd.json') }
  let(:unit_file) { File.join(root, 'etc/systemd/system/aspera-transferd.service') }

  before do
    FileUtils.mkdir_p(sdk_folder)
    FileUtils.touch(File.join(sdk_folder, 'transferd'))
  end

  after { FileUtils.rm_rf(root) }

  describe '.configure' do
    it 'writes configuration and unit, then starts the service' do
      described_class.configure(user_config, sdk_folder, host: host)
      conf = JSON.parse(File.read(config_file))
      expect(conf['port']).to(eq(55002))
      expect(conf['authentication']['api_key']).to(match(/\A\h{64}\z/))
      expect(conf['fasp_runtime']['user_defined']['bin']).to(eq(sdk_folder))
      expect(File.read(unit_file)).to(include("ExecStart=#{sdk_folder}/transferd --config /etc/transferd/transferd.json"))
      expect(commands).to(eq([
        %w[systemctl daemon-reload],
        %w[systemctl enable aspera-transferd],
        %w[systemctl restart aspera-transferd]
      ]))
      expect(listening_calls).to(eq([['127.0.0.1', 55002]]))
    end

    it 'writes files with restricted mode' do
      described_class.configure(user_config, sdk_folder, host: host)
      expect(File.stat(config_file).mode & 0o777).to(eq(0o640))
      expect(File.stat(unit_file).mode & 0o777).to(eq(0o640))
    end

    it 'keeps the existing API key and values not given' do
      described_class.configure(user_config, sdk_folder, host: host)
      key = JSON.parse(File.read(config_file)).dig('authentication', 'api_key')
      described_class.configure({'service' => user_config['service'], 'config' => {'log_level' => 'debug'}}, sdk_folder, host: host)
      conf = JSON.parse(File.read(config_file))
      expect(conf['authentication']['api_key']).to(eq(key))
      expect(conf).to(include('port' => 55002, 'log_level' => 'debug'))
    end

    it 'changes nothing with dry_run' do
      steps = described_class.configure(user_config, sdk_folder, host: host, dry_run: true)
      expect(steps.join("\n")).to(include("write #{config_file}"))
      expect(File.exist?(config_file)).to(be(false))
      expect(File.exist?(unit_file)).to(be(false))
      expect(commands).to(be_empty)
    end

    it 'does not show the API key in dry_run steps' do
      steps = described_class.configure(user_config, sdk_folder, host: host, dry_run: true)
      expect(steps.join("\n")).not_to(match(/\h{64}/))
    end

    it 'fails with the useradd command when the account does not exist' do
      conf = {'service' => {'user' => 'no_such_account_xyz'}}
      expect { described_class.configure(conf, sdk_folder, host: host) }.to(raise_error(Aspera::ParameterError, %r{useradd --system --no-create-home --shell /usr/sbin/nologin no_such_account_xyz}))
    end

    it 'shows the useradd command with dry_run, and does not fail' do
      conf = {'service' => {'user' => 'no_such_account_xyz'}}
      steps = described_class.configure(conf, sdk_folder, host: host, dry_run: true)
      expect(steps.first).to(include('useradd --system --no-create-home --shell /usr/sbin/nologin no_such_account_xyz'))
    end

    it 'fails when systemctl fails' do
      runner_answers[%w[systemctl restart]] = ['boom', false]
      expect { described_class.configure(user_config, sdk_folder, host: host) }.to(raise_error(Aspera::Error, /boom/))
    end

    it 'fails when the port is not listening' do
      slow_host = described_class::Host.new(root: root, runner: runner, listening: ->(_a, _p) { false }, timeout: 0.1)
      expect { described_class.configure(user_config, sdk_folder, host: slow_host) }.to(raise_error(Aspera::Error, /does not listen on 127.0.0.1:55002/))
    end

    it 'refuses invalid service parameters' do
      expect { described_class.configure({'service' => {'usr' => 'x'}}, sdk_folder, host: host) }.to(raise_error(Aspera::ParameterError, /Invalid service parameters/))
    end

    it 'does not wait when the port is dynamic' do
      described_class.configure({'service' => user_config['service']}, sdk_folder, host: host)
      expect(listening_calls).to(be_empty)
    end
  end

  describe '.install' do
    it 'installs the SDK when transferd is not there' do
      FileUtils.rm_f(File.join(sdk_folder, 'transferd'))
      installed = false
      described_class.install(user_config, sdk_folder, host: host, install_sdk: -> { installed = true; FileUtils.touch(File.join(sdk_folder, 'transferd')) }) # rubocop:disable Style/Semicolon
      expect(installed).to(be(true))
      expect(File.exist?(unit_file)).to(be(true))
    end

    it 'does not install the SDK when transferd is there' do
      installed = false
      described_class.install(user_config, sdk_folder, host: host, install_sdk: -> { installed = true })
      expect(installed).to(be(false))
    end

    it 'does not install the SDK with dry_run' do
      FileUtils.rm_f(File.join(sdk_folder, 'transferd'))
      installed = false
      steps = described_class.install(user_config, sdk_folder, host: host, dry_run: true, install_sdk: -> { installed = true })
      expect(installed).to(be(false))
      expect(steps.first).to(include('install the SDK'))
    end
  end

  describe '.status' do
    let(:runner_answers) do
      {
        %w[systemctl is-enabled] => ["enabled\n", true],
        %w[systemctl is-active]  => ["active\n", true]
      }.merge(version_answer)
    end
    let(:version_answer) { {[File.join(sdk_folder, 'transferd'), 'version'] => ["transferd version 1.1.10\n", true]} }

    it 'reports the state and never shows the API key' do
      described_class.configure(user_config, sdk_folder, host: host)
      key = JSON.parse(File.read(config_file)).dig('authentication', 'api_key')
      result = described_class.status(user_config, sdk_folder, host: host)
      expect(result).to(include('installed' => true, 'version' => '1.1.10', 'enabled' => 'enabled', 'active' => 'active', 'port' => 55002, 'listening' => true, 'authentication' => true))
      expect(JSON.generate(result)).not_to(include(key))
    end

    it 'reports a service that is not installed' do
      result = described_class.status(user_config, sdk_folder, host: host)
      expect(result).to(include('installed' => false, 'listening' => false, 'port' => 0))
    end

    it 'shows the environment variables of the unit that override the file' do
      conf = {'service' => user_config['service'].merge('environment' => {'TRANSFERD_PORT' => '55010', 'OTHER' => 'x'}), 'config' => {}}
      described_class.configure(conf, sdk_folder, host: host)
      result = described_class.status(conf, sdk_folder, host: host)
      expect(result).to(include('port' => 55010, 'environment' => {'TRANSFERD_PORT' => '55010'}))
    end
  end

  describe '.uninstall' do
    it 'stops and removes the service' do
      described_class.configure(user_config, sdk_folder, host: host)
      commands.clear
      described_class.uninstall(user_config, host: host)
      expect(File.exist?(unit_file)).to(be(false))
      expect(File.exist?(config_file)).to(be(true))
      expect(commands).to(eq([%w[systemctl disable --now aspera-transferd], %w[systemctl daemon-reload]]))
    end

    it 'removes configuration with purge' do
      described_class.configure(user_config, sdk_folder, host: host)
      described_class.uninstall(user_config, host: host, purge: true)
      expect(File.exist?(config_file)).to(be(false))
    end

    it 'does nothing when not installed' do
      expect(described_class.uninstall(user_config, host: host)).to(be_empty)
      expect(commands).to(be_empty)
    end

    it 'changes nothing with dry_run' do
      described_class.configure(user_config, sdk_folder, host: host)
      commands.clear
      described_class.uninstall(user_config, host: host, dry_run: true, purge: true)
      expect(File.exist?(unit_file)).to(be(true))
      expect(File.exist?(config_file)).to(be(true))
      expect(commands).to(be_empty)
    end
  end

  describe 'secret' do
    it 'declares the API key as secret' do
      described_class.configure(user_config, sdk_folder, host: host, dry_run: true)
      expect(Aspera::Secret::Hider.instance.secret?('api_key', 'x')).to(be(true))
    end
  end
end
