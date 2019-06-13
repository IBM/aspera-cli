require 'asperalm/log'
require 'json'
require 'asperalm/fasp/installation'

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

    def self.add_handler(&block)
      ERROR_HANDLERS.push(block)
    end

    def self.add_error(type,msg,msg_stack,json_response,req,resp)
      msg_stack.push(msg)
      exc_log_file=File.join(Fasp::Installation.instance.config_folder,"exceptions.log")
      if File.exist?(exc_log_file)
        File.open(exc_log_file,"a+") do |f|
          f.write("\n=#{type}=====\n#{req.method} #{req.path}\n#{resp.code}\n#{JSON.generate(json_response)}\n#{msg_stack.join("\n")}")
        end
      end
    end
    add_handler do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      k='user_message'
      add_error("Type 1",d_error[k],msg_stack,json_response,req,resp) if d_error.is_a?(Hash) and d_error[k].is_a?(String)
    end
    add_handler do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      k='description'
      add_error("Type 2",d_error[k],msg_stack,json_response,req,resp) if d_error.is_a?(Hash) and d_error[k].is_a?(String)
    end
    add_handler do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      k='internal_message'
      add_error("Type 3",d_error[k],msg_stack,json_response,req,resp) if d_error.is_a?(Hash) and d_error[k].is_a?(String)
    end
    add_handler do |msg_stack,json_response,req,resp|
      d_error=json_response['error']
      add_error("Type 4",d_error,msg_stack,json_response,req,resp) if d_error.is_a?(String)
    end
    add_handler do |msg_stack,json_response,req,resp|
      # Type 2
      # TODO: json_response['code'] and json_response['message'] ?
      add_error("Type 5",json_response['error_description'],msg_stack,json_response,req,resp) if json_response['error_description'].is_a?(String)
    end
    add_handler do |msg_stack,json_response,req,resp|
      # Type 3
      if json_response['message'].is_a?(String)
        add_error("Type 6",json_response['message'],msg_stack,json_response,req,resp)
        # add other fields as info
        json_response.each do |k,v|
          add_error("Type 6","#{k}: #{v}",msg_stack,json_response,req,resp) unless k.eql?('message')
        end
      end
    end
    add_handler do |msg_stack,json_response,req,resp|
      if json_response['errors'].is_a?(Hash)
        json_response['errors'].each do |k,v|
          add_error("Type 7","#{k}: #{v}",msg_stack,json_response,req,resp)
        end
      end
    end
    # call to upload_setup and download_setup of node api
    add_handler do |msg_stack,json_response,req,resp|
      d_t_s=json_response['transfer_specs']
      if d_t_s.is_a?(Array)
        d_t_s.each do |res|
          r_err=res['transfer_spec']['error']
          if r_err.is_a?(Hash)
            add_error("Type 8","#{r_err['code']}: #{r_err['reason']}: #{r_err['user_message']}",msg_stack,json_response,req,resp)
          end
        end
      end
    end

    # called by the Rest object on any result
    def self.raiseOnError(req,resp)
      # get error messages if any in this list
      msg_stack=[]
      json_response=JSON.parse(resp.body) rescue nil
      if json_response.is_a?(Hash)
        # handlers called only if valid JSON found
        ERROR_HANDLERS.each do |handler|
          begin
            handler.call(msg_stack,json_response,req,resp)
          rescue => e
            Log.log.error("handler: #{e}")
          end
        end
      end
      unless resp.code.start_with?('2') and msg_stack.empty?
        add_error("Type 9",resp.message,msg_stack,json_response,req,resp) if msg_stack.empty?
        raise RestCallError.new(req,resp,msg_stack.join("\n"))
      end
    end
  end
end
