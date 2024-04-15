# frozen_string_literal: true

require 'aspera/transfer/error_info'

module Aspera
  module Transfer
    # error raised if transfer fails
    class Error < StandardError
      attr_reader :err_code

      def initialize(message, err_code=nil)
        super(message)
        @err_code = err_code
      end

      def info
        r = ERROR_INFO[@err_code] || {r: false, c: 'UNKNOWN', m: 'unknown', a: 'unknown'}
        return r.merge({i: @err_code})
      end

      def retryable?; info[:r]; end
    end
  end
end
