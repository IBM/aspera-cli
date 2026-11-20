# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'assert'
require 'zlib'

module Aspera
  # Decompression of zlib data that comes from outside (e.g. a code pasted by a user, a token given by a client or a server).
  # A small input can inflate to gigabytes (decompression bomb): the size of the result is checked while decompressing, not after.
  module Inflate
    class << self
      # @param data     [String]  Zlib data
      # @param max_size [Integer] Maximum size of the result, in bytes
      # @param what     [String]  What is decompressed, for error messages, e.g. `Code`
      # @return [String] Inflated data
      # @raise [ParameterError] If the result is larger than `max_size`, or the data is incomplete
      # @raise [Zlib::Error] If the data is not zlib data
      def limited(data, max_size:, what:)
        output = +''
        inflater = Zlib::Inflate.new
        begin
          inflater.inflate(data) do |chunk|
            output << chunk
            raise ParameterError, "#{what} is too large when decompressed: more than #{max_size} bytes" if output.bytesize > max_size
          end
          raise ParameterError, "#{what} is incomplete" unless inflater.finished?
        ensure
          inflater.close
        end
        output
      end
    end
  end
end
