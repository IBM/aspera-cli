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

    # handlers should probably be defined by plugins
    ERROR_HANDLERS=[]

    def self.add_handler(err_type,&block)
      ERROR_HANDLERS.push(block)
    end
    add_handler("Type 1") do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      k='user_message'
      msg_stack.push(d_error[k]) if d_error.is_a?(Hash) and d_error[k].is_a?(String)
    end
    add_handler("Type 2") do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      k='description'
      msg_stack.push(d_error[k]) if d_error.is_a?(Hash) and d_error[k].is_a?(String)
    end
    add_handler("Type 3") do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      k='internal_message'
      msg_stack.push(d_error[k]) if d_error.is_a?(Hash) and d_error[k].is_a?(String)
    end
    add_handler("Type 4") do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      msg_stack.push(d_error) if d_error.is_a?(String)
    end
    add_handler("Type 5") do |msg_stack,json_response,req,resp|
      # Type 2
      # TODO: json_response['code'] and json_response['message'] ?
      msg_stack.push(json_response['error_description']) if json_response['error_description'].is_a?(String)
    end
    add_handler("Type 6") do |msg_stack,json_response,req,resp|
      # Type 3
      if json_response['message'].is_a?(String)
        msg_stack.push(json_response['message'])
        # add other fields as info
        json_response.each do |k,v|
          msg_stack.push("#{k}: #{v}") unless k.eql?('message')
        end
      end
    end
    add_handler("Type 7") do |msg_stack,json_response,req,resp|
      if json_response['errors'].is_a?(Hash)
        json_response['errors'].each do |k,v|
          msg_stack.push("#{k}: #{v}")
        end
      end
    end
    # call to upload_setup and download_setup of node api
    add_handler("Type 8") do |msg_stack,json_response,req,resp|
      d_t_s=json_response['transfer_specs']
      if d_t_s.is_a?(Array)
        d_t_s.each do |res|
          r_err=res['transfer_spec']['error']
          if r_err.is_a?(Hash)
            msg_stack.push("#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}")
          end
        end
      end
    end

    # called by the Rest object on any result
    def self.raiseOnError(req,resp)
      # get error messages if any
      msg_stack=[]
      begin
        json_response=JSON.parse(resp.body)
        # handlers called only if valid JSON found
        ERROR_HANDLERS.each do |handler|
          handler.call(msg_stack,json_response,req,resp)
        end
      rescue
        nil
      end
      unless resp.code.start_with?('2') and msg_stack.empty?
        msg_stack.push(resp.message) if msg_stack.empty?
        raise RestCallError.new(req,resp,msg_stack.join("\n"))
      end
    end
  end
end
