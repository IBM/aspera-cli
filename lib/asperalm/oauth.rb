#!/bin/echo this is a ruby class:
#
# OAuth 2.0 simple authentication
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/browser_interaction'
require 'asperalm/rest'
require "base64"
require 'date'
require 'rubygems'

# for future use
UNUSED_STATE='ABC'

module Asperalm
  class Oauth
    def self.auth_types
      [ :basic, :web, :jwt ]
    end

    def initialize(baseurl,organization,client_id,client_secret,auth_data)
      @rest=Rest.new(baseurl)
      @organization=organization
      @client_id=client_id
      @client_secret=client_secret
      # key = scope value, e.g. user:all, or node.*
      # subkeys = :data (token value ruby structure), :expiration
      @accesskey_cache={}
      @auth_data=auth_data
      Log.log.debug "auth=#{auth_data}"
    end

    # set token data
    # extract validity date from token value
    def set_token_data(api_scope,token_json)
      @accesskey_cache[api_scope]={}
      token_hash=JSON.parse(token_json)
      @accesskey_cache[api_scope][:data] = token_hash
      decoded_token_info = self.class.decode_access_token(@accesskey_cache[api_scope][:data]['access_token'])
      Log.log.info "decoded_token_info=#{PP.pp(decoded_token_info,'').chomp}"
      @accesskey_cache[api_scope][:expiration]=DateTime.parse(decoded_token_info['expires_at'])
      Log.log.info "token expires at #{@accesskey_cache[api_scope][:expiration]}"
    end

    def save_set_token_data(api_scope,token_json,token_state_file)
      Log.log.info "token_json=#{token_json}"
      File.write(token_state_file,token_json)
      set_token_data(api_scope,token_json)
      Log.log.info "new token is #{@accesskey_cache[api_scope][:data]['access_token']}"
      set_token_data(api_scope,token_json)
    end

    # decode data inside token
    def self.decode_access_token(token)
      return JSON.parse(Zlib::Inflate.inflate(Base64.decode64(token)).partition('==SIGNATURE==').first)
    end

    def get_authorization(api_scope)
      # file name for cache of token
      token_state_file=['token',@auth_data[:type],@organization,@client_id,api_scope].join('.')

      # if first time, try to read from file
      if ! @accesskey_cache.has_key?(api_scope) then
        if File.exist?(token_state_file) then
          Log.log.info "reading token from file cache: #{token_state_file}"
          set_token_data(api_scope,File.read(token_state_file))
        end
      end

      # check if access token is in cache and not expired, if expired: empty cache and try to refresh
      # note: we could also try to use then current token, and , if expired: get a new one
      if @accesskey_cache.has_key?(api_scope) then
        Log.log.info "date=#{PP.pp(@accesskey_cache[api_scope][:expiration],'').chomp}"
        remaining_minutes=((@accesskey_cache[api_scope][:expiration]-DateTime.now)*24*60).round
        Log.log.info "minutes remain=#{remaining_minutes}"
        # TODO: enhance expiration policy ?
        is_expired = remaining_minutes < 10
        if is_expired  then
          if @accesskey_cache[api_scope][:data].has_key?('refresh_token') then
            Log.log.info "token expired"
            # try to refresh
            # note: admin token has no refresh, and lives by default 1800secs
            refresh_token = @accesskey_cache[api_scope][:data]['refresh_token']
            @accesskey_cache.delete(api_scope)
            #Note: we keep the file cache, as refresh_token may be valid
            Log.log.info "refresh=[#{refresh_token}]".bg_green()
            # Note: scope is mandatory in Files, and we can either provide basic auth, or client_Secret in data
            resp=@rest.call({
              :operation=>'POST',
              :subpath=>"oauth2/#{@organization}/token",
              :headers=>{'Accept'=>'application/json'},
              :basic_auth => {:user=>@client_id,:password=>@client_secret}, # this is RFC
              :www_body_params=>{
              :grant_type=>'refresh_token',
              :refresh_token=>refresh_token,
              :scope=>api_scope,
              :client_id=>@client_id,
              #:client_secret=>@client_secret,  # also works, but not compliant to RFC
              :state=>UNUSED_STATE # TODO: remove, not useful
              }})
            save_set_token_data(api_scope,resp[:http].body,token_state_file)
          else
            Log.log.info "token expired, no refresh token, deleting cache and cache file".bg_red()
            @accesskey_cache.delete(api_scope)
            begin
              File.unlink(token_state_file)
            rescue => e
              Log.log.info "error: #{e}"
            end
          end # has refresh
        end # is expired
      end # has cache

      # no cache , or expired, or no refresh
      if !@accesskey_cache.has_key?(api_scope) then
        resp=nil
        case @auth_data[:type]
        when :basic
          # basic password auth, works only for some users
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>"oauth2/#{@organization}/token",
            :headers=>{'Accept'=>'application/json'},
            :www_body_params=>{
            :client_id=>@client_id, # NOTE: not compliant to RFC
            :grant_type=>'password',
            :scope=>api_scope,
            :username=>@auth_data[:username],
            :password=>@auth_data[:password]
            }})
        when :web
          thelogin=@rest.get_uri({
            :operation=>'GET',
            :subpath=>"oauth2/#{@organization}/authorize",
            :url_params=>{
            :response_type=>'code',
            :client_id=>@client_id,
            :redirect_uri=>@auth_data[:bi].redirect_uri,
            :scope=>api_scope,
            :client_secret=>@client_secret,
            :state=>UNUSED_STATE
            }})

          # here, we need a human to authorize on a web page
          code=@auth_data[:bi].goto_page_and_get_code(thelogin)

          # exchange code for token
          resp=@rest.call({
            :operation=>'POST',
            :subpath=>"oauth2/#{@organization}/token",
            :headers=>{'Accept'=>'application/json'},
            :basic_auth => {:user=>@client_id,:password=>@client_secret},
            :www_body_params=>{
            :grant_type=>'authorization_code',
            :code=>code,
            :scope=>api_scope,
            :redirect_uri=>@auth_data[:bi].redirect_uri,
            :client_id=>@client_id,
            :state=>UNUSED_STATE
            }})
        when :jwt
          require 'jwt'

          seconds_since_epoch=Time.new.to_i
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            :iss => @client_id,
            :sub => @auth_data[:subject],
            :aud => "https://api.asperafiles.com/api/v1/oauth2/token",
            :nbf => seconds_since_epoch,
            :exp => seconds_since_epoch+3600 # TODO: configurable ?
          }

          rsa_private =@auth_data[:private_key]
          #rsa_public = rsa_private.public_key

          Log.log.debug("private=[#{rsa_private}]")
          #Log.log.debug("public=[#{rsa_public}]")

          assertion = JWT.encode payload, rsa_private, 'RS256'

          Log.log.debug("assertion=[#{assertion}]")

          resp=@rest.call({
            :operation=>'POST',
            :subpath=>"oauth2/#{@organization}/token",
            :headers=>{'Accept'=>'application/json'},
            :basic_auth => {:user=>@client_id,:password=>@client_secret},
            :www_body_params=>{
            :assertion=>assertion,
            :grant_type=>'urn:ietf:params:oauth:grant-type:jwt-bearer',
            :scope=>api_scope
            }})
        else
          raise "type unknown: #{@auth_data[:type]}"
        end
        if ! resp[:http].code.start_with?('2') then
          error_data=JSON.parse(resp[:http].body)
          if error_data.has_key?('error') then
            raise "API returned: #{error_data['error']}: #{error_data['error_description']}"
          end
          raise "API returned: #{error_data['code']}: #{error_data['message']}"
        end
        save_set_token_data(api_scope,resp[:http].body,token_state_file)
      end

      # ok we shall have a token here
      return 'Bearer '+@accesskey_cache[api_scope][:data]['access_token']
    end

  end
end # Asperalm
