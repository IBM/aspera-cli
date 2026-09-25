# frozen_string_literal: true

require 'spec_helper'
require 'aspera/rest'
require 'aspera/rest/list'
require 'aspera/cli/error'

RSpec.describe(Aspera::Rest::List) do
  # Minimal API returning a fixed list for `read`
  let(:api_class) do
    Class.new do
      include Aspera::Rest::List

      def initialize(items)
        @items = items
      end

      def read(_entity, _query = nil)
        @items
      end
    end
  end

  describe '#lookup_with_q' do
    def lookup(items, value)
      api_class.new(items).lookup_with_q('users', value: value)
    end

    it 'returns single match' do
      expect(lookup([{'name' => 'Bob'}], 'bo')).to(eq({'name' => 'Bob'}))
    end

    it 'extracts items from Hash result' do
      expect(api_class.new({'users' => [{'name' => 'Bob'}]}).lookup_with_q('users', value: 'bob')).to(eq({'name' => 'Bob'}))
    end

    it 'raises when not found' do
      expect { lookup([], 'bob') }.to(raise_error(Aspera::EntityNotFound, /No such users/))
    end

    it 'selects case insensitive full match among partial matches' do
      expect(lookup([{'name' => 'Bobby'}, {'name' => 'BOB'}], 'bob')).to(eq({'name' => 'BOB'}))
    end

    it 'raises when partial matches but no full match' do
      expect { lookup([{'name' => 'Bobby'}, {'name' => 'Bobo'}], 'bob') }.to(raise_error(Aspera::Error, /no case insensitive full match/))
    end

    it 'raises when several full matches' do
      expect { lookup([{'name' => 'bob'}, {'name' => 'Bob'}], 'bob') }.to(raise_error(Aspera::Error, /Multiple entities/))
    end
  end

  describe '.lookup_entity_generic' do
    let(:items) { [{'name' => 'a', 'id' => 1}, {'name' => 'b', 'id' => 2}, {'name' => 'b', 'id' => 3}] }

    it 'returns exact match' do
      expect(described_class.lookup_entity_generic(entity: 'x', value: 'a') { items }).to(eq(items.first))
    end

    it 'raises when not found or ambiguous' do
      expect { described_class.lookup_entity_generic(entity: 'x', value: 'c') { items } }.to(raise_error(Aspera::Cli::BadIdentifier, /not found/))
      expect { described_class.lookup_entity_generic(entity: 'x', value: 'b') { items } }.to(raise_error(Aspera::Cli::BadIdentifier, /found 2/))
    end
  end
end
