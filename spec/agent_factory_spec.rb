# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Agents found through the extension point `agent` of bundles, with the agents of `lib/aspera/agent/` that no bundle provides (legacy):
# `Agent::Factory::ALL`, `Factory#create`, values of option `transfer`, variants of the schema `TransferAgentOptions`.

require 'spec_helper'
require_relative 'bundle_registry_helper'
require_relative '../lib/aspera/agent/factory'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/schema/validator'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/transfer_agent'
require_relative '../lib/aspera/log'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

# Fake bundles of agents
module AgentFactorySpecHelper
  include BundleRegistrySpecHelper

  # `Agent::Factory::ALL` before the extension point `agent`
  TODAY = {
    connect:   {long: 'Connect', short: :c},
    desktop:   {long: 'Desktop', short: :d},
    direct:    {long: 'Direct', short: :a},
    httpgw:    {long: 'Httpgw', short: :h},
    node:      {long: 'Node', short: :n},
    transferd: {long: 'Transferd', short: :t}
  }.freeze

  # Variants of `TransferAgentOptions` before the extension point `agent`: component, by agent, in the order of `oneOf`
  TODAY_VARIANTS = {
    'direct'    => 'DirectAgentOptions',
    'node'      => 'NodeAgentOptions',
    'httpgw'    => 'HttpgwAgentOptions',
    'transferd' => 'TransferdAgentOptions',
    'desktop'   => 'DesktopAgentOptions',
    'connect'   => 'ConnectAgentOptions'
  }.freeze

  # Schema of an entry of the extension point `agent`
  POINT_SCHEMA = {
    'type'                 => 'object',
    'additionalProperties' => false,
    'required'             => %w[name short options_schema],
    'properties'           => {'name' => {'type' => 'string'}, 'short' => {'type' => 'string'}, 'options_schema' => {'type' => 'string'}}
  }.freeze

  # Entry of the fake agent
  ENTRY = {'name' => 'fake', 'short' => 'f', 'file' => 'agent.rb', 'class' => 'Agent', 'options_schema' => 'agent_options.yaml'}.freeze

  # Schema of the parameters of the fake agent
  OPTIONS_SCHEMA = {'type' => 'object', 'description' => 'Parameters of the fake agent.', 'properties' => {'color' => {'type' => 'string'}}}.freeze

  # Bundle that declares the extension point `agent`
  # @param folder [String] Plugin folder
  def write_point_bundle(folder)
    bundle = write_bundle(folder, 'spec_bundle_transfer', manifest: {'commands' => false, 'extension_points' => [{'name' => 'agent', 'schema' => 'agent.schema.yaml'}]}, code: nil)
    File.write(File.join(bundle, 'agent.schema.yaml'), POINT_SCHEMA.to_yaml)
  end

  # @param folder         [String]      Plugin folder
  # @param name           [String]      Name of the bundle
  # @param entries        [Array<Hash>] Entries for `agent`, merged in a valid one (agent `fake`, letter `f`)
  # @param options_schema [Hash, nil]   Schema of the parameters of the agents, `nil`: no file
  # @param code           [String]      Code at the top of `agent.rb`
  # @return [String] Folder of the bundle
  def write_agent_bundle(folder, name = 'spec_bundle_agent', entries: [{}], options_schema: OPTIONS_SCHEMA, code: '')
    entries = entries.map { |entry| ENTRY.merge(entry) }
    bundle = write_bundle(folder, name, manifest: {'commands' => false, 'depends' => %w[spec_bundle_transfer], 'extensions' => {'agent' => entries}}, code: nil)
    File.write(File.join(bundle, 'agent_options.yaml'), options_schema.to_yaml) unless options_schema.nil?
    write_bundle_file(bundle, 'agent.rb', <<~RUBY, code: code)
      class Agent
        attr_reader :options

        def initialize(**options)
          @options = options
        end
      end
    RUBY
    bundle
  end
end

module Aspera
  RSpec.describe('Agents of bundles') do
    include AgentFactorySpecHelper

    let(:folder) { Dir.mktmpdir }
    let(:registry) { BundleRegistry.send(:new, builtin: false) }
    let(:factory) { Agent::Factory.send(:new, registry: registry) }
    # Messages logged at level warn
    let(:warnings) { [] }

    before { allow(Log.log).to(receive(:warn)) { |&block| warnings.push(block.call) } }

    after do
      FileUtils.rm_rf(folder)
      remove_spec_constants
    end

    describe(Agent::Factory) do
      it 'gives the agents of today when no bundle provides an agent' do
        expect(described_class::ALL.to_a).to(eq(AgentFactorySpecHelper::TODAY.to_a))
        registry.add_source(folder)
        expect(factory.all.to_a).to(eq(AgentFactorySpecHelper::TODAY.to_a))
        expect(factory.all).to(be_frozen)
      end

      it 'gives the agents and creates one without the CLI' do
        # Files of the CLI loaded by the factory (Bundler loads the version of the gem; the direct agent loads `cli/formatter` until T24)
        script = <<~RUBY
          before = $LOADED_FEATURES.grep(%r{/aspera/cli/})
          require 'aspera/agent/factory'
          print Aspera::Agent::Factory::ALL.keys.join(','), ' ', ($LOADED_FEATURES.grep(%r{/aspera/cli/}) - before).inspect, ' '
          print Aspera::Agent::Factory.instance.agent_class(:direct)
        RUBY
        out, status = Open3.capture2e(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script)
        expect(status.success?).to(be(true), out)
        expect(out).to(eq("#{AgentFactorySpecHelper::TODAY.keys.join(',')} [] Aspera::Agent::Direct"))
      end

      it 'adds the agents of the bundles, with the letter of the manifest, and the registry scans the sources' do
        write_point_bundle(folder)
        write_agent_bundle(folder, code: "raise 'code of the agent loaded'")
        registry.add_source(folder)
        expect(factory.all.to_a).to(eq(AgentFactorySpecHelper::TODAY.merge(fake: {long: 'Fake', short: :f}).sort.to_a))
      end

      it 'creates an agent of a bundle from the file of its entry' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        expect(defined?(Aspera::Plugins::SpecBundleAgent)).to(be_nil)
        agent = factory.create(:fake, {color: 'blue'})
        expect(agent).to(be_a(Aspera::Plugins::SpecBundleAgent::Agent))
        expect(agent.options).to(eq(color: 'blue'))
        expect(factory.agent_class('fake')).to(be(Aspera::Plugins::SpecBundleAgent::Agent))
      end

      it 'checks the security level of the source of the bundle before loading an agent' do
        write_point_bundle(folder)
        write_agent_bundle(folder, code: "raise 'code of the agent loaded'")
        registry.security_checks(allowed: ->(_level) { true }, check: ->(level, what) { raise Error, "refused #{level} #{what}" })
        registry.add_source(folder, security: :low)
        expect(factory.all).to(include(:fake))
        expect { factory.create(:fake, {}) }.to(raise_error(Error, 'refused low plugin spec_bundle_agent'))
      end

      it 'refuses an agent of an unavailable bundle with the reason' do
        write_point_bundle(folder)
        write_agent_bundle(folder, code: "raise 'code of the agent loaded'")
        registry.add_source(folder)
        allow(registry).to(receive(:missing_gems).and_return(['spec_gem']))
        expect { factory.create(:fake, {}) }.to(raise_error(BundleRegistry::Unavailable, /requires gem spec_gem/))
      end

      it 'uses the agent of a bundle instead of the legacy agent of the same name' do
        write_point_bundle(folder)
        write_agent_bundle(folder, entries: [{'name' => 'direct', 'short' => 'a'}, {'name' => 'node', 'short' => 'm'}])
        registry.add_source(folder)
        expect(factory.all.to_a).to(eq(AgentFactorySpecHelper::TODAY.merge(node: {long: 'Node', short: :m}).to_a))
        expect(factory.agent_class(:direct)).to(be(Aspera::Plugins::SpecBundleAgent::Agent))
        expect(factory.agent_class(:desktop)).to(be(Agent::Desktop))
      end

      it 'leaves out an agent whose name is provided by an earlier entry or whose letter is taken, with a warning, once' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        write_agent_bundle(folder, 'spec_bundle_other', entries: [{'name' => 'fake', 'short' => 'g'}, {'name' => 'other', 'short' => 'f'}, {'name' => 'third', 'short' => 'n'}, {'name' => 'fourth', 'short' => 'yz'}])
        registry.add_source(folder)
        expect(factory.all.keys).to(eq(AgentFactorySpecHelper::TODAY.merge(fake: nil).keys.sort))
        expect(factory.all).to(be(factory.all))
        expect(warnings.grep(/left out/)).to(eq([
          'Agent fake of bundle spec_bundle_other is left out: provided by bundle spec_bundle_agent',
          'Agent other of bundle spec_bundle_other is left out: letter f is taken by agent fake',
          'Agent third of bundle spec_bundle_other is left out: letter n is taken by agent node',
          'Agent of bundle spec_bundle_other is left out: invalid name "fourth" or letter "yz"'
        ]))
      end

      it 'is recomputed when the entries of the bundles change, also for ALL' do
        registry.add_source(folder)
        allow(described_class).to(receive(:instance).and_return(factory))
        expect(described_class::ALL.keys).to(eq(AgentFactorySpecHelper::TODAY.keys))
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        expect(described_class::ALL.keys).to(include(:fake))
      end

      it 'refuses an unknown agent' do
        expect { factory.create(:bogus, {}) }.to(raise_error(AssertError, 'assertion failed: unknown agent: bogus'))
      end

      it 'gives other missing constants to Ruby' do
        expect { described_class::NONE }.to(raise_error(NameError, /NONE/))
      end
    end

    describe 'schema of option transfer' do
      let(:schemas) { Schema::Registry.send(:new) }
      let(:validator) { Schema::Validator.send(:new) }
      let(:selector) { schemas.reader(Schema::Registry::TRANSFER_AGENT_OPTIONS) }

      before do
        registry.add_source(folder)
        allow(BundleRegistry).to(receive(:instance).and_return(registry))
        allow(Schema::Registry).to(receive(:instance).and_return(schemas))
      end

      # @return [Hash] Component by agent, from `discriminator.mapping`, checked with `oneOf`
      def variants
        mapping = selector['discriminator']['mapping']
        expect(selector['oneOf']).to(eq(mapping.values.map { |ref| {'$ref' => ref} }))
        mapping.transform_values { |ref| ref.delete_prefix('#/components/schemas/') }
      end

      it 'gives the variants of today when no bundle provides an agent' do
        allow(BundleRegistry).to(receive(:instance).and_call_original)
        expect(variants.to_a).to(eq(AgentFactorySpecHelper::TODAY_VARIANTS.to_a))
        expect(selector['discriminator']['propertyName']).to(eq('agent'))
        expect(selector.current).not_to(include(Schema::Registry::VARIANTS))
      end

      it 'adds a variant for each agent of the bundles, from the schema of its entry' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        expect(variants.to_a).to(eq(AgentFactorySpecHelper::TODAY_VARIANTS.merge('fake' => 'FakeAgentOptions').to_a))
        expect(schemas.reader('opts:components.schemas.FakeAgentOptions').current).to(eq(AgentFactorySpecHelper::OPTIONS_SCHEMA))
        expect(validator.errors({'agent' => 'fake', 'color' => 'blue'}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).to(be_empty)
        expect(validator.errors({'agent' => 'fake', 'color' => 1}, Schema::Registry::TRANSFER_AGENT_OPTIONS)).to(eq(['value at `/color` is not a string']))
        expect(validator.errors({'agent' => 'bogus'}, Schema::Registry::TRANSFER_AGENT_OPTIONS, partial: true).first).to(include('"fake"'))
      end

      it 'replaces the variant of an agent of the schema by the one of the bundle' do
        write_point_bundle(folder)
        write_agent_bundle(folder, entries: [{'name' => 'direct', 'short' => 'a'}])
        expect(variants.to_a).to(eq(AgentFactorySpecHelper::TODAY_VARIANTS.to_a))
        expect(schemas.reader(Schema::Registry::DIRECT_AGENT_OPTIONS).current).to(eq(AgentFactorySpecHelper::OPTIONS_SCHEMA))
      end

      it 'skips a variant with a warning: schema file that cannot be read, component of another schema, agent of an earlier entry' do
        write_point_bundle(folder)
        write_agent_bundle(folder, entries: [{'name' => 'fake'}, {'name' => 'transfer', 'short' => 'x'}, {'name' => 'fake', 'short' => 'g'}])
        write_agent_bundle(folder, 'spec_bundle_none', entries: [{'name' => 'none', 'short' => 'o'}], options_schema: nil)
        expect(variants.keys).to(eq(AgentFactorySpecHelper::TODAY_VARIANTS.keys + ['fake']))
        expect(warnings.grep(/Variant/)).to(match([
          'Variant transfer of bundle spec_bundle_agent is skipped: component TransferAgentOptions exists',
          'Variant fake of bundle spec_bundle_agent is skipped: added by an earlier entry',
          /\AVariant none of bundle spec_bundle_none is skipped: cannot read .*agent_options.yaml: No such file/
        ]))
      end
    end

    describe(Cli::TransferAgent) do
      let(:schemas) { Schema::Registry.send(:new) }

      before do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        allow(BundleRegistry).to(receive(:instance).and_return(registry))
        allow(Agent::Factory).to(receive(:instance).and_return(factory))
        allow(Schema::Registry).to(receive(:instance).and_return(schemas))
        allow(Schema::Validator).to(receive(:instance).and_return(Schema::Validator.send(:new)))
      end

      # @param argv [Array<String>] Command line
      # @return [Object] Agent created for the command line
      def agent_for(argv)
        context = Cli::Context.new(registry: registry)
        context.options = Cli::Parser.new('test', argv)
        # Declared by the config plugin and the bootstrapper
        context.options.declare(:notify_to, description: 'Notify')
        context.options.declare(:progress_bar, description: 'Display progress bar', allowed: Cli::Type::BOOLEAN, default: true)
        context.main_folder = folder
        context.http_config = double('Http', trusted_cert_locations: [])
        described_class.new(context).agent_instance
      end

      it 'accepts an agent of a bundle as value of option transfer' do
        expect(agent_for(['--transfer=fake'])).to(be_a(Aspera::Plugins::SpecBundleAgent::Agent))
      end

      it 'accepts the parameters of an agent of a bundle, checked with the schema of its entry' do
        expect(agent_for(['--transfer=@json:{"agent":"fake","color":"blue"}']).options).to(include(color: 'blue'))
        expect { agent_for(['--transfer=@json:{"agent":"fake","color":1}']) }.to(raise_error(Cli::BadArgument, %r{/color` is not a string}))
      end
    end
  end
end
