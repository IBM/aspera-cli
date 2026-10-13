# frozen_string_literal: true

require 'aspera/web_server_simple'

RSpec.describe(Aspera::WebServerSimple) do
  describe '.loopback?' do
    it 'is true for local addresses' do
      %w[localhost 127.0.0.1 127.0.0.2 ::1].each { |host| expect(described_class.loopback?(host)).to(be(true), host) }
    end

    it 'is false for other addresses and host names' do
      ['0.0.0.0', '::', '192.168.1.10', 'myhost', '', nil].each { |host| expect(described_class.loopback?(host)).to(be(false), host.inspect) }
    end
  end
end
