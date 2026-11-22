# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Development files of a bundle stay in its folder `lib/aspera/plugins/<name>/`: schemas found by name, specs run by `rspec`,
# integration tests listed by `rake test:list`, and nothing of `spec/` in the gem.

require_relative 'bundle_registry_helper'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/hash_ext'
require_relative '../build/lib/test_env'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'yaml'

module Aspera
  RSpec.describe('Development files of bundles') do
    include BundleRegistrySpecHelper

    let(:folder) { Dir.mktmpdir }
    # Top folder of a fake project
    let(:top) { Pathname.new(folder) }
    let(:plugins) { File.join(folder, 'lib/aspera/plugins') }
    let(:repo) { File.expand_path('..', __dir__) }
    let(:schema) { {'type' => 'object', 'properties' => {'port' => {'type' => 'integer'}}, 'additionalProperties' => false} }

    before do
      allow(Log.log).to(receive(:warn))
      FileUtils.mkdir_p(plugins)
    end

    after { FileUtils.rm_rf(folder) }

    # @param name    [String] Name of the bundle
    # @param schemas [Array<Hash>] Entries `schemas` of the manifest
    def fake_bundle(name, schemas: [])
      bundle = write_bundle(plugins, name, manifest: {'schemas' => schemas}, code: nil)
      File.write(File.join(bundle, 'api.schema.yaml'), schema.to_yaml)
      bundle
    end

    describe 'schemas' do
      subject(:registry) { BundleRegistry.send(:new, builtin: false) }

      before do
        registry.add_source(plugins)
        allow(BundleRegistry).to(receive(:instance).and_return(registry))
      end

      it 'is found by name in the folder of the bundle' do
        fake_bundle('spec_bundle_schema', schemas: [{'key' => 'spec_bundle_api', 'file' => 'api.schema.yaml', 'owned' => true}])
        expect(Schema::Registry.known?(:spec_bundle_api)).to(be(true))
        expect(Schema::Registry.owned?('spec_bundle_api')).to(be(true))
        expect(Schema::Registry.instance.reader('spec_bundle_api')['properties']).to(include('port'))
        expect(registry.schema(:spec_bundle_api).file).to(eq(File.join(plugins, 'spec_bundle_schema', 'api.schema.yaml')))
      end

      it 'is not owned by default (schema of a vendor API)' do
        fake_bundle('spec_bundle_schema', schemas: [{'key' => 'spec_bundle_vendor', 'file' => 'api.schema.yaml'}])
        expect(Schema::Registry.owned?('spec_bundle_vendor:components')).to(be(false))
      end

      it 'is unknown if no bundle provides it' do
        expect(Schema::Registry.known?(:spec_bundle_none)).to(be(false))
        expect(Schema::Registry.owned?('spec_bundle_none')).to(be(false))
        expect { Schema::Registry.instance.reader('spec_bundle_none') }.to(raise_error(AssertError))
      end

      it 'keeps the schemas of the gem' do
        expect(Schema::Registry.known?(:transferd)).to(be(true))
        expect(Schema::Registry.owned?('transferd')).to(be(true))
      end

      it 'gives the origin of a downloaded schema, for `rake tools:openapi`' do
        source = {'url' => 'https://example.com/api.yaml', 'version' => '1.0'}
        fake_bundle('spec_bundle_schema', schemas: [{'key' => 'spec_bundle_api', 'file' => 'api.schema.yaml', 'source' => source}])
        expect(registry.schemas.map(&:source)).to(eq([source]))
      end

      it 'makes the second bundle unavailable if a key is declared twice' do
        fake_bundle('spec_bundle_a', schemas: [{'key' => 'spec_bundle_api', 'file' => 'api.schema.yaml'}])
        fake_bundle('spec_bundle_b', schemas: [{'key' => 'spec_bundle_api', 'file' => 'api.schema.yaml'}])
        registry.scan
        expect(registry.unavailable_reason(:spec_bundle_a)).to(be_nil)
        expect(registry.unavailable_reason(:spec_bundle_b)).to(match(/schema spec_bundle_api is declared by plugin spec_bundle_a/))
        expect(registry.schemas.map(&:bundle)).to(eq([:spec_bundle_a]))
      end
    end

    describe 'specs' do
      it 'of a bundle are run by rspec, with the specs of `spec/`' do
        bundle = fake_bundle('spec_bundle_spec')
        FileUtils.mkdir_p(File.join(bundle, 'spec/sub'))
        File.write(File.join(bundle, 'spec/sub/own_spec.rb'), "RSpec.describe('bundle spec') { it('runs') { expect(1).to(eq(1)) } }\n")
        FileUtils.mkdir_p(File.join(folder, 'spec'))
        FileUtils.cp(File.join(repo, 'spec/plugin_bundle_specs_spec.rb'), File.join(folder, 'spec'))
        out, status = Open3.capture2e(RbConfig.ruby, '-S', 'rspec', '--no-color', '--format', 'documentation', chdir: folder)
        expect(status.success?).to(be(true), out)
        expect(out).to(include('bundle spec', '1 example, 0 failures'))
      end
    end

    describe 'integration tests' do
      let(:test_def) { {'command' => nil, 'args' => %w[spec_bundle_test health]} }

      it 'of a bundle are listed with the others, in the order of the files' do
        tests = File.join(folder, 'tests')
        FileUtils.mkdir_p(tests)
        File.write(File.join(tests, 'tests.yml'), {'main_one' => test_def}.to_yaml)
        %w[spec_bundle_b spec_bundle_a].each do |name|
          FileUtils.mkdir_p(File.join(plugins, name, 'spec'))
          File.write(File.join(plugins, name, 'spec/tests.yml'), {"#{name}_health" => test_def}.to_yaml)
        end
        files = TestEnv.definition_files(top).map { |file| file.relative_path_from(top).to_s }
        expect(Pathname.new(files.first).expand_path(top)).to(eq(Paths::TEST_DEFS.expand_path))
        expect(files.drop(1)).to(eq(%w[lib/aspera/plugins/spec_bundle_a/spec/tests.yml lib/aspera/plugins/spec_bundle_b/spec/tests.yml]))
        all = TestEnv.descriptions([top / 'tests/tests.yml'].concat(TestEnv.definition_files(top).drop(1)))
        expect(all.keys).to(contain_exactly('main_one', 'spec_bundle_a_health', 'spec_bundle_b_health'))
        expect(all['spec_bundle_a_health'][:plugin]).to(eq(:spec_bundle_test))
      end

      it 'cannot redefine a test of another file' do
        file = top / 'one.yml'
        file.write({'same' => test_def}.to_yaml)
        expect { TestEnv.descriptions([file, file]) }.to(raise_error(/already defined/))
      end

      it 'of the project are all defined' do
        expect(TestEnv.definition_files.first).to(eq(Paths::TEST_DEFS))
      end
    end

    describe 'gem' do
      it 'excludes the `spec` folder of bundles' do
        FileUtils.mkdir_p(File.join(folder, 'lib/aspera/cli'))
        %w[version info].each { |name| FileUtils.cp(File.join(repo, "lib/aspera/cli/#{name}.rb"), File.join(folder, 'lib/aspera/cli')) }
        FileUtils.cp(File.join(repo, 'aspera-cli.gemspec'), folder)
        shipped = %w[lib/aspera/plugins/spec_bundle_gem/plugin.yaml lib/aspera/plugins/spec_bundle_gem/commands.rb lib/aspera/plugins/spec_bundle_gem/api.schema.yaml]
        excluded = %w[lib/aspera/plugins/spec_bundle_gem/spec/api_spec.rb lib/aspera/plugins/spec_bundle_gem/spec/fixtures/data/sample.json lib/aspera/plugins/spec_bundle_gem/spec/tests.yml]
        (shipped + excluded).each do |file|
          FileUtils.mkdir_p(File.dirname(File.join(folder, file)))
          File.write(File.join(folder, file), '')
        end
        _, status = Open3.capture2e('git', 'init', '-q', chdir: folder)
        expect(status.success?).to(be(true))
        _, status = Open3.capture2e('git', 'add', '-A', chdir: folder)
        expect(status.success?).to(be(true))
        files = Gem::Specification.load(File.join(folder, 'aspera-cli.gemspec')).files
        expect(files).to(include(*shipped))
        expect(files & excluded).to(be_empty)
      end
    end
  end
end
