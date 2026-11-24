# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `direct`: agent of the extension point `agent` (the default agent), schema of the agent parameters.

require 'spec_helper'
require_relative '../../../../../spec/bundle_registry_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../transfer_agents/transfer_agent'
require_relative '../agent'
require 'fileutils'
require 'tmpdir'

module Aspera
  module Plugins
    module Direct
      RSpec.describe('Bundle direct') do
        include BundleRegistrySpecHelper

        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        describe 'manifest' do
          it 'is available, depends on the bundle transfer_agents, has no command and no gem' do
            registry.scan
            expect(registry.unavailable_reason(:direct)).to(be_nil)
            expect(registry[:direct].depends).to(eq([:transfer_agents]))
            expect(registry[:direct].gems).to(eq([]))
            expect(registry[:direct].commands?).to(be(false))
          end
        end

        describe 'agent' do
          it 'is the entry of the extension point agent, with the letter a' do
            entry = registry.extensions(:agent).find { |item| item.bundle.eql?(:direct) }
            expect(entry).to(have_attributes(file: 'agent.rb', constant: 'Agent'))
            expect(entry.fields).to(eq('name' => 'direct', 'short' => 'a', 'options_schema' => 'schemas/agent_options.yaml'))
            expect(Aspera::Agent::Factory::ALL[:direct]).to(eq(long: 'Direct', short: :a))
            expect(Aspera::Agent::Factory.instance.provided?(:direct)).to(be(true))
          end

          it 'is loaded from the bundle' do
            expect(Aspera::Agent::Factory.instance.agent_class(:direct)).to(be(Aspera::Plugins::Direct::Agent))
          end

          it 'has its parameters in the schema of option transfer, from the file of its entry' do
            selector = Schema::Registry.instance.reader(TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)
            expect(selector['discriminator']['mapping']['direct']).to(eq('#/components/schemas/DirectAgentOptions'))
            parameters = Schema::Registry.instance.reader('transfer_opts:components.schemas.DirectAgentOptions')
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'direct', 'wss' => false, 'quiet' => false}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).to(be_empty)
            expect(validator.errors({'agent' => 'direct', 'wss' => 'maybe'}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).not_to(be_empty)
          end

          it 'is no longer in the file of the framework schema' do
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            selector_file = Yaml.safe_load(File.read(File.join(source_root, 'lib/aspera/plugins/transfer_agents/schemas/options.yaml')))['components']['schemas']
            expect(framework.keys).not_to(include('DirectAgentOptions'))
            expect(selector_file['TransferAgentOptions']['discriminator'].fetch('mapping', {})).not_to(include('direct'))
          end
        end

        describe 'required by the default agent' do
          let(:folder) { Dir.mktmpdir }
          let(:test_registry) { BundleRegistry.send(:new, builtin: false) }
          let(:factory) { Aspera::Agent::Factory.send(:new, registry: test_registry) }

          before { allow(Log.log).to(receive(:warn)) }

          after { FileUtils.rm_rf(folder) }

          it 'fails with the reason when its manifest is invalid' do
            write_bundle(folder, 'direct', manifest: "name: direct\nbogus: [\n", code: nil)
            test_registry.add_source(folder)
            test_registry.scan
            expect(test_registry.unavailable_reason(:direct)).to(start_with('invalid manifest'))
            expect { factory.create(:direct, {}) }.to(raise_error(BundleRegistry::Unavailable, /\Aplugin direct is unavailable: invalid manifest .*plugin.yaml/))
          end

          it 'is unknown when no bundle provides it' do
            expect(factory.all).not_to(include(:direct))
            expect { factory.agent_class(:direct) }.to(raise_error(AssertError, 'assertion failed: unknown agent: direct'))
          end
        end
      end
    end
  end
end
