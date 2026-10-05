# frozen_string_literal: true

# Unit tests for Aspera::Rest::List paging — no server needed.

require 'aspera/rest/list'

module Aspera
  module Rest
    RSpec.describe(List) do
      # API returning the given pages, in order, then empty pages
      let(:api_class) do
        Class.new do
          include List

          attr_reader :queries

          def initialize(pages)
            @pages = pages
            @queries = []
          end

          def call(query:, **)
            @queries.push(query.dup)
            @pages.shift || {'items' => [], 'total_count' => 0}
          end
        end
      end

      def page(items, total_count = nil)
        {'items' => items, 'total_count' => total_count}.compact
      end

      describe '#list_entities_limit_offset_total_count' do
        it 'reads pages until total count' do
          api = api_class.new([page([1, 2], 3), page([3], 3)])
          expect(api.list_entities_limit_offset_total_count(entity: 'items')).to(eq([[1, 2, 3], 3]))
          expect(api.queries.map { |q| q['offset'] }).to(eq([0, 2]))
        end

        it 'stops on an empty page before total count' do
          api = api_class.new([page([1, 2], 5), page([], 5)])
          expect(api.list_entities_limit_offset_total_count(entity: 'items')).to(eq([[1, 2], 5]))
        end

        it 'stops on a partial page without total count' do
          api = api_class.new([page([1, 2]), page([3])])
          expect(api.list_entities_limit_offset_total_count(entity: 'items', query: {'limit' => 2})).to(eq([[1, 2, 3], nil]))
        end

        it 'applies max and pmax, also as String, without modifying the query' do
          query = {'max' => '3', 'limit' => 2}
          api = api_class.new([page([1, 2], 10), page([3, 4], 10)])
          expect(api.list_entities_limit_offset_total_count(entity: 'items', query: query).first).to(eq([1, 2, 3]))
          expect(query).to(eq({'max' => '3', 'limit' => 2}))
          expect(api.queries.first.keys).not_to(include('max'))
          api = api_class.new([page([1, 2], 10), page([3, 4], 10)])
          expect(api.list_entities_limit_offset_total_count(entity: 'items', query: {'pmax' => '1', 'limit' => 2}).first).to(eq([1, 2]))
        end
      end
    end
  end
end
