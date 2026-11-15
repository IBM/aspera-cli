# frozen_string_literal: true

require_relative 'assert'
require 'json'
require 'zlib'
require 'openssl'

module Aspera
  # Converts a Hash to a compact text, typed or pasted by a user, and back. Only Ruby standard libraries are used.
  # Used for the codes exchanged by the user between `ascli` and the browser, or Shares (option `ui.web_auth=paste`).
  #
  # Steps: Hash -> JSON -> deflate -> AES-256-GCM -> Base64 URL-safe, without padding (characters: `A-Z a-z 0-9 - _`).
  #
  # Text layout, once decoded from Base64: `IV (12 bytes) + authentication tag (16 bytes) + encrypted data`.
  # The key is `SHA256(<base key> + <secret> + <YYYYMMDD>)`, with the date in UTC. Base key and secret are optional.
  # The authentication tag detects an incomplete, mistyped or modified text, or a wrong key.
  # There is no prefix nor type in the text: the receiver checks the keys of the Hash.
  #
  # The protection depends on the key: if the base key is a constant (e.g. in the source code) and there is no secret, the key is not secret, and the date is easy to guess:
  # the text is then not readable at first sight and is not valid for long, but it is not confidential.
  # To make it confidential, give a `secret` known only by both sides (e.g. a random `state`).
  #
  # The date changes at midnight UTC, and the clocks of both sides can differ: `unseal` also tries the day before and the day after.
  # When unsealing, spaces and line breaks are ignored (a text split on several lines is valid), as well as quotes and punctuation around the text.
  # Letter case matters.
  module SealedHash
    CIPHER = 'aes-256-gcm'
    IV_SIZE = 12
    TAG_SIZE = 16
    DAY = 86_400
    # Shortest text: IV, tag and one byte of data, in Base64
    MIN_TEXT_LENGTH = ((IV_SIZE + TAG_SIZE + 1) * 4 / 3.0).ceil
    # Limits on what is accepted: protection against an abusive input
    MAX_TEXT_LENGTH = 65_536
    MAX_INFLATED_SIZE = 262_144
    # Days tried to decrypt, relative to the current day
    DAY_OFFSETS = [0, -1, 1].freeze
    TEXT_CHARS = /\A[A-Za-z0-9_-]*\z/
    private_constant :CIPHER, :IV_SIZE, :TAG_SIZE, :DAY, :MIN_TEXT_LENGTH, :MAX_TEXT_LENGTH, :MAX_INFLATED_SIZE, :DAY_OFFSETS, :TEXT_CHARS

    class << self
      # @param data     [Hash]        Data to transform
      # @param secret   [String, nil] Value known by both sides, added to the key
      # @param base_key [String, nil] Base of the key, e.g. the name of the application (optional)
      # @param time     [Time]        Date used for the key
      # @return [String] Base64 URL-safe text, without padding
      def seal(data, secret: nil, base_key: nil, time: Time.now)
        Aspera.assert_type(data, Hash)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = derive_key(base_key, secret, time)
        iv = cipher.random_iv
        body = cipher.update(Zlib::Deflate.deflate(JSON.generate(data), Zlib::BEST_COMPRESSION)) + cipher.final
        [iv + cipher.auth_tag(TAG_SIZE) + body].pack('m0').tr('+/', '-_').delete('=')
      end

      # @param text [String] Text typed or pasted by the user
      # @return [Boolean] `true` if text looks like a sealed hash (characters and length), to be decoded with `unseal`.
      #   A URL or a query always has other characters (`:`, `/`, `?`, `=`, `&`).
      def sealed?(text)
        clean = normalize(text)
        clean.length >= MIN_TEXT_LENGTH && clean.match?(TEXT_CHARS)
      end

      # @param text     [String]      Text produced by `seal`
      # @param secret   [String, nil] Value known by both sides, added to the key
      # @param base_key [String, nil] Base of the key, e.g. the name of the application (optional)
      # @param time     [Time]        Date used for the key
      # @return [Hash] The data
      # @raise [ParameterError] if text is not valid: incomplete, mistyped, modified, or made with another key or another day
      def unseal(text, secret: nil, base_key: nil, time: Time.now)
        clean = normalize(text)
        raise ParameterError, 'Code is too long' if clean.length > MAX_TEXT_LENGTH
        raise ParameterError, 'Code has invalid characters: only letters, digits, - and _ are expected' unless clean.match?(TEXT_CHARS)
        raise ParameterError, 'Code is incomplete' if clean.length < MIN_TEXT_LENGTH
        raw = begin
          "#{clean.tr('-_', '+/')}#{'=' * ((4 - (clean.length % 4)) % 4)}".unpack1('m0')
        rescue ArgumentError
          raise ParameterError, 'Code is incomplete or has typing errors'
        end
        deflated = nil
        DAY_OFFSETS.each do |offset|
          deflated = decrypt(raw, derive_key(base_key, secret, time + (offset * DAY)))
          break unless deflated.nil?
        end
        raise ParameterError, 'Invalid code: incomplete, mistyped, or not made today' if deflated.nil?
        data = JSON.parse(inflate(deflated))
        raise ParameterError, 'Invalid code: unexpected content' unless data.is_a?(Hash)
        data
      rescue JSON::ParserError, Zlib::Error
        raise ParameterError, 'Invalid code: unexpected content'
      end

      private

      # @return [String] Text without spaces and surrounding punctuation (quotes, ...)
      def normalize(text)
        # Only patterns anchored at the start (the end is handled on the reversed text): linear time on any input
        clean = text.to_s.gsub(/\s/, '').sub(/\A[^A-Za-z0-9_-]+/, '')
        clean.reverse.sub(/\A[^A-Za-z0-9_-]+/, '').reverse
      end

      # @return [String] 32 bytes
      def derive_key(base_key, secret, time)
        OpenSSL::Digest.digest('SHA256', "#{base_key}#{secret}#{time.getutc.strftime('%Y%m%d')}")
      end

      # @return [String, nil] Deflated data, or `nil` if the key or the tag is not the expected one
      def decrypt(raw, key)
        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = key
        cipher.iv = raw.byteslice(0, IV_SIZE)
        cipher.auth_tag = raw.byteslice(IV_SIZE, TAG_SIZE)
        cipher.update(raw.byteslice((IV_SIZE + TAG_SIZE)..)) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        nil
      end

      # @param body [String] Deflated data
      # @return [String] Inflated data, limited in size
      def inflate(body)
        output = +''
        inflater = Zlib::Inflate.new
        begin
          inflater.inflate(body) do |chunk|
            output << chunk
            raise ParameterError, 'Invalid code: content is too large' if output.bytesize > MAX_INFLATED_SIZE
          end
          raise ParameterError, 'Code is incomplete' unless inflater.finished?
        ensure
          inflater.close
        end
        output
      end
    end
  end
end
