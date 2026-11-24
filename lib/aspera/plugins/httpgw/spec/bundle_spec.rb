# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `httpgw`: commands, agent of the extension point `agent`, schema of the agent parameters.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../xfer/transfer_agent'
require_relative '../commands'

module Aspera
  module Plugins
    module Httpgw
      RSpec.describe('Bundle httpgw') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The registry scans the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        describe 'commands' do
          it 'are those of plugin httpgw, from the bundle' do
            expect(registry.unavailable_reason(:httpgw)).to(be_nil)
            expect(registry[:httpgw].depends).to(eq([:xfer]))
            expect(registry[:httpgw].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:httpgw)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:httpgw)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('httpgw'))
          end
        end

        describe 'agent' do
          it 'is the entry of the extension point agent, with the letter of the agent before the bundle' do
            entry = registry.extensions(:agent).find { |item| item.bundle.eql?(:httpgw) }
            expect(entry).to(have_attributes(file: 'agent.rb', constant: 'Agent'))
            expect(entry.fields).to(eq('name' => 'httpgw', 'short' => 'h', 'options_schema' => 'schemas/agent_options.yaml'))
            expect(Aspera::Agent::Factory::ALL[:httpgw]).to(eq(long: 'Httpgw', short: :h))
            expect(Aspera::Agent::Factory.instance.provided?(:httpgw)).to(be(true))
          end

          it 'is loaded from the bundle' do
            expect(Aspera::Agent::Factory.instance.agent_class(:httpgw)).to(be(Aspera::Plugins::Httpgw::Agent))
          end

          it 'has its parameters in the schema of option transfer, from the file of its entry' do
            selector = Schema::Registry.instance.reader(Xfer::TransferAgent::TRANSFER_OPTION_SCHEMA)
            expect(selector['discriminator']['mapping']['httpgw']).to(eq('#/components/schemas/HttpgwAgentOptions'))
            parameters = Schema::Registry.instance.reader('transfer_opts:components.schemas.HttpgwAgentOptions')
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'httpgw', 'url' => 'https://gw.example.com', 'synchronous' => true}, Xfer::TransferAgent::TRANSFER_OPTION_SCHEMA)).to(be_empty)
            expect(validator.errors({'agent' => 'httpgw', 'url' => 'https://gw.example.com', 'api_version' => 'v3'}, Xfer::TransferAgent::TRANSFER_OPTION_SCHEMA)).not_to(be_empty)
          end

          it 'is no longer in the file of the framework schema' do
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            selector_file = Yaml.safe_load(File.read(File.join(source_root, 'lib/aspera/plugins/xfer/schemas/options.yaml')))['components']['schemas']
            expect(framework.keys).not_to(include('HttpgwAgentOptions'))
            expect(selector_file['TransferAgentOptions']['discriminator'].fetch('mapping', {})).not_to(include('httpgw'))
          end
        end
      end
    end
  end
end
