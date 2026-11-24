# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Plugins are code: a file of a folder that a client can write is not loaded when the security level is not low.
# The level of the folder applies to every file of a bundle, checked when the code is loaded.

require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/cli/plugins/factory'
require_relative '../lib/aspera/cli/security'
require 'tmpdir'
require 'fileutils'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Factory) do
        subject(:factory) { described_class.send(:new, registry: BundleRegistry.send(:new, builtin: false)) }

        let(:folder) { Dir.mktmpdir }

        after do
          Security.instance.reset
          FileUtils.rm_rf(folder)
        end

        def write_plugin(name) = File.write(File.join(folder, "#{name}.rb"), "# plugin #{name}\n")

        # Bundle whose code raises if loaded
        def write_bundle(name)
          FileUtils.mkdir_p(File.join(folder, name))
          File.write(File.join(folder, name, BundleRegistry::MANIFEST), "name: #{name}\ntitle: Bundle #{name}\ncommands: true\n")
          %w[commands other].each { |file| File.write(File.join(folder, name, "#{file}.rb"), "raise 'code of #{name} loaded'\n") }
        end

        it 'registers plugins of a folder marked `low` at level low' do
          write_plugin('early')
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
          expect(factory.plugin_list).to(eq([:early]))
        end

        it 'does not register a file that appears when the level is high' do
          factory.add_lookup_folder(folder, security: :low)
          Security.instance.lock('in MCP server mode', default: :high)
          write_plugin('late')
          factory.add_plugins_from_lookup_folders
          expect(factory.plugin_list).to(be_empty)
        end

        it 'does not load a plugin registered at level low, when the level is high' do
          write_plugin('early')
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
          Security.instance.lock('in MCP server mode', default: :high)
          expect { factory.plugin_class(:early) }.to(raise_error(BadArgument, /plugin early: disabled by security level high/))
        end

        it 'does not register a bundle that appears when the level is high' do
          factory.add_lookup_folder(folder, security: :low)
          Security.instance.lock('in MCP server mode', default: :high)
          write_bundle('late')
          factory.add_plugins_from_lookup_folders
          expect(factory.plugin_list).to(be_empty)
        end

        it 'does not load any file of a bundle registered at level low, when the level is high' do
          write_bundle('early')
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
          expect(factory.plugin_list).to(eq([:early]))
          Security.instance.lock('in MCP server mode', default: :high)
          expect { factory.plugin_class(:early) }.to(raise_error(BadArgument, /plugin early: disabled by security level high/))
          expect { factory.registry.load_constant(:early, 'other.rb', 'Other') }.to(raise_error(BadArgument, /plugin early: disabled by security level high/))
        end

        it 'loads a bundle registered at level low, at level low' do
          write_bundle('early')
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
          expect { factory.plugin_class(:early) }.to(raise_error(RuntimeError, 'code of early loaded'))
        end

        it 'registers plugins of a folder without restriction at any level' do
          write_plugin('builtin')
          Security.instance.lock('in MCP server mode', default: :high)
          factory.add_lookup_folder(folder)
          factory.add_plugins_from_lookup_folders
          expect(factory.plugin_list).to(eq([:builtin]))
        end
      end
    end
  end
end
