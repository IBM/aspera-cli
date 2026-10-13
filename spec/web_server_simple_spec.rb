# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'openssl'
require 'tmpdir'
require 'uri'

RSpec.describe(Aspera::WebServerSimple) do
  describe '.loopback?' do
    it 'is true for local addresses' do
      %w[localhost 127.0.0.1 127.0.0.2 ::1].each { |host| expect(described_class.loopback?(host)).to(be(true), host) }
    end

    it 'is false for other addresses and host names' do
      ['0.0.0.0', '::', '192.168.1.10', 'myhost', '', nil].each { |host| expect(described_class.loopback?(host)).to(be(false), host.inspect) }
    end
  end

  describe '.assert_protected' do
    it 'accepts a loopback address without protection' do
      expect { described_class.assert_protected('localhost', protected: false, what: 'token') }.not_to(raise_error)
    end

    it 'accepts a protected server on any address' do
      expect { described_class.assert_protected('0.0.0.0', protected: true, what: 'token') }.not_to(raise_error)
    end

    it 'refuses an unprotected server on a non-loopback address' do
      expect { described_class.assert_protected('0.0.0.0', protected: false, what: 'token') }
        .to(raise_error(Aspera::ParameterError, /token is required when the server listens on an address that is not loopback .*: 0\.0\.0\.0/))
    end

    it 'raises the given exception' do
      expect { described_class.assert_protected('myhost', protected: false, what: 'token', type: ArgumentError) }.to(raise_error(ArgumentError))
    end
  end

  describe '.url and .servlet_parameters' do
    it 'splits the parameters of a command' do
      expect(described_class.url({})).to(eq(URI('http://localhost:8080')))
      expect(described_class.servlet_parameters({url: 'http://localhost:1', cert: 'c', key: 'k', chain: 'x', username: 'u'})).to(eq({username: 'u'}))
    end
  end

  describe '.serve' do
    let(:server) { instance_double(described_class, mount: nil, start: nil) }

    before { allow(described_class).to(receive(:new).and_return(server)) }

    it 'mounts the servlet on the path of url, with the arguments of the block, and starts' do
      described_class.serve({url: 'https://127.0.0.1:9443/path', cert: 'c', key: 'k', other: 1}, WEBrick::HTTPServlet::AbstractServlet, protected: false, what: 'token') { %w[a b] }
      expect(described_class).to(have_received(:new).with(URI('https://127.0.0.1:9443/path'), cert: 'c', key: 'k'))
      expect(server).to(have_received(:mount).with('/path', WEBrick::HTTPServlet::AbstractServlet, 'a', 'b'))
      expect(server).to(have_received(:start))
    end

    it 'refuses an unprotected server before creating it and evaluating the arguments' do
      evaluated = false
      expect do
        described_class.serve({url: 'http://0.0.0.0:8080'}, WEBrick::HTTPServlet::AbstractServlet, protected: false, what: 'token') do
          evaluated = true
          []
        end
      end.to(raise_error(Aspera::ParameterError, /token is required/))
      expect(evaluated).to(be(false))
      expect(described_class).not_to(have_received(:new))
    end
  end

  describe '#initialize' do
    it 'listens on an IPv6 address given in brackets in the URL' do
      skip('no IPv6 loopback') if Socket.ip_address_list.none?(&:ipv6_loopback?)
      server = described_class.new(URI('http://[::1]:0'))
      expect(server.config[:BindAddress]).to(eq('::1'))
      expect(server.listeners.map { |listener| listener.local_address.ip_address }).to(eq(['::1']))
    ensure
      server&.shutdown
    end
  end

  describe '#initialize with HTTPS' do
    it 'loads PEM certificate, key and chain' do
      Dir.mktmpdir do |dir|
        key = OpenSSL::PKey::RSA.new(2048)
        cert = described_class.self_signed_cert(key)
        File.write(File.join(dir, 'key.pem'), key.to_pem)
        File.write(File.join(dir, 'cert.pem'), cert.to_pem)
        server = described_class.new(URI('https://127.0.0.1:0'), cert: File.join(dir, 'cert.pem'), key: File.join(dir, 'key.pem'), chain: File.join(dir, 'cert.pem'))
        expect(server.config[:SSLCertificate].to_der).to(eq(cert.to_der))
        expect(server.config[:SSLExtraChainCert].map(&:to_der)).to(eq([cert.to_der]))
      ensure
        server&.shutdown
      end
    end
  end
end
