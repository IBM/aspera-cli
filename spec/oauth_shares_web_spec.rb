# frozen_string_literal: true

require 'spec_helper'
require_relative '../lib/aspera/rest'
require_relative '../lib/aspera/oauth/client/shares_web'
require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/formatter'
require_relative '../lib/aspera/cli/wizard'
require_relative '../lib/aspera/cli/plugins/shares'
require 'securerandom'

RSpec.describe(Aspera::OAuth::SharesWeb) do
  let(:oauth) { described_class.new(redirect_uri: redirect_uri, base_url: 'https://shares.example.com/auth') }
  let(:redirect_uri) { 'http://localhost:12345' }
  let(:opened) { [] }
  let(:environment) { Aspera::Environment.instance }
  let(:token_json) { JSON.generate({'token_type' => 'bearer', 'access_token' => 'new_access', 'refresh_token' => 'new_refresh', 'expires_in' => 86400}) }

  around do |example|
    saved = environment.web_auth
    example.run
  ensure
    environment.web_auth = saved
  end

  before do
    allow(environment).to(receive(:open_uri)) { |url| opened.push(url.to_s) }
    # No cached token: a new one is generated
    allow(Aspera::OAuth::Factory.instance).to(receive(:get_token_info).and_return(nil))
  end

  # @return [String] RelayState of the login page that was opened
  def relay_state_sent
    URI.decode_www_form(URI.parse(opened.first).query).to_h['RelayState']
  end

  # @param extra [Hash] Parameters received on the loopback URL, in addition to the state sent in RelayState
  def receive_on_loopback(**extra)
    server = instance_double(Aspera::WebAuth::Server)
    # evaluated when the answer is waited for: after the browser was opened on the login page
    allow(server).to(receive(:received_request)) do
      {'state' => URI.decode_www_form(URI.parse(relay_state_sent).query).to_h['state']}.merge(extra.transform_keys(&:to_s))
    end
    allow(Aspera::WebAuth::Server).to(receive(:new).and_return(server))
  end

  # The user pastes the code displayed by Shares (evaluated after the login page was opened)
  # @param extra [Hash] content of the code, in addition to the state sent in RelayState
  # @param state [String, nil] state in the code, default: the one that was sent
  def paste_code(state: nil, **extra)
    allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).with('Code', sensitive: true)) do
      Aspera::WebAuth::Blob.encode(:reply, {'state' => state || relay_state_sent.delete_prefix('aspera://device-code?state=')}.merge(extra.transform_keys(&:to_s)))
    end
  end

  def mock_token_call
    allow(oauth.api).to(receive(:create)) { |*args, **kwargs| @create_args = [args, kwargs]; instance_double(Net::HTTPResponse, body: token_json) } # rubocop:disable Style/Semicolon
  end

  it 'requires a loopback redirect_uri, with a path' do
    expect(described_class.new(redirect_uri: 'http://localhost:12345', base_url: 'https://x/auth').instance_variable_get(:@redirect_uri)).to(eq('http://localhost:12345/'))
    expect { described_class.new(redirect_uri: 'http://example.com:12345', base_url: 'https://x/auth') }.to(raise_error(Aspera::AssertError, /loopback/))
  end

  context 'with web_auth=port (default)' do
    before { environment.web_auth = :port }

    it 'opens the SAML login page with a loopback RelayState, then exchanges the received refresh token' do
      receive_on_loopback(access_token: 'browser_access', refresh_token: 'browser_refresh')
      mock_token_call
      expect(oauth.token).to(eq('new_access'))
      # the page of the browser shows the Shares server
      expect(Aspera::WebAuth::Server).to(have_received(:new).with('http://localhost:12345/', include('shares.example.com')))
      login = URI.parse(opened.first)
      expect([login.host, login.path]).to(eq(['shares.example.com', '/auth/saml']))
      expect(relay_state_sent).to(match(%r{\Ahttp://localhost:12345/\?state=[0-9a-f-]{36}\z}))
      expect(relay_state_sent.bytesize).to(be <= 80)
      expect(@create_args.first).to(eq(['oauth2/token', {grant_type: 'refresh_token', refresh_token: 'browser_refresh'}]))
    end

    it 'refuses an answer with another state' do
      allow(Aspera::WebAuth::Server).to(receive(:new).and_return(instance_double(Aspera::WebAuth::Server, received_request: {'state' => 'other', 'refresh_token' => 'x'})))
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /wrong received state/))
    end

    it 'reports a Shares that does not redirect to a loopback URL' do
      receive_on_loopback
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /No token received/))
    end
  end

  context 'with web_auth=paste' do
    before do
      environment.web_auth = :paste
      allow(Aspera::WebAuth::Server).to(receive(:new))
    end

    it 'opens the SAML login page with a device-code RelayState, then exchanges the refresh token of the pasted code' do
      paste_code(refresh_token: 'browser_refresh')
      mock_token_call
      expect(oauth.token).to(eq('new_access'))
      login = URI.parse(opened.first)
      expect([login.host, login.path]).to(eq(['shares.example.com', '/auth/saml']))
      expect(relay_state_sent).to(match(%r{\Aaspera://device-code\?state=[0-9a-f-]{36}\z}))
      expect(relay_state_sent.bytesize).to(be <= 80)
      expect(@create_args.first).to(eq(['oauth2/token', {grant_type: 'refresh_token', refresh_token: 'browser_refresh'}]))
      # no local port
      expect(Aspera::WebAuth::Server).not_to(have_received(:new))
    end

    it 'refuses a code with another state' do
      paste_code(state: 'other', refresh_token: 'x')
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /wrong received state/))
    end

    it 'reports a code without token' do
      paste_code
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /No token received/))
    end

    it 'refuses something that is not a code' do
      allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).and_return('http://localhost:12345/?state=x'))
      expect { oauth.token }.to(raise_error(Aspera::ParameterError, /Not a code/))
    end

    it 'refuses a code of another type' do
      allow(Aspera::Cli::Prompt).to(receive(:prompt_user_input).and_return(Aspera::WebAuth::Blob.encode(:login, {'login_url' => 'https://x'})))
      expect { oauth.token }.to(raise_error(Aspera::ParameterError, /type of code/))
    end
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

        describe '#wizard' do
          let(:wizard_mock) { instance_double(Aspera::Cli::Wizard, required: false) }
          # Generated, none in source
          let(:password) { SecureRandom.alphanumeric(12) }

          it 'generates a basic auth preset with username and password' do
            p = plugin('--auth=basic', '--username=alice', "--password=#{password}")
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result).to(eq(
              preset_ids:   ['alice'],
              preset_value: {url: 'https://shares.example.com', username: 'alice', password: password},
              test_args:    'files browse /'
            ))
          end

          it 'generates a web auth preset with username when auth=web' do
            p = plugin('--auth=web', '--username=alice')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result).to(eq(
              preset_ids:   ['alice'],
              preset_value: {url: 'https://shares.example.com', auth: 'web', username: 'alice'},
              test_args:    'files browse /'
            ))
          end

          it 'generates a web auth preset with web preset_id when username is not provided' do
            p = plugin('--auth=web')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result).to(eq(
              preset_ids:   ['web'],
              preset_value: {url: 'https://shares.example.com', auth: 'web'},
              test_args:    'files browse /'
            ))
          end

          it 'includes redirect_uri in web auth preset when provided' do
            p = plugin('--auth=web', '--redirect-uri=http://localhost:54321')
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result[:preset_value]).to(include(redirect_uri: 'http://localhost:54321'))
          end

          it 'defaults to web auth when SAML is detected and auth is not specified' do
            allow(described_class).to(receive(:health_check).with('https://shares.example.com').and_return({saml: true}))
            p = plugin
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result[:preset_value]).to(include(auth: 'web'))
          end

          it 'defaults to basic auth when password is provided even if auth is not specified' do
            p = plugin('--username=alice', "--password=#{password}")
            result = p.wizard(wizard_mock, 'https://shares.example.com')
            expect(result[:preset_value]).to(eq(url: 'https://shares.example.com', username: 'alice', password: password))
          end

          it 'prompts for auth type interactively when auth and password are not provided' do
            allow(described_class).to(receive(:health_check).with('https://shares.example.com').and_return({saml: true}))
            interactive_wiz = instance_double(Aspera::Cli::Wizard, required: true)
            p = plugin
            allow(p.options).to(receive(:prompt_user_input_in_list).with('auth', described_class::AUTH_TYPES).and_return(:web))
            result = p.wizard(interactive_wiz, 'https://shares.example.com')
            expect(result[:preset_value]).to(include(auth: 'web'))
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
