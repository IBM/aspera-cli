# frozen_string_literal: true

require 'spec_helper'
require 'aspera/rest'
require 'aspera/oauth/client/shares_web'
require 'aspera/cli/context'
require 'aspera/cli/parser'
require 'aspera/cli/formatter'
require 'aspera/cli/wizard'
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
    # the page of the browser shows the Shares server
    expect(Aspera::WebAuth::Server).to(have_received(:new).with('http://localhost:12345/', include('shares.example.com')))
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
          context.formatter = instance_double(Formatter, display_status: nil, display_results: nil)
          described_class.new(context: context).tap { context.options.parse_options! }
        end

        it 'uses user and password by default' do
          params = plugin('--url=https://shares.example.com', '--username=u', '--password=p').basic_auth_params('api/v1')
          expect(params).to(eq(base_url: 'https://shares.example.com/api/v1', auth: {type: :basic, username: 'u', password: 'p'}))
        end

        it 'uses OAuth with a web browser for auth=saml' do
          params = plugin('--url=https://shares.example.com', '--auth=saml', '--username=u').basic_auth_params('node_api')
          expect(params).to(eq(
            base_url: 'https://shares.example.com/node_api',
            auth:     {type: :oauth2, base_url: 'https://shares.example.com/auth', grant_method: :shares_web, redirect_uri: 'http://localhost:12345', cache_ids: ['u']}
          ))
        end

        it 'does not need a user for auth=saml, and accepts another redirect_uri' do
          params = plugin('--url=https://shares.example.com', '--auth=saml', '--redirect-uri=http://127.0.0.1:45678/cb').basic_auth_params
          expect(params).to(include(base_url: 'https://shares.example.com'))
          expect(params[:auth]).to(include(redirect_uri: 'http://127.0.0.1:45678/cb', cache_ids: []))
        end

        describe '#wizard' do
          let(:wizard_mock) { instance_double(Aspera::Cli::Wizard, required: false) }

          it 'generates a basic auth preset with username and password' do
            p = plugin('--auth=basic', '--username=alice', '--password=secret')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result).to(eq(
              preset_ids:   ['alice'],
              preset_value: {url: 'https://shares.example.com', username: 'alice', password: 'secret'},
              test_args:    'files browse /'
            ))
          end

          it 'generates a saml auth preset with username when auth=saml' do
            p = plugin('--auth=saml', '--username=alice')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result).to(eq(
              preset_ids:   ['alice'],
              preset_value: {url: 'https://shares.example.com', auth: 'saml', username: 'alice'},
              test_args:    'files browse /'
            ))
          end

          it 'generates a saml auth preset with saml preset_id when username is not provided' do
            p = plugin('--auth=saml')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result).to(eq(
              preset_ids:   ['saml'],
              preset_value: {url: 'https://shares.example.com', auth: 'saml'},
              test_args:    'files browse /'
            ))
          end

          it 'includes redirect_uri in saml auth preset when provided' do
            p = plugin('--auth=saml', '--redirect-uri=http://localhost:54321')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result[:preset_value]).to(include(redirect_uri: 'http://localhost:54321'))
          end

          it 'defaults to saml auth when SAML is detected and auth is not specified' do
            allow(described_class).to(receive(:health_check).with('https://shares.example.com').and_return({saml: true}))
            p = plugin
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result[:preset_value]).to(include(auth: 'saml'))
          end

          it 'defaults to basic auth when password is provided even if auth is not specified' do
            p = plugin('--username=alice', '--password=secret')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result[:preset_value]).to(eq(url: 'https://shares.example.com', username: 'alice', password: 'secret'))
          end

          it 'prompts for auth type interactively when auth and password are not provided' do
            allow(described_class).to(receive(:health_check).with('https://shares.example.com').and_return({saml: true}))
            interactive_wiz = instance_double(Aspera::Cli::Wizard, required: true)
            p = plugin
            allow(p.options).to(receive(:prompt_user_input_in_list).with('auth', described_class::AUTH_TYPES).and_return(:saml))
            result = p.wizard(interactive_wiz, 'https://shares.example.com')
            expect(result[:preset_value]).to(include(auth: 'saml'))
          end
        end

        describe '.detect' do
          it 'detects SAML when login page contains /auth/saml' do
            rest = instance_double(Rest::Client)
            allow(Rest::Client).to(receive(:new).and_return(rest))
            allow(rest).to(receive(:read).with('', headers: {'Accept' => 'text/html'})).and_return('<html>aspera-Shares (v1.10.0)<a href="/auth/saml">SAML</a></html>')
            allow(rest).to(receive(:read).with('ping', anything)).and_return('')
            allow(rest).to(receive(:read).with('info', anything)).and_return([{'error' => {'user_message' => 'authentication failed'}}, instance_double(Net::HTTPResponse, code: 401)])
            allow(rest).to(receive(:read).with('health_check')).and_return({})

            info = described_class.detect('shares.example.com')
            expect(info).to(include(version: '1.10.0', url: 'https://shares.example.com', saml: true))
          end

          it 'detects no SAML when login page does not contain /auth/saml' do
            rest = instance_double(Rest::Client)
            allow(Rest::Client).to(receive(:new).and_return(rest))
            allow(rest).to(receive(:read).with('', headers: {'Accept' => 'text/html'})).and_return('<html>aspera-Shares (v1.10.0)</html>')
            allow(rest).to(receive(:read).with('ping', anything)).and_return('')
            allow(rest).to(receive(:read).with('info', anything)).and_return([{'error' => {'user_message' => 'authentication failed'}}, instance_double(Net::HTTPResponse, code: 401)])
            allow(rest).to(receive(:read).with('health_check')).and_return({})

            info = described_class.detect('shares.example.com')
            expect(info).to(include(version: '1.10.0', url: 'https://shares.example.com', saml: false))
          end
        end
      end
    end
  end
end
