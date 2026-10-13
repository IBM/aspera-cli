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
