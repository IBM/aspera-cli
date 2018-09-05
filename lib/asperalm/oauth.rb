#!/bin/echo this is a ruby class:
#
# OAuth 2.0 simple authentication
# Aspera 2016
# Laurent Martin
#
##############################################################################
require 'asperalm/open_application'
require 'asperalm/rest'
require 'base64'
require 'date'
require 'socket'
require 'securerandom'

# for future use
UNUSED_STATE='ABC'

module Asperalm
  # implement OAuth 2 for Aspera Files
  # bearer tokens are kept in memory and also in a file cache for re-use
  # used by the RST object
  class Oauth
    private
    TOKEN_FILE_PREFIX='token'
    TOKEN_FILE_SEPARATOR='_'
    TOKEN_FILE_SUFFIX='.txt'
    NO_SCOPE='noscope'
    WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    OFFSET_ALLOWANCE_SEC=300
    ASSERTION_VALIDITY_SEC=3600
    @@token_cache_folder='.'
    def self.persistency_folder; @@token_cache_folder;end

    def self.persistency_folder=(v); @@token_cache_folder=v;end

    # delete cached tokens
    def self.flush_tokens
      tokenfiles=Dir[File.join(@@token_cache_folder,TOKEN_FILE_PREFIX+'*'+TOKEN_FILE_SUFFIX)]
      tokenfiles.each do |filepath|
        File.delete(filepath)
      end
      return tokenfiles
    end

    # OAuth methods supported
    def self.auth_types
      [ :body_userpass, :header_userpass, :web, :jwt, :url_token ]
    end

    # prefix of REST parameters used for oauth
    PARAM_PREFIX='oauth_'

    def initialize(rest_params)
      Log.log.debug "auth=#{rest_params}"
      # just keep keys starting with :oauth_, and remove this prefix
      @params=rest_params.keys.
      map{|k|k.to_s}.
      select{|k|k.start_with?(PARAM_PREFIX)}.
      inject({}){|h,k|h[k[PARAM_PREFIX.length..-1].to_sym]=rest_params[k.to_sym];h}
      @api=Rest.new({
        :base_url       => @params[:base_url],
        :auth_type      => :basic,
        :basic_username => @params[:client_id],
        :basic_password => @params[:client_secret]
      })
      # key = scope value, e.g. user:all, or node.*
      # value = ruby structure of data of returned value
      @token_cache={}
      if @params.has_key?(:redirect_uri)
        uri=URI.parse(@params[:redirect_uri])
        raise "redirect_uri scheme must be http" unless uri.scheme.start_with?('http')
        raise "redirect_uri must have a port" if uri.port.nil?
        # we could check that host is localhost or local address
      end
    end

    # save token data in memory cache
    # returns decoded token data (includes expiration date)
    def set_token_cache(api_scope,token_json)
      @token_cache[api_scope]=JSON.parse(token_json)
      # for debug only, expiration info is not accurate
      begin
        decoded_token_info = JSON.parse(Zlib::Inflate.inflate(Base64.decode64(@token_cache[api_scope]['access_token'])).partition('==SIGNATURE==').first)
        Log.log.dump('decoded_token_info',decoded_token_info)
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
      parts=[@params[:client_id],URI.parse(@params[:base_url]).host.downcase.gsub(/[^a-z]+/,'_'),@params[:type],api_scope]
      parts.push(@params[:user_name]) if @params.has_key?(:user_name)
      basename=parts.dup.unshift(TOKEN_FILE_PREFIX).join(TOKEN_FILE_SEPARATOR)
      # remove windows forbidden chars
      basename.gsub!(WINDOWS_PROTECTED_CHAR,TOKEN_FILE_SEPARATOR)
      # keep dot for extension only (nicer)
      basename.gsub!('.',TOKEN_FILE_SEPARATOR)
      filepath=File.join(@@token_cache_folder,basename+TOKEN_FILE_SUFFIX)
      Log.log.debug("token path=#{filepath}")
      return filepath
    end

    THANK_YOU_HTML = "<html><head><title>Ok</title></head><body><h1>Thank you !</h1><p>You can close this window.</p></body></html>"

    # open the login page, wait for code and check_code, then return code
    def goto_page_and_get_code(login_page_url,check_code)
      request_params=self.class.goto_page_and_get_request(@params[:redirect_uri],login_page_url)
      Log.log.error("state does not match") if !check_code.eql?(request_params['state'])
      code=request_params['code']
      return code
    end

    def create_token(creation_params)
      return @api.create(@params[:path_token],creation_params,:www_body_params)
    end

    public

    # use_refresh_token set to true if auth was just used and failed
    def get_authorization(api_scope=nil,use_refresh_token=false)
      api_scope||=@params[:scope]
      api_scope||=NO_SCOPE
      # file name for cache of token
      token_state_file=token_filepath(api_scope)
      client_id_and_scope={
        :client_id    =>@params[:client_id]
      }
      client_id_and_scope[:scope] = api_scope unless api_scope.eql?(NO_SCOPE)

      # if first time, try to read from file
      if ! @token_cache.has_key?(api_scope) then
        if File.exist?(token_state_file) then
          Log.log.info "reading token from file cache: #{token_state_file}"
          # returns decoded data
          decoded=set_token_cache(api_scope,File.read(token_state_file))
          # check if node token is expired, then force refresh, mandatory as there is no API call, and ascp will complain
          if decoded.is_a?(Hash) and decoded['expires_at'].is_a?(String)
            expires_at=DateTime.parse(decoded['expires_at'])
            use_refresh_token=true if DateTime.now > (expires_at-Rational(3600,86400))
          end
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
          resp=create_token(client_id_and_scope.merge({
            :grant_type   =>'refresh_token',
            :refresh_token=>refresh_token,
            :state        =>UNUSED_STATE})) # TODO: remove, not useful
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
        case @params[:type]
        when :body_userpass
          resp=create_token(client_id_and_scope.merge({
            :grant_type => 'password',
            :username   => @params[:user_name],
            :password   => @params[:user_pass]
          }))
        when :header_userpass
          resp=@api.call({
            :operation       => 'POST',
            :subpath         => @params[:path_token],
            :auth_type       => :basic,
            :basic_username  => @params[:user_name],
            :basic_password  => @params[:user_pass],
            :headers         => {'Accept'=>'application/json'},
            :www_body_params => client_id_and_scope.merge({
            :grant_type => 'password',
            })})
        when :web
          check_code=SecureRandom.uuid
          login_page_url=Rest.build_uri(
          "#{@params[:base_url]}/#{@params[:path_login]}",
          client_id_and_scope.merge({
            :response_type => 'code',
            :redirect_uri  => @params[:redirect_uri],
            :client_secret => @params[:client_secret],
            :state         => check_code
          }))

          # here, we need a human to authorize on a web page
          code=goto_page_and_get_code(login_page_url,check_code)

          # exchange code for token
          resp=create_token(client_id_and_scope.merge({
            :grant_type   => 'authorization_code',
            :code         => code,
            :redirect_uri => @params[:redirect_uri],
            :state        => UNUSED_STATE
          }))
        when :jwt
          require 'jwt'
          # remove 5 minutes to account for time offset
          seconds_since_epoch=Time.new.to_i-OFFSET_ALLOWANCE_SEC
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            :iss => @params[:client_id],
            :sub => @params[:jwt_subject],
            :aud => @params[:jwt_audience],
            :nbf => seconds_since_epoch,
            :exp => seconds_since_epoch+ASSERTION_VALIDITY_SEC # TODO: configurable ?
          }

          rsa_private=@params[:jwt_private_key_obj]  # type: OpenSSL::PKey::RSA

          Log.log.debug("private=[#{rsa_private}]")

          assertion = JWT.encode(payload, rsa_private, 'RS256')

          Log.log.debug("assertion=[#{assertion}]")

          resp=create_token({
            :grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            :assertion  => assertion,
            :scope      => api_scope
          })
        when :url_token
          # exchange url_token for bearer token
          resp=@api.call({
            :operation => 'POST',
            :subpath   => @params[:path_token],
            :headers   => {'Accept'=>'application/json'},
            :url_params=>{
            :grant_type=>'url_token',
            :scope     =>api_scope,
            :state     =>UNUSED_STATE
            },
            :json_params=>{:url_token=>@params[:url_token]}})
        else
          raise "auth type unknown: #{@params[:type]}"
        end

        save_and_set_token_cache(api_scope,resp[:http].body,token_state_file)
      end # if !incache

      # ok we shall have a token here
      return 'Bearer '+@token_cache[api_scope]['access_token']
    end

    # open the login page, wait for code and return parameters
    def self.goto_page_and_get_request(redirect_uri,login_page_url,html_page=THANK_YOU_HTML)
      Log.log.info "login_page_url=#{login_page_url}".bg_red().gray()
      # browser start is not blocking, we hope here that starting is slower than opening port
      OpenApplication.instance.uri(login_page_url)
      port=URI.parse(redirect_uri).port
      Log.log.info "listening on port #{port}"
      request_params=nil
      TCPServer.open('127.0.0.1', port) { |webserver|
        Log.log.info "server=#{webserver}"
        websession = webserver.accept
        sleep 1 # TODO: sometimes: returns nil ? use webrick ?
        line = websession.gets.chomp
        Log.log.info "line=#{line}"
        if ! line.start_with?('GET /?') then
          raise "unexpected request"
        end
        request = line.partition('?').last.partition(' ').first
        data=URI.decode_www_form(request)
        request_params=data.to_h
        Log.log.debug "request_params=#{request_params}"
        websession.print "HTTP/1.1 200/OK\r\nContent-type:text/html\r\n\r\n#{html_page}"
        websession.close
      }
      return request_params
    end

  end # OAuth
end # Asperalm
