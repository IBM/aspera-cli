# frozen_string_literal: true

require 'spec_helper'
require 'aspera/assert'
require 'aspera/schema/reader'

RSpec.describe(Aspera::Schema::Reader) do
  describe '.from_query_params' do
    let(:params) do
      [
        {
          'name'        => 'status',
          'in'          => 'query',
          'description' => 'Filter by package status.',
          'required'    => false,
          'schema'      => {'type' => 'string', 'enum' => %w[completed pending]}
        },
        {
          'name'        => 'per_page',
          'in'          => 'query',
          'description' => 'Number of results per page.',
          'required'    => false,
          'schema'      => {'type' => 'integer'}
        },
        {
          'name'        => 'mandatory_param',
          'in'          => 'query',
          'description' => 'A required param.',
          'required'    => true,
          'schema'      => {'type' => 'string'}
        },
        {
          'name'   => 'path_param',
          'in'     => 'path',
          'schema' => {'type' => 'string'}
        }
      ]
    end

    subject(:reader) { described_class.from_query_params(params) }

    it 'returns a Reader instance' do
      expect(reader).to(be_a(described_class))
    end

    it 'builds a synthetic object schema' do
      expect(reader.current['type']).to(eq('object'))
    end

    it 'includes only in:query params as properties' do
      expect(reader.current['properties'].keys).to(contain_exactly('status', 'per_page', 'mandatory_param'))
    end

    it 'excludes in:path params' do
      expect(reader.current['properties']).not_to(have_key('path_param'))
    end

    it 'copies the schema type into each property' do
      expect(reader.current['properties']['status']['type']).to(eq('string'))
      expect(reader.current['properties']['per_page']['type']).to(eq('integer'))
    end

    it 'copies enum values into the property schema' do
      expect(reader.current['properties']['status']['enum']).to(eq(%w[completed pending]))
    end

    it 'copies OAS-level description into the property when schema has none' do
      expect(reader.current['properties']['status']['description']).to(eq('Filter by package status.'))
    end

    it 'lists required param names in the required array' do
      expect(reader.current['required']).to(eq(['mandatory_param']))
    end

    it 'omits the required key when no params are required' do
      optional_only = params.reject { |p| p['required'] }
      r = described_class.from_query_params(optional_only)
      expect(r.current).not_to(have_key('required'))
    end

    it 'works with each_property (traversable by Schema::Documentation)' do
      names = []
      reader.each_property { |_schema, name, _full| names << name }
      expect(names).to(contain_exactly('status', 'per_page', 'mandatory_param'))
    end

    context 'when schema has its own description' do
      let(:params_with_schema_desc) do
        [{
          'name'        => 'q',
          'in'          => 'query',
          'description' => 'OAS-level description',
          'required'    => false,
          'schema'      => {'type' => 'string', 'description' => 'Schema-level description'}
        }]
      end

      it 'keeps the schema-level description (does not overwrite it)' do
        r = described_class.from_query_params(params_with_schema_desc)
        expect(r.current['properties']['q']['description']).to(eq('Schema-level description'))
      end
    end

    context 'with an empty list' do
      it 'returns a reader with no properties' do
        r = described_class.from_query_params([])
        expect(r.current['properties']).to(be_empty)
        expect(r.current).not_to(have_key('required'))
      end
    end
  end

  describe '#each_property' do
    let(:root) do
      {
        'components' => {
          'schemas' => {
            'Address' => {'type' => 'object', 'properties' => {'city' => {'type' => 'string'}}},
            'Cat'     => {'title' => 'A cat', 'properties' => {'meow' => {'type' => 'boolean'}}},
            'Dog'     => {'properties' => {'bark' => {'type' => 'boolean'}}}
          }
        },
        'type'       => 'object',
        'properties' => {
          'address' => {'$ref' => '#/components/schemas/Address'},
          'pet'     => {
            'oneOf'         => [
              {'$ref' => '#/components/schemas/Cat'},
              {'$ref' => '#/components/schemas/Dog'},
              {'properties' => {'other' => {'type' => 'string'}}}
            ],
            'discriminator' => {'propertyName' => 'kind', 'mapping' => {'cat' => '#/components/schemas/Cat', 'dog' => '#/components/schemas/Dog'}}
          },
          'both'    => {
            'allOf' => [
              {'$ref' => '#/components/schemas/Address'},
              {'properties' => {'zip' => {'type' => 'string'}}}
            ]
          }
        }
      }
    end

    subject(:reader) { described_class.new(root) }

    def full_names(reader)
      names = []
      reader.each_property { |_schema, _name, full| names << full }
      names
    end

    it 'follows $ref when digging' do
      expect(reader.dig('properties', 'address').current).to(eq(root['components']['schemas']['Address']))
    end

    it 'rejects $ref outside of document' do
      bad = described_class.new({'properties' => {'x' => {'$ref' => 'other.json#/x'}}})
      expect { bad.dig('properties', 'x') }.to(raise_error(Aspera::AssertError, /must start with/))
      expect { bad.resolve_ref('other.json#/x') }.to(raise_error(Aspera::AssertError, /must start with/))
    end

    it 'traverses $ref, allOf branches and nested objects' do
      expect(full_names(reader)).to(eq(%w[address address.city pet both both.city both.zip]))
    end

    it 'traverses each oneOf variant with its discriminant value' do
      variants = []
      names = []
      reader.dig('properties', 'pet').each_property(
        on_variant: ->(variant, property, value) { variants << [variant.current['title'], property, value] }
      ) { |_schema, name, _full| names << name }
      expect(names).to(eq(%w[meow bark other]))
      expect(variants).to(eq([['A cat', 'kind', 'cat'], [nil, 'kind', 'dog'], [nil, 'kind', nil]]))
    end

    it 'traverses oneOf without discriminator' do
      no_disc = described_class.new({'oneOf' => [{'properties' => {'a' => {}}}, {'properties' => {'b' => {}}}]})
      values = []
      no_disc.each_property(on_variant: ->(_variant, property, value) { values << [property, value] }) { |*_| nil }
      expect(values).to(eq([[nil, nil], [nil, nil]]))
    end
  end

  describe '#to_rows' do
    subject(:rows) do
      described_class.new({
        'required'   => ['id'],
        'properties' => {
          'id'    => {'type' => %w[string integer], 'description' => 'Identifier'},
          'owner' => {'type' => 'object', 'properties' => {'name' => {'type' => 'string', 'default' => 'me'}}},
          'tags'  => {'type' => 'array', 'items' => {'type' => 'string'}, 'enum' => %w[a b]}
        }
      }).to_rows
    end

    it 'lists fields with union types, nested objects, defaults and enums' do
      expect(rows).to(eq([
        {'name' => 'id', 'type' => 'string, integer', 'required' => true, 'description' => 'Identifier'},
        {'name' => 'owner', 'type' => 'object', 'required' => false, 'description' => ''},
        {'name' => 'owner.name', 'type' => 'string', 'required' => false, 'description' => '', 'default' => 'me'},
        {'name' => 'tags', 'type' => 'Array[string]', 'required' => false, 'description' => '', 'enum' => %w[a b]}
      ]))
    end
  end
end
