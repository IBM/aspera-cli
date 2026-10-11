# frozen_string_literal: true

# Stub the MCP gem classes so this spec can run without the optional `mcp` gem.
unless defined?(MCP::Server)
  module MCP
    class Configuration
      def initialize(**_kwargs); end
    end

    class Server
      attr_reader :name, :version, :description

      def initialize(name:, version:, tools:, configuration: nil, **opts)
        @name        = name
        @version     = version
        @description = opts[:description]
      end

      module Transports
        class StreamableHTTPTransport
          def initialize(_server, **_opts); end
        end

        class StdioTransport
          def initialize(_server, **_opts); end

          def open; end
        end
      end
    end

    class Tool
      class << self
        def tool_name(_name); end

        def description(_text); end

        def input_schema(**_kwargs); end
      end

      class Response
        attr_reader :content, :structured_content

        def initialize(content, structured_content: nil, error: false)
          @content            = content
          @structured_content = structured_content
          @error              = error
        end

        def error?
          @error
        end
      end
    end
  end
end

require 'aspera/cli/plugins/mcp'
require 'aspera/oauth/server/pkce'

RSpec.describe(Aspera::Cli::Plugins::Mcp) do
  # Build a minimal plugin instance without a real CLI context.
  subject(:plugin) do
    described_class.allocate
  end

  # -------------------------------------------------------------------------
  # check_auth_config
  # -------------------------------------------------------------------------
  describe '#check_auth_config (private)' do
    let(:local_binds)    { %w[127.0.0.1 ::1 localhost] }
    let(:nonlocal_bind)  { '0.0.0.0' }

    context 'with a local bind address' do
      it 'accepts no auth at all' do
        local_binds.each do |bind|
          expect { plugin.send(:check_auth_config, nil, false, bind) }.not_to(raise_error)
        end
      end

      it 'accepts auth_token alone' do
        expect { plugin.send(:check_auth_config, 'tok', false, '127.0.0.1') }.not_to(raise_error)
      end

      it 'accepts oauth_enabled alone' do
        expect { plugin.send(:check_auth_config, nil, true, '127.0.0.1') }.not_to(raise_error)
      end
    end

    context 'with a non-local bind address' do
      it 'raises BadArgument when neither auth_token nor oauth_enabled is provided' do
        expect { plugin.send(:check_auth_config, nil, false, nonlocal_bind) }
          .to(raise_error(Aspera::Cli::BadArgument, /auth_token or oauth is required/))
      end

      it 'accepts auth_token' do
        expect { plugin.send(:check_auth_config, 'secret', false, nonlocal_bind) }.not_to(raise_error)
      end

      it 'accepts oauth_enabled' do
        expect { plugin.send(:check_auth_config, nil, true, nonlocal_bind) }.not_to(raise_error)
      end

      it 'accepts both auth_token and oauth_enabled together' do
        expect { plugin.send(:check_auth_config, 'secret', true, nonlocal_bind) }.not_to(raise_error)
      end
    end

    it 'raises BadArgument when auth_token is an empty string' do
      expect { plugin.send(:check_auth_config, '', false, '127.0.0.1') }
        .to(raise_error(Aspera::Cli::BadArgument, /must not be empty/))
    end
  end
end

RSpec.describe(Aspera::OAuth::Server::Pkce) do
  let(:base_url) { 'http://localhost:3000' }
  subject(:oauth) { described_class.new(base_url: base_url) }

  # -------------------------------------------------------------------------
  # metadata
  # -------------------------------------------------------------------------
  describe '#metadata' do
    it 'includes the issuer equal to base_url' do
      expect(oauth.metadata[:issuer]).to(eq(base_url))
    end

    it 'points authorization_endpoint under base_url' do
      expect(oauth.metadata[:authorization_endpoint]).to(start_with(base_url))
      expect(oauth.metadata[:authorization_endpoint]).to(include('/oauth/authorize'))
    end

    it 'points token_endpoint under base_url' do
      expect(oauth.metadata[:token_endpoint]).to(start_with(base_url))
      expect(oauth.metadata[:token_endpoint]).to(include('/oauth/token'))
    end

    it 'advertises S256 as the only code challenge method' do
      expect(oauth.metadata[:code_challenge_methods_supported]).to(eq(['S256']))
    end

    it 'advertises authorization_code and refresh_token grant types' do
      expect(oauth.metadata[:grant_types_supported]).to(include('authorization_code', 'refresh_token'))
    end
  end

  # -------------------------------------------------------------------------
  # pkce_valid? (private)
  # -------------------------------------------------------------------------
  describe '#pkce_valid? (private)' do
    let(:verifier) { 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk' }
    let(:challenge) do
      require 'openssl'
      require 'base64'
      Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false)
    end

    it 'returns true for a matching verifier/challenge pair' do
      expect(oauth.send(:pkce_valid?, verifier, challenge)).to(be(true))
    end

    it 'returns false for a wrong verifier' do
      expect(oauth.send(:pkce_valid?, 'wrong-verifier', challenge)).to(be(false))
    end

    it 'returns false for a tampered challenge' do
      expect(oauth.send(:pkce_valid?, verifier, challenge.reverse)).to(be(false))
    end
  end

  # -------------------------------------------------------------------------
  # authorized?
  # -------------------------------------------------------------------------
  describe '#authorized?' do
    it 'returns false when no token has been issued' do
      expect(oauth.authorized?('Bearer sometoken')).to(be(false))
    end

    it 'returns false for a nil header' do
      expect(oauth.authorized?(nil)).to(be(false))
    end

    it 'returns false for a non-Bearer scheme' do
      expect(oauth.authorized?('Basic dXNlcjpwYXNz')).to(be(false))
    end
  end

  # -------------------------------------------------------------------------
  # authorize_html_from_template (private)
  # -------------------------------------------------------------------------
  describe '#authorize_html_from_template (private)' do
    before { require 'webrick' }

    let(:params) do
      {
        'client_id'             => 'bob',
        'redirect_uri'          => 'http://localhost:9999/cb',
        'state'                 => 'xyz',
        'code_challenge'        => 'abc123',
        'code_challenge_method' => 'S256'
      }
    end
    let(:html) { oauth.send(:authorize_html_from_template, params) }

    it 'contains the client_id' do
      expect(html).to(include('bob'))
    end

    it 'contains a form POSTing to /oauth/authorize' do
      expect(html).to(include("action=\"#{base_url}/oauth/authorize\""))
      expect(html).to(include('method="POST"'))
    end

    it 'embeds the PKCE challenge as a hidden field' do
      expect(html).to(include('name="code_challenge"'))
      expect(html).to(include('value="abc123"'))
    end

    it 'has Allow and Deny buttons' do
      expect(html).to(include('value="allow"'))
      expect(html).to(include('value="deny"'))
    end

    it 'uses the default title' do
      expect(html).to(include('<title>Authorization request</title>'))
    end

    it 'uses a custom title when provided' do
      custom = described_class.new(base_url: base_url, title: 'My Custom Server')
      html2 = custom.send(:authorize_html_from_template, params)
      expect(html2).to(include('<title>My Custom Server</title>'))
    end

    it 'escapes HTML in client_id to prevent XSS' do
      xss_html = oauth.send(:authorize_html_from_template, params.merge('client_id' => '<script>alert(1)</script>'))
      expect(xss_html).not_to(include('<script>alert(1)</script>'))
    end
  end

  # -------------------------------------------------------------------------
  # redirect_uri validation
  # -------------------------------------------------------------------------
  describe 'redirect_uri validation' do
    before { require 'webrick' }

    # Minimal stand-in for WEBrick::HTTPResponse
    let(:response_class) do
      Class.new do
        attr_accessor :status, :body

        def initialize = @headers = {}
        def [](key) = @headers[key]

        def []=(key, value)
          @headers[key] = value
        end
      end
    end
    let(:request_class) { Struct.new(:body, :query) }
    let(:redirect) { 'http://127.0.0.1:19999/cb' }
    let(:res) { response_class.new }
    let(:client_id) { JSON.parse(register([redirect]).body)['client_id'] }

    def register(uris)
      r = response_class.new
      oauth.handle_register(request_class.new(JSON.generate(redirect_uris: uris)), r)
      r
    end

    def post_authorize(client_id, redirect_uri, decision)
      body = URI.encode_www_form(client_id: client_id, redirect_uri: redirect_uri, state: 's1', code_challenge: 'c', code_challenge_method: 'S256', decision: decision)
      oauth.send(:handle_authorize_post, request_class.new(body), res)
    end

    it 'rejects registration without redirect_uris' do
      expect(register(nil).status).to(eq(400))
      expect(register([]).status).to(eq(400))
    end

    it 'redirects to registered redirect_uri on allow' do
      post_authorize(client_id, redirect, 'allow')
      expect(res.status).to(eq(302))
      expect(res['Location']).to(start_with("#{redirect}?code="))
      expect(res['Location']).to(include('&state=s1'))
    end

    it 'refuses unregistered redirect_uri on allow' do
      post_authorize(client_id, 'http://evil.example/cb', 'allow')
      expect(res.status).to(eq(400))
      expect(res['Location']).to(be_nil)
    end

    it 'refuses unregistered redirect_uri on deny (no open redirect)' do
      post_authorize(client_id, 'http://evil.example/cb', 'deny')
      expect(res.status).to(eq(400))
      expect(res['Location']).to(be_nil)
    end

    it 'redirects with access_denied on deny for registered redirect_uri' do
      post_authorize(client_id, redirect, 'deny')
      expect(res.status).to(eq(302))
      expect(res['Location']).to(eq("#{redirect}?error=access_denied&state=s1"))
    end

    it 'appends parameters with & when redirect_uri already has a query' do
      with_query = 'http://127.0.0.1:19999/cb?x=1'
      id = JSON.parse(register([with_query]).body)['client_id']
      post_authorize(id, with_query, 'deny')
      expect(res['Location']).to(eq("#{with_query}&error=access_denied&state=s1"))
    end

    it 'sets anti-framing headers on consent page' do
      query = {'client_id' => client_id, 'redirect_uri' => redirect, 'code_challenge' => 'c', 'code_challenge_method' => 'S256'}
      oauth.send(:handle_authorize_get, request_class.new(nil, query), res)
      expect(res.status).to(eq(200))
      expect(res['X-Frame-Options']).to(eq('DENY'))
      expect(res['Content-Security-Policy']).to(eq("frame-ancestors 'none'"))
    end
  end
end
