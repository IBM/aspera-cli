# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Hooks that bundles declare in their manifest, used without the framework knowing the bundles:
# entries of extension points (`BundleRegistry#extensions`), modules mounted on the command tree of another plugin
# (`Base.include_mounts`, called by `Factory`), services of the context (`Context#service`).

require_relative 'bundle_registry_helper'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/plugins/base'
require_relative '../lib/aspera/cli/plugins/factory'
require_relative '../lib/aspera/cli/security'
require_relative '../lib/aspera/log'
require 'tmpdir'
require 'fileutils'

# Fake bundles of the hooks
module BundleHooksSpecHelper
  include BundleRegistrySpecHelper

  # Schema of an entry of the extension point `spec_point`: a mandatory `label`, nothing else
  POINT_SCHEMA = {'type' => 'object', 'additionalProperties' => false, 'required' => %w[label], 'properties' => {'label' => {'type' => 'string'}}}.freeze

  # Commands of the target of the mounts
  TARGET_BODY = <<~RUBY
    command :first, description: 'First'
    commands_under :first do
      command :one, description: 'One', action: ->(**) {}
    end
    command :last, description: 'Last', action: ->(**) {}
  RUBY

  # Mounted module A: an option, a command under a node of the target, a top level command
  MOUNT_A = <<~RUBY
    module MountA
      def self.included(base)
        base.option(:spec_mount_a, description: 'Option of mount A')
        base.class_exec do
          commands_under :first do
            command :two, description: 'Two', action: ->(**) {}
          end
          command :mounted_a, description: 'Mounted A'
        end
      end
    end
  RUBY

  # Mounted module B: a command under a node of module A, a top level command
  MOUNT_B = <<~RUBY
    module MountB
      def self.included(base)
        base.class_exec do
          commands_under :mounted_a do
            command :sub, description: 'Sub', action: ->(**) {}
          end
          command :mounted_b, description: 'Mounted B', action: ->(**) {}
        end
      end
    end
  RUBY

  # @return [Array<String>] Messages logged at level warn
  def warnings
    messages = []
    expect(Aspera::Log.log).to(have_received(:warn).at_least(:once)) { |&block| messages.push(block.call) }
    messages
  end

  # @param folder [String] Plugin folder
  # @param name   [String] Name of the bundle
  # @param point  [String] Name of the extension point it declares
  # @param schema [Hash, nil] Schema of an entry, `nil`: no schema file
  # @return [String] Folder of the bundle
  def write_point_bundle(folder, name = 'spec_bundle_point', point: 'spec_point', schema: POINT_SCHEMA)
    bundle = write_bundle(folder, name, manifest: {'commands' => false, 'extension_points' => [{'name' => point, 'schema' => 'point.schema.yaml'}]}, code: nil)
    File.write(File.join(bundle, 'point.schema.yaml'), schema.to_yaml) unless schema.nil?
    bundle
  end

  # @param folder  [String]        Plugin folder
  # @param name    [String]        Name of the bundle
  # @param entries [Array<Hash>]   Entries for `spec_point`, merged in a valid one with the code in `entry.rb`
  # @param depends [Array<String>] Dependencies of the bundle
  # @param code    [String]        Code at the top of `entry.rb`
  # @return [String] Folder of the bundle
  def write_extending_bundle(folder, name, entries, depends: %w[spec_bundle_point], code: '')
    entries = entries.map { |entry| {'label' => name, 'file' => 'entry.rb', 'class' => 'Entry'}.merge(entry).compact }
    bundle = write_bundle(folder, name, manifest: {'commands' => false, 'depends' => depends, 'extensions' => {'spec_point' => entries}}, code: nil)
    write_bundle_file(bundle, 'entry.rb', 'class Entry; end', code: code)
    bundle
  end

  # @param folder   [String] Plugin folder
  # @param name     [String] Name of the bundle
  # @param target   [String] Plugin that includes the modules
  # @param manifest [Hash]   Other fields of the manifest
  # @param code     [String] Code at the top of the files of the modules
  # @return [String] Folder of the bundle
  def write_mounting_bundle(folder, name = 'spec_bundle_mounter', target: 'spec_bundle_target', manifest: {}, code: '')
    mounts = [{'target' => target, 'file' => 'mount_a.rb', 'module' => 'MountA'}, {'target' => target, 'file' => 'mount_b.rb', 'module' => 'MountB'}]
    bundle = write_bundle(folder, name, manifest: {'commands' => false, 'mounts' => mounts}.merge(manifest), code: nil)
    write_bundle_file(bundle, 'mount_a.rb', MOUNT_A, code: code)
    write_bundle_file(bundle, 'mount_b.rb', MOUNT_B, code: code)
    bundle
  end

  # @param folder   [String] Plugin folder
  # @param name     [String] Name of the bundle
  # @param service  [String] Name of the service
  # @param manifest [Hash]   Other fields of the manifest
  # @param code     [String] Code at the top of `service.rb`
  # @return [String] Folder of the bundle
  def write_service_bundle(folder, name = 'spec_bundle_service', service: 'spec_service', manifest: {}, code: '')
    services = [{'name' => service, 'file' => 'service.rb', 'class' => 'Service'}]
    bundle = write_bundle(folder, name, manifest: {'commands' => false, 'services' => services}.merge(manifest), code: nil)
    write_bundle_file(bundle, 'service.rb', <<~RUBY, code: code)
      class Service
        attr_reader :context

        def initialize(context)
          @context = context
        end
      end
    RUBY
    bundle
  end
end

module Aspera
  RSpec.describe(BundleRegistry) do
    include BundleHooksSpecHelper

    subject(:registry) { described_class.send(:new, builtin: false) }

    let(:folder) { Dir.mktmpdir }

    before { allow(Log.log).to(receive(:warn)) }

    after do
      FileUtils.rm_rf(folder)
      remove_spec_constants
    end

    def scan
      registry.add_source(folder)
      registry.scan
    end

    describe 'extension points' do
      it 'gives the entries of a point from the available bundles, as data, without loading their code' do
        write_point_bundle(folder)
        write_extending_bundle(folder, 'spec_bundle_two', [{'label' => 'b'}, {'label' => 'c'}], code: "raise 'code of the entry loaded'")
        write_extending_bundle(folder, 'spec_bundle_one', [{'label' => 'a', 'file' => 'other.rb', 'class' => 'Sub::Other'}], code: "raise 'code of the entry loaded'")
        write_extending_bundle(folder, 'spec_bundle_bad', [{}], depends: %w[spec_bundle_point spec_bundle_none])
        scan
        extensions = registry.extensions(:spec_point)
        expect(extensions.map { |extension| [extension.bundle, extension.fields] }).to(eq([[:spec_bundle_one, {'label' => 'a'}], [:spec_bundle_two, {'label' => 'b'}], [:spec_bundle_two, {'label' => 'c'}]]))
        expect(extensions.first).to(have_attributes(point: :spec_point, file: 'other.rb', constant: 'Sub::Other'))
        expect(registry.extensions(:spec_none)).to(be_empty)
      end

      it 'loads the code of an entry on demand' do
        write_point_bundle(folder)
        write_extending_bundle(folder, 'spec_bundle_one', [{}])
        scan
        expect(defined?(Aspera::Plugins::SpecBundleOne)).to(be_nil)
        expect(registry.load_entry(registry.extensions(:spec_point).first)).to(be(Aspera::Plugins::SpecBundleOne::Entry))
      end

      it 'checks the security level of the source before loading the code of an entry' do
        write_point_bundle(folder)
        write_extending_bundle(folder, 'spec_bundle_one', [{}], code: "raise 'code of the entry loaded'")
        registry.security_checks(allowed: ->(_level) { true }, check: ->(level, what) { raise Error, "refused #{level} #{what}" })
        registry.add_source(folder, security: :low)
        registry.scan
        expect { registry.load_entry(registry.extensions(:spec_point).first) }.to(raise_error(Error, 'refused low plugin spec_bundle_one'))
      end

      it 'makes a bundle unavailable when it extends a point that no dependency declares' do
        write_point_bundle(folder)
        write_point_bundle(folder, 'spec_bundle_other', point: 'spec_other')
        write_extending_bundle(folder, 'spec_bundle_one', [{}], depends: [])
        write_extending_bundle(folder, 'spec_bundle_two', [{}], depends: %w[spec_bundle_other])
        scan
        expect(registry.unavailable_reason(:spec_bundle_one)).to(eq('extension point spec_point is not declared by a dependency'))
        expect(registry.unavailable_reason(:spec_bundle_two)).to(eq('extension point spec_point is not declared by a dependency'))
        expect(registry.extensions(:spec_point)).to(be_empty)
        expect(warnings).to(include('Plugin spec_bundle_one is unavailable: extension point spec_point is not declared by a dependency'))
      end

      it 'makes a bundle unavailable when an entry is invalid for the schema of the point' do
        write_point_bundle(folder)
        write_extending_bundle(folder, 'spec_bundle_one', [{}, {'label' => 1}])
        write_extending_bundle(folder, 'spec_bundle_two', [{'unknown' => 'x'}])
        write_extending_bundle(folder, 'spec_bundle_three', [{'label' => nil}])
        scan
        expect(registry.unavailable_reason(:spec_bundle_one)).to(match(/\Ainvalid extension spec_point 2: .+/))
        expect(registry.unavailable_reason(:spec_bundle_two)).to(match(/\Ainvalid extension spec_point 1: .+/))
        expect(registry.unavailable_reason(:spec_bundle_three)).to(match(/\Ainvalid extension spec_point 1: .+label/))
      end

      it 'gives the reason of a schema of the point that cannot be read' do
        write_point_bundle(folder, schema: nil)
        write_extending_bundle(folder, 'spec_bundle_one', [{}])
        scan
        expect(registry.unavailable_reason(:spec_bundle_one)).to(match(/\Ainvalid extension spec_point 1: schema of the extension point: .*point\.schema\.yaml/))
      end

      it 'does not validate the entries of the bundles of the gem with the schema of the point (a spec does)' do
        stub_const('Aspera::BundleRegistry::GEM_FOLDER', folder)
        write_point_bundle(folder)
        write_extending_bundle(folder, 'spec_bundle_one', [{'unknown' => 'x'}])
        scan
        expect(registry.unavailable_reason(:spec_bundle_one)).to(be_nil)
      end

      it 'makes a bundle unavailable when it declares a point already declared by a plugin registered before' do
        write_point_bundle(folder, 'spec_bundle_a')
        write_point_bundle(folder, 'spec_bundle_b')
        scan
        expect(registry.unavailable_reason(:spec_bundle_a)).to(be_nil)
        expect(registry.unavailable_reason(:spec_bundle_b)).to(eq('extension point spec_point is declared by plugin spec_bundle_a'))
      end
    end

    describe 'mounts' do
      it 'gives the mounts on a plugin from the available bundles, as data, without loading their code' do
        write_mounting_bundle(folder, 'spec_bundle_two', code: "raise 'code of the mount loaded'")
        write_mounting_bundle(folder, 'spec_bundle_one', code: "raise 'code of the mount loaded'")
        write_mounting_bundle(folder, 'spec_bundle_other', target: 'spec_bundle_other_target')
        write_mounting_bundle(folder, 'spec_bundle_bad', manifest: {'depends' => %w[spec_bundle_none]})
        scan
        expect(registry.mounts(:spec_bundle_target).map { |mount| [mount.bundle, mount.file, mount.constant] }).to(eq([
          [:spec_bundle_one, 'mount_a.rb', 'MountA'], [:spec_bundle_one, 'mount_b.rb', 'MountB'],
          [:spec_bundle_two, 'mount_a.rb', 'MountA'], [:spec_bundle_two, 'mount_b.rb', 'MountB']
        ]))
        expect(registry.mounts(:spec_bundle_none)).to(be_empty)
      end
    end

    describe 'services' do
      it 'gives the service of the bundle that declares it, as data' do
        write_service_bundle(folder, code: "raise 'code of the service loaded'")
        scan
        expect(registry.service(:spec_service)).to(have_attributes(bundle: :spec_bundle_service, name: :spec_service, file: 'service.rb', constant: 'Service'))
      end

      it 'makes a bundle unavailable when it declares a service already declared by a plugin registered before' do
        write_service_bundle(folder, 'spec_bundle_b')
        write_service_bundle(folder, 'spec_bundle_a')
        scan
        expect(registry.unavailable_reason(:spec_bundle_b)).to(eq('service spec_service is declared by plugin spec_bundle_a'))
        expect(registry.service(:spec_service).bundle).to(eq(:spec_bundle_a))
      end

      it 'refuses a service that no plugin declares, or whose plugin is unavailable, with the reason' do
        write_service_bundle(folder)
        write_service_bundle(folder, 'spec_bundle_bad', service: 'spec_bad', manifest: {'depends' => %w[spec_bundle_none]})
        scan
        expect { registry.service(:spec_none) }.to(raise_error(described_class::Unavailable, 'no plugin provides service spec_none'))
        expect { registry.service(:spec_bad) }.to(raise_error(described_class::Unavailable, 'service spec_bad: plugin spec_bundle_bad is unavailable: dependency spec_bundle_none is missing'))
      end
    end
  end

  module Cli
    RSpec.describe(Context) do
      include BundleHooksSpecHelper

      subject(:context) { described_class.new(registry: registry) }

      let(:registry) { BundleRegistry.send(:new, builtin: false) }
      let(:folder) { Dir.mktmpdir }

      before { allow(Log.log).to(receive(:warn)) }

      after do
        Security.instance.reset
        FileUtils.rm_rf(folder)
        remove_spec_constants
      end

      it 'creates a service once, on first use, with the context' do
        write_service_bundle(folder)
        registry.add_source(folder)
        registry.scan
        expect(defined?(Aspera::Plugins::SpecBundleService)).to(be_nil)
        service = context.service(:spec_service)
        expect(service).to(be_a(Aspera::Plugins::SpecBundleService::Service))
        expect(service.context).to(be(context))
        expect(context.service(:spec_service)).to(be(service))
        expect(described_class.new(registry: registry).service(:spec_service)).not_to(be(service))
      end

      it 'raises a CLI error for a service that no available bundle provides' do
        registry.scan
        expect { context.service(:spec_none) }.to(raise_error(Cli::Error, 'no plugin provides service spec_none'))
      end

      it 'does not load a service of a source refused at the current security level' do
        write_service_bundle(folder, code: "raise 'code of the service loaded'")
        registry.security_checks(allowed: Security.instance.method(:allowed?), check: Security.instance.method(:check_level))
        registry.add_source(folder, security: :low)
        registry.scan
        Security.instance.lock('in MCP server mode', default: :high)
        expect { context.service(:spec_service) }.to(raise_error(BadArgument, /plugin spec_bundle_service: disabled by security level high/))
      end
    end

    module Plugins
      RSpec.describe(Factory) do
        include BundleHooksSpecHelper

        subject(:factory) { described_class.send(:new, registry: registry) }

        let(:registry) { BundleRegistry.send(:new, builtin: false) }
        let(:folder) { Dir.mktmpdir }
        let(:other) { Dir.mktmpdir }

        before { allow(Log.log).to(receive(:warn)) }

        after do
          Security.instance.reset
          FileUtils.rm_rf(folder)
          FileUtils.rm_rf(other)
          remove_spec_constants
        end

        # Target of the mounts in folder `other` (any level), mounting bundle in `folder`
        # @param security [Symbol, nil] Security level of `folder`
        def scan(security: nil)
          factory.add_lookup_folder(other)
          factory.add_lookup_folder(folder, security: security)
          factory.add_plugins_from_lookup_folders
        end

        # @param klass [Class] Plugin class
        # @return [Array] Command tree and options of the class
        def tree(klass)
          commands = klass.command_registry
          [commands.leaf_paths, commands.children_of([]).keys, commands.option_specs.keys]
        end

        it 'includes the mounted modules when it loads the target class, as includes at the end of its body, in the order of the manifest' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY)
          write_mounting_bundle(folder)
          scan
          klass = factory.plugin_class(:spec_bundle_target)
          expect(klass.command_registry.leaf_paths).to(eq([%i[first one], %i[first two], %i[last], %i[mounted_a sub], %i[mounted_b]]))
          reference = Class.new(Base)
          reference.class_eval(BundleHooksSpecHelper::TARGET_BODY)
          reference.include(Aspera::Plugins::SpecBundleMounter::MountA)
          reference.include(Aspera::Plugins::SpecBundleMounter::MountB)
          expect(tree(klass)).to(eq(tree(reference)))
          expect(klass.option_specs).to(include(:spec_mount_a))
        end

        it 'includes the mounted modules once' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY)
          write_mounting_bundle(folder)
          scan
          klass = factory.plugin_class(:spec_bundle_target)
          expect { factory.plugin_class(:spec_bundle_target) }.not_to(raise_error)
          expect(klass.command_registry.leaf_paths.length).to(eq(5))
        end

        it 'places the mounted commands where the class body includes them' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY.sub("command :last, description: 'Last'", "include_mounts\ncommand :last, description: 'Last'"))
          write_mounting_bundle(folder)
          allow(BundleRegistry).to(receive(:instance).and_return(registry))
          scan
          expect(factory.plugin_class(:spec_bundle_target).command_registry.children_of([]).keys).to(eq(%i[first mounted_a mounted_b last]))
        end

        it 'mounts on the commands of a bundle' do
          write_bundle(other, 'spec_bundle_target')
          write_mounting_bundle(folder)
          scan
          expect(factory.plugin_class(:spec_bundle_target).command_registry.leaf_paths).to(eq([%i[first two], %i[mounted_a sub], %i[mounted_b]]))
        end

        it 'loads the mounted modules only with the target class' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY)
          write_single(other, 'spec_bundle_other')
          write_mounting_bundle(folder, code: "raise 'code of the mount loaded'")
          scan
          expect(factory.plugin_list).to(eq(%i[spec_bundle_other spec_bundle_target]))
          expect { factory.plugin_class(:spec_bundle_other) }.not_to(raise_error)
          expect { factory.plugin_class(:spec_bundle_target) }.to(raise_error(RuntimeError, 'code of the mount loaded'))
        end

        it 'gives the security level of the source to the mounted commands and options' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY)
          write_mounting_bundle(folder)
          scan(security: :low)
          klass = factory.plugin_class(:spec_bundle_target)
          commands = klass.command_registry
          expect([%i[first], %i[first one], %i[last]].map { |path| commands[path].security }).to(eq([nil, nil, nil]))
          expect([%i[first two], %i[mounted_a], %i[mounted_a sub], %i[mounted_b]].map { |path| commands[path].security }).to(eq(%i[low low low low]))
          expect(klass.option_specs[:spec_mount_a].security).to(eq(:low))
        end

        it 'does not load the mounted modules of a source refused at the current security level' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY)
          write_mounting_bundle(folder, code: "raise 'code of the mount loaded'")
          scan(security: :low)
          Security.instance.lock('in MCP server mode', default: :high)
          expect(factory.plugin_class(:spec_bundle_target).command_registry.leaf_paths).to(eq([%i[first one], %i[last]]))
        end

        it 'adds no command of a bundle with a missing gem, with a warning, the target works' do
          write_single(other, 'spec_bundle_target', body: BundleHooksSpecHelper::TARGET_BODY)
          write_mounting_bundle(folder, manifest: {'gems' => %w[aspera_spec_missing_gem]}, code: "raise 'code of the mount loaded'")
          scan
          expect(factory.plugin_class(:spec_bundle_target).command_registry.leaf_paths).to(eq([%i[first one], %i[last]]))
          expect(warnings).to(include(/\ACommands of plugin spec_bundle_mounter are not added to spec_bundle_target: .+gem install aspera_spec_missing_gem\z/))
        end
      end
    end
  end
end
