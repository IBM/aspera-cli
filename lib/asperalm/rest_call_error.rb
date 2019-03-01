require 'asperalm/log'
require 'json'

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
      super("#{@response.code} #{@request['host']}: #{msg}")
    end

    # called by the Rest object on any result
    def self.raiseOnError(req,resp)
      data=JSON.parse(resp.body) rescue nil
      # set to non-nil if there is an error
      msg=nil
      # see if there is a more precise message
      # Hum, we would need some consistency here... payload analyzer
      # we have a payload
      if data.is_a?(Hash)
        # Type 1
        d_error=data['error']
        if d_error.is_a?(Hash)
          d_error=data['error']
          if d_error["user_message"].is_a?(String)
            msg=d_error["user_message"]
          elsif d_error["description"].is_a?(String)
            msg=d_error["description"]
          end
          # Faspex
          if d_error['internal_message'].is_a?(String)
            msg=msg+": "+d_error['internal_message']
          end
        elsif data['error'].is_a?(String)
          msg=data['error']
        end
        # Type 2
        # TODO: data['code'] and data['message'] ?
        if data['error_description'].is_a?(String)
          msg=msg+": "+data['error_description']
        end
        # Type 3
        if data['message'].is_a?(String)
          msg=msg+": "+data['message']
          data.delete('message')
          # ???
          data.each do |k,v|
            msg=msg+"\n#{k}: #{v}"
          end
        end
        # Type 4
        if data['errors'].is_a?(Hash)
          data['errors'].each do |k,v|
            msg=msg+"\n#{k}: #{v}"
          end
        end
        # Type 5 : call to upload_setup and download_setup of node api
        d_t_s=data['transfer_specs']
        if d_t_s.is_a?(Array)
          d_t_s.each do |res|
            r_err=res['transfer_spec']['error']
            if r_err.is_a?(Hash)
              msg||=''
              msg="#{msg}\n#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}"
            end
          end
        end
      end
      unless resp.code.start_with?('2') and msg.nil?
        msg||=@response.message
        raise RestCallError.new(req,resp,msg)
      end
    end
  end
end
