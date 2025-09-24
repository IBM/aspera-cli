# frozen_string_literal: true

module Aspera
  # raised on error after REST call
  class RestCallError < StandardError
    attr_reader :request, :response

    # @param req HTTP Request object
    # @param resp HTTP Response object
    # @param msg Error message
    def initialize(msg, req = nil, resp = nil)
      @request = req
      @response = resp
      super(msg)
    end
  end
end
