# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundle `httpgw`: commands, agent of the extension point `agent`, schema of the agent parameters, shims of the moved files.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../cli/plugins/factory'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../commands'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    module Httpgw
      RSpec.describe('Bundle httpgw') do
        let(:source_root) { File.expand_path('../../../../..', __dir__) }
        let(:bundle_folder) { File.expand_path('..', __dir__) }
        let(:registry) { BundleRegistry.instance }

        # @param script [String] Ruby code run in another process: the former constants are not defined in the process of the specs
        # @return [Array(String, String, Process::Status)] stdout, stderr, status
        def run_ruby(script)
          Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
        end

        describe 'commands' do
          it 'are those of plugin httpgw, from the bundle (which hides the shim of the former plugin file)' do
            expect(registry.unavailable_reason(:httpgw)).to(be_nil)
            expect(registry[:httpgw].depends).to(eq([:transfer]))
            expect(registry[:httpgw].gems).to(eq([]))
            expect(Cli::Plugins::Factory.instance.plugin_source(:httpgw)).to(eq(bundle_folder))
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
            selector = Schema::Registry.instance.reader(Schema::Registry::TRANSFER_AGENT_OPTIONS)
            expect(selector['discriminator']['mapping']['httpgw']).to(eq('#/components/schemas/HttpgwAgentOptions'))
            parameters = Schema::Registry.instance.reader("#{Schema::Registry::OPTIONS}:components.schemas.HttpgwAgentOptions")
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => 'httpgw', 'url' => 'https://gw.example.com', 'synchronous' => true}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).to(be_empty)
            expect(validator.errors({'agent' => 'httpgw', 'url' => 'https://gw.example.com', 'api_version' => 'v3'}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).not_to(be_empty)
          end

          it 'is no longer in the file of the framework schema' do
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            expect(framework.keys).not_to(include('HttpgwAgentOptions'))
            expect(framework['TransferAgentOptions']['discriminator']['mapping']).not_to(include('httpgw'))
          end
        end

        describe 'shims of the moved files' do
          # Former path => former constant, new constant, path to use
          MOVED = {
            'aspera/cli/plugins/httpgw' => %w[Aspera::Cli::Plugins::Httpgw Aspera::Plugins::Httpgw::Commands aspera/plugins/httpgw/commands],
            'aspera/agent/httpgw'       => %w[Aspera::Agent::Httpgw Aspera::Plugins::Httpgw::Agent aspera/plugins/httpgw/agent],
            'aspera/api/httpgw'         => %w[Aspera::Api::Httpgw Aspera::Plugins::Httpgw::Api aspera/plugins/httpgw/api]
          }.freeze

          it 'warn once when loaded, and give the moved constants under their former names' do
            MOVED.each do |path, (former, current, new_path)|
              stdout, stderr, status = run_ruby("2.times { require #{path.inspect} }\nputs Object.const_get(#{former.inspect}).name\n")
              expect(status.success?).to(be(true), stderr)
              expect(stdout.chomp).to(eq(current))
              expect(stderr.scan("#{path} is deprecated: use #{new_path} (removed in 5.0)").length).to(eq(1), stderr)
              # `-w`: warning of `deprecate_constant`, and no other warning
              expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(["-e:2: warning: constant #{former} is deprecated"]), stderr)
            end
          end
        end
      end
    end
  end
end
