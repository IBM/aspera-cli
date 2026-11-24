# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Introspection of plugins: `config plugins list` (column `status`) and `config plugins show`.

require_relative 'spec_helper'
require_relative 'bundle_registry_helper'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/cli/plugins/config'
require_relative '../lib/aspera/cli/plugins/factory'
require_relative '../lib/aspera/log'
require 'tmpdir'
require 'fileutils'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Factory) do
        include BundleRegistrySpecHelper

        let(:folder) { Dir.mktmpdir }
        let(:registry) { BundleRegistry.send(:new) }
        let(:factory) { described_class.send(:new, registry: registry) }

        before do
          allow(Log.log).to(receive(:warn))
          write_single(folder, 'spec_bundle_single')
          write_bundle(folder, 'spec_bundle_ok', manifest: {'depends' => %w[node], 'gems' => %w[rake]})
          write_bundle(folder, 'spec_bundle_broken', manifest: {'depends' => %w[spec_bundle_nowhere]})
          write_bundle(folder, 'spec_bundle_missing_gem', manifest: {'gems' => %w[spec-bundle-no-such-gem]})
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
        end

        after { FileUtils.rm_rf(folder) }

        it 'gives a CLI error for a plugin whose code cannot be loaded: no commands.rb, wrong constant, syntax error' do
          write_bundle(folder, 'spec_bundle_no_code', code: nil)
          bundle = write_bundle(folder, 'spec_bundle_wrong', code: nil)
          File.write(File.join(bundle, 'commands.rb'), "module Aspera; module Plugins; module SpecBundleOther; end; end; end\n")
          bundle = write_bundle(folder, 'spec_bundle_syntax', code: nil)
          File.write(File.join(bundle, 'commands.rb'), "def (\n")
          factory.add_plugins_from_lookup_folders
          expect { factory.plugin_class(:spec_bundle_no_code) }.to(raise_error(Cli::Error, /\Aplugin spec_bundle_no_code cannot be loaded: LoadError/))
          expect { factory.plugin_class(:spec_bundle_wrong) }.to(raise_error(Cli::Error, /\Aplugin spec_bundle_wrong cannot be loaded: NameError/))
          expect { factory.plugin_class(:spec_bundle_syntax) }.to(raise_error(Cli::Error, /\Aplugin spec_bundle_syntax cannot be loaded: SyntaxError/))
        ensure
          remove_spec_constants
        end

        it 'does not convert the error of a broken plugin of the gem: it is a bug of ascli, reported with its location' do
          allow(registry).to(receive(:load_constant).and_raise(NameError, 'uninitialized constant Broken'))
          expect(factory.send(:source_of, registry[:node])).to(eq('gem'))
          expect { factory.plugin_class(:node) }.to(raise_error(NameError, /Broken/))
          allow(registry).to(receive(:load_constant).and_raise(LoadError, 'cannot load such file'))
          expect { factory.plugin_class(:node) }.to(raise_error(LoadError))
        end

        it 'gives the reason of a bundle whose manifest is invalid, with the plugins that cannot be loaded' do
          write_bundle(folder, 'spec_bundle_invalid', manifest: "name: [\n")
          factory.add_plugins_from_lookup_folders
          expect(factory.unavailable_plugins[:spec_bundle_invalid]).to(match(/\Aplugin spec_bundle_invalid is unavailable: invalid manifest/))
          expect(factory.unavailable_plugins.keys).to(include(:spec_bundle_broken, :spec_bundle_missing_gem))
          expect(factory.unavailable_plugins).not_to(include(:spec_bundle_ok, :spec_bundle_single))
          expect(factory.plugin_list).not_to(include(:spec_bundle_invalid))
        end

        it 'looks for the gems of each plugin once' do
          allow(Gem::Specification).to(receive(:find_all_by_name).and_call_original)
          factory.plugin_list
          factory.unavailable_plugins
          factory.listed_plugins.each { |name| factory.status(name) }
          expect(Gem::Specification).to(have_received(:find_all_by_name).with('spec-bundle-no-such-gem').once)
        end

        it 'describes a built-in bundle' do
          description = factory.describe(:node)
          expect(description).to(include(plugin: :node, source: 'gem', form: :bundle, security: 'any', status: 'available', commands: true, agents: %w[node], depends: %i[transfer_agents]))
          expect(description[:schemas]).to(include(:node))
          expect(description[:path]).to(eq(File.join(BundleRegistry::GEM_FOLDER, 'node')))
        end

        it 'describes a built-in single file' do
          factory.add_lookup_folder(File.join(File.dirname(__dir__), 'lib/aspera/cli/plugins'))
          factory.add_plugins_from_lookup_folders
          expect(factory.describe(:config)).to(eq(plugin: :config, title: nil, source: 'gem', form: :single, path: File.join(File.dirname(__dir__), 'lib/aspera/cli/plugins/config.rb'),
            security: 'any', status: 'available', commands: true))
        end

        it 'describes a single file of a user folder' do
          expect(factory.describe(:spec_bundle_single)).to(include(source: folder, form: :single, security: :low, status: 'available'))
        end

        it 'describes a bundle with its gems' do
          expect(factory.describe(:spec_bundle_ok)).to(include(source: folder, depends: %i[node], gems: %w[rake], missing_gems: [], status: 'available'))
        end

        it 'describes an unavailable bundle with the reason' do
          description = factory.describe(:spec_bundle_broken)
          expect(description[:status]).to(match(/spec_bundle_nowhere/))
          expect(description).to(include(depends: %i[spec_bundle_nowhere]))
        end

        it 'reports missing gems as status' do
          expect(factory.describe(:spec_bundle_missing_gem)).to(include(missing_gems: %w[spec-bundle-no-such-gem], status: 'missing gem spec-bundle-no-such-gem'))
        end

        it 'raises for an unknown plugin' do
          expect { factory.describe(:spec_bundle_unknown) }.to(raise_error(NoSuchElement, /plugin not found/))
        end

        it 'lists the plugins with commands and those that cannot be loaded' do
          expect(factory.listed_plugins).to(include(:spec_bundle_single, :spec_bundle_ok, :spec_bundle_broken, :spec_bundle_missing_gem))
        end
      end

      RSpec.describe(Config) do
        include BundleRegistrySpecHelper

        subject(:config) { described_class.allocate }

        let(:folder) { Dir.mktmpdir }
        let(:factory) { Factory.send(:new, registry: BundleRegistry.send(:new, builtin: false)) }

        before do
          allow(Log.log).to(receive(:warn))
          write_single(folder, 'spec_bundle_single')
          write_bundle(folder, 'spec_bundle_broken', manifest: {'depends' => %w[spec_bundle_nowhere]}, code: nil)
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
          allow(Factory).to(receive(:instance).and_return(factory))
        end

        after { FileUtils.rm_rf(folder) }

        it 'lists an available plugin with its status' do
          row = config.action_plugins_list.data.find { |item| item[:plugin].eql?(:spec_bundle_single) }
          expect(row).to(include(status: 'available', path: File.join(folder, 'spec_bundle_single.rb')))
        end

        it 'lists an unavailable plugin with the reason and without loading it' do
          row = config.action_plugins_list.data.find { |item| item[:plugin].eql?(:spec_bundle_broken) }
          expect(row[:status]).to(match(/spec_bundle_nowhere/))
          expect(row).to(include(detect: nil, wizard: nil))
        end

        it 'lists a plugin whose code cannot be loaded with the reason, the others are listed' do
          write_bundle(folder, 'spec_bundle_no_code', code: nil)
          factory.add_plugins_from_lookup_folders
          rows = config.action_plugins_list.data
          expect(rows.find { |item| item[:plugin].eql?(:spec_bundle_no_code) }).to(include(detect: nil, wizard: nil, status: match(/cannot be loaded: LoadError/)))
          expect(rows.find { |item| item[:plugin].eql?(:spec_bundle_single) }).to(include(status: 'available'))
        end

        it 'shows a plugin' do
          expect(config.action_plugins_show(name: 'spec_bundle_broken').data).to(include(plugin: :spec_bundle_broken, form: :bundle))
        end
      end
    end
  end
end
