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

    subject(:reader){described_class.from_query_params(params)}

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
      optional_only = params.reject{ |p| p['required']}
      r = described_class.from_query_params(optional_only)
      expect(r.current).not_to(have_key('required'))
    end

    it 'works with each_property (traversable by Schema::Documentation)' do
      names = []
      reader.each_property{ |_schema, name, _full| names << name}
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
end
