# frozen_string_literal: true

require 'spec_helper'
require 'aspera/rest'
require 'aspera/oauth'
require 'aspera/oauth/boot'
require 'base64'
require 'json'

RSpec.describe(Aspera::OAuth::Boot) do
  # In-memory token cache
  let(:store) do
    Class.new do
      attr_reader :data

      def initialize; @data = {}; end
      def get(id); @data[id]; end
      def put(id, value); @data[id] = value; end
      def delete(id); @data.delete(id); end
      def garbage_collect(_category, _max_age); nil; end
    end.new
  end

  let(:base_params) { {base_url: 'https://example.com/oauth2'} }

  def jwt(payload)
    ['{"alg":"none"}', payload.to_json, 'sig'].map { |i| Base64.urlsafe_encode64(i, padding: false) }.join('.')
  end

  let(:token) { jwt({'sub' => 'user@example.com', 'exp' => Time.now.to_i + 3600}) }

  around do |example|
    factory = Aspera::OAuth::Factory.instance
    previous = factory.instance_variable_get(:@persist)
    factory.persist_mgr = store
    example.run
  ensure
    factory.instance_variable_set(:@persist, previous)
  end

  it 'caches token and refresh token from cookie, identified by token subject' do
    boot = described_class.new(cookie: "aoc.token=#{token}; aoc.refresh=r1", **base_params)
    expect(store.data.values).to(eq([JSON.generate({'access_token' => token, 'refresh_token' => 'r1'})]))
    expect(boot.token).to(eq(token))
    # same cache entry is found using username instead of cookie
    expect(described_class.new(username: 'user@example.com', **base_params).token).to(eq(token))
  end

  it 'accepts matching username' do
    described_class.new(cookie: "aoc.token=#{token}", username: 'user@example.com', **base_params)
    expect(JSON.parse(store.data.values.first)).not_to(have_key('refresh_token'))
  end

  it 'rejects username not matching token subject' do
    expect { described_class.new(cookie: "aoc.token=#{token}", username: 'other', **base_params) }
      .to(raise_error(Aspera::AssertError, /does not match token subject/))
  end

  it 'requires aoc.token in cookie' do
    expect { described_class.new(cookie: 'other=1', **base_params) }.to(raise_error(Aspera::ParameterError, /aoc.token/))
  end

  it 'requires a decodable JWT' do
    expect { described_class.new(cookie: 'aoc.token=not_a_jwt', **base_params) }.to(raise_error(Aspera::AssertError, /not a decodable JWT/))
  end

  it 'requires either cookie or username' do
    expect { described_class.new(**base_params) }.to(raise_error(Aspera::ParameterError, /--password/))
  end

  it 'cannot create a token when cache is empty' do
    boot = described_class.new(username: 'nobody', **base_params)
    expect { boot.token }.to(raise_error(Aspera::AssertError, /re-authenticate in browser/))
  end
end
