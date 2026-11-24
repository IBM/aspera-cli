# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Option `plugin_folder`: list of folders where plugins are looked up, `DEF` is the folder `plugins` of the configuration folder.

require_relative 'spec_helper'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/plugins/config'
require_relative '../lib/aspera/cli/plugins/factory'
require_relative '../lib/aspera/cli/special_values'
require_relative '../lib/aspera/log'
require 'tmpdir'
require 'fileutils'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Config) do
        subject(:config) { described_class.allocate }

        let(:factory) { Factory.send(:new, registry: BundleRegistry.send(:new, builtin: false)) }
        let(:home) { Dir.mktmpdir }
        let(:other) { Dir.mktmpdir }
        let(:home_plugins) { File.join(home, 'plugins') }
        let(:options) { instance_double(Parser) }

        before do
          allow(Factory).to(receive(:instance).and_return(factory))
          allow(config).to(receive_messages(context: instance_double(Context, main_folder: home), options: options))
          FileUtils.mkdir_p(home_plugins)
          File.write(File.join(home_plugins, 'mine.rb'), "# plugin mine\n")
          File.write(File.join(other, 'theirs.rb'), "# plugin theirs\n")
        end

        after do
          FileUtils.rm_rf(home)
          FileUtils.rm_rf(other)
        end

        # @param value [Array<String>] Value of option `plugin_folder`
        # @return [Array<Symbol>] Plugins found
        def plugins_with(value)
          allow(options).to(receive(:get_option).with(:plugin_folder).and_return(value))
          config.add_plugin_lookup_folders
          factory.add_plugins_from_lookup_folders
          factory.plugin_list
        end

        it 'uses the folder plugins of the configuration folder by default' do
          expect(plugins_with([SpecialValues::DEF])).to(eq(%i[mine]))
        end

        it 'replaces the default with the folders given' do
          allow(Log.log).to(receive(:warn))
          expect(plugins_with([other])).to(eq(%i[theirs]))
        end

        it 'warns when the folder plugins of the configuration folder has plugins and is not used' do
          allow(Log.log).to(receive(:warn))
          plugins_with([other])
          expect(Log.log).to(have_received(:warn)) { |&block| expect(block.call).to(match(/Plugins of .+ are not used: add DEF to option plugin_folder/)) }
        end

        it 'warns when the folder plugins of the configuration folder has only a bundle and is not used' do
          FileUtils.rm_f(File.join(home_plugins, 'mine.rb'))
          FileUtils.mkdir_p(File.join(home_plugins, 'bundled'))
          File.write(File.join(home_plugins, 'bundled', BundleRegistry::MANIFEST), "name: bundled\ntitle: Bundled\ncommands: true\n")
          allow(Log.log).to(receive(:warn))
          plugins_with([other])
          expect(Log.log).to(have_received(:warn)) { |&block| expect(block.call).to(match(/Plugins of .+ are not used: add DEF to option plugin_folder/)) }
        end

        it 'finds the bundles of the folders' do
          FileUtils.mkdir_p(File.join(other, 'bundled'))
          File.write(File.join(other, 'bundled', BundleRegistry::MANIFEST), "name: bundled\ntitle: Bundled\ncommands: true\n")
          expect(plugins_with([SpecialValues::DEF, other])).to(eq(%i[bundled mine theirs]))
          expect(factory.describe(:bundled)[:path]).to(eq(File.join(other, 'bundled')))
        end

        it 'does not warn when the folder plugins of the configuration folder has no plugin' do
          FileUtils.rm_rf(home_plugins)
          allow(Log.log).to(receive(:warn))
          plugins_with([other])
          expect(Log.log).not_to(have_received(:warn))
        end

        it 'combines DEF and other folders, the last one with priority' do
          File.write(File.join(other, 'mine.rb'), "# other plugin mine\n")
          expect(plugins_with([SpecialValues::DEF, other])).to(eq(%i[mine theirs]))
          expect(factory.describe(:mine)[:path]).to(eq(File.join(other, 'mine.rb')))
        end

        it 'uses no folder for an empty list' do
          allow(Log.log).to(receive(:warn))
          expect(plugins_with([])).to(be_empty)
        end
      end
    end
  end
end
