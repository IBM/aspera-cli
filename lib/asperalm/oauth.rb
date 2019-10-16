require 'asperalm/open_application'

#require 'asperalm/rest'
require 'base64'
require 'date'
require 'socket'
require 'securerandom'

# for future use
UNUSED_STATE='ABC'

module Asperalm
  # implement OAuth 2 for the REST client and generate a bearer token
  # call get_authorization() to get a token.
  # bearer tokens are kept in memory and also in a file cache for later re-use
  # if a token is expired (api returns 4xx), call again get_authorization({:refresh=>true})
  class Oauth
    private
    # definition of token cache filename
    TOKEN_FILE_PREFIX='token'
    TOKEN_FILE_SEPARATOR='_'
    TOKEN_FILE_SUFFIX='.txt'
    NO_SCOPE='noscope'
    WINDOWS_PROTECTED_CHAR=%r{[/:"<>\\\*\?]}
    JWT_NOTBEFORE_OFFSET=300
    JWT_EXPIRY_OFFSET=3600
    @@token_cache_folder='.'
    private_constant :TOKEN_FILE_PREFIX,:TOKEN_FILE_SEPARATOR,:TOKEN_FILE_SUFFIX,:NO_SCOPE,:WINDOWS_PROTECTED_CHAR,:JWT_NOTBEFORE_OFFSET,:JWT_EXPIRY_OFFSET
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
      [ :body_userpass, :header_userpass, :web, :jwt, :url_token, :ibm_apikey ]
    end

    # for supported parameters, look in the code for @params
    # parameters are provided all with oauth_ prefix :
    # :base_url
    # :client_id
    # :client_secret
    # :redirect_uri
    # :jwt_audience
    # :jwt_private_key_obj
    # :jwt_subject
    # :path_authorize (default: 'authorize')
    # :path_token (default: 'token')
    # :scope
    # :grant (one of returned by self.auth_types)
    # :url_token
    # :user_name
    # :user_pass
    # :token_type
    def initialize(auth_params)
      Log.log.debug "auth=#{auth_params}"
      @params=auth_params.clone
      # default values
      # name of field to take as token from result of call to /token
      @params[:token_field]||='access_token'
      # default endpoint for /token
      @params[:path_token]||='token'
      # default endpoint for /authorize
      @params[:path_authorize]||='authorize'
      rest_params={:base_url => @params[:base_url]}
      if @params.has_key?(:client_id)
        rest_params.merge!({:auth     => {
          :type     => :basic,
          :username => @params[:client_id],
          :password => @params[:client_secret]
          }})
      end
      @token_auth_api=Rest.new(rest_params)
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

    # get location of cache for token, using some unique filename
    def token_filepath(api_scope)
      oauth_uri=URI.parse(@params[:base_url])
      parts=[oauth_uri.host.downcase.gsub(/[^a-z]+/,'_'),oauth_uri.path.downcase.gsub(/[^a-z]+/,'_'),@params[:grant],api_scope]
      parts.push(api_scope) if !api_scope.nil?
      parts.push(@params[:user_name]) if @params.has_key?(:user_name)
      parts.push(@params[:url_token]) if @params.has_key?(:url_token)
      parts.push(@params[:api_key]) if @params.has_key?(:api_key)
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

    def create_token_advanced(rest_params)
      return @token_auth_api.call({
        :operation => 'POST',
        :subpath   => @params[:path_token],
        :headers   => {'Accept'=>'application/json'}}.merge(rest_params))
    end

    # shortcut for create_token_advanced
    def create_token_simple(creation_params)
      return create_token_advanced({:www_body_params=>creation_params})
    end

    public

    # @param options : :scope and :refresh
    def get_authorization(options={})
      api_scope=options[:scope] || @params[:scope] || NO_SCOPE
      use_refresh_token=options[:refresh]
      # file name for cache of token
      token_state_file=token_filepath(api_scope)
      client_id_and_scope={}
      client_id_and_scope[:client_id] = @params[:client_id] if @params.has_key?(:client_id)
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
          resp=create_token_simple(client_id_and_scope.merge({
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
        case @params[:grant]
        when :web
          check_code=SecureRandom.uuid
          login_page_url=Rest.build_uri(
          "#{@params[:base_url]}/#{@params[:path_authorize]}",
          client_id_and_scope.merge({
            :response_type => 'code',
            :redirect_uri  => @params[:redirect_uri],
            :client_secret => @params[:client_secret],
            :state         => check_code
          }))

          # here, we need a human to authorize on a web page
          code=goto_page_and_get_code(login_page_url,check_code)

          # exchange code for token
          resp=create_token_simple(client_id_and_scope.merge({
            :grant_type   => 'authorization_code',
            :code         => code,
            :redirect_uri => @params[:redirect_uri],
            :state        => UNUSED_STATE
          }))
        when :jwt
          # https://tools.ietf.org/html/rfc7519
          require 'jwt'
          # remove 5 minutes to account for time offset
          seconds_since_epoch=Time.new.to_i-JWT_NOTBEFORE_OFFSET
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            :iss => @params[:client_id],    # issuer
            :sub => @params[:jwt_subject],  # subject
            :aud => @params[:jwt_audience], # audience
            :nbf => seconds_since_epoch,
            :exp => seconds_since_epoch+JWT_EXPIRY_OFFSET # TODO: configurable ?
          }

          # non standard, only for global ids
          payload.merge!(@params[:jwt_add]) if @params.has_key?(:jwt_add)

          rsa_private=@params[:jwt_private_key_obj]  # type: OpenSSL::PKey::RSA

          Log.log.debug("private=[#{rsa_private}]")

          Log.log.debug("JWT assertion=[#{payload}]")
          assertion = JWT.encode(payload, rsa_private, 'RS256')

          Log.log.debug("assertion=[#{assertion}]")

          resp=create_token_simple({
            :grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            :assertion  => assertion,
            :scope      => api_scope
          })
        when :url_token
          # exchange url_token for bearer token
          resp=create_token_advanced({
            :json_params => {:url_token=>@params[:url_token]},
            :url_params  => {
            :grant_type    => 'url_token',
            :scope         => api_scope,
            :state         => UNUSED_STATE
            }})
        when :ibm_apikey
          resp=create_token_simple({
            'grant_type'    => 'urn:ibm:params:oauth:grant-type:apikey',
            'response_type' => 'cloud_iam',
            'apikey'        => @params[:api_key]
          })
        when :delegated_refresh
          resp=create_token_simple({
            'grant_type'          => 'urn:ibm:params:oauth:grant-type:apikey',
            'response_type'       => 'delegated_refresh_token',
            'apikey'              => @params[:api_key],
            'receiver_client_ids' => 'aspera_ats'
          })
        when :header_userpass
          # used in Faspex apiv4 and shares2
          resp=create_token_advanced({
            :auth        => {
            :type          => :basic,
            :username      => @params[:user_name],
            :password      => @params[:user_pass]},
            :json_params => client_id_and_scope.merge({:grant_type => 'password'}), #:www_body_params also works
          })
        when :body_userpass
          # legacy, not used
          resp=create_token_simple(client_id_and_scope.merge({
            :grant_type => 'password',
            :username   => @params[:user_name],
            :password   => @params[:user_pass]
          }))
        else
          raise "auth grant type unknown: #{@params[:grant]}"
        end

        save_and_set_token_cache(api_scope,resp[:http].body,token_state_file)
      end # if ! in_cache

      # ok we shall have a token here
      return 'Bearer '+@token_cache[api_scope][@params[:token_field]]
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
