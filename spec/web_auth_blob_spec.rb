# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

require 'aspera/web_auth/blob'

RSpec.describe(Aspera::WebAuth::Blob) do
  let(:data) { {'code' => 'abc+/=', 'state' => SecureRandom.uuid, 'refresh_token' => 'ey.' * 200} }

  it 'encodes with letters and digits only, and a prefix with the type' do
    expect(described_class.encode(:login, data)).to(match(/\ADCODE1L[A-Z2-7]+\z/))
    expect(described_class.encode(:reply, data)).to(match(/\ADCODE1R[A-Z2-7]+\z/))
  end

  it 'decodes what it encodes' do
    expect(described_class.decode(described_class.encode(:reply, data))).to(eq([:reply, data]))
    expect(described_class.decode(described_class.encode(:login, data))).to(eq([:login, data]))
  end

  it 'ignores spaces, line breaks, case and quotes' do
    code = described_class.encode(:reply, data)
    split = code.scan(/.{1,40}/).join("\n  ").downcase
    expect(described_class.decode("\"#{split}\"\n")).to(eq([:reply, data]))
  end

  it 'recognizes a code' do
    expect(described_class.code?(" #{described_class.encode(:reply, data).downcase}")).to(be(true))
    expect(described_class.code?('http://localhost:12345/?code=a&state=b')).to(be(false))
    expect(described_class.code?('code=a&state=b')).to(be(false))
  end

  it 'detects a typing error' do
    code = described_class.encode(:reply, data)
    index = (code.length / 2)
    code[index] = code[index].eql?('A') ? 'B' : 'A'
    expect { described_class.decode(code) }.to(raise_error(Aspera::ParameterError, /checksum|invalid/i))
  end

  it 'detects a truncated code' do
    code = described_class.encode(:reply, data)
    expect { described_class.decode(code[0..-9]) }.to(raise_error(Aspera::ParameterError))
    expect { described_class.decode(code[0, 12]) }.to(raise_error(Aspera::ParameterError))
    expect { described_class.decode('DCODE1R') }.to(raise_error(Aspera::ParameterError, /incomplete/))
  end

  it 'refuses what is not a code' do
    expect { described_class.decode('http://localhost') }.to(raise_error(Aspera::ParameterError, /Not a code/))
    expect { described_class.decode('DCODE1X2222222222') }.to(raise_error(Aspera::ParameterError, /type/))
    expect { described_class.decode('DCODE1R1111111111') }.to(raise_error(Aspera::ParameterError, /invalid characters/))
  end

  it 'refuses content that is not a hash' do
    body = Zlib::Deflate.deflate('[1]')
    code = "DCODE1R#{described_class.send(:base32_encode, body + [Zlib.crc32('R'.b + body)].pack('N'))}"
    expect { described_class.decode(code) }.to(raise_error(Aspera::ParameterError, /unexpected content/))
  end

  it 'refuses an inflated content that is too large' do
    body = Zlib::Deflate.deflate(JSON.generate({'x' => 'a' * 1_000_000}), Zlib::BEST_COMPRESSION)
    code = "DCODE1R#{described_class.send(:base32_encode, body + [Zlib.crc32('R'.b + body)].pack('N'))}"
    expect { described_class.decode(code) }.to(raise_error(Aspera::ParameterError, /too large/))
  end
end
