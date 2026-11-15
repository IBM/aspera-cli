# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

require_relative '../lib/aspera/sealed_hash'

RSpec.describe(Aspera::SealedHash) do
  let(:data) { {'code' => 'abc+/=', 'state' => SecureRandom.uuid, 'refresh_token' => 'ey.' * 200, 'unicode' => 'é€'} }
  let(:now) { Time.utc(2026, 11, 15, 10, 0, 0) }

  it 'gives Base64 URL-safe text without padding and without prefix' do
    20.times do
      expect(described_class.seal({'x' => SecureRandom.random_bytes(rand(1..40)).unpack1('H*')})).to(match(/\A[A-Za-z0-9_-]+\z/))
    end
  end

  it 'unseals what it seals' do
    expect(described_class.unseal(described_class.seal(data))).to(eq(data))
  end

  it 'is not deterministic (random IV)' do
    expect(described_class.seal(data)).not_to(eq(described_class.seal(data)))
  end

  it 'refuses another base key' do
    expect { described_class.unseal(described_class.seal(data, base_key: 'key'), base_key: 'other') }.to(raise_error(Aspera::ParameterError, /Invalid code/))
  end

  it 'ignores spaces, line breaks and quotes' do
    text = described_class.seal(data)
    split = text.scan(/.{1,40}/).join("\n  ")
    expect(described_class.unseal("\"#{split}\"\n")).to(eq(data))
  end

  it 'accepts the day before and the day after, not more' do
    text = described_class.seal(data, time: now)
    expect(described_class.unseal(text, time: now + 86_400)).to(eq(data))
    expect(described_class.unseal(text, time: now - 86_400)).to(eq(data))
    expect { described_class.unseal(text, time: now + (2 * 86_400)) }.to(raise_error(Aspera::ParameterError, /Invalid code/))
  end

  it 'uses the UTC date' do
    # 23:30 in UTC-5 is 04:30 the next day in UTC
    local = Time.new(2026, 11, 15, 23, 30, 0, '-05:00')
    expect(described_class.unseal(described_class.seal(data, time: local), time: Time.utc(2026, 11, 16, 12, 0, 0))).to(eq(data))
  end

  it 'detects a typing error' do
    text = described_class.seal(data)
    index = text.length / 2
    text[index] = text[index].eql?('A') ? 'B' : 'A'
    expect { described_class.unseal(text) }.to(raise_error(Aspera::ParameterError, /Invalid code/))
  end

  it 'detects a truncated text' do
    text = described_class.seal(data)
    expect { described_class.unseal(text[0..-5]) }.to(raise_error(Aspera::ParameterError))
    expect { described_class.unseal(text[0, 10]) }.to(raise_error(Aspera::ParameterError, /incomplete/))
    expect { described_class.unseal('') }.to(raise_error(Aspera::ParameterError, /incomplete/))
  end

  it 'refuses invalid characters' do
    expect { described_class.unseal('abc+/=' * 10) }.to(raise_error(Aspera::ParameterError, /invalid characters/))
  end

  it 'refuses what is not a Hash' do
    expect { described_class.seal([1]) }.to(raise_error(Aspera::AssertError))
  end

  it 'refuses an inflated content that is too large' do
    expect { described_class.unseal(described_class.seal({'x' => 'a' * 1_000_000})) }.to(raise_error(Aspera::ParameterError, /too large/))
  end

  describe '.sealed?' do
    it 'recognizes a sealed hash' do
      expect(described_class.sealed?(" #{described_class.seal({'a' => 1})}\n")).to(be(true))
    end

    it 'does not recognize a URL, a query or a short text' do
      expect(described_class.sealed?('http://localhost:12345/?code=a&state=b')).to(be(false))
      expect(described_class.sealed?('?code=a&state=b')).to(be(false))
      expect(described_class.sealed?('code=a&state=b')).to(be(false))
      expect(described_class.sealed?('short')).to(be(false))
    end
  end

  context 'with a secret' do
    it 'unseals only with the same secret' do
      text = described_class.seal(data, secret: 'state-1')
      expect(described_class.unseal(text, secret: 'state-1')).to(eq(data))
      expect { described_class.unseal(text, secret: 'state-2') }.to(raise_error(Aspera::ParameterError, /Invalid code/))
      expect { described_class.unseal(text) }.to(raise_error(Aspera::ParameterError, /Invalid code/))
    end
  end
end
