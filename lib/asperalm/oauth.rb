require 'asperalm/open_application'
require 'base64'
require 'date'
require 'socket'
require 'securerandom'

module Asperalm
  # implement OAuth 2 for the REST client and generate a bearer token
  # call get_authorization() to get a token.
  # bearer tokens are kept in memory and also in a file cache for later re-use
  # if a token is expired (api returns 4xx), call again get_authorization({:refresh=>true})
  class Oauth
    private
    # remove 5 minutes to account for time offset (TODO: configurable?)
    JWT_NOTBEFORE_OFFSET=300
    # one hour validity (TODO: configurable?)
    JWT_EXPIRY_OFFSET=3600
    private_constant :JWT_NOTBEFORE_OFFSET,:JWT_EXPIRY_OFFSET
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
    # :scope (optional)
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
      if @params.has_key?(:redirect_uri)
        uri=URI.parse(@params[:redirect_uri])
        raise "redirect_uri scheme must be http" unless uri.scheme.start_with?('http')
        raise "redirect_uri must have a port" if uri.port.nil?
        # we could check that host is localhost or local address
      end
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

    # @return String  a unique identifier of token
    def token_cache_id(api_scope)
      oauth_uri=URI.parse(@params[:base_url])
      parts=[oauth_uri.host.downcase.gsub(/[^a-z]+/,'_'),oauth_uri.path.downcase.gsub(/[^a-z]+/,'_'),@params[:grant]]
      parts.push(api_scope) unless api_scope.nil?
      parts.push(@params[:jwt_subject]) if @params.has_key?(:jwt_subject)
      parts.push(@params[:user_name]) if @params.has_key?(:user_name)
      parts.push(@params[:url_token]) if @params.has_key?(:url_token)
      parts.push(@params[:api_key]) if @params.has_key?(:api_key)
      return OauthCache.ids_to_id(parts)
    end

    public

    # @param options : :scope and :refresh
    def get_authorization(options={})
      # api scope can be overriden to get auth for other scope
      api_scope=options[:scope] || @params[:scope]
      # as it is optional in many place: create struct
      p_scope={}
      p_scope[:scope] = api_scope unless api_scope.nil?
      p_client_id_and_scope=p_scope.clone
      p_client_id_and_scope[:client_id] = @params[:client_id] if @params.has_key?(:client_id)
      use_refresh_token=options[:refresh]

      # generate token identifier to use with cache
      token_id=token_cache_id(api_scope)

      # get from cache (or nil)
      cached_token_data=OauthCache.instance.get(token_id)

      # Optional optimization: check if node token is expired, then force refresh
      # else, anyway, faspmanager is equipped with refresh code
      if !cached_token_data.nil?
        decoded_node_token = Node.decode_bearer_token(cached_token_data['access_token']) rescue nil
        Log.dump('decoded_node_token',decoded_node_token)
        if decoded_node_token.is_a?(Hash) and decoded_node_token['expires_at'].is_a?(String)
          expires_at=DateTime.parse(decoded_node_token['expires_at'])
          # refresh if less than one hour
          use_refresh_token=true if DateTime.now > (expires_at-Rational(3600,86400))
        end
      end

      # an API was already called, but failed, we need to regenerate or refresh
      if use_refresh_token
        if cached_token_data.is_a?(Hash) and cached_token_data.has_key?('refresh_token')
          # save possible refresh token, before deleting the cache
          refresh_token=cached_token_data['refresh_token']
        end
        # delete caches
        OauthCache.instance.discard(token_id)
        cached_token_data=nil
        # lets try the existing refresh token
        if !refresh_token.nil?
          Log.log.info("refresh=[#{refresh_token}]".bg_green)
          # try to refresh
          # note: admin token has no refresh, and lives by default 1800secs
          # Note: scope is mandatory in Files, and we can either provide basic auth, or client_Secret in data
          resp=create_token_simple(p_client_id_and_scope.merge({
            :grant_type   =>'refresh_token',
            :refresh_token=>refresh_token}))
          if resp[:http].code.start_with?('2') then
            # save only if success ?
            cached_token_data=JSON.parse(resp[:http].body)
            OauthCache.instance.save(token_id,cached_token_data)
          else
            Log.log.debug("refresh failed: #{resp[:http].body}".bg_red)
          end
        end
      end

      # no cache
      if cached_token_data.nil? then
        resp=nil
        case @params[:grant]
        when :web
          check_code=SecureRandom.uuid
          login_page_url=Rest.build_uri(
          "#{@params[:base_url]}/#{@params[:path_authorize]}",
          p_client_id_and_scope.merge({
            :response_type => 'code',
            :redirect_uri  => @params[:redirect_uri],
            :client_secret => @params[:client_secret],
            :state         => check_code
          }))

          # here, we need a human to authorize on a web page
          code=goto_page_and_get_code(login_page_url,check_code)

          # exchange code for token
          resp=create_token_simple(p_client_id_and_scope.merge({
            :grant_type   => 'authorization_code',
            :code         => code,
            :redirect_uri => @params[:redirect_uri]
          }))
        when :jwt
          # https://tools.ietf.org/html/rfc7519
          # https://tools.ietf.org/html/rfc7523
          require 'jwt'
          seconds_since_epoch=Time.new.to_i
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            :iss => @params[:client_id],    # issuer
            :sub => @params[:jwt_subject],  # subject
            :aud => @params[:jwt_audience], # audience
            :nbf => seconds_since_epoch-JWT_NOTBEFORE_OFFSET, # not before
            :exp => seconds_since_epoch+JWT_EXPIRY_OFFSET # expiration
          }

          # non standard, only for global ids
          payload.merge!(@params[:jwt_add]) if @params.has_key?(:jwt_add)

          rsa_private=@params[:jwt_private_key_obj]  # type: OpenSSL::PKey::RSA

          Log.log.debug("private=[#{rsa_private}]")

          Log.log.debug("JWT assertion=[#{payload}]")
          assertion = JWT.encode(payload, rsa_private, 'RS256')

          Log.log.debug("assertion=[#{assertion}]")

          resp=create_token_simple(p_scope.merge({
            :grant_type => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            :assertion  => assertion
          }))
        when :url_token
          # exchange url_token for bearer token
          resp=create_token_advanced({
            :json_params => {:url_token=>@params[:url_token]},
            :url_params  => p_scope.merge({
            :grant_type    => 'url_token'
            })})
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
            :json_params => p_client_id_and_scope.merge({:grant_type => 'password'}), #:www_body_params also works
          })
        when :body_userpass
          # legacy, not used
          resp=create_token_simple(p_client_id_and_scope.merge({
            :grant_type => 'password',
            :username   => @params[:user_name],
            :password   => @params[:user_pass]
          }))
          when :body_data
          # used in Faspex apiv5
          resp=create_token_advanced({
            :auth        => {:type => :none},
            :json_params => @params[:userpass_body],
          })
        else
          raise "auth grant type unknown: #{@params[:grant]}"
        end
        # TODO: test return code ?
        cached_token_data=JSON.parse(resp[:http].body)
        OauthCache.instance.save(token_id,cached_token_data)
      end # if ! in_cache

      # ok we shall have a token here
      return 'Bearer '+cached_token_data[@params[:token_field]]
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
