# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/rest'
require_relative '../lib/aspera/oauth/client/generic'
require 'securerandom'
require 'base64'
require 'json'
require 'time'

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
      expect(cached).to(include('access_token' => new_token))
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
      expect(cached).to(include('access_token' => new_token))
    end

    it 'stores when the token was obtained, and the expiration of an opaque token' do
      server('client_credentials' => {'access_token' => refresh_token, 'expires_in' => 86_400})
      oauth.token
      expect(Time.parse(cached['obtained_at'])).to(be_within(5).of(Time.now))
      expect(Time.parse(cached['expires_at'])).to(be_within(5).of(Time.now + 86_400))
    end

    it 'refreshes a cached opaque token if it expires soon' do
      cache('access_token' => SecureRandom.alphanumeric(12), 'refresh_token' => refresh_token, 'expires_at' => (Time.now + 10).utc.iso8601)
      server('refresh_token' => {'access_token' => new_token})
      expect(oauth.token).to(eq(new_token))
      expect(@grants).to(eq(['refresh_token']))
    end

    context 'with token_refresh_max_age' do
      around do |example|
        parameters = Aspera::OAuth::Factory.instance.parameters
        parameters[:token_refresh_max_age] = 3600
        example.run
      ensure
        parameters[:token_refresh_max_age] = 0
      end

      it 'refreshes a cached token obtained since more than the maximum age' do
        cache('access_token' => valid_token, 'refresh_token' => refresh_token, 'obtained_at' => (Time.now - 3700).utc.iso8601)
        server('refresh_token' => {'access_token' => new_token})
        expect(oauth.token).to(eq(new_token))
        expect(@grants).to(eq(['refresh_token']))
      end

      it 'uses a cached token obtained since less than the maximum age' do
        cache('access_token' => valid_token, 'refresh_token' => refresh_token, 'obtained_at' => (Time.now - 60).utc.iso8601)
        server({})
        expect(oauth.token).to(eq(valid_token))
        expect(@grants).to(be_empty)
      end
    end

    it 'rejects an answer without token' do
      server('client_credentials' => {'other' => 'x'})
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /No such field in answer: access_token/))
    end

    context 'with a nested token field' do
      # e.g. Slack: the user token is in `authed_user`
      let(:oauth) { Aspera::OAuth::Generic.new(grant_type: 'client_credentials', base_url: 'https://example.com/oauth2', token_field: 'authed_user.access_token') }

      it 'generates a token read from the nested field, and uses it from cache' do
        server('client_credentials' => {'ok' => true, 'authed_user' => {'access_token' => new_token}})
        expect(oauth.token).to(eq(new_token))
        expect(cached).to(include('authed_user' => {'access_token' => new_token}))
        expect(oauth.token).to(eq(new_token))
        expect(@grants).to(eq(['client_credentials']))
      end

      it 'rejects an answer without the nested field' do
        server('client_credentials' => {'ok' => true, 'authed_user' => 'x', 'access_token' => valid_token})
        expect { oauth.token }.to(raise_error(Aspera::AssertError, /No such field in answer: authed_user.access_token/))
      end
    end
  end

  describe 'Factory.token_value' do
    it 'reads a field, or a dot-separated path of a nested field' do
      expect(Aspera::OAuth::Factory.token_value({'access_token' => 'a'}, 'access_token')).to(eq('a'))
      expect(Aspera::OAuth::Factory.token_value({'authed_user' => {'access_token' => 'b'}}, 'authed_user.access_token')).to(eq('b'))
    end

    it 'gives nil for a missing field, or an intermediate value that is not a Hash' do
      expect(Aspera::OAuth::Factory.token_value({'other' => 'x'}, 'access_token')).to(be_nil)
      expect(Aspera::OAuth::Factory.token_value({'authed_user' => 'x'}, 'authed_user.access_token')).to(be_nil)
      expect(Aspera::OAuth::Factory.token_value({}, 'authed_user.access_token')).to(be_nil)
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
      expect(cached).to(include('access_token' => new_token))
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

  describe 'token end point as absolute URL' do
    let(:token_url) { 'https://token.example.org/token' }
    let(:oauth_abs) { Aspera::OAuth::Generic.new(grant_type: 'client_credentials', base_url: 'https://example.com/oauth2', path_token: token_url) }

    it 'gives the URL of an end point, relative to the base URL or absolute' do
      expect(oauth.endpoint_url('authorize')).to(eq('https://example.com/oauth2/authorize'))
      expect(oauth.endpoint_url('HTTPS://other.example.org/auth')).to(eq('HTTPS://other.example.org/auth'))
    end

    it 'uses the OAuth API for a path, and an API on the URL for an absolute URL' do
      expect(oauth.endpoint_api('token')).to(eq([oauth.api, 'token']))
      token_api, subpath = oauth_abs.endpoint_api(token_url)
      expect([token_api.base_url, subpath]).to(eq([token_url, '']))
      expect(token_api.params.except(:base_url)).to(eq(oauth_abs.api.params.except(:base_url)))
    end

    it 'creates the token on the absolute URL' do
      token_api = instance_double(Aspera::Rest::Client)
      allow(Aspera::Rest::Client).to(receive(:new).and_call_original)
      allow(Aspera::Rest::Client).to(receive(:new).with(hash_including(base_url: token_url)).and_return(token_api))
      allow(token_api).to(receive(:create).and_return(instance_double(Net::HTTPResponse, body: JSON.generate({'access_token' => new_token}))))
      expect(oauth_abs.token).to(eq(new_token))
      expect(token_api).to(have_received(:create).with('', include(grant_type: 'client_credentials'), any_args))
    end

    it 'keeps the token cache id of the base URL' do
      expect(oauth_abs.instance_variable_get(:@token_cache_id)).to(eq(oauth.instance_variable_get(:@token_cache_id)))
    end
  end
end
