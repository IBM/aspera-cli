# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `transferd`: commands, agent of the extension point `agent`, schemas, module mounted on plugin config,
# generated gRPC files, shims of the moved files.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../cli/info'
require_relative '../../../cli/plugins/config'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
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

        # @param script [String] Ruby code run in another process: the former constants are not defined in the process of the specs
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin transferd, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:transferd)).to(be_nil)
            expect(registry[:transferd].depends).to(eq([:transfer_agents]))
            expect(registry[:transferd].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:transferd)).to(eq(bundle_folder))
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
            selector = Schema::Registry.instance.reader(Schema::Registry::TRANSFER_AGENT_OPTIONS)
            expect(selector['discriminator']['mapping']['transferd']).to(eq('#/components/schemas/TransferdAgentOptions'))
            parameters = Schema::Registry.instance.reader("#{Schema::Registry::OPTIONS}:components.schemas.TransferdAgentOptions")
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'transferd', 'url' => ':0', 'stop' => false}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).to(be_empty)
            expect(validator.errors({'agent' => 'transferd', 'stop' => 'no'}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).not_to(be_empty)
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
            expect(framework.keys).not_to(include('TransferdAgentOptions', 'ServiceOptions', 'TransferdServiceConfig'))
            expect(framework['TransferAgentOptions']['discriminator'].fetch('mapping', {})).not_to(include('transferd'))
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
          it 'are in the folder grpc, put in the load path by the API: the shims of lib are not loaded' do
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

        describe 'shims of the moved files' do
          # Former path => former constant (`nil`: generated file, no constant of its own), new constant, path to use
          MOVED = {
            'aspera/cli/plugins/transferd'      => %w[Aspera::Cli::Plugins::Transferd Aspera::Plugins::Transferd::Commands aspera/plugins/transferd/commands],
            'aspera/products/transferd_service' => %w[Aspera::Products::TransferdService Aspera::Plugins::Transferd::Service aspera/plugins/transferd/service]
          }.freeze
          # Moved files that require the gem grpc
          MOVED_GRPC = {
            'aspera/agent/transferd' => %w[Aspera::Agent::Transferd Aspera::Plugins::Transferd::Agent aspera/plugins/transferd/agent],
            'transferd_pb'           => [nil, 'Transferd::Api::TransferInfo', 'aspera/plugins/transferd/grpc/transferd_pb'],
            'transferd_services_pb'  => [nil, 'Transferd::Api::TransferService::Stub', 'aspera/plugins/transferd/api']
          }.freeze

          # @param moved [Hash] Former path => former constant, new constant, path to use
          # Each shim in its own process: once the API is loaded, `require 'transferd_pb'` is the generated file, not the shim
          # @param moved [Hash] Former path => former constant, new constant, path to use
          def check_shims(moved)
            moved.each do |path, (former, current, new_path)|
              stdout, stderr, status = run_ruby("2.times { require #{path.inspect} }\nputs Object.const_get(#{(former || current).inspect}).name\n")
              expect(status.success?).to(be(true), stderr)
              expect(stdout.chomp).to(eq(current))
              expect(stderr.scan("#{path} is deprecated: use #{new_path} (removed in 5.0)").length).to(eq(1), stderr)
              # `-w`: warning of `deprecate_constant`, and no other warning
              deprecated = former.nil? ? [] : ["-e:2: warning: constant #{former} is deprecated"]
              expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(deprecated), stderr)
            end
          end

          it 'warn once when loaded, and give the moved constants under their former names' do
            check_shims(MOVED)
          end

          it 'warn once when loaded, and give the moved constants under their former names, with the gem grpc' do
            reason = grpc_missing
            skip(reason) unless reason.nil?
            check_shims(MOVED_GRPC)
          end
        end
      end
    end
  end
end
