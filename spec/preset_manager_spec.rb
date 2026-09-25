# frozen_string_literal: true

require 'spec_helper'
require 'aspera/cli/preset_manager'
require 'aspera/cli/error'
require 'tmpdir'

RSpec.describe(Aspera::Cli::PresetManager) do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:config_file) { File.join(@dir, 'config.yaml') }

  def manager(content = nil, **kwargs)
    File.write(config_file, content) unless content.nil?
    described_class.new(config_file: config_file, **kwargs)
  end

  describe 'config file' do
    it 'starts with a new configuration when there is no file' do
      pm = manager
      expect(pm.config_presets.keys).to(eq(['config']))
      expect(pm.config_presets['config']['version']).to(eq(Aspera::Cli::VERSION))
    end

    it 'raises on YAML syntax error' do
      expect { manager("a: [\n") }.to(raise_error(Psych::SyntaxError))
    end

    it 'renames an invalid config file and raises' do
      expect { manager("config: {}\n") }.to(raise_error(Aspera::Cli::Error, /No version found/))
      expect(File.exist?(config_file)).to(be(false))
      expect(Dir.children(@dir).first).to(match(/manual_conversion_needed$/))
    end

    it 'saves only when changed' do
      pm = manager
      expect(pm.save_if_needed).to(be(true))
      expect(pm.save_if_needed).to(be(false))
      expect(manager.config_presets['config']['version']).to(eq(Aspera::Cli::VERSION))
    end
  end

  describe '#plugin_default_name' do
    it 'raises when default preset does not exist' do
      pm = manager("config: {version: '1'}\ndefault: {node: missing}\n")
      expect { pm.plugin_default_name(:node) }.to(raise_error(Aspera::Cli::Error, /No such preset: missing/))
    end

    it 'ignores defaults when disabled' do
      pm = manager("config: {version: '1'}\ndefault: {node: missing}\n", use_plugin_defaults: false)
      expect(pm.plugin_default_name(:node)).to(be_nil)
    end
  end

  describe '#set_key' do
    subject(:pm) { manager("config: {version: '1'}\np: {a: 1, outer: {x: 1, y: 2}}\n") }

    it 'merges and deletes values using dot notation' do
      pm.set_key('p', 'outer.z', 3)
      pm.set_key('p', 'new.deep.k', 'v')
      expect(pm.config_presets['p']).to(eq({'a' => 1, 'outer' => {'x' => 1, 'y' => 2, 'z' => 3}, 'new' => {'deep' => {'k' => 'v'}}}))
      pm.set_key('p', 'outer.x', nil)
      pm.set_key('p', 'absent.x', nil)
      expect(pm.config_presets['p']['outer']).to(eq({'y' => 2, 'z' => 3}))
    end

    it 'sets, keeps and deletes simple values' do
      pm.set_key('p', :b, 2)
      pm.set_key('p', 'a', 1)
      pm.set_key('p', 'a', nil)
      expect(pm.config_presets['p']).to(eq({'outer' => {'x' => 1, 'y' => 2}, 'b' => 2}))
    end

    it 'creates the preset if needed' do
      pm.set_key('q', 'k', 'v')
      expect(pm.config_presets['q']).to(eq({'k' => 'v'}))
    end
  end

  describe '#set_global_default' do
    it 'creates the global preset and declares it as default' do
      pm = manager
      pm.set_global_default(:format, 'json')
      expect(pm.config_presets['default']).to(eq({'config' => 'global_common_defaults'}))
      expect(pm.config_presets['global_common_defaults']).to(eq({'format' => 'json'}))
      pm.set_global_default(:display, 'data')
      expect(pm.config_presets['global_common_defaults']).to(eq({'format' => 'json', 'display' => 'data'}))
    end
  end

  describe '#global_default_preset' do
    it 'declares and creates the global preset, so that the saved configuration can be loaded' do
      pm = manager
      expect(pm.global_default_preset).to(eq('global_common_defaults'))
      expect(pm.config_presets['default']).to(eq({'config' => 'global_common_defaults'}))
      expect(pm.config_presets['global_common_defaults']).to(eq({}))
      pm.save_if_needed
      expect(manager.plugin_default_name(:config)).to(eq('global_common_defaults'))
    end

    it 'returns the declared global preset without modification' do
      pm = manager("config: {version: '1'}\ndefault: {config: mine}\nmine: {a: 1}\n")
      expect(pm.global_default_preset).to(eq('mine'))
      expect(pm.config_presets['mine']).to(eq({'a' => 1}))
      expect(pm.config_presets.key?('global_common_defaults')).to(be(false))
    end
  end

  describe '#lookup_preset' do
    it 'finds preset by canonical URL and username' do
      pm = manager("config: {version: '1'}\ns: {url: 'https://h:443/', username: u}\nt: text\n")
      expect(pm.lookup_preset(url: 'https://h', username: 'u')).to(eq({'url' => 'https://h:443/', 'username' => 'u'}))
      expect(pm.lookup_preset(url: 'https://h', username: 'v')).to(be_nil)
    end
  end

  describe '.deep_merge!' do
    it 'merges nested hashes, source wins on scalars' do
      dst = {'a' => {'b' => 1, 'c' => 2}, 'd' => 1}
      expect(described_class.deep_merge!(dst, {'a' => {'c' => 3}, 'd' => {'e' => 1}})).to(eq({'a' => {'b' => 1, 'c' => 3}, 'd' => {'e' => 1}}))
    end
  end
end
