# frozen_string_literal: true

# Plugins are code: a file of a folder that a client can write is not loaded when the security level is not low.

require_relative '../lib/aspera/cli/plugins/factory'
require_relative '../lib/aspera/cli/security'
require 'tmpdir'
require 'fileutils'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Factory) do
        subject(:factory) { described_class.send(:new) }

        let(:folder) { Dir.mktmpdir }

        after do
          Security.instance.reset
          FileUtils.rm_rf(folder)
        end

        def write_plugin(name) = File.write(File.join(folder, "#{name}.rb"), "# plugin #{name}\n")

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
