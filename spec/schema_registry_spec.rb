# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/schema/validator'
require_relative '../lib/aspera/transfer/spec'
require 'tmpdir'
require 'yaml'

RSpec.describe(Aspera::Schema::Registry) do
  let(:folder) { Dir.mktmpdir }
  let(:registry) { described_class.send(:new) }

  around do |example|
    registered = described_class.instance_variable_get(:@registered).dup
    example.run
  ensure
    described_class.instance_variable_set(:@registered, registered)
    FileUtils.rm_rf(folder)
  end

  # @param name    [String] File name
  # @param content [Hash]   Schema
  # @return [String] Path of the file
  def write_schema(name, content)
    path = File.join(folder, name)
    File.write(path, content.to_yaml)
    path
  end

  describe '.register' do
    it 'gives the schemas of the domain library, added by the files that read them, and only the framework in LOCATIONS' do
      expect(described_class::LOCATIONS.keys).to(eq(%i[opts manifest]))
      expect(described_class.registered(:spec)[:file]).to(end_with('/aspera/transfer/spec.schema.yaml'))
      expect(described_class.known?(:spec)).to(be(true))
      expect(described_class.owned?(described_class::TRANSFER_SPEC)).to(be(true))
      expect(described_class.built_in?(:spec)).to(be(true))
      expect(registry.reader(described_class::TRANSFER_SPEC)['properties']).to(include('direction'))
    end

    it 'adds an owned schema read from its file, again with the same file, not with another one' do
      file = write_schema('a.yaml', {'type' => 'object', 'properties' => {'x' => {'type' => 'string'}}})
      described_class.register(:spec_registry_a, file)
      described_class.register('spec_registry_a', file)
      expect(described_class.known?(:spec_registry_a)).to(be(true))
      expect(described_class.owned?('spec_registry_a:properties.x')).to(be(true))
      expect(registry.reader('spec_registry_a:properties.x').current).to(eq({'type' => 'string'}))
      expect { described_class.register(:spec_registry_a, write_schema('b.yaml', {})) }.to(raise_error(Aspera::AssertError, /registered with another file/))
      expect { described_class.register(:opts, file) }.to(raise_error(Aspera::AssertError, /built-in schema/))
    end

    it 'reserves the keys of the domain library, whether or not their file is loaded' do
      expect(described_class::RESERVED).to(eq(%i[spec conf args async_tables ascp_log]))
      described_class.instance_variable_set(:@registered, {})
      expect(described_class.built_in?(:conf)).to(be(true))
      expect(described_class.registered(:conf)).to(be_nil)
    end

    it 'refuses a key already provided by a bundle, naming both owners' do
      file = write_schema('a.yaml', {'type' => 'object'})
      claimed = Struct.new(:bundle, :file).new(:spec_bundle_x, '/x/api.yaml')
      allow(described_class).to(receive(:bundle_schema).with(:spec_registry_a).and_return(claimed))
      expect { described_class.register(:spec_registry_a, file) }.to(raise_error(Aspera::AssertError, /#{Regexp.escape(file)}.*spec_bundle_x/))
    end

    it 'gives the options of documentation of the whole schema' do
      file = write_schema('a.yaml', {'type' => 'object'})
      described_class.register(:spec_registry_a, file, doc_options: -> { {code_highlight: true} })
      expect(registry.doc_options('spec_registry_a')).to(eq({code_highlight: true}))
      expect(registry.doc_options('spec_registry_a:properties')).to(eq({}))
      expect(registry.doc_options(described_class::OPTIONS)).to(eq({}))
      expect(registry.doc_options(described_class::TRANSFER_SPEC)).to(include(:annotate))
    end
  end

  describe 'reference to another schema' do
    it 'is replaced by a copy of the node, for the reader and the validator' do
      file = write_schema('a.yaml', {
        'openapi'    => '3.1.0',
        'components' => {'schemas' => {'Server' => {'allOf' => [{'$ref' => 'opts:#/components/schemas/WebServerOptions'}, {'type' => 'object', 'properties' => {'name' => {'type' => 'string'}}}]}}}
      })
      described_class.register(:spec_registry_a, file)
      allow(described_class).to(receive(:instance).and_return(registry))
      web_server = registry.reader(described_class::WEB_SERVER_OPTIONS).current
      expect(registry.reader('spec_registry_a:components.schemas.Server')['allOf'].first).to(eq(web_server))
      validator = Aspera::Schema::Validator.send(:new)
      expect(validator.errors({'url' => 'http://localhost:9080', 'name' => 'x'}, 'spec_registry_a:components.schemas.Server')).to(eq([]))
      expect(validator.errors({'url' => 1}, 'spec_registry_a:components.schemas.Server')).not_to(be_empty)
    end

    it 'refuses a node with references, sibling keys, a reference to the same schema, and circular references' do
      {
        'opts:#/components/schemas/McpServerOptions' => /may not contain references/,
        'spec_registry_a:#/components' => /use a local reference/
      }.merge('opts:#/components/schemas/LogOptions' => nil).each do |ref, error|
        file = write_schema('a.yaml', {'components' => {'schemas' => {'Server' => {'$ref' => ref}}}})
        described_class.instance_variable_get(:@registered).delete(:spec_registry_a)
        described_class.register(:spec_registry_a, file)
        reader = described_class.send(:new)
        if error.nil?
          expect(reader.reader('spec_registry_a:components.schemas.Server').current).to(be_a(Hash))
        else
          expect { reader.reader('spec_registry_a') }.to(raise_error(Aspera::AssertError, error))
        end
      end
      described_class.instance_variable_get(:@registered).delete(:spec_registry_a)
      described_class.register(:spec_registry_a, write_schema('a.yaml', {'x' => {'$ref' => 'opts:#/components/schemas/LogOptions', 'description' => 'd'}}))
      expect { described_class.send(:new).reader('spec_registry_a') }.to(raise_error(Aspera::AssertError, /no sibling keys/))
      described_class.register(:spec_registry_b, write_schema('b.yaml', {'x' => {'$ref' => 'spec_registry_c:#/x'}}))
      described_class.register(:spec_registry_c, write_schema('c.yaml', {'x' => {'$ref' => 'spec_registry_b:#/x'}}))
      expect { described_class.send(:new).reader('spec_registry_b') }.to(raise_error(Aspera::AssertError, /circular reference between schemas/))
    end
  end
end
