# frozen_string_literal: true

module Aspera
  module Transfer
    # Generates a pseudo file stream.
    class FauxFile
      SCHEME = 'faux'
      # marker for faux file
      PREFIX = "#{SCHEME}:///"
      # size units, kilo, mega ...
      SIZE_UNITS = %w[k m g t p e].freeze
      private_constant :SCHEME, :PREFIX, :SIZE_UNITS
      class << self
        # Parse a faux URI and return a `FauxFile` instance, or `nil` if the URI does not use the faux scheme.
        # URI format: `faux:///<path>?<size>`, where `<size>` is a decimal integer with an optional
        # case-insensitive unit suffix: `k`, `m`, `g`, `t`, `p`, `e` (powers of 1024).
        # When no suffix is given, the size is interpreted as raw bytes.
        # Examples: `faux:///file.bin?10` (10 bytes), `faux:///file.bin?10m` (10 MiB)
        # @param name [String] source file name, possibly a faux URI
        # @return [FauxFile, nil] `nil` if not a faux scheme, else a `FauxFile` instance
        def create(name)
          return unless name.start_with?(PREFIX)
          name_params = name.delete_prefix(PREFIX).split('?', 2)
          Aspera.assert(name_params.length.eql?(2), type: Error){"Format: #{PREFIX}<file path>?<size>"}
          m = name_params[1].downcase.match(/^(\d+)([#{SIZE_UNITS.join('')}]?)$/)
          Aspera.assert(m, type: Error){"Format: <integer>[#{SIZE_UNITS.join(',')}]"}
          size = m[2].empty? ? m[1].to_i : m[1].to_i * (1024**(SIZE_UNITS.index(m[2]) + 1))
          return FauxFile.new(name_params[0], size)
        end
      end
      # @return [String]  virtual file path
      # @return [Integer] total size in bytes
      attr_reader :path, :size

      # @param path [String]  virtual file path (from the faux URI)
      # @param size [Integer] total number of bytes to produce
      def initialize(path, size)
        @path = path
        @size = size
        @offset = 0
        # cache chunks by size so repeated reads of the same chunk length reuse the same buffer
        @chunk_by_size = {}
      end

      # Read up to `chunk_size` bytes from the stream and advance the internal offset.
      # Returns `nil` when the stream is exhausted.
      # @param chunk_size [Integer] maximum number of bytes to read
      # @return [String, nil] null-byte string of the bytes actually read, or `nil` at EOF
      def read(chunk_size)
        return if eof?
        bytes_to_read = [chunk_size, @size - @offset].min
        @offset += bytes_to_read
        @chunk_by_size[bytes_to_read] ||= "\x00" * bytes_to_read
        return @chunk_by_size[bytes_to_read]
      end

      # No-op: required to satisfy the IO-like interface used by transfer agents.
      # @return [nil]
      def close
      end

      # @return [Boolean] true when all bytes have been read
      def eof?
        return @offset >= @size
      end
    end
  end
end
