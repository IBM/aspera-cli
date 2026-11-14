# frozen_string_literal: true

require_relative '../assert'
require 'json'
require 'zlib'

module Aspera
  module WebAuth
    # Text code exchanged by the user between `ascli` on a remote host and `ascli` on the workstation that has the browser (option `ui.web_auth=paste`).
    #
    # Format: `DCODE1` + type letter + Base32 of (deflated JSON + CRC32).
    # - Type: `L` (login, from the remote host to the workstation) or `R` (reply, from the workstation to the remote host)
    # - Base32 (RFC 4648 alphabet, no padding): letters and digits only, selected with a double click and typed without quotes in any shell
    # - CRC32 of type and deflated data: detects an incomplete or mistyped code
    # Spaces, line breaks and case are ignored when decoding, so that a code split on several lines is valid.
    # A code is not encrypted: it is an encoding, the reply contains a code or tokens.
    module Blob
      PREFIX = 'DCODE1'
      TYPES = {login: 'L', reply: 'R'}.freeze
      ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
      # Limits on what is accepted: protection against an abusive input
      MAX_TEXT_LENGTH = 65_536
      MAX_INFLATED_SIZE = 262_144
      private_constant :ALPHABET, :MAX_TEXT_LENGTH, :MAX_INFLATED_SIZE

      class << self
        # @param text [String] Text typed or pasted by the user
        # @return [Boolean] `true` if text looks like a code (prefix), to be decoded with `decode`
        def code?(text)
          normalize(text).start_with?(PREFIX)
        end

        # @param type [Symbol] `:login` or `:reply`
        # @param data [Hash]   Data to transmit
        # @return [String] The code
        def encode(type, data)
          tag = TYPES.fetch(type)
          body = Zlib::Deflate.deflate(JSON.generate(data), Zlib::BEST_COMPRESSION)
          "#{PREFIX}#{tag}#{base32_encode(body + [Zlib.crc32(tag.b + body)].pack('N'))}"
        end

        # @param text [String] A code
        # @return [Array(Symbol, Hash)] Type (`:login` or `:reply`) and data
        # @raise [ParameterError] if text is not a valid code
        def decode(text)
          code = normalize(text)
          raise ParameterError, "Not a code: expecting #{PREFIX}..." unless code.start_with?(PREFIX)
          raise ParameterError, 'Code is too long' if code.length > MAX_TEXT_LENGTH
          tag = code[PREFIX.length]
          type = TYPES.key(tag)
          raise ParameterError, "Unknown type of code: #{tag.inspect}" if type.nil?
          raw = base32_decode(code[(PREFIX.length + 1)..])
          raise ParameterError, 'Code is incomplete' if raw.bytesize <= 4
          body = raw.byteslice(0, raw.bytesize - 4)
          crc = raw.byteslice(-4, 4).unpack1('N')
          raise ParameterError, 'Code is incomplete or has typing errors: checksum mismatch' unless Zlib.crc32(tag.b + body).eql?(crc)
          data = JSON.parse(inflate(body))
          raise ParameterError, 'Invalid code: unexpected content' unless data.is_a?(Hash)
          [type, data]
        rescue JSON::ParserError, Zlib::Error
          raise ParameterError, 'Invalid code: unexpected content'
        end

        private

        # @return [String] Text without spaces and surrounding punctuation (quotes, ...), in upper case
        def normalize(text)
          chars = text.to_s.gsub(/\s/, '').upcase.chars
          chars.shift while !chars.empty? && !chars.first.match?(/[A-Z0-9]/)
          chars.pop while !chars.empty? && !chars.last.match?(/[A-Z0-9]/)
          chars.join
        end

        # @param bytes [String] Binary data
        # @return [String] Base32 without padding
        def base32_encode(bytes)
          bits = bytes.unpack1('B*')
          bits += '0' * ((5 - (bits.length % 5)) % 5)
          bits.scan(/.{5}/).map { |five| ALPHABET[five.to_i(2)] }.join
        end

        # @param text [String] Base32 without padding
        # @return [String] Binary data
        def base32_decode(text)
          raise ParameterError, 'Code has invalid characters: only letters and digits 2-7 are expected' unless text.match?(/\A[A-Z2-7]*\z/)
          bits = text.each_char.map { |char| ALPHABET.index(char).to_s(2).rjust(5, '0') }.join
          [bits[0, bits.length / 8 * 8]].pack('B*')
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
end
