# frozen_string_literal: true

require 'aspera/cli/mcp/http_servlet'
require 'json'

RSpec.describe(Aspera::Cli::Mcp::HttpServlet) do
  subject(:servlet) { described_class.new(webrick, options) }

  let(:webrick) { WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [], DoNotListen: true) }
  # Rack app of the MCP transport: records calls
  let(:app) do
    calls = []
    app = ->(env) { calls.push(env) && [200, {'Content-Type' => 'application/json'}, ['{"result":1}']] }
    app.define_singleton_method(:calls) { calls }
    app
  end
  let(:web_secret) { instance_double(Aspera::Cli::WebSecret, handle: nil) }
  let(:options) { {app: app, server_info: {name: 'test'}, web_secret: web_secret} }
  # Minimal stand-in for WEBrick::HTTPRequest
  let(:request_class) do
    Struct.new(:request_method, :path, :headers) do
      def [](key) = headers[key]
      def header = headers.transform_values { |v| [v] }
      def query_string = nil
      def host = 'localhost'
      def port = 3000
      def http_version = '1.1'
      def body = '{}'
    end
  end
  # Minimal stand-in for WEBrick::HTTPResponse
  let(:response_class) do
    Class.new do
      attr_accessor :status, :body, :chunked

      def initialize = @headers = {}
      def [](key) = @headers[key]

      def []=(key, value)
        @headers[key] = value
      end
    end
  end

  # @return [Object] response of the servlet to the request
  def request(method, path, headers = {})
    res = response_class.new
    servlet.public_send(:"do_#{method}", request_class.new(method, path, headers), res)
    res
  end

  it 'answers discovery without authentication' do
    options[:auth_token] = 'tok'
    res = request('GET', '/')
    expect(res.status).to(eq(200))
    expect(JSON.parse(res.body)).to(eq('name' => 'test'))
  end

  it 'calls the MCP app without authentication if none is configured' do
    res = request('POST', '/mcp')
    expect(res.status).to(eq(200))
    expect(res.body).to(eq('{"result":1}'))
    expect(app.calls.first).to(include('REQUEST_METHOD' => 'POST', 'PATH_INFO' => '/mcp'))
  end

  context 'with a static token' do
    before { options[:auth_token] = 'tok' }

    it 'refuses a request without token' do
      res = request('POST', '/mcp')
      expect(res.status).to(eq(401))
      expect(res['WWW-Authenticate']).to(eq('Bearer'))
      expect(app.calls).to(be_empty)
    end

    it 'refuses a wrong token' do
      expect(request('POST', '/mcp', 'Authorization' => 'Bearer bad').status).to(eq(401))
    end

    it 'calls the MCP app with the token' do
      expect(request('POST', '/mcp', 'Authorization' => 'Bearer tok').status).to(eq(200))
      expect(app.calls.size).to(eq(1))
    end
  end

  context 'without OAuth' do
    it 'does not serve OAuth endpoints' do
      expect(request('GET', '/.well-known/oauth-authorization-server').status).to(eq(404))
      expect(request('POST', '/oauth/token').status).to(eq(404))
      expect(request('GET', '/oauth/token').status).to(eq(405))
    end
  end

  context 'with OAuth' do
    let(:oauth_server) do
      instance_double(Aspera::OAuth::Server::Pkce, www_authenticate_header: 'Bearer realm="x"', handle_authorize: nil).tap do |oauth|
        allow(oauth).to(receive(:authorized?)) { |header| header.eql?('Bearer access') }
      end
    end

    before do
      require 'aspera/oauth/server/pkce'
      options[:oauth_server] = oauth_server
    end

    it 'refuses a request without token, with OAuth metadata' do
      res = request('POST', '/mcp')
      expect(res.status).to(eq(401))
      expect(res['WWW-Authenticate']).to(eq('Bearer realm="x"'))
    end

    it 'calls the MCP app with an OAuth access token' do
      expect(request('POST', '/mcp', 'Authorization' => 'Bearer access').status).to(eq(200))
    end

    it 'routes OAuth endpoints to the OAuth server' do
      request('GET', '/oauth/authorize')
      expect(oauth_server).to(have_received(:handle_authorize))
    end
  end

  it 'routes secret pages to the secret pages, without bearer token' do
    options[:auth_token] = 'tok'
    request('GET', '/secret/abc')
    expect(web_secret).to(have_received(:handle))
    expect(app.calls).to(be_empty)
  end
end
