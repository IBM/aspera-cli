# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `node`: commands, API, agent of the extension point `agent`, Node API emulator, schemas, mounts by the plugins that use the Node API.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../transfer_agents/transfer_agent'
require_relative '../../cos/commands'
require_relative '../../shares/commands'
require_relative '../commands'
require_relative '../emulator'
require_relative '../../../../../spec/bundle_registry_helper'
require 'fileutils'
require 'net/http'
require 'open3'
require 'tmpdir'
require 'rbconfig'

module Aspera
  module Plugins
    module Node
      RSpec.describe('Bundle node') do
        include BundleRegistrySpecHelper

        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # The entries of the registry scan the plugin folders on first use: this spec also runs alone
        before { registry.extensions(:agent) }

        # @param script [String] Ruby code run in another process: only what it requires is loaded in it
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin node, from the bundle' do
            expect(registry.unavailable_reason(:node)).to(be_nil)
            # no `transferd`: the emulator gets the agent `transferd` from the factory when it starts
            expect(registry[:node].depends).to(eq(%i[transfer_agents]))
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

        describe 'emulator' do
          it 'and the other files of the bundle load neither the bundle transferd nor grpc' do
            script = "%w[commands agent api emulator].each { |file| require \"aspera/plugins/node/\#{file}\" }\nputs $LOADED_FEATURES.grep(%r{plugins/transferd|grpc}).length\n"
            stdout, stderr, status = run_ruby(script)
            expect(status.success?).to(be(true), stderr)
            expect(stdout.chomp).to(eq('0'))
          end
        end

        describe 'API' do
          it 'loads without gem net-ssh (needed only for the public key of a dynamic key)' do
            stdout, stderr, status = run_ruby("require 'aspera/plugins/node/api'\nputs $LOADED_FEATURES.grep(%r{/net/ssh/}).length\n")
            expect(status.success?).to(be(true), stderr)
            expect(stdout.chomp).to(eq('0'))
          end

          it 'registers the handler of the errors of the transfer specs of upload_setup and download_setup' do
            req = Net::HTTP::Post.new('/files/upload_setup')
            req['host'] = 'node.example.com'
            http = instance_double(Net::HTTPResponse, code: '200', message: 'OK')
            body = {'transfer_specs' => [{'transfer_spec' => {'error' => {'code' => 1, 'reason' => 'Forbidden'}}}]}
            expect { Rest::ErrorAnalyzer.instance.raise_on_error(req, body, http) }.to(raise_error(Rest::CallError, '1: Forbidden'))
          end
        end

        describe 'hints' do
          it 'are given for the errors of configuration of the server' do
            hints = Cli::Hints.instance_variable_get(:@added).select { |hint| hint[:exception].eql?(Rest::CallError) }.map { |hint| hint[:match] }
            expect(hints).to(include(/Server is not configured for this request/, /Please configure ACLs for this URI/))
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
            selector = Schema::Registry.instance.reader(TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)
            expect(selector['discriminator']['mapping']['node']).to(eq('#/components/schemas/NodeAgentOptions'))
            parameters = Schema::Registry.instance.reader('transfer_opts:components.schemas.NodeAgentOptions')
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'node', 'url' => 'https://node.example.com', 'username' => 'u', 'password' => '<PASSWORD>'}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).to(be_empty)
            expect(validator.errors({'agent' => 'node', 'url' => 'https://node.example.com'}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).not_to(be_empty)
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
            %i[NODE_AGENT_OPTIONS NODE_EMULATOR_OPTIONS].each { |name| expect(Schema::Registry.const_defined?(name, false)).to(be(false), name) }
            # The file, not the document of the registry: `NodeAgentOptions` is added to it as variant of `TransferAgentOptions`
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            selector_file = Yaml.safe_load(File.read(File.join(source_root, 'lib/aspera/plugins/transfer_agents/schemas/options.yaml')))['components']['schemas']
            expect(framework.keys).not_to(include('NodeAgentOptions', 'NodeBearerTokenOptions', 'NodeEmulatorOptions', 'NodeTelemetryOptions'))
            expect(selector_file['TransferAgentOptions']).not_to(include('oneOf'))
            expect(selector_file['TransferAgentOptions']['discriminator']).not_to(include('mapping'))
          end
        end

        describe 'without the bundle transferd' do
          let(:folder) { Dir.mktmpdir }
          let(:test_registry) { BundleRegistry.send(:new, builtin: false) }
          let(:factory) { Aspera::Agent::Factory.send(:new, registry: test_registry) }

          before do
            allow(Log.log).to(receive(:warn))
            # the bundles of the gem, with an unavailable transferd
            Dir.children(BundleRegistry::GEM_FOLDER).each do |name|
              next if name.eql?('transferd')
              File.symlink(File.join(BundleRegistry::GEM_FOLDER, name), File.join(folder, name))
            end
            write_bundle(folder, 'transferd', manifest: "name: transferd\nbogus: [\n", code: nil)
            test_registry.add_source(folder)
            test_registry.scan
          end

          after { FileUtils.rm_rf(folder) }

          it 'keeps node and the bundles that depend on it available, and the agent node can be created' do
            expect(test_registry.unavailable_reason(:transferd)).to(start_with('invalid manifest'))
            %i[node cos shares ats preview aoc].each { |name| expect(test_registry.unavailable_reason(name)).to(be_nil, name.to_s) }
            expect(factory.agent_class(:node)).to(be(Agent))
            expect { factory.agent_class(:transferd) }.to(raise_error(BundleRegistry::Unavailable, /\Aplugin transferd is unavailable: invalid manifest/))
          end

          it 'fails to start the emulator, naming transferd' do
            allow(Aspera::Agent::Factory).to(receive(:instance).and_return(factory))
            expect { Emulator.new(retention_sec: 60) }.to(raise_error(BundleRegistry::Unavailable, /\Aplugin transferd is unavailable: /))
          end
        end
      end
    end
  end
end
