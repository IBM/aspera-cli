#!/bin/echo this is a ruby class:
#
# REST call helper
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'net/http'
require 'net/https'
require 'logger'
require 'json'
require 'asperalm/colors'

module Asperalm
  # a simple class to make HTTP calls
  class Rest
    @@debug=false
    def initialize(logger,baseurl,opt_call_data=nil)
      @logger=logger
      @api_base=baseurl.gsub(/\/+$/,'')
      @opt_call_data=opt_call_data
    end

    def self.set_debug(flag,logger)
      logger.debug "debug http=#{flag}" if !logger.nil?
      @@debug=flag
    end

    def get_uri(call_data)
      uri=URI.parse(@api_base+"/"+call_data[:subpath])
      if call_data.has_key?(:url_params) and !call_data[:url_params].nil? then
        uri.query=URI.encode_www_form(call_data[:url_params])
      end
      return uri
    end

    # basic HTTP call
    # call_data has keys:
    # :subpath, :headers, :oauth, :scope, :operation, :json_params, :www_body_params, :basic_auth
    def call(call_data)
      @logger.debug "accessing #{call_data[:subpath]}".red.bold.bg_green
      if !call_data.has_key?(:headers) then
        call_data[:headers]={}
      end
      if !@opt_call_data.nil? then
        call_data.merge!(@opt_call_data) { |key, v1, v2| next v1.merge(v2) if v1.is_a?(Hash) and v2.is_a?(Hash); v1 }
      end
      #if (! call_data[:headers].has_key?('Content-Type')) then
      #  call_data[:headers]['Content-Type']='application/json'
      #end
      if !call_data[:headers].has_key?('Authorization') and call_data.has_key?(:oauth) then
        call_data[:headers]['Authorization']=call_data[:oauth].get_authorization(call_data[:scope])
      end
      uri=get_uri(call_data)
      #@logger.debug "URI=#{PP.pp(uri,'').chomp}"
      @logger.debug "URI=#{uri}"
      #@logger.debug "calldata=#{call_data}"
      http=Net::HTTP.new(uri.host, uri.port)
      if @@debug then
        http.set_debug_output($stdout)
      end
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      case call_data[:operation]
      when 'GET'
        req = Net::HTTP::Get.new(uri.request_uri)
      when 'POST'
        req = Net::HTTP::Post.new(uri.request_uri)
      when 'PUT'
        req = Net::HTTP::Put.new(uri.request_uri)
      else
        raise "unknown op : #{operation}"
      end
      if call_data.has_key?(:json_params) then
        req.body=JSON.generate(call_data[:json_params])
        #@logger.debug "body JSON data=#{PP.pp(call_data[:json_params],'').chomp}"
        @logger.debug "body JSON data=#{call_data[:json_params]}"
        req['Content-Type'] = 'application/json'
        call_data[:headers]['Accept']='application/json'
      end
      if call_data.has_key?(:www_body_params) then
        req.body=URI.encode_www_form(call_data[:www_body_params])
        @logger.debug "body www data=#{req.body.chomp}"
        req['Content-Type'] = 'application/x-www-form-urlencoded'
      end
      if call_data.has_key?(:headers) then
        call_data[:headers].keys.each do |key|
          req[key] = call_data[:headers][key]
        end
      end
      if call_data.has_key?(:basic_auth) then
        req.basic_auth(call_data[:basic_auth][:user],call_data[:basic_auth][:password])
        @logger.debug "using Basic auth"
      end
      resp = http.request(req)

      @logger.debug "result code=#{resp.code}"
      @logger.debug "result body=#{resp.body}"

      if ! resp.code.start_with?('2') then
        raise "Error code "+resp.code+", body=["+resp.body+"]"
      end
      result={:http=>resp}
      if !call_data.nil? and call_data.has_key?(:headers) and call_data[:headers].has_key?('Accept') and call_data[:headers]['Accept'].eql?('application/json') then
        result[:data]=JSON.parse(resp.body) if !resp.body.nil?
      end
      @logger.debug "result=#{result}" # .pretty_inspect
      return result
    end

    def list(resource_type,args=nil)
      return call({:operation=>'GET',:subpath=>resource_type,:url_params=>args,:headers=>{'Accept'=>'application/json'}})
    end

    def create(resource_type,params)
      return call({:operation=>'POST',:subpath=>resource_type,:json_params=>params,:headers=>{'Accept'=>'application/json'}})
    end

    def read(resource_type,resource_id=nil)
      subpath=resource_type
      if !resource_id.nil? then
        subpath=subpath+'/'+resource_id
      end
      return call({:operation=>'GET',:subpath=>subpath,:headers=>{'Accept'=>'application/json'}})
    end

    def update(resource_type,resource_id,params)
      return call({:operation=>'PUT',:subpath=>resource_type+'/'+resource_id,:json_params=>params,:headers=>{'Accept'=>'application/json'}})
    end

    def delete(resource_type,resource_id)
      return call({:operation=>'DELETE',:subpath=>resource_type+'/'+resource_id,:headers=>{'Accept'=>'application/json'}})
    end
  end
end #module Asperalm
