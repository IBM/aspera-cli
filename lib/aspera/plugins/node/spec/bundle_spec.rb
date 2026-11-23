# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `node`: commands, API, agent of the extension point `agent`, Node API emulator, schemas, mounts by the plugins that use the Node API, shims of the moved files.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../cos/commands'
require_relative '../../shares/commands'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Node
      RSpec.describe('Bundle node') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The entries of the registry scan the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        # @param script [String] Ruby code run in another process: the former constants are not defined in the process of the specs
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin node, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:node)).to(be_nil)
            # transferd: the emulator executes its transfers with the transfer daemon
            expect(registry[:node].depends).to(eq(%i[transfer_agents transferd]))
            expect(registry[:node].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:node)).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:node)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('node'))
          end

          it 'are mounted by the bundles that use the Node API' do
            expect(Cos::Commands.command_registry.mount_of([:node])).to(have_attributes(plugin: Commands, only: Commands::COMMANDS_COS))
            expect(Shares::Commands.command_registry.mount_of([:files])).to(have_attributes(plugin: Commands, only: Commands::COMMANDS_SHARES))
          end
        end

        describe 'API' do
          it 'loads without gem net-ssh (needed only for the public key of a dynamic key)' do
            stdout, stderr, status = run_ruby("require 'aspera/plugins/node/api'\nputs $LOADED_FEATURES.grep(%r{/net/ssh/}).length\n")
            expect(status.success?).to(be(true), stderr)
            expect(stdout.chomp).to(eq('0'))
          end
        end

        describe 'agent' do
          it 'is the entry of the extension point agent, with the letter of the agent before the bundle' do
            entry = registry.extensions(:agent).find { |item| item.bundle.eql?(:node) }
            expect(entry).to(have_attributes(file: 'agent.rb', constant: 'Agent'))
            expect(entry.fields).to(eq('name' => 'node', 'short' => 'n', 'options_schema' => 'schemas/agent_options.yaml'))
            expect(Aspera::Agent::Factory::ALL[:node]).to(eq(long: 'Node', short: :n))
            expect(Aspera::Agent::Factory.instance.provided?(:node)).to(be(true))
          end

          it 'is loaded from the bundle' do
            expect(Aspera::Agent::Factory.instance.agent_class(:node)).to(be(Agent))
          end

          it 'has its parameters in the schema of option transfer, from the file of its entry' do
            selector = Schema::Registry.instance.reader(Schema::Registry::TRANSFER_AGENT_OPTIONS)
            expect(selector['discriminator']['mapping']['node']).to(eq('#/components/schemas/NodeAgentOptions'))
            parameters = Schema::Registry.instance.reader("#{Schema::Registry::OPTIONS}:components.schemas.NodeAgentOptions")
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'node', 'url' => 'https://node.example.com', 'username' => 'u', 'password' => '<PASSWORD>'}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).to(be_empty)
            expect(validator.errors({'agent' => 'node', 'url' => 'https://node.example.com'}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).not_to(be_empty)
          end
        end

        describe 'schemas' do
          it 'give the Node API (downloaded, vendor) and the options of the commands (owned), no longer in the framework' do
            api = registry.schema(:node)
            expect(api).to(have_attributes(bundle: :node, file: File.join(bundle_folder, 'schemas/IBM Aspera Node API-4.4.6.yaml'), owned: false))
            expect(api.source['url']).to(end_with('/openapi/IBM%20Aspera%20Node%20API-4.4.6.yaml'))
            expect(registry.schema(:node_opts)).to(have_attributes(file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(Schema::Registry::LOCATIONS).not_to(include(:node))
            expect(Schema::Registry.owned?(Commands::EMULATOR_OPTIONS)).to(be(true))
            expect(Schema::Registry.owned?("#{Commands::API_SCHEMA}:components.schemas.transferPostRequest")).to(be(false))
            expect(Schema::Registry.instance.reader(Commands::EMULATOR_OPTIONS).current['properties']).to(include('url', 'docroot', 'retention_sec'))
            %i[NODE NODE_AGENT_OPTIONS NODE_EMULATOR_OPTIONS].each { |name| expect(Schema::Registry.const_defined?(name, false)).to(be(false), name) }
            # The file, not the document of the registry: `NodeAgentOptions` is added to it as variant of `TransferAgentOptions`
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            expect(framework.keys).not_to(include('NodeAgentOptions', 'NodeBearerTokenOptions', 'NodeEmulatorOptions', 'NodeTelemetryOptions'))
            expect(framework['TransferAgentOptions']).not_to(include('oneOf'))
            expect(framework['TransferAgentOptions']['discriminator']).not_to(include('mapping'))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constants, new constants, path to use
          MOVED = {
            'aspera/cli/plugins/node' => [%w[Aspera::Cli::Plugins::Node], %w[Aspera::Plugins::Node::Commands], 'aspera/plugins/node/commands'],
            'aspera/agent/node'       => [%w[Aspera::Agent::Node], %w[Aspera::Plugins::Node::Agent], 'aspera/plugins/node/agent'],
            'aspera/api/node'         => [%w[Aspera::Api::Node Aspera::Api::NodeFileId], %w[Aspera::Plugins::Node::Api Aspera::Plugins::Node::NodeFileId], 'aspera/plugins/node/api'],
            'aspera/node_emulator'    => [
              %w[Aspera::NodeEmulator Aspera::NodeEmulatorServlet], %w[Aspera::Plugins::Node::Emulator Aspera::Plugins::Node::NodeEmulatorServlet], 'aspera/plugins/node/emulator'
            ]
          }.freeze

          it 'warn once when loaded, and give the moved constants under their former names' do
            MOVED.each do |path, (formers, currents, new_path)|
              stdout, stderr, status = run_ruby("2.times { require #{path.inspect} }\n#{formers.map { |former| "puts Object.const_get(#{former.inspect}).name\n" }.join}")
              expect(status.success?).to(be(true), stderr)
              expect(stdout.lines(chomp: true)).to(eq(currents))
              expect(stderr.scan("#{path} is deprecated: use #{new_path} (removed in 5.0)").length).to(eq(1), stderr)
              # `-w`: warning of `deprecate_constant`, and no other warning
              expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(formers.each_with_index.map { |former, index| "-e:#{index + 2}: warning: constant #{former} is deprecated" }), stderr)
            end
          end
        end
      end
    end
  end
end
