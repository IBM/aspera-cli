# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../../../rest'
require_relative '../../../cli/context'
require_relative '../../../cli/parser'
require_relative '../../../cli/formatter'
require_relative '../../../cli/wizard'
require_relative '../commands'
require_relative '../shares_web'
require 'securerandom'

RSpec.describe(Aspera::Plugins::Shares::SharesWeb) do
  let(:oauth) { described_class.new(redirect_uri: redirect_uri, base_url: 'https://shares.example.com/auth') }
  let(:redirect_uri) { 'http://localhost:12345' }
  let(:opened) { [] }
  let(:environment) { Aspera::Environment.instance }
  let(:token_json) { JSON.generate({'token_type' => 'bearer', 'access_token' => '<ACCESS_TOKEN>', 'refresh_token' => '<REFRESH_TOKEN>', 'expires_in' => 86400}) }

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

  # The user pastes a text in the prompt, which validates it (not valid: error, as without terminal) and returns it
  # @yieldreturn [String] Text pasted (evaluated after the login page was opened)
  def paste
    allow(Aspera::Prompt).to(receive(:prompt_user_input).with('Code', sensitive: true, validate: kind_of(Proc))) { |*, validate:, **| yield.tap { |text| validate.call(text) } }
  end

  # @param extra [Hash] content of the code, in addition to the state sent in RelayState
  # @param state [String, nil] state in the code, default: the one that was sent
  # @param key_state [String, nil] state used for the key of the code, default: the one that was sent
  # @return [String] Code displayed by Shares (to call after the login page was opened)
  def code_of_shares(state: nil, key_state: nil, **extra)
    sent = relay_state_sent.delete_prefix('aspera://device-code?state=')
    # Shares uses the state received in RelayState as secret of the code
    Aspera::SealedHash.seal({'state' => state || sent}.merge(extra.transform_keys(&:to_s)), secret: key_state || sent, base_key: Aspera::Cli::Info::CMD_NAME)
  end

  # The user pastes the code displayed by Shares
  def paste_code(**params)
    paste { code_of_shares(**params) }
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
      receive_on_loopback(access_token: '<BROWSER_ACCESS_TOKEN>', refresh_token: '<BROWSER_REFRESH_TOKEN>')
      mock_token_call
      expect(oauth.token).to(eq('<ACCESS_TOKEN>'))
      # the page of the browser shows the Shares server
      expect(Aspera::WebAuth::Server).to(have_received(:new).with('http://localhost:12345/', include('shares.example.com')))
      login = URI.parse(opened.first)
      expect([login.host, login.path]).to(eq(['shares.example.com', '/auth/saml']))
      expect(relay_state_sent).to(match(%r{\Ahttp://localhost:12345/\?state=[0-9a-f-]{36}\z}))
      expect(relay_state_sent.bytesize).to(be <= 80)
      expect(@create_args.first).to(eq(['oauth2/token', {grant_type: 'refresh_token', refresh_token: '<BROWSER_REFRESH_TOKEN>'}]))
    end

    it 'refuses an answer with another state' do
      allow(Aspera::WebAuth::Server).to(receive(:new).and_return(instance_double(Aspera::WebAuth::Server, received_request: {'state' => 'other', 'refresh_token' => '<OTHER_REFRESH_TOKEN>'})))
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
      paste_code(refresh_token: '<BROWSER_REFRESH_TOKEN>')
      mock_token_call
      expect(oauth.token).to(eq('<ACCESS_TOKEN>'))
      login = URI.parse(opened.first)
      expect([login.host, login.path]).to(eq(['shares.example.com', '/auth/saml']))
      expect(relay_state_sent).to(match(%r{\Aaspera://device-code\?state=[0-9a-f-]{36}\z}))
      expect(relay_state_sent.bytesize).to(be <= 80)
      expect(@create_args.first).to(eq(['oauth2/token', {grant_type: 'refresh_token', refresh_token: '<BROWSER_REFRESH_TOKEN>'}]))
      # no local port
      expect(Aspera::WebAuth::Server).not_to(have_received(:new))
    end

    it 'refuses a code with another state' do
      paste_code(state: 'other', refresh_token: '<OTHER_REFRESH_TOKEN>')
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /wrong received state/))
    end

    it 'refuses a code made for another login' do
      paste_code(key_state: 'other', refresh_token: '<OTHER_REFRESH_TOKEN>')
      expect { oauth.token }.to(raise_error(Aspera::ParameterError, /Invalid code/))
    end

    it 'reports a code without token' do
      paste_code
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /No token received/))
    end

    it 'refuses something that is not a code' do
      paste { 'http://localhost:12345/?state=x' }
      expect { oauth.token }.to(raise_error(Aspera::ParameterError, /Not a code/))
    end

    it 'refuses a code that is not a reply of Shares (e.g. a login code)' do
      paste { Aspera::SealedHash.seal({'login_url' => 'https://x'}, secret: relay_state_sent.delete_prefix('aspera://device-code?state='), base_key: Aspera::Cli::Info::CMD_NAME) }
      expect { oauth.token }.to(raise_error(Aspera::AssertError, /wrong received state/))
    end

    context 'when the code is pasted in a terminal' do
      around do |example|
        saved = Rainbow.enabled
        Rainbow.enabled = false
        example.run
      ensure
        Rainbow.enabled = saved
      end

      it 'shows if the code is valid, and asks again if not' do
        allow(Aspera::Environment).to(receive(:unicode_environment?).and_return(false))
        allow($stdin).to(receive(:tty?).and_return(true))
        inputs = [-> { code_of_shares(key_state: 'other', refresh_token: '<OTHER_REFRESH_TOKEN>') }, -> { code_of_shares(refresh_token: '<BROWSER_REFRESH_TOKEN>') }]
        allow($stdin).to(receive(:raw)) { |&block| block.call(StringIO.new("#{inputs.shift.call}\r")) }
        mock_token_call
        expect { expect(oauth.token).to(eq('<ACCESS_TOKEN>')) }
          .to(output(/Code> [^\n]*invalid\r\nInvalid code: [^\n]*\. Try again, or Ctrl-C to stop\.\nCode> [^\n]*\x08valid\r\n\z/).to_stderr)
        expect(@create_args.first).to(eq(['oauth2/token', {grant_type: 'refresh_token', refresh_token: '<BROWSER_REFRESH_TOKEN>'}]))
      end
    end
  end
end

module Aspera
  module Plugins
    module Shares
      RSpec.describe(Commands) do
        def plugin(*argv)
          context = Cli::Context.new
          context.man_header = false
          context.options = Cli::Parser.new('test', argv)
          context.formatter = instance_double(Cli::Formatter, display_status: nil, display_results: nil)
          described_class.new(context: context).tap { context.options.parse_options! }
        end

        it 'uses user and password by default' do
          params = plugin('--url=https://shares.example.com', '--username=u', '--password=<PASSWORD>').basic_auth_params('api/v1')
          expect(params).to(eq(base_url: 'https://shares.example.com/api/v1', auth: {type: :basic, username: 'u', password: '<PASSWORD>'}))
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
