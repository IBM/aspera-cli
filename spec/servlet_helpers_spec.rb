# frozen_string_literal: true

require 'aspera/servlet_helpers'

RSpec.describe(Aspera::ServletHelpers) do
  # Minimal stand-in for WEBrick::HTTPRequest
  let(:request_class) do
    Struct.new(:headers, :body) do
      def [](key) = headers[key]
    end
  end

  describe '.origin' do
    it 'keeps scheme, host and port of the URL, without default port and path' do
      expect(described_class.origin('http://localhost:3000/base')).to(eq('http://localhost:3000'))
      expect(described_class.origin('https://MCP.example.com:443/')).to(eq('https://mcp.example.com'))
      expect(described_class.origin('http://[::1]:3000')).to(eq('http://[::1]:3000'))
    end
  end

  describe '#json_error' do
    it 'sets status, JSON body and other headers' do
      response = WEBrick::HTTPResponse.new(WEBrick::Config::HTTP)
      Class.new { include Aspera::ServletHelpers }.new.json_error(response, 401, 'Unauthorized', headers: {'WWW-Authenticate' => 'Bearer'})
      expect(response.status).to(eq(401))
      expect(response['Content-Type']).to(eq('application/json'))
      expect(response['WWW-Authenticate']).to(eq('Bearer'))
      expect(JSON.parse(response.body)).to(eq('error' => 'Unauthorized'))
    end
  end

  describe '#check_request' do
    let(:bind) { 'localhost' }
    let(:servlet) do
      server = WEBrick::HTTPServer.new(BindAddress: bind, Port: 0, Logger: WEBrick::Log.new(File::NULL), AccessLog: [], DoNotListen: true)
      Class.new(WEBrick::HTTPServlet::AbstractServlet) { include Aspera::ServletHelpers }.new(server)
    end

    # @param headers [Hash] Headers of the request
    # @param body    [String, nil] Body of the request
    # @param options [Hash] Options of check_request
    def check(headers, body: nil, **options)
      servlet.check_request(request_class.new(headers, body), **options)
    end

    context 'when the server listens on loopback' do
      it 'accepts loopback names and addresses in Host, or no Host' do
        ['localhost:8080', 'LOCALHOST', '127.0.0.2:8080', '[::1]:8080', nil].each do |host|
          expect { check({'Host' => host}) }.not_to(raise_error)
        end
      end

      it 'refuses another host name, as after DNS rebinding' do
        expect { check({'Host' => 'attacker.example.com:8080'}) }.to(raise_error(WEBrick::HTTPStatus::Forbidden, /Host is not a loopback address/))
      end

      it 'accepts allowed_hosts, by name or with port' do
        expect { check({'Host' => 'myhost:8080'}, allowed_hosts: ['MyHost']) }.not_to(raise_error)
        expect { check({'Host' => 'myhost:8080'}, allowed_hosts: ['myhost:8080']) }.not_to(raise_error)
        expect { check({'Host' => 'myhost:9090'}, allowed_hosts: ['myhost:8080']) }.to(raise_error(WEBrick::HTTPStatus::Forbidden))
      end
    end

    context 'when the server listens on another address' do
      let(:bind) { '0.0.0.0' }

      it 'accepts any Host: authentication is required there' do
        expect { check({'Host' => 'myhost.example.com:8080'}) }.not_to(raise_error)
      end
    end

    describe 'Origin' do
      it 'accepts the origin of the server, with or without default port' do
        expect { check({'Host' => 'localhost:8080', 'Origin' => 'http://localhost:8080'}) }.not_to(raise_error)
        expect { check({'Host' => 'localhost', 'Origin' => 'http://localhost:80'}) }.not_to(raise_error)
        expect { check({'Host' => 'localhost:443', 'Origin' => 'https://localhost'}) }.not_to(raise_error)
      end

      it 'refuses another origin, null, or an origin without Host' do
        expect { check({'Host' => 'localhost:8080', 'Origin' => 'https://attacker.example.com'}) }.to(raise_error(WEBrick::HTTPStatus::Forbidden, /Origin/))
        expect { check({'Host' => 'localhost:8080', 'Origin' => 'http://localhost:9090'}) }.to(raise_error(WEBrick::HTTPStatus::Forbidden))
        expect { check({'Host' => 'localhost:8080', 'Origin' => 'null'}) }.to(raise_error(WEBrick::HTTPStatus::Forbidden))
        expect { check({'Origin' => 'http://localhost:8080'}) }.to(raise_error(WEBrick::HTTPStatus::Forbidden))
      end

      it 'accepts allowed_origins' do
        expect { check({'Host' => 'localhost:8080', 'Origin' => 'https://MCP.example.com'}, allowed_origins: ['https://mcp.example.com']) }.not_to(raise_error)
      end
    end

    describe 'JSON body' do
      it 'accepts JSON types, with parameters' do
        ['application/json', 'Application/JSON; charset=utf-8', 'application/vnd.api+json'].each do |type|
          expect { check({'Content-Type' => type}, body: '{}', json: true) }.not_to(raise_error)
        end
      end

      it 'refuses types that a web page sends without preflight, or no type' do
        ['text/plain', 'application/x-www-form-urlencoded', 'multipart/form-data; boundary=x', nil].each do |type|
          expect { check({'Content-Type' => type}, body: '{}', json: true) }.to(raise_error(WEBrick::HTTPStatus::UnsupportedMediaType, %r{Content-Type shall be application/json}))
        end
      end

      it 'does not check a request without body, or a body not parsed as JSON' do
        expect { check({}, json: true) }.not_to(raise_error)
        expect { check({'Content-Type' => 'text/plain'}, body: 'a=b') }.not_to(raise_error)
      end
    end
  end
end
