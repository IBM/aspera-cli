# frozen_string_literal: true

require 'spec_helper'
require 'aspera/rest'
require 'aspera/oauth/client/shares_web'
require 'aspera/cli/context'
require 'aspera/cli/parser'
require 'aspera/cli/plugins/shares'

RSpec.describe(Aspera::OAuth::SharesWeb) do
  let(:oauth) { described_class.new(redirect_uri: redirect_uri, base_url: 'https://shares.example.com/auth') }
  let(:redirect_uri) { 'http://localhost:12345' }
  let(:opened) { [] }
  let(:token_json) { JSON.generate({'token_type' => 'bearer', 'access_token' => 'new_access', 'refresh_token' => 'new_refresh', 'expires_in' => 86400}) }

  before do
    allow(Aspera::Environment.instance).to(receive(:open_uri)) { |url| opened.push(url) }
  end

  # @param extra [Hash] Parameters received on the loopback URL, in addition to the state sent in RelayState
  def receive_on_loopback(**extra)
    server = instance_double(Aspera::WebAuth::Server)
    # evaluated when the answer is waited for: after the browser was opened on the login page
    allow(server).to(receive(:received_request)) do
      relay_state = URI.decode_www_form(URI.parse(opened.first).query).to_h['RelayState']
      {'state' => URI.decode_www_form(URI.parse(relay_state).query).to_h['state']}.merge(extra.transform_keys(&:to_s))
    end
    allow(Aspera::WebAuth::Server).to(receive(:new).and_return(server))
  end

  it 'requires a loopback redirect_uri, with a path' do
    expect(described_class.new(redirect_uri: 'http://localhost:12345', base_url: 'https://x/auth').instance_variable_get(:@redirect_uri)).to(eq('http://localhost:12345/'))
    expect { described_class.new(redirect_uri: 'http://example.com:12345', base_url: 'https://x/auth') }.to(raise_error(Aspera::AssertError, /loopback/))
  end

  it 'opens the SAML login page with a loopback RelayState, then exchanges the received refresh token' do
    receive_on_loopback(access_token: 'browser_access', refresh_token: 'browser_refresh')
    create_args = nil
    allow(oauth.api).to(receive(:create)) { |*args, **kwargs| create_args = [args, kwargs]; instance_double(Net::HTTPResponse, body: token_json) } # rubocop:disable Style/Semicolon
    expect(oauth.token(cache: false)).to(eq('new_access'))
    login = URI.parse(opened.first)
    expect([login.host, login.path]).to(eq(['shares.example.com', '/auth/saml']))
    relay_state = URI.decode_www_form(login.query).to_h['RelayState']
    expect(relay_state).to(match(%r{\Ahttp://localhost:12345/\?state=[0-9a-f-]{36}\z}))
    expect(relay_state.bytesize).to(be <= 80)
    expect(create_args.first).to(eq(['oauth2/token', {grant_type: 'refresh_token', refresh_token: 'browser_refresh'}]))
  end

  it 'refuses an answer with another state' do
    allow(Aspera::WebAuth::Server).to(receive(:new).and_return(instance_double(Aspera::WebAuth::Server, received_request: {'state' => 'other', 'refresh_token' => 'x'})))
    expect { oauth.token(cache: false) }.to(raise_error(Aspera::AssertError, /wrong received state/))
  end

  it 'reports a Shares that does not redirect to a loopback URL' do
    receive_on_loopback
    expect { oauth.token(cache: false) }.to(raise_error(Aspera::AssertError, /loopback URL/))
  end
end

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Shares) do
        def plugin(*argv)
          context = Context.new
          context.man_header = false
          context.options = Parser.new('test', argv)
          described_class.new(context: context).tap { context.options.parse_options! }
        end

        it 'uses user and password by default' do
          params = plugin('--url=https://shares.example.com', '--username=u', '--password=p').basic_auth_params('api/v1')
          expect(params).to(eq(base_url: 'https://shares.example.com/api/v1', auth: {type: :basic, username: 'u', password: 'p'}))
        end

        it 'uses OAuth with a web browser for auth=web' do
          params = plugin('--url=https://shares.example.com', '--auth=web', '--username=u').basic_auth_params('node_api')
          expect(params).to(eq(
            base_url: 'https://shares.example.com/node_api',
            auth:     {type: :oauth2, base_url: 'https://shares.example.com/auth', grant_method: :shares_web, redirect_uri: 'http://localhost:12345', cache_ids: ['u']}
          ))
        end

        it 'does not need a user for auth=web, and accepts another redirect_uri' do
          params = plugin('--url=https://shares.example.com', '--auth=web', '--redirect-uri=http://127.0.0.1:45678/cb').basic_auth_params
          expect(params).to(include(base_url: 'https://shares.example.com'))
          expect(params[:auth]).to(include(redirect_uri: 'http://127.0.0.1:45678/cb', cache_ids: []))
        end
      end
    end
  end
end
