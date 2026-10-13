# frozen_string_literal: true

require 'aspera/secret_strength'
require 'securerandom'

RSpec.describe(Aspera::SecretStrength) do
  # Secrets easy to guess: repeats, sequences, keyboard rows, words, years, l33t
  weak_secrets = [
    'mysecret', 'Password123!', 'a' * 24, 'abcdefghijklmnopqrstuvwx', 'qwertyuiopasdfghjkl', 'abcabcabcabcabcabc',
    'Tr0ub4dor&3', 'MySecretToken2024!', 'correcthorsebatterystaple', 'ThisIsMyVeryLongWebhookSecret2026', 'Summer2024!Summer2024!'
  ].freeze
  # Random secrets generated as recommended
  random_secrets = Array.new(50) { SecureRandom.hex(32) } + Array.new(50) { SecureRandom.urlsafe_base64(32) }

  describe '.estimate_bits' do
    it 'is low for weak secrets' do
      weak_secrets.each { |secret| expect(described_class.estimate_bits(secret)).to(be < 80, secret) }
    end

    it 'is high for random secrets of 32 bytes' do
      random_secrets.each { |secret| expect(described_class.estimate_bits(secret)).to(be > 128, secret) }
    end

    it 'is 0 for an empty secret' do
      expect(described_class.estimate_bits('')).to(eq(0.0))
    end
  end

  describe '.bits' do
    it 'uses the built-in estimate when zxcvbn is not installed' do
      allow(described_class).to(receive(:zxcvbn?).and_return(false))
      expect(described_class.bits('MySecretToken2024!')).to(eq(described_class.estimate_bits('MySecretToken2024!')))
    end

    it 'uses zxcvbn when installed' do
      skip('gem zxcvbn not installed') unless described_class.send(:zxcvbn?)
      expect(described_class.bits('mysecret')).to(eq(Math.log2(Zxcvbn.test('mysecret').guesses)))
      weak_secrets.each { |secret| expect(described_class.bits(secret)).to(be < 90, secret) }
      random_secrets.first(10).each { |secret| expect(described_class.bits(secret)).to(be > 128, secret) }
    end

    it 'is 0 for an empty or nil secret' do
      expect(described_class.bits('')).to(eq(0.0))
      expect(described_class.bits(nil)).to(eq(0.0))
    end
  end

  describe '.assert_strong' do
    it 'accepts a random secret of 32 bytes' do
      expect { described_class.assert_strong(random_secrets.first, name: 'my_token') }.not_to(raise_error)
    end

    it 'refuses an empty or nil secret, also with min_bits 0' do
      ['', nil].each do |secret|
        expect { described_class.assert_strong(secret, name: 'my_token', min_bits: 0) }
          .to(raise_error(Aspera::ParameterError, 'my_token must not be empty'))
      end
    end

    it 'refuses a weak secret, with the name of the parameter of the minimum' do
      expect { described_class.assert_strong('MySecretToken2024!', name: 'my_token') }
        .to(raise_error(Aspera::ParameterError, /\Amy_token is too weak: about \d+ bits, minimum 80 \(my_token_min_bits\)\. Generate one with: openssl rand -hex 32\z/))
    end

    it 'accepts a weak secret if min_bits allows it' do
      expect { described_class.assert_strong('mysecret', name: 'my_token', min_bits: 0) }.not_to(raise_error)
    end

    it 'raises the given exception' do
      expect { described_class.assert_strong('mysecret', name: 'my_token', type: ArgumentError) }.to(raise_error(ArgumentError, /my_token is too weak/))
    end
  end
end
