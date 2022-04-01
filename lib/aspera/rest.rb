# frozen_string_literal: true

require 'aspera/log'
require 'aspera/oauth'
require 'aspera/rest_error_analyzer'
require 'aspera/hash_ext'
require 'aspera/rest_errors_aspera'
require 'net/http'
require 'net/https'
require 'json'
require 'base64'
require 'cgi'
require 'ruby-progressbar'

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

module Aspera
  # a simple class to make HTTP calls, equivalent to rest-client
  # rest call errors are raised as exception RestCallError
  # and error are analyzed in RestErrorAnalyzer
  class Rest
    # global settings also valid for any subclass
    @@global = { # rubocop:disable Style/ClassVars
      debug:                   false,
      # true if https ignore certificate
      insecure:                false,
      user_agent:              'Ruby',
      download_partial_suffix: '.http_partial',
      # a lambda which takes the Net::HTTP as arg, use this to change parameters
      session_cb:              nil
    }

    class << self
      # define accessors
      @@global.keys.each do |p|
        define_method(p){@@global[p]}
        define_method("#{p}="){|val|Log.log.debug("#{p} => #{val}".red);@@global[p] = val}
      end

      def basic_creds(user,pass); return "Basic #{Base64.strict_encode64("#{user}:#{pass}")}";end

      # build URI from URL and parameters and check it is http or https
      def build_uri(url,params=nil)
        uri = URI.parse(url)
        raise "REST endpoint shall be http/s not #{uri.scheme}" unless ['http','https'].include?(uri.scheme)
        if !params.nil?
          # support array url params, there is no standard. Either p[]=1&p[]=2, or p=1&p=2
          if params.is_a?(Hash)
            orig = params
            params = []
            orig.each do |k,v|
              case v
              when Array
                suffix = v.first.eql?('[]') ? v.shift : ''
                v.each do |e|
                  params.push([k + suffix,e])
                end
              else
                params.push([k,v])
              end
            end
          end
          # CGI.unescape to transform back %5D into []
          uri.query = CGI.unescape(URI.encode_www_form(params))
        end
        return uri
      end
    end

    private

    # create and start keep alive connection on demand
    def http_session
      if @http_session.nil?
        uri = self.class.build_uri(@params[:base_url])
        # this honors http_proxy env var
        @http_session = Net::HTTP.new(uri.host, uri.port)
        @http_session.use_ssl = uri.scheme.eql?('https')
        @http_session.verify_mode = OpenSSL::SSL::VERIFY_NONE if self.class.insecure
        @http_session.set_debug_output($stdout) if self.class.debug
        # set http options in callback, such as timeout and cert. verification
        self.class.session_cb.call(@http_session) unless self.class.session_cb.nil?
        # manually start session for keep alive (if supported by server, else, session is closed every time)
        @http_session.start
      end
      return @http_session
    end

    public

    attr_reader :params

    def oauth
      if @oauth.nil?
        raise 'ERROR: no OAuth defined' unless @params[:auth][:type].eql?(:oauth2)
        @oauth = Oauth.new(@params[:auth])
      end
      return @oauth
    end

    # @param a_rest_params [Hash] default call parameters (merged at call)
    def initialize(a_rest_params)
      raise 'ERROR: expecting Hash' unless a_rest_params.is_a?(Hash)
      raise 'ERROR: expecting base_url' unless a_rest_params[:base_url].is_a?(String)
      @params = a_rest_params.clone
      Log.dump('REST params',@params)
      # base url without trailing slashes (note: string may be frozen)
      @params[:base_url] = @params[:base_url].gsub(/\/+$/,'')
      @http_session = nil
      # default is no auth
      @params[:auth] ||= {type: :none}
      @params[:not_auth_codes] ||= ['401']
      @oauth = nil
      Log.dump('REST params(2)',@params)
    end

    def oauth_token(force_refresh: false)
      raise "ERROR: expecting boolean, have #{force_refresh}" unless [true,false].include?(force_refresh)
      return oauth.get_authorization(use_refresh_token: force_refresh)
    end

    def build_request(call_data)
      # TODO: shall we percent encode subpath (spaces) test with access key delete with space in id
      # URI.escape()
      uri = self.class.build_uri("#{call_data[:base_url]}#{['','/'].include?(call_data[:subpath]) ? '' : '/'}#{call_data[:subpath]}",call_data[:url_params])
      Log.log.debug("URI=#{uri}")
      begin
        # instanciate request object based on string name
        req = Net::HTTP.const_get(call_data[:operation].capitalize).new(uri)
      rescue NameError
        raise "unsupported operation : #{call_data[:operation]}"
      end
      if call_data.has_key?(:json_params) && !call_data[:json_params].nil?
        req.body = JSON.generate(call_data[:json_params])
        Log.dump('body JSON data',call_data[:json_params])
        #Log.log.debug("body JSON data=#{JSON.pretty_generate(call_data[:json_params])}")
        req['Content-Type'] = 'application/json'
        #call_data[:headers]['Accept']='application/json'
      end
      if call_data.has_key?(:www_body_params)
        req.body = URI.encode_www_form(call_data[:www_body_params])
        Log.log.debug("body www data=#{req.body.chomp}")
        req['Content-Type'] = 'application/x-www-form-urlencoded'
      end
      if call_data.has_key?(:text_body_params)
        req.body = call_data[:text_body_params]
        Log.log.debug("body data=#{req.body.chomp}")
      end
      # set headers
      if call_data.has_key?(:headers)
        call_data[:headers].keys.each do |key|
          req[key] = call_data[:headers][key]
        end
      end
      # :type = :basic
      req.basic_auth(call_data[:auth][:username],call_data[:auth][:password]) if call_data[:auth][:type].eql?(:basic)
      return req
    end

    # HTTP/S REST call
    # call_data has keys:
    # :auth
    # :operation
    # :subpath
    # :headers
    # :json_params
    # :url_params
    # :www_body_params
    # :text_body_params
    # :save_to_file (filepath) default: nil
    # :return_error (bool) default: nil
    # :redirect_max (int) default: 0
    # :not_auth_codes (array)
    # ----
    # authentication (:auth) :
    # :type (:none, :basic, :oauth2, :url)
    # :username   [:basic]
    # :password   [:basic]
    # :url_creds  [:url] a hash
    # :*          [:oauth2] see Oauth class
    def call(call_data)
      raise "Hash call parameter is required (#{call_data.class})" unless call_data.is_a?(Hash)
      call_data[:subpath] = '' if call_data[:subpath].nil?
      Log.log.debug("accessing #{call_data[:subpath]}".red.bold.bg_green)
      call_data[:headers] ||= {}
      call_data[:headers]['User-Agent'] ||= self.class.user_agent
      # defaults from @params are overriden by call data
      call_data = @params.deep_merge(call_data)
      case call_data[:auth][:type]
      when :none
        # no auth
      when :basic
        Log.log.debug('using Basic auth')
        # done in build_req
      when :oauth2
        call_data[:headers]['Authorization'] = oauth_token unless call_data[:headers].has_key?('Authorization')
      when :url
        call_data[:url_params] ||= {}
        call_data[:auth][:url_creds].each do |key, value|
          call_data[:url_params][key] = value
        end
      else raise "unsupported auth type: [#{call_data[:auth][:type]}]"
      end
      req = build_request(call_data)
      Log.log.debug("call_data = #{call_data}")
      result = {http: nil}
      # start a block to be able to retry the actual HTTP request
      begin
        # we try the call, and will retry only if oauth, as we can, first with refresh, and then re-auth if refresh is bad
        oauth_tries ||= 2
        tries_remain_redirect ||= call_data[:redirect_max].nil? ? 0 : call_data[:redirect_max].to_i
        Log.log.debug('send request')
        # make http request (pipelined)
        http_session.request(req) do |response|
          result[:http] = response
          if !call_data[:save_to_file].nil? && result[:http].code.to_s.start_with?('2')
            total_size = result[:http]['Content-Length'].to_i
            progress = ProgressBar.create(
            format:     '%a %B %p%% %r KB/sec %e',
            rate_scale: lambda{|rate|rate / 1024},
            title:      'progress',
            total:      total_size)
            Log.log.debug('before write file')
            target_file = call_data[:save_to_file]
            # override user's path to path in header
            if !response['Content-Disposition'].nil? && (m = response['Content-Disposition'].match(/filename="([^"]+)"/))
              target_file = File.join(File.dirname(target_file),m[1])
            end
            # download with temp filename
            target_file_tmp = "#{target_file}#{self.class.download_partial_suffix}"
            Log.log.debug("saving to: #{target_file}")
            File.open(target_file_tmp, 'wb') do |file|
              result[:http].read_body do |fragment|
                file.write(fragment)
                new_process = progress.progress + fragment.length
                new_process = total_size if new_process > total_size
                progress.progress = new_process
              end
            end
            # rename at the end
            File.rename(target_file_tmp, target_file)
            progress = nil
          end # save_to_file
        end
        # sometimes there is a UTF8 char (e.g. (c) )
        result[:http].body.force_encoding('UTF-8') if result[:http].body.is_a?(String)
        Log.log.debug("result: body=#{result[:http].body}")
        result_mime = (result[:http]['Content-Type'] || 'text/plain').split(';').first
        result[:data] = case result_mime
        when 'application/json','application/vnd.api+json'
          JSON.parse(result[:http].body) rescue nil
        else #when 'text/plain'
          result[:http].body
        end
        Log.dump("result: parsed: #{result_mime}",result[:data])
        Log.log.debug("result: code=#{result[:http].code}")
        RestErrorAnalyzer.instance.raise_on_error(req,result)
      rescue RestCallError => e
        # not authorized: oauth token expired
        if call_data[:not_auth_codes].include?(result[:http].code.to_s) && call_data[:auth][:type].eql?(:oauth2)
          begin
            # try to use refresh token
            req['Authorization'] = oauth_token(force_refresh: true)
          rescue RestCallError => e
            Log.log.error('refresh failed'.bg_red)
            # regenerate a brand new token
            req['Authorization'] = oauth_token
          end
          Log.log.debug("using new token=#{call_data[:headers]['Authorization']}")
          retry unless (oauth_tries -= 1).zero?
        end # if oauth
        # moved ?
        raise e unless e.response.is_a?(Net::HTTPRedirection)
        if tries_remain_redirect.positive?
          tries_remain_redirect -= 1
          current_uri = URI.parse(call_data[:base_url])
          new_url=e.response['location']
          new_url="#{current_uri.scheme}:#{new_url}" unless new_url.start_with?('http')
          Log.log.info("URL is moved: #{new_url}")
          redir_uri = URI.parse(new_url)
          call_data[:base_url] = new_url
          call_data[:subpath] = ''
          if current_uri.host.eql?(redir_uri.host) && current_uri.port.eql?(redir_uri.port)
            req = build_request(call_data)
            retry
          else
            # change host
            Log.log.info("Redirect changes host: #{current_uri.host} -> #{redir_uri.host}")
            return self.class.new(call_data).call(call_data)
          end
        else
          raise e unless call_data[:return_error]
        end
        # raise exception if could not retry and not return error in result
        raise e unless call_data[:return_error]
      end # begin request
      Log.log.debug("result=#{result}")
      return result
    end

    #
    # CRUD methods here
    #

    # @param encoding : one of: :json_params, :url_params
    def create(subpath,params,encoding=:json_params)
      return call({operation: 'POST',subpath: subpath,headers: {'Accept' => 'application/json'},encoding => params})
    end

    def read(subpath,args=nil)
      return call({operation: 'GET',subpath: subpath,headers: {'Accept' => 'application/json'},url_params: args})
    end

    def update(subpath,params)
      return call({operation: 'PUT',subpath: subpath,headers: {'Accept' => 'application/json'},json_params: params})
    end

    def delete(subpath)
      return call({operation: 'DELETE',subpath: subpath,headers: {'Accept' => 'application/json'}})
    end

    def cancel(subpath)
      return call({operation: 'CANCEL',subpath: subpath,headers: {'Accept' => 'application/json'}})
    end
  end
end #module Aspera
