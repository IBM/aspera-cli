# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/products/transferd_service'
require 'tmpdir'
require 'etc'
require 'fileutils'
require 'json'

RSpec.describe(Aspera::Products::TransferdService) do
  let(:root) { Dir.mktmpdir('transferd_layout') }
  let(:prefix) { File.join(root, 'opt/transferd') }
  let(:current) { File.join(prefix, 'current') }
  let(:commands) { [] }
  let(:restart_fails) { [] }
  let(:runner) do
    lambda do |*cmd|
      commands.push(cmd)
      cmd.first(2).eql?(%w[systemctl restart]) && !restart_fails.empty? && restart_fails.shift ? ['boom', false] : ['', true]
    end
  end
  let(:host) { described_class::Host.new(root: root, runner: runner, listening: ->(_a, _p) { true }, timeout: 1) }
  let(:current_user) { Etc.getpwuid(Process.uid).name }
  let(:user_config) { {'service' => {'user' => current_user}, 'config' => {'port' => 55002}} }
  let(:config_file) { File.join(root, 'etc/transferd/transferd.json') }
  let(:unit_file) { File.join(root, 'etc/systemd/system/aspera-transferd.service') }
  let(:install_sdk) do
    lambda do |folder|
      FileUtils.mkdir_p(folder)
      FileUtils.touch(File.join(folder, 'transferd'))
    end
  end

  after { FileUtils.rm_rf(root) }

  def install(version, **kwargs)
    described_class.install(user_config, current, host: host, install_sdk: install_sdk, version: version, **kwargs)
  end

  describe 'layout' do
    it 'is used only when the folder is named current' do
      expect(described_class.layout?(current)).to(be(true))
      expect(described_class.layout?(File.join(prefix, 'sdk'))).to(be(false))
    end

    it 'installs two versions, the link points to the last one' do
      install('1.1.9')
      install('1.1.10')
      expect(described_class.versions(current)).to(eq([
        {'version' => '1.1.9', 'folder' => File.join(prefix, '1.1.9'), 'current' => false},
        {'version' => '1.1.10', 'folder' => File.join(prefix, '1.1.10'), 'current' => true}
      ]))
      expect(File.readlink(current)).to(eq('1.1.10'))
    end

    it 'uses the link in the unit and in the configuration' do
      install('1.1.9')
      expect(File.read(unit_file)).to(include("ExecStart=#{current}/transferd --config /etc/transferd/transferd.json"))
      expect(JSON.parse(File.read(config_file)).dig('fasp_runtime', 'user_defined')).to(eq('bin' => current, 'etc' => current))
    end

    it 'resolves the link' do
      install('1.1.9')
      expect(described_class.resolve(current)).to(eq(File.realpath(File.join(prefix, '1.1.9'))))
    end

    it 'does not install again an installed version' do
      install('1.1.9')
      calls = []
      described_class.install(user_config, current, host: host, install_sdk: ->(folder) { calls.push(folder) }, version: '1.1.9')
      expect(calls).to(be_empty)
    end

    it 'requires a valid version' do
      expect { install(nil) }.to(raise_error(Aspera::ParameterError, /Invalid version/))
      expect { install('../x') }.to(raise_error(Aspera::ParameterError, /Invalid version/))
    end

    it 'changes nothing with dry_run' do
      steps = install('1.1.9', dry_run: true)
      expect(steps.first).to(include('install the SDK'))
      expect(File.exist?(prefix)).to(be(false))
      expect(commands).to(be_empty)
    end

    it 'goes back to no link when the first install fails' do
      slow_host = described_class::Host.new(root: root, runner: runner, listening: ->(_a, _p) { false }, timeout: 0.1)
      expect { described_class.install(user_config, current, host: slow_host, install_sdk: install_sdk, version: '1.1.9') }.to(raise_error(Aspera::Error, /does not listen/))
      expect(File.symlink?(current)).to(be(false))
    end
  end

  describe '.use' do
    before do
      install('1.1.9')
      install('1.1.10')
      commands.clear
    end

    it 'switches the link and restarts the service' do
      described_class.use(user_config, current, '1.1.9', host: host)
      expect(File.readlink(current)).to(eq('1.1.9'))
      expect(commands).to(eq([%w[systemctl restart aspera-transferd]]))
    end

    it 'does nothing when the version is in use' do
      expect(described_class.use(user_config, current, '1.1.10', host: host)).to(be_empty)
      expect(commands).to(be_empty)
    end

    it 'refuses a version that is not installed' do
      expect { described_class.use(user_config, current, '1.0.0', host: host) }.to(raise_error(Aspera::ParameterError, /not installed/))
      expect(File.readlink(current)).to(eq('1.1.10'))
    end

    it 'goes back to the previous version when the restart fails' do
      restart_fails.push(true)
      expect { described_class.use(user_config, current, '1.1.9', host: host) }.to(raise_error(Aspera::Error, /boom/))
      expect(File.readlink(current)).to(eq('1.1.10'))
      expect(commands).to(eq([%w[systemctl restart aspera-transferd], %w[systemctl restart aspera-transferd]]))
    end

    it 'changes nothing with dry_run' do
      steps = described_class.use(user_config, current, '1.1.9', host: host, dry_run: true)
      expect(steps.first).to(include('link'))
      expect(File.readlink(current)).to(eq('1.1.10'))
      expect(commands).to(be_empty)
    end

    it 'refuses a folder that is not a layout' do
      expect { described_class.use(user_config, File.join(prefix, 'sdk'), '1.1.9', host: host) }.to(raise_error(Aspera::ParameterError, /must be named current/))
    end
  end

  describe 'without layout' do
    let(:sdk_folder) { File.join(root, 'sdk') }

    it 'uses the folder as is' do
      FileUtils.mkdir_p(sdk_folder)
      FileUtils.touch(File.join(sdk_folder, 'transferd'))
      described_class.install(user_config, sdk_folder, host: host)
      expect(described_class.resolve(sdk_folder)).to(eq(sdk_folder))
      expect(File.read(unit_file)).to(include("ExecStart=#{sdk_folder}/transferd"))
    end
  end
end
