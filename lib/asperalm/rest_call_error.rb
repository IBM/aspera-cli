require 'asperalm/log'
require 'json'

module Asperalm
  # builds a meaningful error message from known formats in Aspera products
  class RestCallError < StandardError
    attr_accessor :request
    attr_accessor :response
    # @param http response
    def initialize(req,resp)
      @request = req
      @response = resp
      Log.log.debug "Error code:#{@response.code}, msg=#{@response.message.red}, body=[#{@response.body}, req.uri=#{@request['host']}]"
      # default error message is response type
      msg=@response.message
      # see if there is a more precise message
      # Hum, we would need some consistency here...
      if !@response.body.nil?
        data=JSON.parse(@response.body) rescue nil
        if data.is_a?(Hash)
          # we have a payload
          if data['error'].is_a?(Hash)
            if data['error']["user_message"].is_a?(String)
              msg=data['error']["user_message"]
            elsif data['error']["description"].is_a?(String)
              msg=data['error']["description"]
            end
          elsif data['error'].is_a?(String)
            msg=data['error']
          end
          # TODO: data['code'] and data['message'] ?
          if data['error_description'].is_a?(String)
            msg=msg+": "+data['error_description']
          end
          if data['message'].is_a?(String)
            msg=msg+": "+data['message']
            data.delete('message')
            data.each do |k,v|
              msg=msg+"\n#{k}: #{v}"
            end
          end
          if data['errors'].is_a?(Hash)
            data['errors'].each do |k,v|
              msg=msg+"\n#{k}: #{v}"
            end
          end
        end
      end
      super("#{@response.code} #{@request['host']}: "+msg)
    end
  end
end
