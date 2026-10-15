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
require 'securerandom'

RSpec.describe(Aspera::Cli::Plugins::Mcp) do
  # Build a minimal plugin instance without a real CLI context.
  subject(:plugin) do
    described_class.allocate
  end

  # -------------------------------------------------------------------------
  # start_http_transport
  # -------------------------------------------------------------------------
  describe '#start_http_transport (private)' do
    let(:token)      { SecureRandom.hex(32) }
    let(:mcp_server) { MCP::Server.new(name: 'ascli', version: '1', tools: []) }
    # Arguments of WebServerSimple.new: URI and TLS parameters
    let(:created) { [] }
    # Arguments of WebServerSimple#mount: path, servlet, servlet options
    let(:mounted) { [] }

    around do |example|
      saved = Aspera::Cli::Mcp::Tool.web_secret
      example.run
    ensure
      Aspera::Cli::Mcp::Tool.web_secret = saved
    end

    before do
      require 'aspera/cli/mcp/tool'
      require 'aspera/cli/mcp/http_servlet'
      web_server = instance_double(Aspera::WebServerSimple, start: nil)
      allow(web_server).to(receive(:mount)) { |*args| mounted.replace(args) }
      allow(Aspera::WebServerSimple).to(receive(:new)) do |uri, **tls|
        created.replace([uri.to_s, tls])
        web_server
      end
    end

    # @param mcp_options [Hash] Options of the server
    # @return [Hash] Options of the servlet
    def start(**mcp_options)
      plugin.send(:start_http_transport, mcp_server, mcp_options)
      mounted.last
    end

    it 'listens on 127.0.0.1:3000 by default, with the servlet on /' do
      options = start
      expect(created).to(eq(['http://127.0.0.1:3000', {}]))
      expect(mounted.first(2)).to(eq(['', Aspera::Cli::Mcp::HttpServlet]))
      expect(options[:web_secret].url('id')).to(eq('http://127.0.0.1:3000/secret/id'))
      expect(options[:allowed_origins]).to(eq(['http://127.0.0.1:3000']))
    end

    it 'accepts no auth on a loopback address' do
      %w[http://127.0.0.1:3000 http://127.0.0.2:3000 http://[::1]:3000 http://[::ffff:127.0.0.1]:3000 http://localhost:3000/].each do |url|
        expect { start(url: url) }.not_to(raise_error, url)
      end
    end

    it 'requires auth_token on an address that is not loopback, also with oauth' do
      expect { start(url: 'http://0.0.0.0:3000') }
        .to(raise_error(Aspera::Cli::BadArgument, /auth_token is required when/))
      expect { start(url: 'http://0.0.0.0:3000', oauth: true, public_url: 'http://myhost:3000') }
        .to(raise_error(Aspera::Cli::BadArgument, /auth_token \(asked on the consent page\) is required when/))
      expect(Aspera::WebServerSimple).not_to(have_received(:new))
    end

    it 'requires auth_token when public_url is not loopback, even if url is loopback' do
      expect { start(url: 'http://127.0.0.1:3000', public_url: 'https://mcp.example.com') }
        .to(raise_error(Aspera::Cli::BadArgument, /auth_token is required when public_url is not loopback.*mcp\.example\.com/))
      expect { start(url: 'http://127.0.0.1:3000', public_url: 'https://mcp.example.com', oauth: true) }
        .to(raise_error(Aspera::Cli::BadArgument, /auth_token \(asked on the consent page\) is required when public_url/))
      expect(Aspera::WebServerSimple).not_to(have_received(:new))
      expect { start(url: 'http://127.0.0.1:3000', public_url: 'http://localhost:3000') }.not_to(raise_error)
      expect { start(url: 'http://127.0.0.1:3000', public_url: 'https://mcp.example.com', auth_token: token) }.not_to(raise_error)
    end

    it 'accepts auth_token on an address that is not loopback, also with oauth' do
      expect(start(url: 'http://0.0.0.0:3000', auth_token: token)[:auth_token]).to(eq(token))
      options = start(url: 'http://0.0.0.0:3000', auth_token: token, oauth: true, public_url: 'http://myhost:3000/')
      expect(options[:oauth_server]).to(be_a(Aspera::OAuth::Server::Pkce))
      expect(options[:allowed_origins]).to(eq(['http://myhost:3000']))
    end

    it 'refuses an empty or weak auth_token, unless min_bits allows it' do
      expect { start(auth_token: '') }.to(raise_error(Aspera::Cli::BadArgument, /must not be empty/))
      expect { start(auth_token: 'MySecretToken2024!') }.to(raise_error(Aspera::Cli::BadArgument, /auth_token is too weak: about \d+ bits, minimum 80/))
      expect { start(auth_token: 'tok', auth_token_min_bits: 0) }.not_to(raise_error)
    end

    it 'listens on HTTPS with cert, key and chain' do
      options = start(url: 'https://127.0.0.1:8443', cert: 'cert.pem', key: 'key.pem', chain: 'chain.pem')
      expect(created).to(eq(['https://127.0.0.1:8443', {cert: 'cert.pem', key: 'key.pem', chain: 'chain.pem'}]))
      expect(options[:web_secret].url('id')).to(eq('https://127.0.0.1:8443/secret/id'))
    end

    it 'accepts deprecated bind and port, but not with url' do
      start(bind: '0.0.0.0', port: 8080, auth_token: token)
      expect(created.first).to(eq('http://0.0.0.0:8080'))
      start(bind: '::1')
      expect(created.first).to(eq('http://[::1]:3000'))
      expect { start(url: 'http://127.0.0.1:3000', port: 8080) }.to(raise_error(Aspera::Cli::BadArgument, /url cannot be used with bind or port/))
    end

    it 'refuses a url with a path' do
      expect { start(url: 'http://127.0.0.1:3000/mcp') }.to(raise_error(Aspera::Cli::BadArgument, /url shall have no path/))
    end
  end

  # -------------------------------------------------------------------------
  # http_base_url
  # -------------------------------------------------------------------------
  describe '#http_base_url (private)' do
    # @return [String] base URL for the given listening URL
    def base_url(url, base_url = nil, oauth: true) = plugin.send(:http_base_url, URI.parse(url), base_url, oauth)

    it 'uses the scheme, host and port of url' do
      expect(base_url('http://192.168.1.10:3000')).to(eq('http://192.168.1.10:3000'))
      expect(base_url('https://myhost')).to(eq('https://myhost'))
    end

    it 'keeps brackets around an IPv6 address' do
      expect(base_url('http://[::1]:3000')).to(eq('http://[::1]:3000'))
    end

    it 'uses localhost for a wildcard address without OAuth' do
      expect(base_url('http://0.0.0.0:3000', oauth: false)).to(eq('http://localhost:3000'))
      expect(base_url('https://[::]:8443', oauth: false)).to(eq('https://localhost:8443'))
    end

    it 'requires public_url with OAuth on a wildcard address' do
      expect { base_url('http://0.0.0.0:3000') }
        .to(raise_error(Aspera::Cli::BadArgument, /public_url is required/))
    end

    it 'uses the provided public_url without trailing slash' do
      expect(base_url('http://0.0.0.0:3000', 'https://mcp.example.com/')).to(eq('https://mcp.example.com'))
    end
  end

  # -------------------------------------------------------------------------
  # action_server: security level
  # -------------------------------------------------------------------------
  describe '#action_server security level' do
    let(:extended) { Aspera::Cli::ExtendedValue.instance }
    let(:security) { Aspera::Cli::Security.instance }

    around do |example|
      saved = extended.instance_variable_get(:@handlers).dup
      example.run
    ensure
      extended.instance_variable_set(:@handlers, saved)
      extended.send(:update_regex)
      security.reset
    end

    before { allow(plugin).to(receive(:start_mcp_server)) }

    it 'is high by default, and cannot be changed by the client' do
      plugin.action_server
      expect(security.level).to(eq(:high))
      expect { security.options = {'level' => 'low'} }.to(raise_error(Aspera::Cli::BadArgument, /security cannot be changed in MCP server mode/))
      expect { extended.evaluate('@stdin:', context: 'test') }.to(raise_error(Aspera::Cli::BadArgument, /disabled in MCP server mode/))
    end

    it 'keeps the level set by option' do
      security.options = {'level' => 'low'}
      plugin.action_server
      expect(security.level).to(eq(:low))
    end
  end

  # -------------------------------------------------------------------------
  # action_server: options of the transport
  # -------------------------------------------------------------------------
  describe '#action_server options of the transport' do
    it 'refuses options of the http transport with stdio, the default' do
      expect { plugin.action_server(mcp_options: {'url' => 'http://127.0.0.1:3000', 'auth_token' => 'x'}) }
        .to(raise_error(Aspera::Cli::BadArgument, /not used with transport stdio: url, auth_token/))
      expect { plugin.action_server(mcp_options: {'transport' => 'stdio', 'allowed_hosts' => ['h']}) }
        .to(raise_error(Aspera::Cli::BadArgument, /not used with transport stdio: allowed_hosts/))
    end

    it 'refuses options of the stdio transport with http' do
      expect { plugin.action_server(mcp_options: {'transport' => 'http', 'max_line_bytes' => 1000}) }
        .to(raise_error(Aspera::Cli::BadArgument, /not used with transport http: max_line_bytes/))
    end

    it 'refuses unknown options' do
      expect { plugin.action_server(mcp_options: {'foo' => 1}) }.to(raise_error(Aspera::Cli::BadArgument, /Unknown MCP option\(s\): foo/))
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
  # access_token_valid?
  # -------------------------------------------------------------------------
  describe '#access_token_valid?' do
    it 'returns false when no token has been issued' do
      expect(oauth.access_token_valid?('sometoken')).to(be(false))
    end

    it 'returns false for no token' do
      expect(oauth.access_token_valid?(nil)).to(be(false))
    end

    it 'returns true for an issued access token, not for a refresh token' do
      tokens = oauth.send(:issue_tokens)
      expect(oauth.access_token_valid?(tokens[:access_token])).to(be(true))
      expect(oauth.access_token_valid?(tokens[:refresh_token])).to(be(false))
    end

    it 'returns false for an expired access token' do
      expired = described_class.new(base_url: base_url, access_token_ttl: -1)
      expect(expired.access_token_valid?(expired.send(:issue_tokens)[:access_token])).to(be(false))
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

    it 'shows where the code is sent: origin of redirect_uri' do
      expect(html).to(include('sent to <span class="client">http://localhost:9999</span>'))
      {
        'cursor://anysphere.cursor-retrieval/oauth/cb' => 'cursor://anysphere.cursor-retrieval',
        'com.example.app:/cb'                          => 'com.example.app:/cb'
      }.each do |redirect_uri, shown|
        expect(oauth.send(:authorize_html_from_template, params.merge('redirect_uri' => redirect_uri))).to(include("sent to <span class=\"client\">#{shown}</span>"))
      end
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
      r = response_class.new
      oauth.handle_register(request_class.new('[1]'), r)
      expect(r.status).to(eq(400))
    end

    it 'rejects too many, too long, relative redirect_uris, or with fragment' do
      expect(register(Array.new(11) { |i| "http://127.0.0.1:#{19_000 + i}/cb" }).body).to(include('at most 10 values'))
      expect(register(["http://127.0.0.1:19999/#{'a' * 2048}"]).body).to(include('at most 2048 characters'))
      ['/cb', 'http://127.0.0.1:19999/cb#frag', 'http://[bad'].each do |redirect_uri|
        expect(register([redirect_uri]).body).to(include('absolute URI without fragment'), redirect_uri)
      end
      expect(register(['cursor://anysphere.cursor-retrieval/oauth/cb']).status).to(eq(201))
    end

    it 'removes the least recently used client beyond the limit' do
      max_clients = described_class.const_get(:MAX_CLIENTS)
      used = client_id
      unused = JSON.parse(register([redirect]).body)['client_id']
      (max_clients - 2).times { register([redirect]) }
      # use the oldest client
      expect(oauth.send(:client_redirect_valid?, used, redirect)).to(be(true))
      register([redirect])
      expect(oauth.send(:client_redirect_valid?, unused, redirect)).to(be(false))
      expect(oauth.send(:client_redirect_valid?, used, redirect)).to(be(true))
      expect(oauth.instance_variable_get(:@clients).size).to(eq(max_clients))
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

    it 'sets anti-framing, no-cache and same-origin referrer headers on consent page' do
      query = {'client_id' => client_id, 'redirect_uri' => redirect, 'code_challenge' => 'c', 'code_challenge_method' => 'S256'}
      oauth.send(:handle_authorize_get, request_class.new(nil, query), res)
      expect(res.status).to(eq(200))
      expect(res['X-Frame-Options']).to(eq('DENY'))
      expect(res['Content-Security-Policy']).to(eq("frame-ancestors 'none'"))
      expect(res['Cache-Control']).to(eq('no-store'))
      expect(res['Referrer-Policy']).to(eq('same-origin'))
    end

    it 'redirects with invalid_request on allow without PKCE challenge' do
      body = URI.encode_www_form(client_id: client_id, redirect_uri: redirect, state: 's1', decision: 'allow')
      oauth.send(:handle_authorize_post, request_class.new(body), res)
      expect(res.status).to(eq(302))
      expect(res['Location']).to(start_with("#{redirect}?error=invalid_request&"))
      expect(res['Location']).not_to(include('code='))
    end

    context 'with a consent secret' do
      subject(:oauth) { described_class.new(base_url: base_url, consent_secret: 'pass') }

      def post_allow(secret)
        body = URI.encode_www_form(client_id: client_id, redirect_uri: redirect, state: 's1', code_challenge: 'c', code_challenge_method: 'S256', decision: 'allow', consent_secret: secret)
        oauth.send(:handle_authorize_post, request_class.new(body), res)
      end

      it 'asks for the access code on the consent page' do
        query = {'client_id' => client_id, 'redirect_uri' => redirect, 'code_challenge' => 'c', 'code_challenge_method' => 'S256'}
        oauth.send(:handle_authorize_get, request_class.new(nil, query), res)
        expect(res.body).to(include('name="consent_secret"'))
      end

      it 'shows the consent page again with an error on a wrong access code' do
        post_allow('wrong')
        expect(res.status).to(eq(401))
        expect(res['Location']).to(be_nil)
        expect(res.body).to(include('Invalid access code'))
      end

      it 'redirects with a code on the right access code' do
        post_allow('pass')
        expect(res.status).to(eq(302))
        expect(res['Location']).to(start_with("#{redirect}?code="))
      end

      it 'does not need the access code to deny' do
        post_authorize(client_id, redirect, 'deny')
        expect(res['Location']).to(eq("#{redirect}?error=access_denied&state=s1"))
      end
    end
  end

  # -------------------------------------------------------------------------
  # token endpoint
  # -------------------------------------------------------------------------
  describe '#handle_token' do
    before do
      require 'webrick'
      require 'base64'
    end

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
    let(:verifier) { 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk' }
    let(:challenge) { Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false) }
    let(:client_id) do
      r = response_class.new
      oauth.handle_register(request_class.new(JSON.generate(redirect_uris: [redirect])), r)
      JSON.parse(r.body)['client_id']
    end

    # @return [String] authorization code
    def authorization_code
      r = response_class.new
      body = URI.encode_www_form(client_id: client_id, redirect_uri: redirect, code_challenge: challenge, code_challenge_method: 'S256', decision: 'allow')
      oauth.send(:handle_authorize_post, request_class.new(body), r)
      URI.decode_www_form(URI(r['Location']).query).to_h['code']
    end

    # @return [Object] response of token endpoint
    def token(**params)
      r = response_class.new
      oauth.handle_token(request_class.new(URI.encode_www_form(params)), r)
      r
    end

    it 'issues tokens for a valid code and verifier' do
      r = token(grant_type: 'authorization_code', code: authorization_code, client_id: client_id, redirect_uri: redirect, code_verifier: verifier)
      expect(r.status).to(eq(200))
      expect(JSON.parse(r.body)).to(include('access_token', 'refresh_token'))
    end

    it 'refuses a code issued to another client' do
      r = token(grant_type: 'authorization_code', code: authorization_code, client_id: 'other', redirect_uri: redirect, code_verifier: verifier)
      expect(r.status).to(eq(400))
    end

    it 'refuses an expired refresh token' do
      short = described_class.new(base_url: 'http://localhost:3000', refresh_token_ttl: -1)
      refresh = short.send(:issue_tokens)[:refresh_token]
      r = response_class.new
      short.handle_token(request_class.new(URI.encode_www_form(grant_type: 'refresh_token', refresh_token: refresh)), r)
      expect(r.status).to(eq(400))
      expect(r.body).to(include('invalid_grant'))
    end
  end
end
