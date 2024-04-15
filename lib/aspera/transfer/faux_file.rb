# frozen_string_literal: true

module Aspera
  module Fasp
    # generates a pseudo file stream
    class FauxFile
      # marker for faux file
      PREFIX = 'faux:///'
      # size suffix
      SUFFIX = %w[k m g t p e]
      class << self
        def open(name)
          return nil unless name.start_with?(PREFIX)
          parts = name[PREFIX.length..-1].split('?')
          raise 'Format: #{PREFIX}<file path>?<size>' unless parts.length.eql?(2)
          raise "Format: <integer>[#{SUFFIX.join(',')}]" unless (m = parts[1].downcase.match(/^(\d+)([#{SUFFIX.join('')}])$/))
          size = m[1].to_i
          suffix = m[2]
          SUFFIX.each do |s|
            size *= 1024
            break if s.eql?(suffix)
          end
          return FauxFile.new(parts[0], size)
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
        return nil if eof?
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
