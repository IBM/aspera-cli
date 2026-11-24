# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Agents found through the extension point `agent` of bundles:
# `Agent::Factory::ALL`, `Factory#create`, values of option `transfer`, variants of the schema `TransferAgentOptions`.

require 'spec_helper'
require_relative 'bundle_registry_helper'
require_relative '../lib/aspera/agent/factory'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/schema/validator'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/plugins/xfer/transfer_agent'
require_relative '../lib/aspera/plugins/xfer/ascp_actions'
require_relative '../lib/aspera/cli/plugins/config'
require_relative '../lib/aspera/log'
require_relative '../lib/aspera/yaml'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'rbconfig'

# Fake bundles of agents
module AgentFactorySpecHelper
  include BundleRegistrySpecHelper

  # `Agent::Factory::ALL` with the bundles of the gem
  TODAY = {
    connect:   {long: 'Connect', short: :c},
    desktop:   {long: 'Desktop', short: :d},
    direct:    {long: 'Direct', short: :a},
    httpgw:    {long: 'Httpgw', short: :h},
    node:      {long: 'Node', short: :n},
    transferd: {long: 'Transferd', short: :t}
  }.freeze

  # Variants of `TransferAgentOptions` in its file (bundle xfer): component, by agent, in the order of `oneOf` (none: every agent is in a bundle)
  SCHEMA_VARIANTS = {}.freeze
  # Schema of option `transfer`
  OPTION_SCHEMA = Aspera::Plugins::Xfer::TransferAgent::TRANSFER_OPTION_SCHEMA

  # Variants with the bundles of the gem: those of the schema, then the agents of the bundles (by name of bundle)
  TODAY_VARIANTS = SCHEMA_VARIANTS.merge(
    'connect'   => 'ConnectAgentOptions',
    'desktop'   => 'DesktopAgentOptions',
    'direct'    => 'DirectAgentOptions',
    'httpgw'    => 'HttpgwAgentOptions',
    'node'      => 'NodeAgentOptions',
    'transferd' => 'TransferdAgentOptions'
  ).freeze

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

  # Bundle that declares the extension point `agent`, and the schema of option `transfer` (`TransferAgentOptions` of the bundle xfer, which has the marker of the variants)
  # @param folder [String] Plugin folder
  def write_point_bundle(folder)
    key = OPTION_SCHEMA.split(':', 2).first
    manifest = {'commands' => false, 'extension_points' => [{'name' => 'agent', 'schema' => 'agent.schema.yaml'}], 'schemas' => [{'key' => key, 'file' => 'options.yaml', 'owned' => true}]}
    bundle = write_bundle(folder, 'spec_bundle_transfer', manifest: manifest, code: nil)
    File.write(File.join(bundle, 'agent.schema.yaml'), POINT_SCHEMA.to_yaml)
    selector = Aspera::Yaml.safe_load(File.read(File.join(Aspera::BundleRegistry::GEM_FOLDER, 'xfer', 'schemas', 'options.yaml'))).dig('components', 'schemas', 'TransferAgentOptions')
    File.write(File.join(bundle, 'options.yaml'), {'openapi' => '3.1.0', 'components' => {'schemas' => {'TransferAgentOptions' => selector}}}.to_yaml)
  end

  # @param folder         [String]      Plugin folder
  # @param name           [String]      Name of the bundle
  # @param entries        [Array<Hash>] Entries for `agent`, merged in a valid one (agent `fake`, letter `f`)
  # @param options_schema [Hash, nil]   Schema of the parameters of the agents, `nil`: no file
  # @param code           [String]      Code at the top of `agent.rb`
  # @return [String] Folder of the bundle
  def write_agent_bundle(folder, name = 'spec_bundle_agent', entries: [{}], options_schema: OPTIONS_SCHEMA, code: '', depends: %w[spec_bundle_transfer])
    entries = entries.map { |entry| ENTRY.merge(entry) }
    bundle = write_bundle(folder, name, manifest: {'commands' => false, 'depends' => depends, 'extensions' => {'agent' => entries}}, code: nil)
    File.write(File.join(bundle, 'agent_options.yaml'), options_schema.to_yaml) unless options_schema.nil?
    write_bundle_file(bundle, 'agent.rb', <<~RUBY, code: "require 'aspera/agent/base'\n#{code}")
      class Agent < Aspera::Agent::Base
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
    # @return [Class] Class that includes the module of `config ascp` and `config agents`, with the class method `option` of plugins (options are not tested here)
    def actions_class
      Class.new do
        class << self
          def option(*, **); end
        end
        include Aspera::Plugins::Xfer::AscpActions
      end
    end

    include AgentFactorySpecHelper

    let(:folder) { Dir.mktmpdir }
    let(:registry) { BundleRegistry.send(:new, builtin: false) }
    let(:factory) { Agent::Factory.send(:new, registry: registry) }
    # Messages logged at level warn
    let(:warnings) { [] }

    # A warning is given with a message, or with a block
    before { allow(Log.log).to(receive(:warn)) { |message = nil, &block| warnings.push(block.nil? ? message : block.call) } }

    after do
      FileUtils.rm_rf(folder)
      remove_spec_constants
    end

    describe(Agent::Factory) do
      it 'gives the agents of the bundles of the gem, and none without bundle' do
        expect(described_class::ALL.to_a).to(eq(AgentFactorySpecHelper::TODAY.to_a))
        expect(described_class.send(:new, registry: BundleRegistry.send(:new)).all.to_a).to(eq(AgentFactorySpecHelper::TODAY.to_a))
        registry.add_source(folder)
        expect(factory.all).to(eq({}))
        expect(factory.all).to(be_frozen)
      end

      it 'gives the agents and creates one without the CLI' do
        # Files of the CLI loaded by the factory (Bundler loads the version of the gem)
        script = <<~RUBY
          before = $LOADED_FEATURES.grep(%r{/aspera/cli/})
          require 'aspera/agent/factory'
          print Aspera::Agent::Factory::ALL.keys.join(','), ' ', ($LOADED_FEATURES.grep(%r{/aspera/cli/}) - before).inspect, ' '
          print Aspera::Agent::Factory.instance.agent_class(:direct)
        RUBY
        out, status = Open3.capture2e(RbConfig.ruby, '-I', File.expand_path('../lib', __dir__), '-e', script)
        expect(status.success?).to(be(true), out)
        expect(out).to(eq("#{AgentFactorySpecHelper::TODAY.keys.join(',')} [] Aspera::Plugins::Direct::Agent"))
      end

      it 'adds the agents of the bundles, with the letter of the manifest, and the registry scans the sources' do
        write_point_bundle(folder)
        write_agent_bundle(folder, code: "raise 'code of the agent loaded'")
        registry.add_source(folder)
        expect(factory.all.to_a).to(eq([[:fake, {long: 'Fake', short: :f}]]))
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

      it 'refuses an agent that no bundle provides, also when an unavailable bundle of the same name declares no agent' do
        write_bundle(folder, 'node', manifest: {'depends' => %w[spec_bundle_missing]})
        registry.add_source(folder)
        factory.all
        expect(registry.unavailable_reason(:node)).to(include('spec_bundle_missing'))
        expect { factory.agent_class(:node) }.to(raise_error(AssertError, 'assertion failed: unknown agent: node'))
      end

      it 'refuses an agent of an unavailable bundle of the same name that declares it, with the reason' do
        write_point_bundle(folder)
        write_bundle(folder, 'node', manifest: {'commands' => false, 'depends' => %w[spec_bundle_missing], 'extensions' => {'agent' => [AgentFactorySpecHelper::ENTRY.merge('name' => 'node')]}}, code: nil)
        registry.add_source(folder)
        expect { factory.agent_class(:node) }.to(raise_error(BundleRegistry::Unavailable, /plugin node is unavailable: .*spec_bundle_missing/))
      end

      it 'refuses an agent of a bundle of the same name whose manifest cannot be read, with the reason' do
        write_bundle(folder, 'node', manifest: "name: [\n", code: nil)
        registry.add_source(folder)
        expect { factory.agent_class(:node) }.to(raise_error(BundleRegistry::Unavailable, /plugin node is unavailable: invalid manifest/))
      end

      it 'leaves out an agent whose name is provided by an earlier entry or whose letter is taken, with a warning, once' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        write_agent_bundle(folder, 'spec_bundle_other', entries: [{'name' => 'fake', 'short' => 'g'}, {'name' => 'other', 'short' => 'f'}, {'name' => 'third', 'short' => 'n'}, {'name' => 'fourth', 'short' => 'yz'}])
        registry.add_source(folder)
        expect(factory.all.keys).to(eq(%i[fake third]))
        expect(factory.all).to(be(factory.all))
        expect(warnings.grep(/left out/)).to(eq([
          'Agent fake of bundle spec_bundle_other is left out: provided by bundle spec_bundle_agent',
          'Agent other of bundle spec_bundle_other is left out: letter f is taken by agent fake',
          'Agent of bundle spec_bundle_other is left out: invalid name "fourth" or letter "yz"'
        ]))
      end

      it 'gives the name of the agent of an instance, and tells agents of bundles' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        expect(factory.agent_name(factory.create(:fake, {}))).to(eq(:fake))
        expect(factory.agent_name(Object.new)).to(be_nil)
        expect([factory.provided?(:fake), factory.provided?('node')]).to(eq([true, false]))
      end

      it 'gives the name of the agent of an instance without loading the code of the other bundles' do
        write_point_bundle(folder)
        write_agent_bundle(folder, code: "raise 'code of the agent loaded'")
        write_agent_bundle(folder, 'spec_bundle_other', entries: [{'name' => 'other', 'short' => 'o'}])
        registry.add_source(folder)
        expect(factory.agent_name(factory.create(:other, {}))).to(eq(:other))
        expect(factory.agent_name(Class.new.new)).to(be_nil)
      end

      it 'gives the name of the agent of an instance when the security level refuses another bundle' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        write_agent_bundle(folder, 'spec_bundle_other', entries: [{'name' => 'other', 'short' => 'o'}])
        registry.add_source(folder)
        instance = factory.create(:other, {})
        registry.security_checks(allowed: ->(_level) { true }, check: ->(level, what) { raise Error, "refused #{level} #{what}" })
        registry.add_source(folder, security: :low)
        expect(factory.agent_name(instance)).to(eq(:other))
      end

      it 'refuses an agent of an unavailable bundle that is not named like the agent, with the reason' do
        write_point_bundle(folder)
        write_bundle(folder, 'spec_bundle_agents', manifest: {'commands' => false, 'depends' => %w[spec_bundle_missing], 'extensions' => {'agent' => [AgentFactorySpecHelper::ENTRY.merge('name' => 'foo', 'short' => 'o')]}}, code: nil)
        registry.add_source(folder)
        expect(factory.unavailable_reason(:foo)).to(match(/plugin spec_bundle_agents is unavailable: .*spec_bundle_missing/))
        expect { factory.create(:foo, {}) }.to(raise_error(BundleRegistry::Unavailable, /plugin spec_bundle_agents is unavailable: .*spec_bundle_missing/))
        expect(factory.unavailable_reason(:bogus)).to(be_nil)
        expect(factory.unavailable_reason(:fake)).to(be_nil)
      end

      it 'is recomputed when the entries of the bundles change, also for ALL' do
        registry.add_source(folder)
        allow(described_class).to(receive(:instance).and_return(factory))
        expect(described_class::ALL.keys).to(eq([]))
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
      let(:selector) { schemas.reader(AgentFactorySpecHelper::OPTION_SCHEMA) }

      before do
        # The schema of option transfer: given by the bundle of the extension point
        write_point_bundle(folder)
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

      it 'gives the variants of today: those of the schema, then the agents of the bundles of the gem' do
        allow(BundleRegistry).to(receive(:instance).and_call_original)
        expect(variants.to_a).to(eq(AgentFactorySpecHelper::TODAY_VARIANTS.to_a))
        expect(selector['discriminator']['propertyName']).to(eq('agent'))
        expect(selector.current).not_to(include(Schema::Registry::VARIANTS))
      end

      it 'adds a variant for each agent of the bundles, from the schema of its entry' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        expect(variants.to_a).to(eq(AgentFactorySpecHelper::SCHEMA_VARIANTS.merge('fake' => 'FakeAgentOptions').to_a))
        expect(schemas.reader('transfer_opts:components.schemas.FakeAgentOptions').current).to(eq(AgentFactorySpecHelper::OPTIONS_SCHEMA))
        expect(validator.errors({'agent' => 'fake', 'color' => 'blue'}, AgentFactorySpecHelper::OPTION_SCHEMA)).to(be_empty)
        expect(validator.errors({'agent' => 'fake', 'color' => 1}, AgentFactorySpecHelper::OPTION_SCHEMA)).to(eq(['value at `/color` is not a string']))
        expect(validator.errors({'agent' => 'bogus'}, AgentFactorySpecHelper::OPTION_SCHEMA, partial: true).first).to(include('"fake"'))
      end

      it 'adds no variant for an agent left out by Agent::Factory: its letter is taken' do
        write_agent_bundle(folder, entries: [{}, {'name' => 'other', 'short' => 'f'}, {'name' => 'third', 'short' => 't'}])
        allow(Agent::Factory).to(receive(:instance).and_return(factory))
        expect(factory.all.keys).to(eq(%i[fake third]))
        expect(variants.keys).to(eq(AgentFactorySpecHelper::SCHEMA_VARIANTS.keys + %w[fake third]))
        expect(warnings.grep(/Variant other/)).to(eq(['Variant other of bundle spec_bundle_agent is skipped: short f is taken by fake']))
      end

      it 'reads the variants again when the entries of the extension point change (bundles of a plugin folder added later)' do
        agents = -> { schemas.reader(AgentFactorySpecHelper::OPTION_SCHEMA)['discriminator']['mapping'].keys }
        expect(agents.call).to(eq(AgentFactorySpecHelper::SCHEMA_VARIANTS.keys))
        expect(validator.errors({'agent' => 'fake'}, AgentFactorySpecHelper::OPTION_SCHEMA, partial: true)).not_to(be_empty)
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        expect(agents.call).to(eq(AgentFactorySpecHelper::SCHEMA_VARIANTS.keys + ['fake']))
        expect(validator.errors({'agent' => 'fake', 'color' => 'blue'}, AgentFactorySpecHelper::OPTION_SCHEMA)).to(be_empty)
        expect(schemas.reader(Schema::Registry::LOG_OPTIONS).current).to(be(schemas.reader(Schema::Registry::LOG_OPTIONS).current))
      end

      # @param selector [Hash] `oneOf` and `discriminator` of the component with the marker
      # @param others   [Hash] Other components of the document
      # @return [Hash] Components of a document with that component (`Selector`), after the variants are added
      def assembled(selector, others = {})
        marker = {'point' => 'agent', 'value' => 'name', 'schema' => 'options_schema', 'suffix' => 'AgentOptions'}
        document = {'components' => {'schemas' => {'Selector' => selector.merge(Schema::Registry::VARIANTS => marker)}.merge(others)}}
        schemas.send(:add_variants, document, File.join(folder, 'document.yaml')).dig('components', 'schemas')
      end

      it 'gives the reason when the agent is declared by an unavailable bundle, and keeps the message for an unknown agent' do
        write_agent_bundle(folder, 'spec_bundle_agent')
        write_agent_bundle(folder, 'spec_bundle_down', entries: [{'name' => 'foo', 'short' => 'x'}], depends: %w[spec_bundle_transfer spec_bundle_nowhere])
        expect(variants.keys).to(eq(AgentFactorySpecHelper::SCHEMA_VARIANTS.keys + %w[fake]))
        option = AgentFactorySpecHelper::OPTION_SCHEMA
        reason = registry.load_error(:spec_bundle_down)
        expect(reason).to(match(/\Aplugin spec_bundle_down is unavailable: /))
        expect(validator.errors({'agent' => 'foo'}, option, partial: true)).to(eq([reason]))
        expect(validator.errors({'agent' => 'bogus'}, option, partial: true).first).to(match(/is not one of: .*"fake"/))
        expect(validator.errors({'agent' => 'fake', 'color' => 'blue'}, option)).to(be_empty)
        expect(selector[Schema::Registry::UNAVAILABLE]).to(eq('foo' => reason))
        expect(variants.keys).not_to(include('foo'))
      end

      it 'skips an entry whose letter is missing or is not one letter, as Agent::Factory does, with a warning' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        entry = registry.extensions(:agent).first
        entries = [{'name' => 'one', 'short' => nil}, {'name' => 'two', 'short' => 'tt'}, {'name' => 'three', 'short' => 4}, {'name' => 'four', 'short' => ''}]
        extensions = entries.map { |fields| entry.with(fields: AgentFactorySpecHelper::ENTRY.except('file', 'class').merge(fields)) }
        allow(registry).to(receive(:extensions).with(:agent).and_return(extensions))
        marker = {'point' => 'agent', 'value' => 'name', 'schema' => 'options_schema', 'suffix' => 'AgentOptions', 'unique' => 'short'}
        document = {'components' => {'schemas' => {'Selector' => {'oneOf' => [], 'discriminator' => {'propertyName' => 'agent'}, Schema::Registry::VARIANTS => marker}}}}
        components = schemas.send(:add_variants, document, File.join(folder, 'document.yaml')).dig('components', 'schemas')
        expect(components.keys).to(eq(['Selector']))
        expect(warnings.grep(/one-letter string/).size).to(eq(4))
        expect(factory.send(:provided_agents, extensions)).to(be_empty)
      end

      it 'replaces a variant of the document by the one of the bundle with the same agent, at its place' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        components = assembled({
          'oneOf'         => [{'$ref' => '#/components/schemas/FakeAgentOptions'}, {'$ref' => '#/components/schemas/Other'}],
          'discriminator' => {'propertyName' => 'agent', 'mapping' => {'fake' => '#/components/schemas/FakeAgentOptions', 'other' => '#/components/schemas/Other'}}
        }, 'FakeAgentOptions' => {'type' => 'object'})
        expect(components['Selector']['oneOf']).to(eq([{'$ref' => '#/components/schemas/FakeAgentOptions'}, {'$ref' => '#/components/schemas/Other'}]))
        expect(components['Selector']['discriminator']['mapping'].keys).to(eq(%w[fake other]))
        expect(components['FakeAgentOptions']).to(eq(AgentFactorySpecHelper::OPTIONS_SCHEMA))
      end

      it 'creates oneOf and the mapping of the discriminator when the document has no variant' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        components = assembled('discriminator' => {'propertyName' => 'agent'})
        expect(components['Selector']).to(eq(
          'oneOf'         => [{'$ref' => '#/components/schemas/FakeAgentOptions'}],
          'discriminator' => {'propertyName' => 'agent', 'mapping' => {'fake' => '#/components/schemas/FakeAgentOptions'}}
        ))
        expect { assembled({}) }.to(raise_error(AssertError, /discriminator/))
      end

      it 'skips a variant with a warning: schema file that cannot be read, component of another schema, agent of an earlier entry' do
        write_point_bundle(folder)
        write_agent_bundle(folder, entries: [{'name' => 'fake'}, {'name' => 'transfer', 'short' => 'x'}, {'name' => 'fake', 'short' => 'g'}])
        write_agent_bundle(folder, 'spec_bundle_none', entries: [{'name' => 'none', 'short' => 'o'}], options_schema: nil)
        expect(variants.keys).to(eq(AgentFactorySpecHelper::SCHEMA_VARIANTS.keys + ['fake']))
        expect(warnings.grep(/Variant/)).to(match([
          'Variant transfer of bundle spec_bundle_agent is skipped: component TransferAgentOptions exists',
          'Variant fake of bundle spec_bundle_agent is skipped: added by an earlier entry',
          /\AVariant none of bundle spec_bundle_none is skipped: cannot read .*agent_options.yaml: No such file/
        ]))
      end
    end

    describe(Plugins::Xfer::ConfigCommands) do
      let(:specs) { Cli::Plugins::Config.command_registry }

      it 'accepts an agent of a bundle added after the class of config is loaded, for the commands of agents and of ascp' do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        allow(Agent::Factory).to(receive(:instance).and_return(factory))
        [%i[agents show], %i[agents parameters], %i[ascp schema], %i[ascp spec]].each do |path|
          expect(specs[path].arguments.first.allowed).to(include(:fake))
        end
      end

      it 'uses the constant of config for the last version of the deprecated commands' do
        expect(described_class.const_defined?(:DEPRECATED_LAST, false)).to(be(false))
      end
    end

    describe(Plugins::Xfer::AscpActions) do
      let(:schemas) { Schema::Registry.send(:new) }
      let(:actions) { actions_class.new }

      before do
        write_point_bundle(folder)
        write_agent_bundle(folder)
        registry.add_source(folder)
        allow(BundleRegistry).to(receive(:instance).and_return(registry))
        allow(Agent::Factory).to(receive(:instance).and_return(factory))
        allow(Schema::Registry).to(receive(:instance).and_return(schemas))
      end

      it 'gives the parameters of an agent of a bundle, from the schema of its entry' do
        rows = actions.action_agents_list.data
        expect(rows.find { |row| row['name'].eql?('fake') }).to(include('short' => 'f', 'parameters' => 'color'))
        expect(actions.action_agents_show(agent_name: :fake).data['description']).to(eq('Parameters of the fake agent.'))
        expect(actions.action_agents_parameters(agent_name: :fake)).to(be_a(Cli::Result::ObjectList))
        expect(actions.action_agents_parameters(agent_name: :desktop)).to(be_a(Cli::Result::Nothing))
      end
    end

    describe('parameters of the agents of the gem bundles') do
      let(:schemas) { Schema::Registry.send(:new) }
      let(:actions) { actions_class.new }
      let(:gem_registry) { BundleRegistry.send(:new) }
      let(:gem_factory) { Agent::Factory.send(:new, registry: gem_registry) }

      before do
        allow(BundleRegistry).to(receive(:instance).and_return(gem_registry))
        allow(Agent::Factory).to(receive(:instance).and_return(gem_factory))
        allow(Schema::Registry).to(receive(:instance).and_return(schemas))
      end

      it 'gives nothing and "(no configurable parameters)" for the agents without parameter (connect, desktop)' do
        %i[connect desktop].each do |agent|
          expect(actions.action_agents_parameters(agent_name: agent)).to(be_a(Cli::Result::Nothing))
          expect(actions.action_agents_show(agent_name: agent).data['description']).to(eq('(no configurable parameters)'))
        end
        rows = actions.action_agents_list.data.to_h { |row| [row['name'], row['parameters']] }
        expect(rows.values_at('connect', 'desktop')).to(eq(['', '']))
      end

      it 'gives the parameters of the other agents' do
        %i[direct httpgw transferd node].each do |agent|
          expect(actions.action_agents_parameters(agent_name: agent)).to(be_a(Cli::Result::ObjectList))
          expect(actions.action_agents_show(agent_name: agent).data['description']).not_to(eq('(no configurable parameters)'))
          expect(actions.action_agents_list.data.find { |row| row['name'].eql?(agent.to_s) }['parameters']).not_to(be_empty)
        end
      end
    end

    describe(Plugins::Xfer::TransferAgent) do
      let(:schemas) { Schema::Registry.send(:new) }

      before do
        # The folder of file lists of transfers is not used here
        allow(Transfer::Parameters).to(receive(:file_list_folder=))
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
        context.options.declare(:progress_bar, description: 'Display progress bar', allowed: Cli::Option::Type::BOOLEAN, default: true)
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

      it 'gives the name of the agent: of option transfer, of an agent instance given' do
        write_agent_bundle(folder, 'spec_bundle_other', entries: [{'name' => 'other', 'short' => 'o'}])
        registry.add_source(folder)
        context = Cli::Context.new(registry: registry)
        context.options = Cli::Parser.new('test', ['--transfer=fake'])
        context.options.declare(:notify_to, description: 'Notify')
        context.options.declare(:progress_bar, description: 'Display progress bar', allowed: Cli::Option::Type::BOOLEAN, default: true)
        context.main_folder = folder
        context.http_config = double('Http', trusted_cert_locations: [])
        transfer = described_class.new(context)
        transfer.agent_instance
        expect(transfer.agent_name).to(eq('fake'))
        transfer.agent_instance = factory.agent_class(:other).allocate
        expect(transfer.agent_name).to(eq('other'))
      end

      it 'gives a CLI error with the reason for the default agent when its bundle is unavailable' do
        write_bundle(folder, 'direct', manifest: "name: [\n", code: nil)
        registry.add_source(folder)
        expect { agent_for([]) }.to(raise_error(Cli::Error, /plugin direct is unavailable: invalid manifest/))
        # An explicit value is refused by the schema of option transfer, which lists the available agents only
        expect { agent_for(['--transfer=bogus']) }.to(raise_error(Cli::BadArgument, /is not one of/))
      end

      it 'gives a CLI error for an agent of a bundle that cannot be loaded' do
        allow(registry).to(receive(:missing_gems).and_return(['spec_gem']))
        expect { agent_for(['--transfer=fake']) }.to(raise_error(Cli::Error, 'plugin spec_bundle_agent requires gem spec_gem: gem install spec_gem'))
      end
    end
  end
end
