# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'assert'
require_relative 'inflate'
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
  # The key is `SHA256(<base key> + <secret> + <slot>)`, where slot is the Unix time divided by the period (15 minutes by default), rounded down.
  # Base key and secret are optional.
  # The authentication tag detects an incomplete, mistyped or modified text, or a wrong key.
  # There is no prefix nor type in the text: the receiver checks the keys of the Hash.
  #
  # The protection depends on the key: if the base key is a constant (e.g. in the source code) and there is no secret, the key is not secret, and the slot is easy to guess:
  # the text is then not readable at first sight and is not valid for long, but it is not confidential.
  # To make it confidential, give a `secret` known only by both sides (e.g. a random `state`).
  #
  # The slot changes every period, and the clocks of both sides can differ: `unseal` also tries the previous slot and the next one.
  # So a text is valid from 1 to 2 periods after its creation (15 to 30 minutes by default), and is also accepted if the clock of the receiver is up to 1 period behind.
  # When unsealing, spaces and line breaks are ignored (a text split on several lines is valid), as well as quotes and punctuation around the text.
  # Letter case matters.
  #
  # With `encrypt: false`, there is no encryption and no validity period: the text is only Hash -> JSON -> deflate -> Base64 URL-safe, readable by anyone, without detection of errors.
  # It is used for links that must stay valid and are decoded by other programs (e.g. JavaScript in a browser).
  # `sealed?` does not know this mode.
  # With `reverse: true`, the final text is reversed (it must be the same on both sides), in any mode.
  module SealedHash
    CIPHER = 'aes-256-gcm'
    IV_SIZE = 12
    TAG_SIZE = 16
    # Duration of a slot, in seconds
    PERIOD = 900
    # Shortest text: IV, tag and one byte of data, in Base64
    MIN_TEXT_LENGTH = ((IV_SIZE + TAG_SIZE + 1) * 4 / 3.0).ceil
    # Limits on what is accepted: protection against an abusive input
    MAX_TEXT_LENGTH = 65_536
    MAX_INFLATED_SIZE = 262_144
    # Slots tried to decrypt, relative to the current slot
    SLOT_OFFSETS = [0, -1, 1].freeze
    TEXT_CHARS = /\A[A-Za-z0-9_-]*\z/
    private_constant :CIPHER, :IV_SIZE, :TAG_SIZE, :MIN_TEXT_LENGTH, :MAX_TEXT_LENGTH, :MAX_INFLATED_SIZE, :SLOT_OFFSETS, :TEXT_CHARS

    class << self
      # @param data     [Hash]        Data to transform
      # @param secret   [String, nil] Value known by both sides, added to the key
      # @param base_key [String, nil] Base of the key, e.g. the name of the application (optional)
      # @param time     [Time]        Time used for the key
      # @param period   [Integer]     Duration of a slot, in seconds (must be the same on both sides)
      # @param encrypt  [Boolean]     `false`: no encryption, no validity period (secret, base_key, time and period are ignored)
      # @param reverse  [Boolean]     `true`: the text is reversed
      # @return [String] Base64 URL-safe text, without padding
      def seal(data, secret: nil, base_key: nil, time: Time.now, period: PERIOD, encrypt: true, reverse: false)
        Aspera.assert_type(data, Hash)
        deflated = Zlib::Deflate.deflate(JSON.generate(data), Zlib::BEST_COMPRESSION)
        raw =
          if encrypt
            cipher = OpenSSL::Cipher.new(CIPHER).encrypt
            cipher.key = derive_key(base_key, secret, time.to_i / period)
            iv = cipher.random_iv
            body = cipher.update(deflated) + cipher.final
            iv + cipher.auth_tag(TAG_SIZE) + body
          else
            deflated
          end
        text = [raw].pack('m0').tr('+/', '-_').delete('=')
        reverse ? text.reverse : text
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
      # @param time     [Time]        Time used for the key
      # @param period   [Integer]     Duration of a slot, in seconds (must be the same on both sides)
      # @param encrypt  [Boolean]     Same value as for `seal`
      # @param reverse  [Boolean]     Same value as for `seal`
      # @return [Hash] The data
      # @raise [ParameterError] if text is not valid: incomplete, mistyped, modified, or made with another key or too long ago
      def unseal(text, secret: nil, base_key: nil, time: Time.now, period: PERIOD, encrypt: true, reverse: false)
        clean = normalize(text)
        clean = clean.reverse if reverse
        raise ParameterError, 'Code is too long' if clean.length > MAX_TEXT_LENGTH
        raise ParameterError, 'Code has invalid characters: only letters, digits, - and _ are expected' unless clean.match?(TEXT_CHARS)
        raise ParameterError, 'Code is incomplete' if clean.length < (encrypt ? MIN_TEXT_LENGTH : 1)
        raw = begin
          "#{clean.tr('-_', '+/')}#{'=' * ((4 - (clean.length % 4)) % 4)}".unpack1('m0')
        rescue ArgumentError
          raise ParameterError, 'Code is incomplete or has typing errors'
        end
        if encrypt
          deflated = nil
          SLOT_OFFSETS.each do |offset|
            deflated = decrypt(raw, derive_key(base_key, secret, (time.to_i / period) + offset))
            break unless deflated.nil?
          end
          raise ParameterError, 'Invalid code: incomplete, mistyped, expired, or the clock is wrong (check the time of both computers)' if deflated.nil?
        else
          deflated = raw
        end
        data = JSON.parse(Inflate.limited(deflated, max_size: MAX_INFLATED_SIZE, what: 'Code'))
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
      def derive_key(base_key, secret, slot)
        OpenSSL::Digest.digest('SHA256', "#{base_key}#{secret}#{slot}")
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
    end
  end
end
