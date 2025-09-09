# frozen_string_literal: true

module Aspera
  module Transfer
    # generates a pseudo file stream
    class FauxFile
      # marker for faux file
      PREFIX = 'faux:///'
      # size suffix
      SUFFIX = %w[k m g t p e]
      private_constant :PREFIX, :SUFFIX
      class << self
        # @return nil if not a faux: scheme, else a FauxFile instance
        def create(name)
          return nil unless name.start_with?(PREFIX)
          name_params = name[PREFIX.length..-1].split('?', 2)
          raise Error, 'Format: #{PREFIX}<file path>?<size>' unless name_params.length.eql?(2)
          raise Error, "Format: <integer>[#{SUFFIX.join(',')}]" unless (m = name_params[1].downcase.match(/^(\d+)([#{SUFFIX.join('')}])$/))
          size = m[1].to_i
          suffix = m[2]
          SUFFIX.each do |s|
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
