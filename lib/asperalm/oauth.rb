#!/bin/echo this is a ruby class:
#
# OAuth 2.0 simple authentication
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/operating_system'
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
    # get location of cache for token
    def token_filepath(parts)
      basename=parts.dup.unshift(TOKEN_FILE_PREFIX).join(TOKEN_FILE_SEPARATOR)
      # remove windows forbidden chars
      basename.gsub!(WINDOWS_PROTECTED_CHAR,TOKEN_FILE_SEPARATOR)
      # keep dot for extension only (nicer)
      basename.gsub!('.',TOKEN_FILE_SEPARATOR)
      File.join(@auth_data[:persist_folder],basename+TOKEN_FILE_SUFFIX)
    end

    # delete cached tokens
    def self.flush_tokens
      tokenfiles=Dir[File.join(Main.tool.config_folder,TOKEN_FILE_PREFIX+'*')]
      tokenfiles.each do |filepath|
        File.delete(filepath)
      end
      return tokenfiles
    end

    def self.auth_types
      [ :basic, :web, :jwt ]
    end

    # base_url comes from FilesApi.baseurl
    def initialize(baseurl,organization,auth_data)
      Log.log.debug "auth=#{auth_data}"
      @rest=Rest.new(baseurl)
      @organization=organization
      @auth_data=auth_data
      @auth_data[:persist_folder]='.' if !auth_data.has_key?(:persist_folder)
      # key = scope value, e.g. user:all, or node.*
      # subkeys = :data (token value ruby structure), :expiration
      @token_cache={}
    end

    # set token data
    # extract validity date from token value
    def set_token_data(api_scope,token_json)
      @token_cache[api_scope]={:data => JSON.parse(token_json)}
      decoded_token_info = self.class.decode_access_token(@token_cache[api_scope][:data]['access_token'])
      Log.log.info "decoded_token_info=#{PP.pp(decoded_token_info,'').chomp}"
      @token_cache[api_scope][:expiration]=DateTime.parse(decoded_token_info['expires_at'])
      Log.log.info "token expires at #{@token_cache[api_scope][:expiration]}"
    end

    def save_set_token_data(api_scope,token_json,token_state_file)
      Log.log.info "token_json=#{token_json}"
      File.write(token_state_file,token_json)
      set_token_data(api_scope,token_json)
      Log.log.info "new token is #{@token_cache[api_scope][:data]['access_token']}"
    end

    # decode data inside token
    def self.decode_access_token(token)
      return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition('==SIGNATURE==').first)
    end

    def get_authorization(api_scope,force_regenerate=false)
      # file name for cache of token
      token_state_file=token_filepath([@auth_data[:type],@organization,@auth_data[:client_id],api_scope])

      if force_regenerate
        File.delete(token_state_file) if File.exist?(token_state_file)
        @token_cache.delete(api_scope)
        # force refresh if present
        @token_cache[api_scope][:expiration]=DateTime.now if @token_cache.has_key?(api_scope)
      end

      # if first time, try to read from file
      if ! @token_cache.has_key?(api_scope) then
        if File.exist?(token_state_file) then
          Log.log.info "reading token from file cache: #{token_state_file}"
          set_token_data(api_scope,File.read(token_state_file))
        end
      end

      # check if access token is in cache and not expired, if expired: empty cache and try to refresh
      # note: we could also try to use then current token, and , if expired: get a new one
      if @token_cache.has_key?(api_scope) then
        Log.log.info "expiration date=#{PP.pp(@token_cache[api_scope][:expiration],'').chomp}"
        remaining_minutes=((@token_cache[api_scope][:expiration]-DateTime.now)*24*60).round
        Log.log.info "minutes remain=#{remaining_minutes}"
        # TODO: enhance expiration policy ?
        # Token expiration date is probably only informational, do not rely on it
        is_expired = remaining_minutes < 10
        if is_expired  then
          if @token_cache[api_scope][:data].has_key?('refresh_token') then
            Log.log.info "token expired"
            # try to refresh
            # note: admin token has no refresh, and lives by default 1800secs
            refresh_token = @token_cache[api_scope][:data]['refresh_token']
            @token_cache.delete(api_scope)
            #Note: we keep the file cache, as refresh_token may be valid
            Log.log.info "refresh=[#{refresh_token}]".bg_green()
            # Note: scope is mandatory in Files, and we can either provide basic auth, or client_Secret in data
            resp=@rest.call({
              :operation=>'POST',
              :subpath=>"oauth2/#{@organization}/token",
              :headers=>{'Accept'=>'application/json'},
              :auth=>{:type=>:basic,:user=>@auth_data[:client_id],:password=>@auth_data[:client_secret]}, # this is RFC
              :www_body_params=>{
              :grant_type=>'refresh_token',
              :refresh_token=>refresh_token,
              :scope=>api_scope,
              :client_id=>@auth_data[:client_id],
              #:client_secret=>@auth_data[:client_secret],  # also works, but not compliant to RFC
              :state=>UNUSED_STATE # TODO: remove, not useful
              }})
            # TODO: save only if success ?
            save_set_token_data(api_scope,resp[:http].body,token_state_file)
          else
            Log.log.info "token expired, no refresh token, deleting cache and cache file".bg_red()
            @token_cache.delete(api_scope)
            begin
              File.unlink(token_state_file)
            rescue => e
              Log.log.info "error: #{e}"
            end
          end # has refresh
        end # is expired
      end # has cache

      # no cache , or expired, or no refresh
      if !@token_cache.has_key?(api_scope) then
        resp=nil
        case @auth_data[:type]
        when :basic
          # basic password auth, works only for some users in aspera files, deprecated
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>"oauth2/#{@organization}/token",
            :headers=>{'Accept'=>'application/json'},
            :www_body_params=>{
            :client_id=>@auth_data[:client_id], # NOTE: not compliant to RFC
            :grant_type=>'password',
            :scope=>api_scope,
            :username=>@auth_data[:username],
            :password=>@auth_data[:password]
            }})
        when :web
          check_code=SecureRandom.uuid
          thelogin=@rest.get_uri({
            :operation=>'GET',
            :subpath=>"oauth2/#{@organization}/authorize",
            :url_params=>{
            :response_type=>'code',
            :client_id=>@auth_data[:client_id],
            :redirect_uri=>@auth_data[:redirect_uri],
            :scope=>api_scope,
            :client_secret=>@auth_data[:client_secret],
            :state=>check_code
            }})

          # here, we need a human to authorize on a web page
          code=goto_page_and_get_code(thelogin,check_code)

          # exchange code for token
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>"oauth2/#{@organization}/token",
            :headers=>{'Accept'=>'application/json'},
            :auth=>{:type=>:basic,:user=>@auth_data[:client_id],:password=>@auth_data[:client_secret]},
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
          seconds_since_epoch=Time.new.to_i-300
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            :iss => @auth_data[:client_id],
            :sub => @auth_data[:subject],
            :aud => @rest.base_url+"/oauth2/token",
            :nbf => seconds_since_epoch,
            :exp => seconds_since_epoch+3600 # TODO: configurable ?
          }

          rsa_private =@auth_data[:private_key]  # rsa_private.public_key

          Log.log.debug("private=[#{rsa_private}]")

          assertion = JWT.encode(payload, rsa_private, 'RS256')

          Log.log.debug("assertion=[#{assertion}]")

          resp=@rest.call({
            :operation=>'POST',
            :subpath=>"oauth2/#{@organization}/token",
            :headers=>{'Accept'=>'application/json'},
            :auth=>{:type=>:basic,:user=>@auth_data[:client_id],:password=>@auth_data[:client_secret]},
            :www_body_params=>{
            :assertion=>assertion,
            :grant_type=>'urn:ietf:params:oauth:grant-type:jwt-bearer',
            :scope=>api_scope
            }})
        else
          raise "type unknown: #{@auth_data[:type]}"
        end

        # Check result
        if ! resp[:http].code.start_with?('2') then
          error_data=JSON.parse(resp[:http].body)
          if error_data.has_key?('error') then
            raise "API returned: #{error_data['error']}: #{error_data['error_description']}"
          end
          raise "API returned: #{error_data['code']}: #{error_data['message']}"
        end
        save_set_token_data(api_scope,resp[:http].body,token_state_file)
      end # if !incache

      # ok we shall have a token here
      return 'Bearer '+@token_cache[api_scope][:data]['access_token']
    end

    # open the login page, wait for code and check_code, then return code
    def goto_page_and_get_code(thelogin,check_code)
      code=nil
      Log.log.info "thelogin=#{thelogin}".bg_red().gray()
      # browser start is not blocking
      OperatingSystem.open_uri(thelogin)
      port=URI.parse(@auth_data[:redirect_uri]).port
      Log.log.info "listening on port #{port}"
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
        datah=data.to_h
        Log.log.debug "datah=#{PP.pp(datah,'').chomp}"
        Log.log.error("state does not match") if !check_code.eql?(datah['state'])
        code=datah['code']
        websession.print "HTTP/1.1 200/OK\r\nContent-type:text/html\r\n\r\n<html><body><h1>received answer (code)</h1><code>#{code}</code></body></html>"
        websession.close
      }
      return code
    end

  end # OAuth
end # Asperalm
