# frozen_string_literal: true

require 'aspera/web_auth/server'

RSpec.describe(Aspera::WebAuth::Servlet) do
  # Minimal stand-in for WEBrick::HTTPRequest
  let(:request_class) do
    Struct.new(:request_method, :path, :headers) do
      def [](key) = headers[key]
    end
  end
  let(:web_auth) { instance_double(Aspera::WebAuth::Server, expected_path: '/cb', additional_info: '<b>info</b>', signal_request: nil) }
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
    expect(response.body).to(include('Authentication Successful'))
    expect(response.body).to(include('&lt;b&gt;info&lt;/b&gt;'))
    expect(web_auth).to(have_received(:signal_request).with(request))
  end

  it 'refuses another path' do
    expect { servlet.service(request_class.new('GET', '/other', {}), response) }.to(raise_error(WEBrick::HTTPStatus::NotFound))
    expect(web_auth).not_to(have_received(:signal_request))
  end
end
