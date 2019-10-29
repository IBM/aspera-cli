module Asperalm
  # builds a meaningful error message from known formats in Aspera products
  class RestCallError < StandardError
    attr_accessor :request
    attr_accessor :response
    # @param http response
    def initialize(req,resp,msg)
      @request = req
      @response = resp
      Log.log.debug("Error code:#{@response.code}, msg=#{@response.message.red}, body=[#{@response.body}, req.uri=#{@request['host']}]")
      # default error message is response type
      super("#{msg}\n#{@response.code} #{@request['host']}")
    end
  end
end
