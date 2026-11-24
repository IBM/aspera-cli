# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Schemas that validate values (options, arguments, manifests): each object says if other keys are accepted (`additionalProperties`),
# so that an unknown key is refused by the schema, with a message for the user, or accepted on purpose (with a comment that tells why).
# Not checked: schemas downloaded from their source (vendor files), schemas that are not used to validate values
# (sync configuration and arguments, async tables, ascp logs: they describe command lines and results).

require 'json'
require_relative '../lib/aspera/bundle_registry'
require_relative '../lib/aspera/schema/registry'
require_relative '../lib/aspera/yaml'

# Reading of the schema files of the spec
module SchemaObjects
  # Keywords of a composition: its alternatives or branches state `additionalProperties`
  COMPOSITION = %w[oneOf anyOf allOf].freeze

  module_function

  # @param file [String] Schema file, YAML or JSON
  # @return [Hash] The schema
  def read(file)
    file.end_with?('.json') ? JSON.parse(File.read(file)) : Aspera::Yaml.safe_load(File.read(file))
  end

  # Objects of a schema: nodes of type `object` or with `properties`, in the keywords that contain schemas.
  # @param node    [Hash]   Schema node
  # @param pointer [String] JSON pointer of the node
  # @yieldparam node    [Hash]   Object node
  # @yieldparam pointer [String] Its JSON pointer
  def each(node, pointer = '#', &block)
    return unless node.is_a?(Hash)
    yield(node, pointer) if Array(node['type']).include?('object') || node.key?('properties')
    %w[properties patternProperties $defs definitions].each do |key|
      node[key].each { |name, sub| each(sub, "#{pointer}/#{key}/#{name}", &block) } if node[key].is_a?(Hash)
    end
    node.dig('components', 'schemas')&.each { |name, sub| each(sub, "#{pointer}/components/schemas/#{name}", &block) }
    %w[items additionalProperties unevaluatedProperties not if then else contains].each do |key|
      each(node[key], "#{pointer}/#{key}", &block) if node[key].is_a?(Hash)
    end
    (COMPOSITION + %w[prefixItems]).each do |key|
      node[key].each_with_index { |sub, index| each(sub, "#{pointer}/#{key}/#{index}", &block) } if node[key].is_a?(Array)
    end
  end

  # @param node [Hash] Object node
  # @return [Boolean] `true` if the node says if other keys are accepted
  def stated?(node) = node.key?('additionalProperties') || node.key?('unevaluatedProperties')
end

RSpec.describe('additionalProperties of the schemas of ascli') do
  lib_folder = File.expand_path('../lib', __dir__)
  manifests = Dir.glob(File.join(Aspera::BundleRegistry::GEM_FOLDER, '*', Aspera::BundleRegistry::MANIFEST)).to_h do |file|
    [File.dirname(file), Aspera::Yaml.safe_load(File.read(file))]
  end
  # Schemas of the framework and of the domain, used to validate values
  schema_files = Aspera::Schema::Registry::LOCATIONS.values.map { |path| File.join(lib_folder, path) }
  schema_files.push(File.join(lib_folder, 'aspera/transfer/spec.schema.yaml'))
  manifests.each do |folder, manifest|
    manifest.fetch('schemas', []).each { |schema| schema_files.push(File.join(folder, schema['file'])) if schema['owned'] && !schema.key?('source') }
    manifest.fetch('extension_points', []).each { |point| schema_files.push(File.join(folder, point['schema'])) }
  end
  # Variants of a selector (`x-cli-variants`): schema files given by the entries of the extension point
  variant_files = schema_files.flat_map do |file|
    SchemaObjects.read(file).dig('components', 'schemas').to_h.values.filter_map { |node| node['x-cli-variants'] if node.is_a?(Hash) }.flat_map do |marker|
      manifests.flat_map do |folder, manifest|
        manifest.dig('extensions', marker['point']).to_a.filter_map { |entry| File.join(folder, entry[marker['schema']]) if entry[marker['schema']] }
      end
    end
  end

  it 'finds the schemas and the variants' do
    expect(schema_files.size).to(be > 10)
    expect(variant_files.size).to(be >= 6)
  end

  schema_files.each do |file|
    it "states additionalProperties in each object of #{file.delete_prefix("#{lib_folder}/")}" do
      unstated = []
      SchemaObjects.each(SchemaObjects.read(file)) do |node, pointer|
        next if SchemaObjects::COMPOSITION.any? { |key| node.key?(key) }
        unstated.push(pointer) unless SchemaObjects.stated?(node)
      end
      expect(unstated).to(be_empty)
    end
  end

  variant_files.each do |file|
    it "lets the selector refuse other keys, and states additionalProperties in nested objects of #{file.delete_prefix("#{lib_folder}/")}" do
      wrong = []
      SchemaObjects.each(SchemaObjects.read(file)) do |node, pointer|
        # Root: the keys of the selector (e.g. `agent`) are in the value, `unevaluatedProperties` of the selector refuses other keys
        if pointer.eql?('#')
          wrong.push("#{pointer}: stated") if SchemaObjects.stated?(node)
        else
          wrong.push(pointer) unless SchemaObjects.stated?(node)
        end
      end
      expect(wrong).to(be_empty)
    end
  end
end
