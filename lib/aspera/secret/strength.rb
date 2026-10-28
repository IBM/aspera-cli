# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Secret
    # Estimate of the strength of a secret (e.g. a token), in bits: log2 of the number of guesses to find it
    #
    # Uses gem `zxcvbn` if installed (dictionaries, l33t, dates...), else a built-in estimate, the lowest of:
    # - alphabet: length x log2(size of character classes used)
    # - Shannon: empirical entropy of characters (catches repeats)
    # - patterns: repeats, sequences and keyboard rows cost 1 bit per character, words and years 2 bits per character
    # Both under-estimate random secrets: a random secret of 32 bytes (e.g. `openssl rand -hex 32`) is far above any usual minimum.
    module Strength
      # Default minimum strength of tokens, in bits: random tokens of 32 bytes are far above
      DEFAULT_MIN_BITS = 80
      # Classes of characters, with their size
      CHARACTER_CLASSES = [[/[a-z]/, 26], [/[A-Z]/, 26], [/\d/, 10], [/[^a-zA-Z\d]/, 33]].freeze
      # Adjacent characters in those rows form a sequence
      KEYBOARD_ROWS = %w[1234567890 qwertyuiop asdfghjkl zxcvbnm azertyuiop qsdfghjklm wxcvbn].freeze
      # Words (3+ letters, optionally capitalized) and years
      LOW_ENTROPY_REGEXES = [/[A-Z]?[a-z]{3,}/, /(?:19|20)\d\d/].freeze
      # Entropy of English text is 1 to 1.5 bit per letter: keep a margin
      LOW_ENTROPY_BITS = 2.0
      # zxcvbn is slow on long secrets: the beginning is enough to assess strength
      ZXCVBN_MAX_LENGTH = 100
      private_constant :CHARACTER_CLASSES, :KEYBOARD_ROWS, :LOW_ENTROPY_REGEXES, :LOW_ENTROPY_BITS, :ZXCVBN_MAX_LENGTH

      class << self
        # @param secret [String] Secret to assess
        # @return [Float] Estimated strength in bits
        def bits(secret)
          secret = secret.to_s
          return 0.0 if secret.empty?
          zxcvbn_bits(secret) || estimate_bits(secret)
        end

        # Refuse an empty or weak secret: an empty one would often accept requests without secret
        # @param secret   [String]    Secret to check
        # @param name     [String]    Name of the parameter holding the secret, its minimum is in parameter `<name>_min_bits`
        # @param min_bits [Integer]   Minimum estimated strength in bits, `0` checks only that the secret is not empty
        # @param type     [Exception] Exception to raise
        # @raise [Exception] if the secret is empty or weaker than `min_bits`
        def assert_strong(secret, name:, min_bits: DEFAULT_MIN_BITS, type: ParameterError)
          Aspera.assert(!secret.to_s.empty?, type: type) { "#{name} must not be empty" }
          strength = bits(secret)
          Aspera.assert(strength >= min_bits, type: type) do
            "#{name} is too weak: about #{strength.round} bits, minimum #{min_bits} (#{name}_min_bits). Generate one with: openssl rand -hex 32"
          end
        end

        # Built-in estimate, without dictionary
        # @param secret [String] Secret to assess
        # @return [Float] Estimated strength in bits
        def estimate_bits(secret)
          return 0.0 if secret.empty?
          bits_per_char = Math.log2(CHARACTER_CLASSES.sum { |regex, size| secret.match?(regex) ? size : 0 })
          [secret.size * bits_per_char, shannon_bits(secret), pattern_bits(secret, bits_per_char)].min
        end

        private

        # @return [Float, nil] Strength estimated by gem `zxcvbn`, or `nil` if not installed
        def zxcvbn_bits(secret)
          return unless zxcvbn?
          Math.log2(Zxcvbn.test(secret[0, ZXCVBN_MAX_LENGTH]).guesses)
        rescue StandardError => e
          Log.log.debug { "zxcvbn failed: #{e.message}" }
          nil
        end

        # @return [Boolean] `true` if gem `zxcvbn` (or `zxcvbn-ruby`) is installed
        def zxcvbn?
          return @zxcvbn unless @zxcvbn.nil?
          @zxcvbn =
            begin
              require 'zxcvbn'
              true
            rescue LoadError
              false
            end
        end

        # Empirical Shannon entropy of characters of the secret
        def shannon_bits(secret)
          secret.chars.tally.values.sum do |count|
            probability = count.fdiv(secret.size)
            -probability * Math.log2(probability)
          end * secret.size
        end

        # Sum of bits of each character, depending on patterns
        def pattern_bits(secret, bits_per_char)
          # Bits of characters in words and years
          low = Array.new(secret.size)
          LOW_ENTROPY_REGEXES.each do |regex|
            secret.scan(regex) { low.fill(LOW_ENTROPY_BITS, Regexp.last_match.begin(0)...Regexp.last_match.end(0)) }
          end
          secret.chars.each_with_index.sum do |char, index|
            next 1.0 if index.positive? && sequence?(secret[index - 1], char)
            low[index] || bits_per_char
          end
        end

        # @return [Boolean] `true` if `char` repeats `previous`, or follows it in alphabet, digits or keyboard row
        def sequence?(previous, char)
          previous = previous.downcase
          char = char.downcase
          return true if (char.ord - previous.ord).abs <= 1
          KEYBOARD_ROWS.any? { |row| (one = row.index(previous)) && (two = row.index(char)) && (one - two).abs.eql?(1) }
        end
      end
    end
  end
end
