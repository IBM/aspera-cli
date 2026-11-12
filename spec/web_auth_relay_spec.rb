# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'aspera/web_auth/relay'
require 'aspera/web_auth/paste'
require 'aspera/web_auth/blob'

RSpec.describe(Aspera::WebAuth::Relay) do
  let(:valid) { {'login_url' => 'https://idp.example.com/authorize?a=1&b=2', 'redirect_uri' => 'http://localhost:12345/', 'reply_keys' => %w[code state]} }

  describe '.parse' do
    it 'accepts a valid login, and calculates the host' do
      login = described_class.parse(valid)
      expect(login.host).to(eq('idp.example.com'))
      expect(login.login_url.to_s).to(eq(valid['login_url']))
      expect(login.redirect_uri).to(eq('http://localhost:12345/'))
      expect(login.reply_keys).to(eq(%w[code state]))
    end

    it 'does not use a host given in the code' do
      expect(described_class.parse(valid.merge('host' => 'trusted.example.com')).host).to(eq('idp.example.com'))
    end

    it 'accepts loopback addresses' do
      ['http://127.0.0.1:1/cb', 'http://[::1]:1/cb', 'http://localhost:1'].each do |uri|
        expect(described_class.parse(valid.merge('redirect_uri' => uri)).redirect_uri).to(eq(uri))
      end
    end

    it 'refuses a login page that is not https' do
      expect { described_class.parse(valid.merge('login_url' => 'http://idp.example.com/a')) }.to(raise_error(Aspera::ParameterError, /https/))
      expect { described_class.parse(valid.merge('login_url' => 'file:///etc/passwd')) }.to(raise_error(Aspera::ParameterError, /https/))
      expect { described_class.parse(valid.merge('login_url' => 'javascript:alert(1)')) }.to(raise_error(Aspera::ParameterError))
    end

    it 'refuses a redirect_uri that is not loopback' do
      expect { described_class.parse(valid.merge('redirect_uri' => 'http://example.com:12345/')) }.to(raise_error(Aspera::ParameterError, /loopback/))
      expect { described_class.parse(valid.merge('redirect_uri' => 'http://0.0.0.0:12345/')) }.to(raise_error(Aspera::ParameterError, /loopback/))
      expect { described_class.parse(valid.merge('redirect_uri' => 'http://192.168.1.2:12345/')) }.to(raise_error(Aspera::ParameterError, /loopback/))
    end

    it 'refuses a missing or invalid url' do
      expect { described_class.parse(valid.except('login_url')) }.to(raise_error(Aspera::ParameterError, /login_url is missing/))
      expect { described_class.parse(valid.merge('redirect_uri' => 'http://localhost:12345/ a')) }.to(raise_error(Aspera::ParameterError, /not a valid URL/))
    end

    it 'refuses invalid reply keys' do
      [nil, [], 'code', ['Code'], ['a b'], [1], ['a'] * 17, ["code\n"]].each do |keys|
        expect { described_class.parse(valid.merge('reply_keys' => keys)) }.to(raise_error(Aspera::ParameterError, /reply_keys/))
      end
    end

    it 'refuses a content that is not a hash' do
      expect { described_class.parse([]) }.to(raise_error(Aspera::ParameterError))
    end
  end

  describe '.run' do
    # port 0 is not usable: the redirect_uri is given in the code
    let(:port) { TCPServer.open('127.0.0.1', 0) { |server| server.addr[1] } }
    let(:opened) { [] }

    before { allow(Aspera::Environment.instance).to(receive(:open_uri)) { |url| opened.push(url.to_s) } }

    it 'opens the login page, then gives the reply code in the page, with only the reply keys' do
      login = described_class.parse(valid.merge('redirect_uri' => "http://127.0.0.1:#{port}/"))
      thread = Thread.new { described_class.run(login) }
      response = nil
      20.times do
        response = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/?code=AB%2Bcd&state=s-1&extra=zzz"))
        break
      rescue Errno::ECONNREFUSED
        sleep 0.1
      end
      thread.join(15)
      expect(opened).to(eq([valid['login_url']]))
      expect(response.code).to(eq('200'))
      csp = response['Content-Security-Policy']
      expect(csp).to(include("default-src 'none'"))
      nonce = csp[/nonce-([^']+)/, 1]
      expect(response.body).to(include(%(<script nonce="#{nonce}">)))
      expect(response['Cache-Control']).to(eq('no-store'))
      reply = response.body[/ASCLI1R[A-Z2-7]+/]
      expect(reply).not_to(be_nil)
      # the code is only in the script, not in the visible page
      expect(response.body.scan(reply).length).to(eq(1))
      expect(Aspera::WebAuth::Paste.parse(reply)).to(eq('code' => 'AB+cd', 'state' => 's-1'))
      expect(response.body).not_to(include('zzz'))
    end
  end
end
