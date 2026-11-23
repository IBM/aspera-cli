# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Schema of the manifest `plugin.yaml` of a bundle, and validity of the manifests of the bundles of the gem
# (not validated when read, see `BundleRegistry`).

require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/schema/validator'
require_relative '../lib/aspera/yaml'

RSpec.describe(Aspera::BundleRegistry::MANIFEST) do
  # @param manifest [Hash, String] Manifest, or its YAML text
  # @return [Array<String>] Errors of validation
  def errors(manifest)
    manifest = Aspera::Yaml.safe_load(manifest) if manifest.is_a?(String)
    Aspera::Schema::Validator.instance.errors(manifest, Aspera::Schema::Registry::MANIFEST)
  end

  let(:minimal) { {'name' => 'console', 'title' => 'IBM Aspera Console'} }

  it 'accepts the full example of the design (bundle transferd)' do
    expect(errors(<<~YAML)).to(be_empty)
      name: transferd
      title: IBM Aspera Transfer Daemon
      depends:
        - transfer_agents
      gems:
        - grpc
      commands: true
      schemas:
        - key: transferd
          file: schemas/transferd-config.schema.json
          owned: true
          source:
            url: https://raw.githubusercontent.com/laurent-martin/aspera-api-examples/refs/heads/main/openapi/transferd-config.schema.json
        - key: transferd_opts
          file: schemas/options.yaml
          owned: true
      extensions:
        agent:
          - name: transferd
            short: t
            file: agent.rb
            class: Agent
            options_schema: schemas/agent_options.yaml
      mounts:
        - target: config
          file: config_commands.rb
          module: ConfigCommands
    YAML
  end

  it 'accepts the minimal example of the design (bundle console)' do
    expect(errors(<<~YAML)).to(be_empty)
      name: console
      title: IBM Aspera Console
      commands: true
      schemas:
        - key: console
          file: schemas/IBM Aspera Console-enhanced.yaml
          source:
            url: https://raw.githubusercontent.com/laurent-martin/aspera-api-examples/refs/heads/main/openapi/IBM%20Aspera%20Console-enhanced.yaml
            version: 1.0.0
    YAML
  end

  it 'accepts extension points and services (bundle transfer_agents)' do
    expect(errors(<<~YAML)).to(be_empty)
      name: transfer_agents
      title: Aspera transfer agents, ascp and async
      extension_points:
        - name: agent
          schema: schemas/agent_extension.schema.yaml
      services:
        - name: transfer
          file: transfer_agent.rb
          class: TransferAgent
      mounts:
        - target: config
          file: ascp_actions.rb
          module: AscpActions
    YAML
  end

  it 'requires name and title' do
    expect(errors({'title' => 'x'}).join).to(match(/name/))
    expect(errors({'name' => 'x'}).join).to(match(/title/))
  end

  it 'refuses an unknown field at the top level' do
    expect(errors(minimal.merge('unknown' => 1))).not_to(be_empty)
  end

  it 'refuses an unknown field in an entry' do
    %w[schemas extension_points mounts services].each do |field|
      expect(errors(minimal.merge(field => [{'unknown' => 1}]))).not_to(be_empty, field)
    end
    expect(errors(minimal.merge('schemas' => [{'key' => 'k', 'file' => 'f.yaml', 'source' => {'url' => 'https://x', 'unknown' => 1}}]))).not_to(be_empty)
  end

  it 'accepts the fields of an extension point in an extension entry, with file and class' do
    expect(errors(minimal.merge('extensions' => {'agent' => [{'file' => 'agent.rb', 'class' => 'Agent', 'short' => 't'}]}))).to(be_empty)
    expect(errors(minimal.merge('extensions' => {'agent' => [{'file' => 'agent.rb'}]}))).not_to(be_empty)
    expect(errors(minimal.merge('extensions' => {'Agent' => []}))).not_to(be_empty)
  end

  it 'refuses a name that is not lower case letters, digits and underscores' do
    %w[Console 1console con-sole].each do |name|
      expect(errors(minimal.merge('name' => name))).not_to(be_empty, name)
    end
    expect(errors(minimal.merge('depends' => %w[Node]))).not_to(be_empty)
  end

  it 'refuses a file outside the folder of the bundle' do
    ['../x.rb', '/x.rb', 'a/../x.rb', '.hidden.rb', 'a\\x.rb'].each do |file|
      expect(errors(minimal.merge('services' => [{'name' => 's', 'file' => file, 'class' => 'S'}]))).not_to(be_empty, file)
    end
    expect(errors(minimal.merge('services' => [{'name' => 's', 'file' => 'sub/x.rb', 'class' => 'Sub::S'}]))).to(be_empty)
  end

  it 'refuses a class that is not a constant path' do
    expect(errors(minimal.merge('services' => [{'name' => 's', 'file' => 'x.rb', 'class' => '::S'}]))).not_to(be_empty)
    expect(errors(minimal.merge('services' => [{'name' => 's', 'file' => 'x.rb', 'class' => 'service'}]))).not_to(be_empty)
  end

  it 'refuses a dependency or a gem listed twice' do
    expect(errors(minimal.merge('depends' => %w[node node]))).not_to(be_empty)
    expect(errors(minimal.merge('gems' => %w[grpc grpc]))).not_to(be_empty)
  end

  it 'makes every bundle of the gem available, with its manifest and its extension entries validated' do
    registry = Aspera::BundleRegistry.send(:new, builtin: false)
    registry.add_source(Aspera::BundleRegistry::GEM_FOLDER)
    # Validated as a bundle that is not in the gem
    stub_const('Aspera::BundleRegistry::GEM_FOLDER', File.join(__dir__, 'not_the_gem_folder'))
    registry.scan
    expect(registry.names.to_h { |name| [name, registry.unavailable_reason(name)] }.compact).to(be_empty)
  end

  Dir.glob(File.join(Aspera::BundleRegistry::GEM_FOLDER, '*', Aspera::BundleRegistry::MANIFEST)).each do |file|
    name = File.basename(File.dirname(file))
    it "#{name}: manifest of the gem is valid" do
      manifest = Aspera::Yaml.safe_load(File.read(file))
      expect(errors(manifest)).to(be_empty)
      expect(manifest['name']).to(eq(name))
    end
  end
end
