#!/bin/echo this is a ruby class:
#
# OAuth 2.0 simple authentication
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/open_application'
require 'asperalm/rest'
require 'asperalm/files_api'
require 'base64'
require 'date'
require 'rubygems'
require 'socket'
require 'pp'
require 'securerandom'

# for future use
UNUSED_STATE='ABC'

module Asperalm
  # implement OAuth 2 for Aspera Files
  # bearer tokens are kept in memory and also in a file cache for re-use
  class Oauth
    TOKEN_FILE_PREFIX='token'
    TOKEN_FILE_SEPARATOR='_'
    TOKEN_FILE_SUFFIX='.txt'
    WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    OFFSET_ALLOWANCE_SEC=300
    ASSERTION_VALIDITY_SEC=3600
    # delete cached tokens
    def self.flush_tokens(persist_folder)
      tokenfiles=Dir[File.join(persist_folder,TOKEN_FILE_PREFIX+'*'+TOKEN_FILE_SUFFIX)]
      tokenfiles.each do |filepath|
        File.delete(filepath)
      end
      return tokenfiles
    end

    def self.auth_types
      [ :basic, :web, :jwt, :url_token ]
    end

    # base_url comes from FilesApi.baseurl
    def initialize(auth_data)
      Log.log.debug "auth=#{auth_data}"
      @auth_data=auth_data
      @rest=Rest.new(@auth_data[:baseurl])
      @auth_data[:persist_folder]='.' if !auth_data.has_key?(:persist_folder)
      # key = scope value, e.g. user:all, or node.*
      # value = ruby structure of data of returned value
      @token_cache={}
    end

    # save token data in memory cache
    # returns recoded token data
    def set_token_cache(api_scope,token_json)
      @token_cache[api_scope]=JSON.parse(token_json)
      # for debug only, expiration info is not accurate
      begin
        decoded_token_info = JSON.parse(Zlib::Inflate.inflate(Base64.decode64(@token_cache[api_scope]['access_token'])).partition('==SIGNATURE==').first)
        Log.log.info "decoded_token_info=#{PP.pp(decoded_token_info,'').chomp}"
        return decoded_token_info
      rescue
        return nil
      end
    end

    # save token data in memory and disk cache
    def save_and_set_token_cache(api_scope,token_json,token_state_file)
      Log.log.info "token_json=#{token_json}"
      File.write(token_state_file,token_json)
      set_token_cache(api_scope,token_json)
      Log.log.info "new saved token is #{@token_cache[api_scope]['access_token']}"
    end

    # get location of cache for token
    def token_filepath(api_scope)
      parts=[@auth_data[:client_id],URI.parse(@auth_data[:baseurl]).host.downcase.gsub(/[^a-z]+/,'_'),@auth_data[:type],api_scope]
      parts.push(@auth_data[:username]) if @auth_data.has_key?(:username)
      basename=parts.dup.unshift(TOKEN_FILE_PREFIX).join(TOKEN_FILE_SEPARATOR)
      # remove windows forbidden chars
      basename.gsub!(WINDOWS_PROTECTED_CHAR,TOKEN_FILE_SEPARATOR)
      # keep dot for extension only (nicer)
      basename.gsub!('.',TOKEN_FILE_SEPARATOR)
      File.join(@auth_data[:persist_folder],basename+TOKEN_FILE_SUFFIX)
    end

    # use_refresh_token set to true if auth was just used and failed
    def get_authorization(api_scope,use_refresh_token=false)
      # file name for cache of token
      token_state_file=token_filepath(api_scope)

      # if first time, try to read from file
      if ! @token_cache.has_key?(api_scope) then
        if File.exist?(token_state_file) then
          Log.log.info "reading token from file cache: #{token_state_file}"
          # returns decoded data
          set_token_cache(api_scope,File.read(token_state_file))
          # TODO: check if node token is expired, then force refresh, mandatory as there is no API call, and ascp will complain
        end
      end

      # an api was already called, but failed, we need to regenerate or refresh
      if use_refresh_token
        if @token_cache[api_scope].is_a?(Hash) and @token_cache[api_scope].has_key?('refresh_token')
          # save possible refresh token, before deleting the cache
          refresh_token=@token_cache[api_scope]['refresh_token']
        end
        # delete caches
        Log.log.info "deleting cache file and memory for token"
        File.delete(token_state_file) if File.exist?(token_state_file)
        @token_cache.delete(api_scope)
        # this token failed, but it has a refresh token
        if !refresh_token.nil?
          Log.log.info "refresh=[#{refresh_token}]".bg_green()
          # try to refresh
          # note: admin token has no refresh, and lives by default 1800secs
          # Note: scope is mandatory in Files, and we can either provide basic auth, or client_Secret in data
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>@auth_data[:token_path],
            :headers=>{'Accept'=>'application/json'},
            :auth=>{:type=>:basic,:username=>@auth_data[:client_id],:password=>@auth_data[:client_secret]}, # this is RFC
            :www_body_params=>{
            :grant_type=>'refresh_token',
            :refresh_token=>refresh_token,
            :scope=>api_scope,
            :client_id=>@auth_data[:client_id],
            #:client_secret=>@auth_data[:client_secret],  # also works, but not compliant to RFC
            :state=>UNUSED_STATE # TODO: remove, not useful
            }})
          if resp[:http].code.start_with?('2') then
            # save only if success ?
            save_and_set_token_cache(api_scope,resp[:http].body,token_state_file)
          else
            Log.log.debug "refresh failed: #{resp[:http].body}".bg_red()
          end
        end
      end

      # no cache
      if !@token_cache.has_key?(api_scope) then
        resp=nil
        case @auth_data[:type]
        when :basic
          call_data={
            :operation=>'POST',
            :subpath=>@auth_data[:token_path],
            :headers=>{'Accept'=>'application/json'},
            :www_body_params=>{
            :client_id=>@auth_data[:client_id], # NOTE: not compliant to RFC
            :grant_type=>'password',
            :scope=>api_scope
            }}
          case @auth_data[:basic_type]
          when :header
            call_data[:auth]={:type=>:basic}
            call_data[:auth][:username]=@auth_data[:username]
            call_data[:auth][:password]=@auth_data[:password]
          else
            call_data[:www_body_params][:username]=@auth_data[:username]
            call_data[:www_body_params][:password]=@auth_data[:password]
          end
          # basic password auth, works only for some users in aspera files, deprecated
          resp=@rest.call(call_data)
        when :web
          check_code=SecureRandom.uuid
          login_page_url=@rest.get_uri({
            :operation=>'GET',
            :subpath=>@auth_data[:authorize_path],
            :url_params=>{
            :response_type=>'code',
            :client_id=>@auth_data[:client_id],
            :redirect_uri=>@auth_data[:redirect_uri],
            :scope=>api_scope,
            :client_secret=>@auth_data[:client_secret],
            :state=>check_code
            }})

          # here, we need a human to authorize on a web page
          code=goto_page_and_get_code(login_page_url,check_code)

          # exchange code for token
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>@auth_data[:token_path],
            :headers=>{'Accept'=>'application/json'},
            :auth=>{:type=>:basic,:username=>@auth_data[:client_id],:password=>@auth_data[:client_secret]},
            :www_body_params=>{
            :grant_type=>'authorization_code',
            :code=>code,
            :scope=>api_scope,
            :redirect_uri=>@auth_data[:redirect_uri],
            :client_id=>@auth_data[:client_id],
            :state=>UNUSED_STATE
            }})
        when :jwt
          require 'jwt'
          # remove 5 minutes to account for time offset
          seconds_since_epoch=Time.new.to_i-OFFSET_ALLOWANCE_SEC
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            :iss => @auth_data[:client_id],
            :sub => @auth_data[:username],
            :aud => @auth_data[:audience],
            :nbf => seconds_since_epoch,
            :exp => seconds_since_epoch+ASSERTION_VALIDITY_SEC # TODO: configurable ?
          }

          rsa_private=@auth_data[:private_key_obj]  # rsa_private.public_key

          Log.log.debug("private=[#{rsa_private}]")

          assertion = JWT.encode(payload, rsa_private, 'RS256')

          Log.log.debug("assertion=[#{assertion}]")

          resp=@rest.call({
            :operation=>'POST',
            :subpath=>@auth_data[:token_path],
            :headers=>{'Accept'=>'application/json'},
            :auth=>{:type=>:basic,:username=>@auth_data[:client_id],:password=>@auth_data[:client_secret]},
            :www_body_params=>{
            :assertion=>assertion,
            :grant_type=>'urn:ietf:params:oauth:grant-type:jwt-bearer',
            :scope=>api_scope
            }})
        when :url_token
          # exchange code for token
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>@auth_data[:token_path],
            :headers=>{'Accept'=>'application/json'},
            :auth=>{:type=>:basic,:username=>@auth_data[:client_id],:password=>@auth_data[:client_secret]},
            :url_params=>{
            :grant_type=>'url_token',
            :scope=>api_scope,
            :state=>UNUSED_STATE
            },
            :json_params=>{:url_token=>@auth_data[:url_token]}})
        else
          raise "auth type unknown: #{@auth_data[:type]}"
        end

        # Check result
        if ! resp[:http].code.start_with?('2') then
          error_data=JSON.parse(resp[:http].body)
          if error_data.has_key?('error') then
            raise "API returned: #{error_data['error']}: #{error_data['error_description']}"
          end
          raise "API returned: #{error_data['code']}: #{error_data['message']}"
        end
        save_and_set_token_cache(api_scope,resp[:http].body,token_state_file)
      end # if !incache

      # ok we shall have a token here
      return 'Bearer '+@token_cache[api_scope]['access_token']
    end

    THANK_YOU_HTML = "<html><head><title>Ok</title></head><body><h1>Thank you !</h1><p>You can close this window.</p></body></html>"

    # open the login page, wait for code and return parameters
    def self.goto_page_and_get_request(redirect_uri,login_page_url,html_page=THANK_YOU_HTML)
      Log.log.info "login_page_url=#{login_page_url}".bg_red().gray()
      # browser start is not blocking
      OpenApplication.instance.uri(login_page_url)
      port=URI.parse(redirect_uri).port
      Log.log.info "listening on port #{port}"
      request_params=nil
      TCPServer.open('127.0.0.1', port) { |webserver|
        Log.log.info "server=#{webserver}"
        websession = webserver.accept
        sleep 1 # TODO: sometimes, returns nil ? use sinatra ?
        line = websession.gets.chomp
        Log.log.info "line=#{line}"
        if ! line.start_with?('GET /?') then
          raise "unexpected request"
        end
        request = line.partition('?').last.partition(' ').first
        data=URI.decode_www_form(request)
        request_params=data.to_h
        Log.log.debug "request_params=#{PP.pp(request_params,'').chomp}"
        websession.print "HTTP/1.1 200/OK\r\nContent-type:text/html\r\n\r\n#{html_page}"
        websession.close
      }
      return request_params
    end

    # open the login page, wait for code and check_code, then return code
    def goto_page_and_get_code(login_page_url,check_code)
      request_params=self.class.goto_page_and_get_request(@auth_data[:redirect_uri],login_page_url)
      Log.log.error("state does not match") if !check_code.eql?(request_params['state'])
      code=request_params['code']
      return code
    end

  end # OAuth
end # Asperalm
