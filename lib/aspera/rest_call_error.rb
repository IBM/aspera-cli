module Aspera
  # raised on error after REST call
  class RestCallError < StandardError
    attr_accessor :request
    attr_accessor :response
    # @param http response
    def initialize(req,resp,msg)
      @request = req
      @response = resp
      super(msg)
    end
  end
end
