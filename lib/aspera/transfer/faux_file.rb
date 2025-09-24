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
        # @return nil if not a faux: scheme, else a FauxFile instance
        def create(name)
          return unless name.start_with?(PREFIX)
          name_params = name[PREFIX.length..-1].split('?', 2)
          raise Error, 'Format: #{PREFIX}<file path>?<size>' unless name_params.length.eql?(2)
          raise Error, "Format: <integer>[#{SIZE_UNITS.join(',')}]" unless (m = name_params[1].downcase.match(/^(\d+)([#{SIZE_UNITS.join('')}])$/))
          size = m[1].to_i
          suffix = m[2]
          SIZE_UNITS.each do |s|
            size *= 1024
            break if s.eql?(suffix)
          end
          return FauxFile.new(name_params[0], size)
        end
      end
      attr_reader :path, :size

      def initialize(path, size)
        @path = path
        @size = size
        @offset = 0
        # we cache large chunks, anyway most of them will be the same size
        @chunk_by_size = {}
      end

      def read(chunk_size)
        return if eof?
        bytes_to_read = [chunk_size, @size - @offset].min
        @offset += bytes_to_read
        @chunk_by_size[bytes_to_read] = "\x00" * bytes_to_read unless @chunk_by_size.key?(bytes_to_read)
        return @chunk_by_size[bytes_to_read]
      end

      def close
      end

      def eof?
        return @offset >= @size
      end
    end
  end
end
