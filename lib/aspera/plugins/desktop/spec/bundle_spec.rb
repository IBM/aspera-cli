# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Bundles `desktop` and `connect`: agents of the extension point `agent`, schemas of the agent parameters, shims of the moved files.

require 'spec_helper'
require_relative '../../../agent/factory'
require_relative '../../../bundle_registry'
require_relative '../../../schema/registry'
require_relative '../../../schema/validator'
require_relative '../../transfer_agents/transfer_agent'
require_relative '../../desktop/agent'
require_relative '../../connect/agent'
require 'open3'
require 'rbconfig'

module Aspera
  module Plugins
    RSpec.describe('Bundles desktop and connect') do
      let(:source_root) { File.expand_path('../../../../..', __dir__) }
      let(:registry) { BundleRegistry.instance }

      # The registry scans the plugin folders on first use: this spec also runs alone
      before { registry.extensions(:agent) }

      # @param script [String] Ruby code run in another process: the former constant is not defined in the process of the specs
      # @return [Array(String, String, Process::Status)] stdout, stderr, status
      def run_ruby(script)
        Open3.capture3(RbConfig.ruby, '-w', '-I', File.join(source_root, 'lib'), '-e', script)
      end

      {
        desktop: {letter: 'd', klass: 'Desktop', agent_class: Desktop::Agent},
        connect: {letter: 'c', klass: 'Connect', agent_class: Connect::Agent}
      }.each do |name, info|
        describe("bundle #{name}") do
          let(:bundle_folder) { File.expand_path("../../#{name}", __dir__) }

          it 'is available, depends on the bundle transfer_agents, has no command and no gem' do
            registry.scan
            expect(registry.unavailable_reason(name)).to(be_nil)
            expect(registry[name].depends).to(eq([:transfer_agents]))
            expect(registry[name].gems).to(eq([]))
            expect(registry[name].commands?).to(be(false))
          end

          it "is the entry of the extension point agent, with the letter #{info[:letter]}" do
            entry = registry.extensions(:agent).find { |item| item.bundle.eql?(name) }
            expect(entry).to(have_attributes(file: 'agent.rb', constant: 'Agent'))
            expect(entry.fields).to(eq('name' => name.to_s, 'short' => info[:letter], 'options_schema' => 'schemas/agent_options.yaml'))
            expect(Aspera::Agent::Factory::ALL[name]).to(eq(long: info[:klass], short: info[:letter].to_sym))
            expect(Aspera::Agent::Factory.instance.agent_class(name)).to(be(info[:agent_class]))
          end

          it 'has its parameters in the schema of option transfer, from the file of its entry' do
            component = "#{info[:klass]}AgentOptions"
            selector = Schema::Registry.instance.reader(TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)
            expect(selector['discriminator']['mapping'][name.to_s]).to(eq("#/components/schemas/#{component}"))
            parameters = Schema::Registry.instance.reader("transfer_opts:components.schemas.#{component}")
            expect(parameters.current).to(eq(Yaml.safe_load(File.read(File.join(bundle_folder, 'schemas/agent_options.yaml')))))
            validator = Schema::Validator.instance
            expect(validator.errors({'agent' => name.to_s}, TransferAgents::TransferAgent::TRANSFER_OPTION_SCHEMA)).to(be_empty)
          end

          it 'is no longer in the file of the framework schema' do
            framework = Yaml.safe_load(File.read(File.join(source_root, 'lib', Schema::Registry::LOCATIONS[:opts])))['components']['schemas']
            selector_file = Yaml.safe_load(File.read(File.join(source_root, 'lib/aspera/plugins/transfer_agents/schemas/options.yaml')))['components']['schemas']
            expect(framework.keys).not_to(include("#{info[:klass]}AgentOptions"))
            expect(selector_file['TransferAgentOptions']['discriminator'].fetch('mapping', {})).not_to(include(name.to_s))
          end

          it 'has a shim that warns once when loaded, and gives the moved constant under its former name' do
            path = "aspera/agent/#{name}"
            stdout, stderr, status = run_ruby("2.times { require #{path.inspect} }\nputs Aspera::Agent::#{info[:klass]}.name\n")
            expect(status.success?).to(be(true), stderr)
            expect(stdout.chomp).to(eq("Aspera::Plugins::#{info[:klass]}::Agent"))
            expect(stderr.scan("#{path} is deprecated: use aspera/plugins/#{name}/agent (removed in 5.0)").length).to(eq(1), stderr)
            expect(stderr.lines(chomp: true).grep(/warning:/)).to(eq(["-e:2: warning: constant Aspera::Agent::#{info[:klass]} is deprecated"]), stderr)
          end
        end
      end

      it 'connect does not depend on the bundle desktop: the deprecation message names the product of the domain' do
        expect(Connect::Agent.const_get(:DEPRECATION_MESSAGE)).to(include(Aspera::Products::Desktop::APP_NAME))
        expect(registry[:connect].depends).not_to(include(:desktop))
      end

      it 'the code of the connect product raises Aspera::Error without the CLI' do
        allow(Aspera::Products::Connect.instance).to(receive(:cdn_api).and_return(double('cdn', read: double('resp', body: 'garbage'))))
        expect { Aspera::Products::Connect.instance.versions }.to(raise_error(Aspera::Error, /connect versions/))
      end
    end
  end
end
