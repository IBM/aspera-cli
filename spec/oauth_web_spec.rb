# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../lib/aspera/rest'
require_relative '../lib/aspera/oauth/client/web'
require 'securerandom'

RSpec.describe(Aspera::OAuth::Web) do
  def web(redirect_uri, **kwargs) = described_class.new(redirect_uri: redirect_uri, base_url: 'https://example.com/oauth2', **kwargs)

  it 'accepts a loopback redirect_uri, also IPv6' do
    %w[http://localhost:12345 http://127.0.0.1:12345 http://127.0.0.2:12345/cb http://[::1]:12345 https://[::1]:12345/cb].each do |redirect_uri|
      expect { web(redirect_uri) }.not_to(raise_error, redirect_uri)
    end
  end

  it 'refuses a redirect_uri that is not loopback' do
    %w[http://example.com:12345 http://0.0.0.0:12345 http://[::]:12345].each do |redirect_uri|
      expect { web(redirect_uri) }.to(raise_error(Aspera::AssertError, /redirect_uri host must be loopback/), redirect_uri)
    end
  end

  it 'computes the PKCE S256 challenge without padding (RFC 7636 Appendix B)' do
    expect(described_class.pkce_challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk')).to(eq('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM'))
  end

  describe '#create_token' do
    # @return [Array(Hash, Hash)] query of the login page, parameters of the code exchange
    def run_login(**kwargs)
      client = web('http://localhost:12345', params: {client_id: 'CLIENT', client_secret: SecureRandom.hex}, **kwargs)
      login_query = nil
      receiver = double('receiver')
      allow(Aspera::WebAuth).to(receive(:receiver)) do |_uri, _info, login_url:, reply_keys:|
        login_query = Aspera::Rest.query_to_h(URI.parse(login_url).query)
        allow(receiver).to(receive(:received_request).and_return({'code' => 'CODE', 'state' => login_query['state']}))
        receiver
      end
      allow(Aspera::WebAuth).to(receive(:open_login_page))
      exchange = nil
      allow(client).to(receive(:create_token_base)) { |**params| exchange = params }
      client.create_token
      [login_query, exchange]
    end

    it 'sends a S256 challenge, then its verifier, with PKCE' do
      login_query, exchange = run_login(pkce: true)
      expect(login_query).to(include('response_type' => 'code', 'client_id' => 'CLIENT', 'code_challenge_method' => 'S256'))
      expect(login_query).not_to(have_key('client_secret'))
      expect(exchange[:code_verifier]).to(match(/\A[A-Za-z0-9_-]{43}\z/))
      expect(login_query['code_challenge']).to(eq(described_class.pkce_challenge(exchange[:code_verifier])))
      expect(exchange).to(include(grant_type: 'authorization_code', code: 'CODE', include_secret: true))
    end

    it 'uses a new verifier at each login' do
      expect(run_login(pkce: true).last[:code_verifier]).not_to(eq(run_login(pkce: true).last[:code_verifier]))
    end

    it 'opens the login page at an absolute URL' do
      opened = nil
      client = web('http://localhost:12345', params: {client_id: 'CLIENT'}, path_authorize: 'https://login.example.org/o/auth')
      allow(Aspera::WebAuth).to(receive(:receiver)) do |_uri, _info, login_url:, **|
        opened = login_url.to_s
        raise 'stop'
      end
      expect { client.create_token }.to(raise_error('stop'))
      expect(opened).to(start_with('https://login.example.org/o/auth?'))
    end

    it 'sends no PKCE parameter without PKCE' do
      login_query, exchange = run_login
      expect(login_query.keys).not_to(include('code_challenge', 'code_challenge_method'))
      expect(exchange).not_to(have_key(:code_verifier))
    end
  end
end
