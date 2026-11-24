# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `transferd`: commands, agent of the extension point `agent`, schemas, module mounted on plugin config,
# generated gRPC files.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../cli/info'
require_relative '../../../cli/plugins/config'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../transfer_agents/transfer_agent'
require_relative '../commands'
require_relative '../config_commands'
require 'open3'
require 'rbconfig'
require 'tmpdir'

module Aspera
  module Plugins
    module Transferd
      RSpec.describe('Bundle transferd') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # @return [String, nil] Why the gem grpc cannot be loaded, `nil` if it can
        def grpc_missing
          require 'grpc'
          nil
        rescue LoadError => e
          "optional gem grpc: #{e.message}"
        end

        # @param script [String] Ruby code run in another process: only what it requires is loaded in it
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin transferd, from the bundle' do
            expect(registry.unavailable_reason(:transferd)).to(be_nil)
            expect(registry[:transferd].depends).to(eq([:transfer_agents]))
            expect(registry[:transferd].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.describe(:transferd)[:path]).to(eq(bundle_folder))
            expect(Cli::Plugins::Factory.instance.plugin_class(:transferd)).to(be(Commands))
            expect(Commands.plugin_name).to(eq('transferd'))
          end
        end

        describe 'agent' do
          it 'is the entry of the extension point agent, with the letter of the agent before the bundle' do
            entry = registry.extensions(:agent).find { |item| item.bundle.eql?(:transferd) }
            expect(entry).to(have_attributes(file: 'agent.rb', constant: 'Agent'))
            expect(entry.fields).to(eq('name' => 'transferd', 'short' => 't', 'options_schema' => 'schemas/agent_options.yaml'))
            expect(Aspera::Agent::Factory::ALL[:transferd]).to(eq(long: 'Transferd', short: :t))
            expect(Aspera::Agent::Factory.instance.provided?(:transferd)).to(be(true))
          end

          it 'is loaded from the bundle' do
            reason = grpc_missing
            skip(reason) unless reason.nil?
            expect(Aspera::Agent::Factory.instance.agent_class(:transferd)).to(be(Aspera::Plugins::Transferd::Agent))
          end

          it 'has its parameters in the schema of option transfer, from the file of its entry' do
            selector = Schema::Registry.instance.reader(TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)
            expect(selector['discriminator']['mapping']['transferd']).to(eq('#/components/schemas/TransferdAgentOptions'))
            parameters = Schema::Registry.instance.reader('transfer_opts:components.schemas.TransferdAgentOptions')
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'transferd', 'url' => ':0', 'stop' => false}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).to(be_empty)
            expect(validator.errors({'agent' => 'transferd', 'stop' => 'no'}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).not_to(be_empty)
          end
        end

        describe 'schemas' do
          it 'give the configuration of the daemon (downloaded) and the options of the service, owned, no longer in the framework' do
            daemon = registry.schema(:transferd)
            expect(daemon).to(have_attributes(bundle: :transferd, file: File.join(bundle_folder, 'schemas/transferd-config.schema.json'), owned: true))
            expect(daemon.source['url']).to(end_with('/openapi/transferd-config.schema.json'))
            expect(registry.schema(:transferd_opts)).to(have_attributes(file: File.join(bundle_folder, 'schemas/options.yaml'), owned: true))
            expect(Schema::Registry::LOCATIONS).not_to(include(:transferd))
            expect(Schema::Registry.owned?(Service::SERVICE_CONFIG)).to(be(true))
            # The file, not the document of the registry: `TransferdAgentOptions` is added to it as variant of `TransferAgentOptions`
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            selector_file = Yaml.safe_load(File.read(File.join(source_root, 'lib/aspera/plugins/transfer_agents/schemas/options.yaml')))['components']['schemas']
            expect(framework.keys).not_to(include('TransferdAgentOptions', 'ServiceOptions', 'TransferdServiceConfig'))
            expect(selector_file['TransferAgentOptions']['discriminator'].fetch('mapping', {})).not_to(include('transferd'))
          end
        end

        describe 'module mounted on plugin config' do
          let(:commands) { Cli::Plugins::Config.command_registry }

          it 'gives the deprecated config transferd, last command of config, with install, list and service of the plugin' do
            mounts = registry.mounts(:config).select { |mount| mount.bundle.eql?(:transferd) }
            expect(mounts.map(&:constant)).to(eq(%w[ConfigCommands]))
            expect(Cli::Plugins::Config.ancestors).to(include(ConfigCommands))
            expect(commands.children_of([]).keys.last).to(eq(:transferd))
            expect(commands.mount_of([:transferd])).to(have_attributes(plugin: Commands, instance: :transferd_commands_plugin, only: %i[install list service]))
          end

          it 'creates the plugin found by name, with a deprecation warning' do
            config = Cli::Plugins::Config.allocate
            allow(config).to(receive(:context).and_return(:context))
            allow(Commands).to(receive(:new).with(context: :context).and_return(:plugin))
            expect(Log.log).to(receive(:warn)) { |&block| expect(block.call).to(eq('Command config ascp install is deprecated after 4.28.0: use transferd install')) }
            expect(config.transferd_plugin(command: 'config ascp install', replacement: 'transferd install')).to(be(:plugin))
          end

          it 'creates the class of the mount, with a deprecation warning' do
            config = Cli::Plugins::Config.allocate
            allow(config).to(receive(:context).and_return(:context))
            allow(Commands).to(receive(:new).with(context: :context).and_return(:plugin))
            expect(Log.log).to(receive(:warn)) { |&block| expect(block.call).to(eq('Command config transferd is deprecated after 4.28.0: use transferd')) }
            expect(config.transferd_commands_plugin).to(be(:plugin))
          end

          it 'runs the commands of the plugin' do
            Dir.mktmpdir do |home|
              cmd = [RbConfig.ruby, "-I#{source_root}/lib", File.join(source_root, 'bin', Cli::Info::CMD_NAME), 'config', 'transferd', 'service', 'spec', '--format=csv', '--fields=name', '--version-check-days=0']
              stdout, stderr, status = Open3.capture3({'ASCLI_HOME' => home}, *cmd)
              expect(status.success?).to(be(true), stderr)
              expect(stdout.lines(chomp: true)).to(include('port', 'fasp_runtime'))
              expect(stderr).to(include('Command config transferd is deprecated after 4.28.0: use transferd'))
            end
          end
        end

        describe 'generated gRPC files' do
          it 'are in the folder grpc, put in the load path by the API' do
            reason = grpc_missing
            skip(reason) unless reason.nil?
            stdout, stderr, status = run_ruby(<<~RUBY)
              require 'aspera/plugins/transferd/api'
              puts $LOADED_FEATURES.grep(/_pb\\.rb\\z/)
              puts ::Transferd::Api::TransferService::Stub.name
            RUBY
            expect(status.success?).to(be(true), stderr)
            expect(stderr).to(be_empty)
            grpc = File.join(bundle_folder, 'grpc')
            expect(stdout.lines(chomp: true)).to(eq(%W[#{grpc}/transferd_pb.rb #{grpc}/transferd_services_pb.rb Transferd::Api::TransferService::Stub]))
          end
        end
      end
    end
  end
end
