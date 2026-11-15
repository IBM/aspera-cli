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

  it 'accepts the previous and the next slot, not more' do
    text = described_class.seal(data, time: now)
    expect(described_class.unseal(text, time: now + 900)).to(eq(data))
    expect(described_class.unseal(text, time: now - 900)).to(eq(data))
    expect { described_class.unseal(text, time: now + (2 * 900)) }.to(raise_error(Aspera::ParameterError, /expired/))
    expect { described_class.unseal(text, time: now - (2 * 900)) }.to(raise_error(Aspera::ParameterError, /expired/))
  end

  it 'is valid from 1 to 2 periods' do
    # `now` is at the start of a slot: 10:00:00
    text = described_class.seal(data, time: now)
    expect(described_class.unseal(text, time: now + 1799)).to(eq(data))
    expect { described_class.unseal(text, time: now + 1800) }.to(raise_error(Aspera::ParameterError, /expired/))
    # created at the end of a slot: valid 15 min only
    text = described_class.seal(data, time: now + 899)
    expect(described_class.unseal(text, time: now + 1799)).to(eq(data))
    expect { described_class.unseal(text, time: now + 1800) }.to(raise_error(Aspera::ParameterError, /expired/))
  end

  it 'uses a custom period, that must be the same on both sides' do
    text = described_class.seal(data, time: now, period: 60)
    expect(described_class.unseal(text, time: now + 100, period: 60)).to(eq(data))
    expect { described_class.unseal(text, time: now + 200, period: 60) }.to(raise_error(Aspera::ParameterError, /expired/))
    expect { described_class.unseal(text, time: now, period: 120) }.to(raise_error(Aspera::ParameterError, /Invalid code/))
  end

  it 'does not depend on the time zone' do
    local = Time.new(2026, 11, 15, 5, 0, 0, '-05:00')
    expect(local.utc).to(eq(now))
    expect(described_class.unseal(described_class.seal(data, time: local), time: now)).to(eq(data))
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
