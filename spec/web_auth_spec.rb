# frozen_string_literal: true

require 'aspera/web_auth/server'

RSpec.describe(Aspera::WebAuth::Servlet) do
  # Minimal stand-in for WEBrick::HTTPRequest
  let(:request_class) do
    Struct.new(:request_method, :path, :headers) do
      def [](key) = headers[key]
    end
  end
  let(:reply_keys) { nil }
  let(:web_auth) { instance_double(Aspera::WebAuth::Server, expected_path: '/cb', additional_info: '<b>info</b>', reply_keys: reply_keys, signal_request: nil) }
  let(:servlet) do
    server = WEBrick::HTTPServer.new(BindAddress: 'localhost', Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [], DoNotListen: true)
    described_class.new(server, web_auth)
  end
  let(:response) { WEBrick::HTTPResponse.new(WEBrick::Config::HTTP) }

  it 'shows the page with security headers, then signals the callback' do
    request = request_class.new('GET', '/cb', {'Host' => 'localhost:12345'})
    servlet.service(request, response)
    expect(response.status).to(eq(200))
    expect(response['Content-Type']).to(eq('text/html; charset=utf-8'))
    expect(response['X-Frame-Options']).to(eq('DENY'))
    expect(response['Cache-Control']).to(eq('no-store'))
    expect(response['Referrer-Policy']).to(eq('same-origin'))
    expect(response.body).to(include('Authentication Received'))
    expect(response.body).to(include('&lt;b&gt;info&lt;/b&gt;'))
    # the query of the callback URL (code, tokens) is removed from the address bar
    expect(response.body).to(include('history.replaceState(null, \'\', location.pathname)'))
    expect(web_auth).to(have_received(:signal_request).with(request))
  end

  context 'when the reply is given to the user' do
    let(:reply_keys) { %w[code state] }
    let(:request) do
      Struct.new(:request_method, :path, :headers, :query) do
        def [](key) = headers[key]
      end.new('GET', '/cb', {'Host' => 'localhost:12345'}, {'code' => 'c1', 'state' => 's1', 'other' => 'zzz'})
    end

    it 'shows a page with a strict policy and the code, only with the reply keys' do
      servlet.service(request, response)
      expect(response.status).to(eq(200))
      csp = response['Content-Security-Policy']
      expect(csp).to(match(/\Adefault-src 'none'.*script-src 'nonce-[^']+'.*frame-ancestors 'none'\z/))
      expect(response['Cache-Control']).to(eq('no-store'))
      expect(response.body).to(include('Login Complete'))
      expect(response.body).to(include("nonce=\"#{csp[/nonce-([^']+)/, 1]}\""))
      expect(response.body).to(include('&lt;b&gt;info&lt;/b&gt;'))
      expect(response.body).to(include('Copy'))
      reply = response.body[/DCODE1R[A-Z2-7]+/]
      expect(Aspera::WebAuth::Blob.decode(reply)).to(eq([:reply, {'code' => 'c1', 'state' => 's1'}]))
      expect(response.body).not_to(include('zzz'))
      expect(web_auth).to(have_received(:signal_request).with(request))
    end

    it 'uses another nonce for each page' do
      other = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
      servlet.service(request, response)
      servlet.service(request, other)
      expect(other['Content-Security-Policy']).not_to(eq(response['Content-Security-Policy']))
    end
  end

  it 'refuses another path' do
    expect { servlet.service(request_class.new('GET', '/other', {}), response) }.to(raise_error(WEBrick::HTTPStatus::NotFound))
    expect(web_auth).not_to(have_received(:signal_request))
  end
end
