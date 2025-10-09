# frozen_string_literal: true

require 'aspera/ascp/management'

module Aspera
  module Transfer
    # error raised if transfer fails
    class Error < StandardError
      attr_reader :err_code

      # @param description [String] `Description` on management port
      # @param code [Integer] `Description` on management port, use zero if unknown
      def initialize(description, code: nil)
        super(description)
        @err_code = code.to_i
      end

      def info
        r = Ascp::Management::ERRORS[@err_code] || Ascp::Management::ERRORS[0]
        return r.merge({i: @err_code})
      end

      # @param message [String, nil] Optional actual message on management port
      def retryable?
        return false if @err_code.eql?(14) && message.eql?('Target address not available')
        info[:r]
      end
    end
  end
end
