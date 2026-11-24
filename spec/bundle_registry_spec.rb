# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Registry of plugins: single files and bundles of the plugin folders, manifests read without loading code,
# dependencies, gems checked when the code is loaded, and the plugins with commands given by `Cli::Plugins::Factory`.

require_relative 'bundle_registry_helper'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/cli/plugins/base'
require_relative '../lib/aspera/cli/plugins/config'
require_relative '../lib/aspera/cli/plugins/factory'
require_relative '../lib/aspera/cli/runner'
require_relative '../lib/aspera/log'
require 'tmpdir'
require 'fileutils'

module Aspera
  RSpec.describe(BundleRegistry) do
    include BundleRegistrySpecHelper

    subject(:registry) { described_class.send(:new, builtin: false) }

    let(:folder) { Dir.mktmpdir }
    let(:other) { Dir.mktmpdir }

    before { allow(Log.log).to(receive(:warn)) }

    after do
      FileUtils.rm_rf(folder)
      FileUtils.rm_rf(other)
      remove_spec_constants
    end

    # @return [Array<String>] Messages logged at level warn
    def warnings
      messages = []
      expect(Log.log).to(have_received(:warn).at_least(:once)) { |&block| messages.push(block.call) }
      messages
    end

    def scan(*folders)
      folders.each { |f| registry.add_source(f) }
      registry.scan
    end

    describe 'sources' do
      it 'has the folder of the bundles of the gem by default' do
        expect(described_class.send(:new).folders).to(eq([described_class::GEM_FOLDER]))
      end

      it 'puts the last folder added first, or last with last: true' do
        registry.add_source(folder)
        registry.add_source(other, last: true)
        registry.add_source(File.join(other, 'top'))
        expect(registry.folders).to(eq([File.join(other, 'top'), folder, other]))
      end

      it 'keeps the place of a folder added again, with the new security level' do
        write_single(folder, 'spec_bundle_one')
        registry.add_source(folder)
        registry.add_source(other)
        registry.add_source(folder, security: :low)
        registry.scan
        expect(registry.folders).to(eq([other, folder]))
        expect(registry[:spec_bundle_one].security).to(eq(:low))
      end

      it 'gives the new security level to the plugins already registered from a folder added again' do
        write_single(folder, 'spec_bundle_one')
        write_bundle(folder, 'spec_bundle_two')
        scan(folder)
        expect(registry[:spec_bundle_two].security).to(be_nil)
        registry.add_source(folder, security: :low)
        expect(registry.names.map { |name| registry[name].security }).to(eq(%i[low low]))
      end

      it 'replaces a plugin registered from a source of less priority by the one of a source added later' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'title' => 'Gem'})
        write_bundle(other, 'spec_bundle_two', manifest: {'title' => 'User'})
        scan(folder)
        expect(registry[:spec_bundle_two].title).to(eq('Gem'))
        registry.add_source(other, security: :low)
        registry.scan
        expect(registry[:spec_bundle_two]).to(have_attributes(title: 'User', security: :low))
        registry.add_source(folder)
        registry.scan
        expect(registry[:spec_bundle_two].title).to(eq('User'))
      end

      it 'computes the schemas once until the plugins, the sources or the security checks change' do
        write_bundle(folder, 'spec_bundle_two')
        registry.add_source(folder)
        allow(registry).to(receive(:available_plugins).and_call_original)
        first = registry.schemas
        3.times { registry.schemas }
        registry.schema(:spec_none)
        expect(registry.schemas).to(be(first))
        expect(registry).to(have_received(:available_plugins).once)
        registry.add_source(other)
        registry.schemas
        expect(registry).to(have_received(:available_plugins).twice)
      end

      it 'looks for the gems of a plugin once until the plugins change' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'gems' => %w[spec-bundle-no-such-gem]})
        registry.add_source(folder)
        registry.scan
        allow(Gem::Specification).to(receive(:find_all_by_name).and_call_original)
        3.times { expect(registry.missing_gems(:spec_bundle_two)).to(eq(%w[spec-bundle-no-such-gem])) }
        expect(Gem::Specification).to(have_received(:find_all_by_name).once)
        write_bundle(other, 'spec_bundle_two', manifest: {'gems' => %w[spec-bundle-other-gem]})
        registry.add_source(other)
        registry.scan
        expect(registry.missing_gems(:spec_bundle_two)).to(eq(%w[spec-bundle-other-gem]))
      end

      it 'scans the sources once for the schemas' do
        write_bundle(folder, 'spec_bundle_two')
        registry.add_source(folder)
        allow(registry).to(receive(:children).and_call_original)
        3.times { registry.schemas }
        expect(registry).to(have_received(:children).once)
        registry.add_source(other)
        registry.schemas
        expect(registry).to(have_received(:children).exactly(3).times)
      end
    end

    describe 'lookup' do
      it 'registers a single file: commands only' do
        path = write_single(folder, 'spec_bundle_one')
        scan(folder)
        expect(registry.names).to(eq([:spec_bundle_one]))
        expect(registry[:spec_bundle_one]).to(have_attributes(form: :single, path: path, commands?: true, depends: [], gems: []))
      end

      it 'registers a bundle from its manifest, without loading its code' do
        bundle = write_bundle(folder, 'spec_bundle_two', code: "raise 'code of the bundle loaded'")
        expect { scan(folder) }.not_to(raise_error)
        expect(registry[:spec_bundle_two]).to(have_attributes(form: :bundle, path: bundle, title: 'Product spec_bundle_two', commands?: true))
        expect(registry.unavailable_reason(:spec_bundle_two)).to(be_nil)
      end

      it 'registers single files and bundles of the same folder' do
        write_single(folder, 'spec_bundle_one')
        write_bundle(folder, 'spec_bundle_two')
        scan(folder)
        expect(registry.names).to(eq(%i[spec_bundle_one spec_bundle_two]))
      end

      it 'uses the bundle when a folder has both forms of a name, with a warning' do
        write_single(folder, 'spec_bundle_one')
        write_bundle(folder, 'spec_bundle_one')
        scan(folder)
        expect(registry[:spec_bundle_one].form).to(eq(:bundle))
        expect(warnings).to(include(/Plugin spec_bundle_one: bundle .+ is used, not .+spec_bundle_one\.rb/))
      end

      it 'uses the plugin of the first source for a name' do
        write_bundle(folder, 'spec_bundle_one')
        write_single(other, 'spec_bundle_one')
        registry.add_source(folder)
        registry.add_source(other)
        registry.scan
        expect(registry[:spec_bundle_one].form).to(eq(:single))
      end

      it 'keeps a registered plugin when a source of less priority gets the same name later' do
        write_single(folder, 'spec_bundle_one')
        scan(folder)
        write_bundle(other, 'spec_bundle_one')
        registry.add_source(other, last: true)
        registry.scan
        expect(registry[:spec_bundle_one].form).to(eq(:single))
      end

      it 'ignores ignored names, folders without manifest, other files and missing folders' do
        write_single(folder, 'base')
        FileUtils.mkdir_p(File.join(folder, 'spec_bundle_empty'))
        File.write(File.join(folder, 'notes.txt'), 'not a plugin')
        registry.add_source(folder, ignore: %i[base])
        registry.add_source(File.join(other, 'missing'))
        registry.scan
        expect(registry.names).to(be_empty)
      end

      it 'does not scan a source refused by the security check' do
        write_single(folder, 'spec_bundle_one')
        registry.security_checks(allowed: ->(level) { level.nil? }, check: ->(_level, _what) {})
        registry.add_source(folder, security: :low)
        registry.scan
        expect(registry.names).to(be_empty)
      end
    end

    describe 'manifest' do
      it 'makes a bundle with an invalid manifest unavailable, with the reason, the others work' do
        write_bundle(folder, 'spec_bundle_bad', manifest: {'unknown' => 1})
        write_bundle(folder, 'spec_bundle_two')
        write_single(folder, 'spec_bundle_one')
        scan(folder)
        expect(registry.names).to(eq(%i[spec_bundle_bad spec_bundle_one spec_bundle_two]))
        expect(registry.unavailable_reason(:spec_bundle_bad)).to(match(%r{invalid manifest .+/spec_bundle_bad/plugin.yaml: .*unknown}))
        expect(registry[:spec_bundle_bad].manifest).to(be_empty)
        expect(registry.unavailable_reason(:spec_bundle_two)).to(be_nil)
        expect(registry.unavailable_reason(:spec_bundle_one)).to(be_nil)
        expect(warnings).to(include(/Plugin spec_bundle_bad is unavailable: invalid manifest/))
      end

      it 'gives the reason of a manifest that is not YAML' do
        write_bundle(folder, 'spec_bundle_bad', manifest: "name: [unclosed\n")
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_bad)).to(match(/invalid manifest .+plugin.yaml: .+/))
      end

      it 'gives the reason of a manifest that is not a mapping' do
        write_bundle(folder, 'spec_bundle_bad', manifest: "- a list\n")
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_bad)).to(match(/not a mapping/))
      end

      it 'makes a bundle unavailable when the name of its manifest is not the name of its folder' do
        write_bundle(folder, 'spec_bundle_bad', manifest: {'name' => 'spec_bundle_other'})
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_bad)).to(match(/name spec_bundle_other is not the name of the folder spec_bundle_bad/))
      end

      it 'does not validate the manifests of the gem with the schema (a spec does)' do
        stub_const('Aspera::BundleRegistry::GEM_FOLDER', folder)
        write_bundle(folder, 'spec_bundle_two', manifest: {'unknown' => 1})
        allow(Schema::Validator.instance).to(receive(:errors).and_call_original)
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_two)).to(be_nil)
        expect(Schema::Validator.instance).not_to(have_received(:errors))
      end
    end

    describe 'depends' do
      it 'makes a bundle unavailable when a dependency is missing' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'depends' => %w[spec_bundle_none]})
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_two)).to(eq('dependency spec_bundle_none is missing'))
        expect(warnings).to(include('Plugin spec_bundle_two is unavailable: dependency spec_bundle_none is missing'))
      end

      it 'makes a bundle unavailable when a dependency is unavailable' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'depends' => %w[spec_bundle_bad]})
        write_bundle(folder, 'spec_bundle_bad', manifest: {'depends' => %w[spec_bundle_none]})
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_two)).to(eq('dependency spec_bundle_bad is unavailable: dependency spec_bundle_none is missing'))
      end

      it 'makes the bundles of a dependency cycle unavailable' do
        write_bundle(folder, 'spec_bundle_one', manifest: {'depends' => %w[spec_bundle_two]})
        write_bundle(folder, 'spec_bundle_two', manifest: {'depends' => %w[spec_bundle_one]})
        scan(folder)
        expect(registry.unavailable_reason(:spec_bundle_one)).to(match(/dependency cycle: spec_bundle_one → spec_bundle_two → spec_bundle_one/))
        expect(registry.unavailable_reason(:spec_bundle_two)).not_to(be_nil)
      end

      it 'gives the mounts of a bundle after those of its dependencies, not by name' do
        mount = [{'target' => 'config', 'file' => 'mount.rb', 'module' => 'Mount'}]
        write_bundle(folder, 'spec_bundle_a', manifest: {'depends' => %w[spec_bundle_z], 'mounts' => mount})
        write_bundle(folder, 'spec_bundle_z', manifest: {'mounts' => mount})
        write_bundle(folder, 'spec_bundle_m', manifest: {'mounts' => mount})
        scan(folder)
        expect(registry.mounts(:config).map(&:bundle)).to(eq(%i[spec_bundle_z spec_bundle_a spec_bundle_m]))
      end

      it 'keeps available a bundle whose dependencies are available, in other sources' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'depends' => %w[spec_bundle_one]})
        write_bundle(other, 'spec_bundle_one')
        scan(folder, other)
        expect(registry.unavailable_reason(:spec_bundle_two)).to(be_nil)
      end
    end

    describe 'loading' do
      it 'loads a file of a bundle and gets its constant' do
        write_bundle(folder, 'spec_bundle_two')
        scan(folder)
        expect(registry.load_constant(:spec_bundle_two, 'commands.rb', 'Commands')).to(be(Aspera::Plugins::SpecBundleTwo::Commands))
      end

      it 'loads the code of a bundle only on use' do
        write_bundle(folder, 'spec_bundle_two', code: "raise 'code of the bundle loaded'")
        scan(folder)
        expect { registry.require_code(:spec_bundle_two, 'commands.rb') }.to(raise_error(RuntimeError, 'code of the bundle loaded'))
      end

      it 'refuses to load a bundle with a missing gem, that is still listed' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'gems' => %w[json aspera_spec_missing_gem]}, code: "raise 'code of the bundle loaded'")
        scan(folder)
        expect(registry.names).to(include(:spec_bundle_two))
        expect(registry.unavailable_reason(:spec_bundle_two)).to(be_nil)
        expect { registry.require_code(:spec_bundle_two, 'commands.rb') }
          .to(raise_error(described_class::Unavailable, 'plugin spec_bundle_two requires gem aspera_spec_missing_gem: gem install aspera_spec_missing_gem'))
      end

      it 'loads a bundle whose gems are installed' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'gems' => %w[json]})
        scan(folder)
        expect { registry.require_code(:spec_bundle_two, 'commands.rb') }.not_to(raise_error)
      end

      it 'refuses to load an unavailable bundle, with the reason' do
        write_bundle(folder, 'spec_bundle_two', manifest: {'depends' => %w[spec_bundle_none]}, code: "raise 'code of the bundle loaded'")
        scan(folder)
        expect { registry.require_code(:spec_bundle_two, 'commands.rb') }
          .to(raise_error(described_class::Unavailable, 'plugin spec_bundle_two is unavailable: dependency spec_bundle_none is missing'))
      end

      it 'checks the security level of the source before loading any file' do
        write_bundle(folder, 'spec_bundle_two', code: "raise 'code of the bundle loaded'")
        File.write(File.join(folder, 'spec_bundle_two', 'other.rb'), "raise 'other code loaded'\n")
        checks = []
        check = lambda do |level, what|
          checks.push([level, what])
          raise Error, 'refused'
        end
        registry.security_checks(allowed: ->(_level) { true }, check: check)
        registry.add_source(folder, security: :low)
        registry.scan
        expect { registry.require_code(:spec_bundle_two, 'commands.rb') }.to(raise_error(Error, 'refused'))
        expect { registry.load_constant(:spec_bundle_two, 'other.rb', 'Other') }.to(raise_error(Error, 'refused'))
        expect(checks).to(eq([[:low, 'plugin spec_bundle_two']] * 2))
      end

      it 'requires a file for a bundle and none for a single file' do
        write_single(folder, 'spec_bundle_one')
        write_bundle(folder, 'spec_bundle_two')
        scan(folder)
        expect { registry.require_code(:spec_bundle_two) }.to(raise_error(AssertError))
        expect { registry.require_code(:spec_bundle_one, 'commands.rb') }.to(raise_error(AssertError))
        expect { registry.require_code(:spec_bundle_none) }.to(raise_error(EntityNotFound, /plugin not found: spec_bundle_none/))
      end
    end
  end

  module Cli
    module Plugins
      RSpec.describe(Factory) do
        include BundleRegistrySpecHelper

        subject(:factory) { described_class.send(:new, registry: registry) }

        let(:registry) { BundleRegistry.send(:new, builtin: false) }
        let(:folder) { Dir.mktmpdir }

        before { allow(Log.log).to(receive(:warn)) }

        after do
          Security.instance.reset
          FileUtils.rm_rf(folder)
          remove_spec_constants
        end

        def scan
          factory.add_lookup_folder(folder, security: :low)
          factory.add_plugins_from_lookup_folders
        end

        it 'lists the available plugins with commands, without loading the code of bundles' do
          write_single(folder, 'spec_bundle_one')
          write_bundle(folder, 'spec_bundle_two', code: "raise 'code of the bundle loaded'")
          write_bundle(folder, 'spec_bundle_gem', manifest: {'gems' => %w[aspera_spec_missing_gem]})
          write_bundle(folder, 'spec_bundle_agent', manifest: {'commands' => false}, code: nil)
          write_bundle(folder, 'spec_bundle_bad', manifest: {'depends' => %w[spec_bundle_none]})
          scan
          expect(factory.plugin_list).to(eq(%i[spec_bundle_one spec_bundle_two]))
        end

        it 'leaves out of the list a bundle with a missing gem, so that loading every class works, and gives the reason' do
          write_single(folder, 'spec_bundle_one')
          write_bundle(folder, 'spec_bundle_gem', manifest: {'gems' => %w[aspera_spec_missing_gem]}, code: "raise 'code of the bundle loaded'")
          write_bundle(folder, 'spec_bundle_dep', manifest: {'depends' => %w[spec_bundle_none]})
          write_bundle(folder, 'spec_bundle_agent', manifest: {'commands' => false}, code: nil)
          scan
          expect(factory.plugin_list.map { |name| factory.plugin_class(name) }).to(eq([SpecBundleOne]))
          expect(factory.unavailable_plugins).to(eq(
            spec_bundle_dep: 'plugin spec_bundle_dep is unavailable: dependency spec_bundle_none is missing',
            spec_bundle_gem: 'plugin spec_bundle_gem requires gem aspera_spec_missing_gem: gem install aspera_spec_missing_gem'
          ))
        end

        it 'gives the class of a single file, with its plugin name' do
          path = write_single(folder, 'spec_bundle_one')
          scan
          klass = factory.plugin_class(:spec_bundle_one)
          expect(klass).to(be(SpecBundleOne))
          expect(klass).to(have_attributes(plugin_name: 'spec_bundle_one', application_name: 'SpecBundleOne'))
          expect(factory.describe(:spec_bundle_one)[:path]).to(eq(path))
        end

        it 'gives the class Commands of a bundle, with its plugin name' do
          bundle = write_bundle(folder, 'spec_bundle_two')
          scan
          klass = factory.plugin_class(:spec_bundle_two)
          expect(klass).to(be(Aspera::Plugins::SpecBundleTwo::Commands))
          expect(klass).to(have_attributes(plugin_name: 'spec_bundle_two', application_name: 'SpecBundleTwo'))
          expect(factory.describe(:spec_bundle_two)[:path]).to(eq(bundle))
        end

        it 'refuses to load a bundle with a missing gem' do
          write_bundle(folder, 'spec_bundle_gem', manifest: {'gems' => %w[aspera_spec_missing_gem]})
          scan
          expect { factory.plugin_class(:spec_bundle_gem) }.to(raise_error(Cli::Error, /gem install aspera_spec_missing_gem/))
        end

        it 'does not give a bundle without commands, or an unavailable bundle' do
          write_bundle(folder, 'spec_bundle_agent', manifest: {'commands' => false}, code: nil)
          write_bundle(folder, 'spec_bundle_bad', manifest: {'unknown' => 1})
          write_bundle(folder, 'spec_bundle_dep', manifest: {'depends' => %w[spec_bundle_none]})
          scan
          expect { factory.plugin_class(:spec_bundle_agent) }.to(raise_error(NoSuchElement, /plugin not found: spec_bundle_agent/))
          expect { factory.plugin_class(:spec_bundle_bad) }.to(raise_error(NoSuchElement, /plugin not found: spec_bundle_bad/))
          expect { factory.plugin_class(:spec_bundle_dep) }.to(raise_error(Cli::Error, /plugin spec_bundle_dep is unavailable: dependency spec_bundle_none is missing/))
        end

        it 'makes the runner give the reason when the command names a plugin that cannot be loaded, not an unknown command' do
          write_bundle(folder, 'spec_bundle_gem', manifest: {'gems' => %w[aspera_spec_missing_gem]})
          write_bundle(folder, 'spec_bundle_dep', manifest: {'depends' => %w[spec_bundle_none]})
          scan
          allow(Plugins::Factory).to(receive(:instance).and_return(factory))
          {
            'spec_bundle_gem' => /plugin spec_bundle_gem requires gem aspera_spec_missing_gem: gem install aspera_spec_missing_gem/,
            'spec_bundle_dep' => /plugin spec_bundle_dep is unavailable: dependency spec_bundle_none is missing/
          }.each do |name, message|
            runner = Cli::Runner.new([name])
            allow(runner).to(receive(:init_agents_and_options))
            allow(runner.context.config).to(receive(:add_plugin_lookup_folders))
            allow(runner.context.config).to(receive(:periodic_check_newer_gem_version))
            allow(runner.context).to(receive(:options).and_return(instance_double(Cli::Parser, command_or_arg_empty?: false)))
            # Options of the mounts of config and of the service transfer
            allow(Config).to(receive(:declare_options))
            allow(runner.context).to(receive(:transfer))
            allow(runner.context.options).to(receive(:next_arguments?)) { |values| values.eql?([name]) }
            expect { runner.run_with_result }.to(raise_error(Cli::Error, message))
          end
        end

        it 'looks up the user folders, then the bundles of the gem, then the single files of the gem' do
          gem_bundles = File.join(folder, 'gem_bundles')
          registry.add_source(gem_bundles)
          factory.add_lookup_folder(Config.gem_plugins_folder)
          factory.add_lookup_folder(folder, security: :low)
          expect(factory.lookup_folders).to(eq([folder, gem_bundles, Config.gem_plugins_folder]))
        end
      end

      RSpec.describe(Base) do
        it 'gives a plugin name from the class name when not set by the factory' do
          expect(Config.plugin_name).to(eq('config'))
          stub_const('Aspera::Plugins::SpecBundleName::Commands', Class.new(described_class))
          expect(Aspera::Plugins::SpecBundleName::Commands.plugin_name).to(eq('spec_bundle_name'))
        end
      end
    end
  end
end
