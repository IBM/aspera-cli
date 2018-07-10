#
# REST call helper
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'net/http'
require 'net/https'
require 'json'
require 'asperalm/log'

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
  # builds a meaningful error message from known formats in Aspera products
  class RestCallError < StandardError
    attr_accessor :response
    # @param http response
    def initialize(response)
      # default error message is response type
      message=response.message+" (#{response.code})"
      # see if there is a more precise message
      # Hum, we would need some consistency here...
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
          # TODO: data['code'] and data['message'] ?
          if data['error_description'].is_a?(String)
            message=message+": "+data['error_description']
          end
          if data['message'].is_a?(String)
            message=message+": "+data['message']
            data.delete('message')
            data.each do |k,v|
              message=message+"\n#{k}: #{v}"
            end
          end
          if data['errors'].is_a?(Hash)
            data['errors'].each do |k,v|
              message=message+"\n#{k}: #{v}"
            end
          end
        end
      end
      super(message)
      Log.log.debug "Error code:#{response.code}, msg=#{response.message.red}, body=[#{response.body}]"
      @response = response
    end
  end

  # a simple class to make HTTP calls, equivalent to rest-client
  class Rest

    private
    # create and start keep alive connection on demand
    def http_session
      if @http_session.nil?
        uri=self.class.build_uri(@params[:base_url])
        # this honors http_proxy env var
        @http_session=Net::HTTP.new(uri.host, uri.port)
        @http_session.use_ssl = uri.scheme == 'https'
        Log.log.debug("insecure=#{@@insecure}")
        @http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE if @@insecure
        @http_session.set_debug_output($stdout) if @@debug
        # manually start session for keep alive (if supported by server, else, session is closed every time)
        @http_session.start
      end
      return @http_session
    end

    # set to true enables debug in HTTP class
    @@debug=false
    @@insecure=false

    public

    def self.insecure=(v); Log.log.debug("insecure => #{@@insecure}".red);@@insecure=v;end

    def self.insecure; @@insecure;end

    def self.debug=(flag); Log.log.debug "debug http=#{flag}"; @@debug=flag; end

    attr_reader :params

    # @param a_rest_params authentication and default call parameters
    # :auth_type (:basic, :oauth2, :url)
    # :basic_username   [:basic]
    # :basic_password   [:basic]
    # :auth_url_creds   [:url]
    # :oauth_*          [:oauth2]
    def initialize(a_rest_params)
      raise "ERROR: expecting Hash" unless a_rest_params.is_a?(Hash)
      raise "ERROR: expecting base_url" unless a_rest_params[:base_url].is_a?(String)
      @params=a_rest_params.clone
      # base url without trailing slashes
      @params[:base_url].gsub!(/\/+$/,'')
      @http_session=nil
      if @params[:auth_type].eql?(:oauth2)
        @oauth=Oauth.new(@params)
      end
      Log.log.debug("Rest.new #{@params}")
    end

    def oauth_token(api_scope=nil,use_refresh_token=false)
      raise "ERROR" unless @oauth.is_a?(Oauth)
      return @oauth.get_authorization(api_scope,use_refresh_token)
    end

    # build URI from URL and parameters and check it is http or https
    def self.build_uri(url,params=nil)
      uri=URI.parse(url)
      raise "REST endpoint shall be http(s)" unless ['http','https'].include?(uri.scheme)
      uri.query=URI.encode_www_form(params) unless params.nil?
      return uri
    end

    # HTTP/S REST call
    # call_data has keys:
    # :operation
    # :subpath
    # :headers
    # :json_params
    # :url_params
    # :www_body_params
    # :text_body_params
    # :save_to_file (filepath)
    # :return_error (bool)
    def call(call_data)
      raise "Hash call parameter is required (#{call_data.class})" unless call_data.is_a?(Hash)
      Log.log.debug "accessing #{call_data[:subpath]}".red.bold.bg_green
      call_data[:headers]||={}
      call_data.merge!(@params) { |key, v1, v2| next v1.merge(v2) if v1.is_a?(Hash) and v2.is_a?(Hash); v1 }
      # :auth_type = :oauth2 requires generation of token
      if call_data[:auth_type].eql?(:oauth2) and !call_data[:headers].has_key?('Authorization') then
        call_data[:headers]['Authorization']=oauth_token
      end
      # :auth_type = :url
      if call_data[:auth_type].eql?(:url) then
        call_data[:url_params]||={}
        call_data[:auth_url_creds].each do |key, value|
          call_data[:url_params][key]=value
        end
      end
      uri=self.class.build_uri("#{@params[:base_url]}/#{call_data[:subpath]}",call_data[:url_params])
      Log.log.debug "URI=#{uri}"
      begin
        # instanciate request object based on string name
        req=Object::const_get('Net::HTTP::'+call_data[:operation].capitalize).new(uri.request_uri)
      rescue NameError => e
        raise "unknown op : #{call_data[:operation]}"
      end
      if call_data.has_key?(:json_params) and !call_data[:json_params].nil? then
        req.body=JSON.generate(call_data[:json_params])
        Log.log.debug "body JSON data=#{call_data[:json_params]}"
        req['Content-Type'] = 'application/json'
        #call_data[:headers]['Accept']='application/json'
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
      # :auth_type = :basic
      if call_data[:auth_type].eql?(:basic) then
        req.basic_auth(call_data[:basic_username],call_data[:basic_password])
        Log.log.debug "using Basic auth"
      end

      Log.log.debug "call_data = #{call_data}"
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
        raise RestCallError.new(result[:http]) unless result[:http].code.start_with?('2')
        if call_data.has_key?(:headers) and
        call_data[:headers].has_key?('Accept') and
        call_data[:headers]['Accept'].eql?('application/json') then
          Log.log.debug "result: body=#{result[:http].body}"
          result[:data]=JSON.parse(result[:http].body) if !result[:http].body.nil?
        end
      rescue RestCallError => e
        # not authorized: oauth token expired
        if ['401'].include?(result[:http].code.to_s) and call_data[:auth_type].eql?(:oauth2)
          begin
            # try to use refresh token
            req['Authorization']=oauth_token(nil,true)
          rescue RestCallError => e
            Log.log.error("refresh failed".bg_red)
            # regenerate a brand new token
            req['Authorization']=oauth_token()
          end
          Log.log.debug "using new token=#{call_data[:headers]['Authorization']}"
          retry unless (oauth_tries -= 1).zero?
        end # if
        # raise exception if could not retry and not return error in result
        raise e unless call_data[:return_error]
      end
      Log.log.debug "result=#{result}"
      return result

    end

    #
    # CRUD methods here
    #

    # @param encoding : one of: :json_params, :url_params
    def create(subpath,params,encoding=:json_params)
      return call({:operation=>'POST',:subpath=>subpath,:headers=>{'Accept'=>'application/json'},encoding=>params})
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
