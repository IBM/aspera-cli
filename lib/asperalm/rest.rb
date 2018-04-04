#!/bin/echo this is a ruby class:
#
# REST call helper
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/log'
require 'net/http'
require 'net/https'
require 'json'

# add cancel method to http
class Net::HTTP::Cancel < Net::HTTPRequest
  METHOD = 'CANCEL'
  REQUEST_HAS_BODY  = false
  RESPONSE_HAS_BODY = false
end

#class Net::HTTP::Delete < Net::HTTPRequest
#  METHOD = 'DELETE'
#  REQUEST_HAS_BODY  = false
#  RESPONSE_HAS_BODY = false
#end

module Asperalm
  # builds a meaningful error message from known formats
  class RestCallError < StandardError
    attr_accessor :response
    def initialize(response)
      # default error message is response type
      message=response.message+" (#{response.code})"
      # see if there is a more precise message
      if !response.body.nil?
        data=JSON.parse(response.body) rescue nil
        if data.is_a?(Hash)
          # we have a payload
          if data['error'].is_a?(Hash)
            if data['error']["user_message"].is_a?(String)
              message=data['error']["user_message"]
            elsif data['error']["description"].is_a?(String)
              message=data['error']["description"]
            end
          elsif data['error'].is_a?(String)
            message=data['error']
          end
          if data['error_description'].is_a?(String)
            message=message+": "+data['error_description']
          end
        end
      end
      super(message)
      Log.log.debug "Error code:#{response.code}, msg=#{response.message.red}, body=[#{response.body}]"
      @response = response
    end
  end

  # a simple class to make HTTP calls
  class Rest
    # set to true enables debug in HTTP class
    @@debug=false
    @@insecure=false
    def self.insecure=(v); @@insecure=v;end

    def self.insecure; @@insecure;end

    # opt_call_data can contain default call data , as in "call"
    def initialize(baseurl,opt_call_data=nil)
      # base url without trailing slashes
      @api_base=baseurl.gsub(/\/+$/,'')
      @opt_call_data=opt_call_data
      @http_session=nil
    end

    # create and start keep alive connection on demand
    def http_session
      if @http_session.nil?
        uri=get_uri({:subpath=>''})
        @http_session=Net::HTTP.new(uri.host, uri.port)
        @http_session.use_ssl = uri.scheme == 'https'
        @http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE if @@insecure
        @http_session.set_debug_output($stdout) if @@debug
        # manually start session for keep alive (if supported by server, else, session is closed every time)
        @http_session.start
      end
      return @http_session
    end

    def base_url;@api_base;end

    def param_default; @opt_call_data; end

    def self.set_debug(flag)
      Log.log.debug "debug http=#{flag}"
      @@debug=flag
    end

    # build URI from URL and parameters
    def get_uri(call_data)
      uri=URI.parse(@api_base+"/"+call_data[:subpath])
      if ! ['http','https'].include?(uri.scheme)
        raise "REST endpoint shall be http(s)"
      end
      if call_data.has_key?(:url_params) and !call_data[:url_params].nil? then
        uri.query=URI.encode_www_form(call_data[:url_params])
      end
      return uri
    end

    # HTTPS call
    # call_data has keys:
    # :auth, :operation, :subpath, :headers, :json_params, :url_params, :www_body_params, :text_body_params, :save_to_file (filepath), :return_error (bool)
    # :auth  = {:type=>:basic,:username,:password}
    # :auth  = {:type=>:oauth2,:obj,:scope}
    # :auth  = {:type=>:url,:url_creds}
    def call(call_data)
      raise "call parameters are required" if !call_data.is_a?(Hash)
      Log.log.debug "accessing #{call_data[:subpath]}".red.bold.bg_green
      call_data[:headers]={} if !call_data.has_key?(:headers)
      if !@opt_call_data.nil? then
        call_data.merge!(@opt_call_data) { |key, v1, v2| next v1.merge(v2) if v1.is_a?(Hash) and v2.is_a?(Hash); v1 }
      end
      # OAuth requires generation of token
      if !call_data[:headers].has_key?('Authorization') and call_data.has_key?(:auth) and call_data[:auth].has_key?(:obj) then
        call_data[:headers]['Authorization']=call_data[:auth][:obj].get_authorization(call_data[:auth][:scope])
      end
      # Url auth
      if call_data.has_key?(:auth) and call_data[:auth].has_key?(:url_creds) then
        call_data[:url_params]={} if call_data[:url_params].nil?
        call_data[:auth][:url_creds].each do |key, value|
          call_data[:url_params][key]=value
        end
      end
      uri=get_uri(call_data)
      Log.log.debug "URI=#{uri}"
      case call_data[:operation]
      when 'GET'; req = Net::HTTP::Get.new(uri.request_uri)
      when 'POST'; req = Net::HTTP::Post.new(uri.request_uri)
      when 'PUT'; req = Net::HTTP::Put.new(uri.request_uri)
      when 'CANCEL'; req = Net::HTTP::Cancel.new(uri.request_uri)
      when 'DELETE'; req = Net::HTTP::Delete.new(uri.request_uri)
      else raise "unknown op : #{operation}"
      end
      if call_data.has_key?(:json_params) and !call_data[:json_params].nil? then
        req.body=JSON.generate(call_data[:json_params])
        Log.log.debug "body JSON data=#{call_data[:json_params]}"
        req['Content-Type'] = 'application/json'
        call_data[:headers]['Accept']='application/json'
      end
      if call_data.has_key?(:www_body_params) then
        req.body=URI.encode_www_form(call_data[:www_body_params])
        Log.log.debug "body www data=#{req.body.chomp}"
        req['Content-Type'] = 'application/x-www-form-urlencoded'
      end
      if call_data.has_key?(:text_body_params) then
        req.body=call_data[:text_body_params]
        Log.log.debug "body data=#{req.body.chomp}"
      end
      # set headers
      if call_data.has_key?(:headers) then
        call_data[:headers].keys.each do |key|
          req[key] = call_data[:headers][key]
        end
      end
      # basic auth
      if call_data.has_key?(:auth) and call_data[:auth][:type].eql?(:basic) then
        req.basic_auth(call_data[:auth][:username],call_data[:auth][:password])
        Log.log.debug "using Basic auth"
      end

      result={:http=>nil}
      begin
        # we try the call, and will retry only if oauth, as we can, first with refresh, and then re-auth if refresh is bad
        oauth_tries ||= 2
        Log.log.debug "send request"
        http_session.request(req) do |response|
          result[:http] = response
          if call_data.has_key?(:save_to_file)
            require 'ruby-progressbar'
            progress=ProgressBar.create(
            :format     => '%a %B %p%% %r KB/sec %e',
            :rate_scale => lambda{|rate|rate/1024},
            :title      => 'progress',
            :total      => result[:http]['Content-Length'].to_i)
            Log.log.debug "before write file"
            File.open(call_data[:save_to_file], "wb") do |file|
              result[:http].read_body do |fragment|
                file.write(fragment)
                progress.progress+=fragment.length
              end
            end
            progress=nil
          end
        end

        Log.log.debug "result: code=#{result[:http].code}"
        raise RestCallError.new(result[:http]) if !result[:http].code.start_with?('2')
        if call_data.has_key?(:headers) and
        call_data[:headers].has_key?('Accept') and
        call_data[:headers]['Accept'].eql?('application/json') then
          Log.log.debug "result: body=#{result[:http].body}"
          result[:data]=JSON.parse(result[:http].body) if !result[:http].body.nil?
        end
      rescue RestCallError => e
        # give a second try if oauth token expired
        if ['401'].include?(result[:http].code.to_s) and
        call_data.has_key?(:auth) and
        call_data[:auth][:type].eql?(:oauth2)
          # try a refresh and/or regeneration of token
          begin
            req['Authorization']=call_data[:auth][:obj].get_authorization(call_data[:auth][:scope],true)
          rescue RestCallError => e
            Log.log.error("refresh failed".bg_red)
            req['Authorization']=call_data[:auth][:obj].get_authorization(call_data[:auth][:scope])
          end
          Log.log.debug "using new token=#{call_data[:headers]['Authorization']}"
          retry unless (oauth_tries -= 1).zero?
        end # if
        raise e unless call_data[:return_error]
      end
      Log.log.debug "result=#{result}" # .pretty_inspect
      return result

    end

    #
    # CRUD methods here
    #

    def create(subpath,params)
      return call({:operation=>'POST',:subpath=>subpath,:headers=>{'Accept'=>'application/json'},:json_params=>params})
    end

    def read(subpath,args=nil)
      return call({:operation=>'GET',:subpath=>subpath,:headers=>{'Accept'=>'application/json'},:url_params=>args})
    end

    def update(subpath,params)
      return call({:operation=>'PUT',:subpath=>subpath,:headers=>{'Accept'=>'application/json'},:json_params=>params})
    end

    def delete(subpath)
      return call({:operation=>'DELETE',:subpath=>subpath,:headers=>{'Accept'=>'application/json'}})
    end

    def cancel(subpath)
      return call({:operation=>'CANCEL',:subpath=>subpath,:headers=>{'Accept'=>'application/json'}})
    end
  end
end #module Asperalm
