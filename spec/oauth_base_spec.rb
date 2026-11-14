# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/rest'
require_relative '../lib/aspera/oauth/client/generic'
require 'securerandom'
require 'base64'
require 'json'

RSpec.describe(Aspera::OAuth::Base) do
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

  let(:oauth) { Aspera::OAuth::Generic.new(grant_type: 'client_credentials', base_url: 'https://example.com/oauth2') }

  # Values of tokens are generated, none in source
  def jwt(ttl_sec)
    ['{"alg":"none"}', {'exp' => Time.now.to_i + ttl_sec}.to_json, 'sig'].map { |i| Base64.urlsafe_encode64(i, padding: false) }.join('.')
  end

  let(:valid_token) { jwt(3600) }
  let(:expiring_token) { jwt(10) }
  let(:new_token) { jwt(3600) }
  let(:refresh_token) { SecureRandom.alphanumeric(12) }

  # @param token_data [Hash] Token to put in cache
  def cache(token_data)
    store.put(oauth.instance_variable_get(:@token_cache_id), JSON.generate(token_data))
  end

  # @return [Hash, nil] Token in cache
  def cached
    value = store.get(oauth.instance_variable_get(:@token_cache_id))
    value && JSON.parse(value)
  end

  # Answers of the OAuth server, by grant type: Hash, or Exception to raise
  # Grant type of each token creation call is recorded in `@grants`
  # @param answers [Hash{String => Object}]
  def server(answers)
    @grants = []
    allow(oauth.api).to(receive(:create)) do |_path, body, **|
      @grants.push(body[:grant_type])
      answer = answers.fetch(body[:grant_type])
      raise answer if answer.is_a?(Exception)
      instance_double(Net::HTTPResponse, body: JSON.generate(answer))
    end
  end

  around do |example|
    factory = Aspera::OAuth::Factory.instance
    previous = factory.instance_variable_get(:@persist)
    factory.persist_mgr = store
    example.run
  ensure
    factory.instance_variable_set(:@persist, previous)
  end

  describe '#token' do
    it 'generates and caches a token if none in cache' do
      server('client_credentials' => {'access_token' => new_token})
      expect(oauth.token).to(eq(new_token))
      expect(cached).to(eq({'access_token' => new_token}))
    end

    it 'uses the cached token if it does not expire soon' do
      cache('access_token' => valid_token, 'refresh_token' => refresh_token)
      server({})
      expect(oauth.token).to(eq(valid_token))
      expect(@grants).to(be_empty)
    end

    it 'refreshes the cached token if it expires soon' do
      cache('access_token' => expiring_token, 'refresh_token' => refresh_token)
      server('refresh_token' => {'access_token' => new_token})
      expect(oauth.token).to(eq(new_token))
      expect(oauth.api).to(have_received(:create).with('token', include(grant_type: 'refresh_token', refresh_token: refresh_token), any_args))
      expect(cached).to(eq({'access_token' => new_token}))
    end

    it 'rejects an answer without token' do
      server('client_credentials' => {'other' => 'x'})
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /No such field in answer: access_token/))
    end
  end

  describe '#renew_token' do
    it 'refreshes the cached token, even if it does not expire soon' do
      cache('access_token' => valid_token, 'refresh_token' => refresh_token)
      server('refresh_token' => {'access_token' => new_token})
      expect(oauth.renew_token).to(eq(new_token))
      expect(@grants).to(eq(['refresh_token']))
    end

    it 'generates a new token if refresh fails' do
      cache('access_token' => valid_token, 'refresh_token' => refresh_token)
      server('refresh_token' => Aspera::Rest::CallError.new('refresh'), 'client_credentials' => {'access_token' => new_token})
      expect(oauth.renew_token).to(eq(new_token))
      expect(@grants).to(eq(%w[refresh_token client_credentials]))
      expect(cached).to(eq({'access_token' => new_token}))
    end

    it 'generates a new token if refresh is not supported' do
      cache('access_token' => valid_token, 'refresh_token' => 'not_supported')
      server('client_credentials' => {'access_token' => new_token})
      expect(oauth.renew_token).to(eq(new_token))
      expect(@grants).to(eq(['client_credentials']))
    end

    it 'raises the error of generation, after a single attempt, and discards the cached token' do
      cache('access_token' => valid_token, 'refresh_token' => refresh_token)
      server('refresh_token' => Aspera::Rest::CallError.new('refresh'), 'client_credentials' => Aspera::Rest::CallError.new('generate'))
      expect { oauth.renew_token }.to(raise_error(Aspera::Rest::CallError, 'generate'))
      expect(@grants).to(eq(%w[refresh_token client_credentials]))
      expect(cached).to(be_nil)
    end
  end

  describe 'Authorization header' do
    it 'prefixes the token with Bearer' do
      cache('access_token' => valid_token)
      server('client_credentials' => {'access_token' => new_token})
      expect(oauth.authorization).to(eq("Bearer #{valid_token}"))
      expect(oauth.renewed_authorization).to(eq("Bearer #{new_token}"))
    end
  end
end
