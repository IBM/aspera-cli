# frozen_string_literal: true

require 'aspera/secret_strength'
require 'securerandom'

RSpec.describe(Aspera::SecretStrength) do
  letters = ('a'..'z').to_a
  # Secrets easy to guess, generated at each run: repeats, sequences, keyboard rows, years, short
  weak_secrets = [
    SecureRandom.alphanumeric(1) * 24, letters.drop(rand(3)).first(24).join, 'qwertyuiop'[rand(3), 8],
    SecureRandom.alphanumeric(3) * 6, rand(1950..2030).to_s * 5, SecureRandom.alphanumeric(10)
  ].freeze
  # Without dictionary, the built-in estimate takes lowercase letters as words
  word_secrets = [Array.new(25) { letters.sample }.join, "#{Array.new(8) { letters.sample }.join.capitalize}#{rand(1950..2030)}!"].freeze
  # Random secrets generated as recommended
  random_secrets = Array.new(50) { SecureRandom.hex(32) } + Array.new(50) { SecureRandom.urlsafe_base64(32) }

  describe '.estimate_bits' do
    it 'is low for weak secrets' do
      (weak_secrets + word_secrets).each { |secret| expect(described_class.estimate_bits(secret)).to(be < 80, secret) }
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
      expect(described_class.bits(word_secrets.last)).to(eq(described_class.estimate_bits(word_secrets.last)))
    end

    it 'uses zxcvbn when installed' do
      skip('gem zxcvbn not installed') unless described_class.send(:zxcvbn?)
      expect(described_class.bits(word_secrets.last)).to(eq(Math.log2(Zxcvbn.test(word_secrets.last).guesses)))
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
      expect { described_class.assert_strong(weak_secrets.first, name: 'my_token') }
        .to(raise_error(Aspera::ParameterError, /\Amy_token is too weak: about \d+ bits, minimum 80 \(my_token_min_bits\)\. Generate one with: openssl rand -hex 32\z/))
    end

    it 'accepts a weak secret if min_bits allows it' do
      expect { described_class.assert_strong(weak_secrets.first, name: 'my_token', min_bits: 0) }.not_to(raise_error)
    end

    it 'raises the given exception' do
      expect { described_class.assert_strong(weak_secrets.first, name: 'my_token', type: ArgumentError) }.to(raise_error(ArgumentError, /my_token is too weak/))
    end
  end
end
