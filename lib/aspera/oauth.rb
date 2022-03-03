require 'aspera/open_application'
require 'aspera/web_auth'
require 'aspera/id_generator'
require 'base64'
require 'date'
require 'socket'
require 'securerandom'

module Aspera
  # Implement OAuth 2 for the REST client and generate a bearer token
  # call get_authorization() to get a token.
  # bearer tokens are kept in memory and also in a file cache for later re-use
  # if a token is expired (api returns 4xx), call again get_authorization({refresh: true})
  class Oauth
    # used for code exchange
    DEFAULT_PATH_AUTHORIZE='authorize'
    # to generate token
    DEFAULT_PATH_TOKEN='token'
    # field with token in result
    DEFAULT_TOKEN_FIELD='access_token'
    private
    # remove 5 minutes to account for time offset (TODO: configurable?)
    JWT_NOTBEFORE_OFFSET_SEC=300
    # one hour validity (TODO: configurable?)
    JWT_EXPIRY_OFFSET_SEC=3600
    # tokens older than 30 minutes will be discarded from cache
    TOKEN_CACHE_EXPIRY_SEC=1800
    # a prefix for persistency of tokens (garbage collect)
    PERSIST_CATEGORY_TOKEN='token'
    ONE_HOUR_AS_DAY_FRACTION=Rational(1,24)

    private_constant :JWT_NOTBEFORE_OFFSET_SEC,:JWT_EXPIRY_OFFSET_SEC,:PERSIST_CATEGORY_TOKEN,:TOKEN_CACHE_EXPIRY_SEC,:ONE_HOUR_AS_DAY_FRACTION
    class << self
      # OAuth methods supported
      def auth_types
        [:body_userpass, :header_userpass, :web, :jwt, :url_token, :ibm_apikey]
      end

      def persist_mgr=(manager)
        @persist=manager
      end

      def persist_mgr
        if @persist.nil?
          Log.log.warn('Not using persistency (use Aspera::Oauth.persist_mgr=Aspera::PersistencyFolder.new)')
          # create NULL persistency class
          @persist=Class.new do
            def get(x);nil;end;def delete(x);nil;end;def put(x,y);nil;end;def garbage_collect(x,y);nil;end
          end.new
        end
        return @persist
      end

      def flush_tokens
        persist_mgr.garbage_collect(PERSIST_CATEGORY_TOKEN,nil)
      end

      def register_decoder(method)
        @decoders||=[]
        @decoders.push(method)
      end

      def decode_token(token)
        Log.log.debug(">>>> #{token} : #{@decoders.length}")
        @decoders.each do |decoder|
          result=decoder.call(token) rescue nil
          return result unless result.nil?
        end
        return nil
      end
    end # self

    # seems to be quite standard token encoding (RFC?)
    register_decoder lambda { |token| parts=token.split('.'); raise 'not aoc token' unless parts.length.eql?(3); JSON.parse(Base64.decode64(parts[1]))}

    # for supported parameters, look in the code for @params
    # parameters are provided all with oauth_ prefix :
    # :base_url
    # :client_id
    # :client_secret
    # :redirect_uri
    # :jwt_audience
    # :jwt_private_key_obj
    # :jwt_subject
    # :path_authorize (default: DEFAULT_PATH_AUTHORIZE)
    # :path_token (default: DEFAULT_PATH_TOKEN)
    # :scope (optional)
    # :grant (one of returned by self.auth_types)
    # :url_token
    # :user_name
    # :user_pass
    # :token_type
    def initialize(auth_params)
      Log.log.debug("auth=#{auth_params}")
      @handlers={}
      @params=auth_params.clone
      # default values
      # name of field to take as token from result of call to /token
      @params[:token_field]||=DEFAULT_TOKEN_FIELD
      # default endpoint for /token
      @params[:path_token]||=DEFAULT_PATH_TOKEN
      # default endpoint for /authorize
      @params[:path_authorize]||=DEFAULT_PATH_AUTHORIZE
      rest_params={base_url: @params[:base_url]}
      if @params.has_key?(:client_id)
        rest_params.merge!({auth: {
          type:     :basic,
          username: @params[:client_id],
          password: @params[:client_secret]
          }})
      end
      @token_auth_api=Rest.new(rest_params)
      if @params.has_key?(:redirect_uri)
        uri=URI.parse(@params[:redirect_uri])
        raise 'redirect_uri scheme must be http' unless uri.scheme.start_with?('http')
        raise 'redirect_uri must have a port' if uri.port.nil?
        # we could check that host is localhost or local address
      end
      # cleanup expired tokens
      self.class.persist_mgr.garbage_collect(PERSIST_CATEGORY_TOKEN,TOKEN_CACHE_EXPIRY_SEC)
    end

    def create_token(rest_params)
      return @token_auth_api.call({
        operation: 'POST',
        subpath:   @params[:path_token],
        headers:   {'Accept'=>'application/json'}}.merge(rest_params))
    end

    # @return unique identifier of token
    def token_cache_id(api_scope)
      oauth_uri=URI.parse(@params[:base_url])
      parts=[PERSIST_CATEGORY_TOKEN,api_scope,oauth_uri.host,oauth_uri.path]
      # add some of the parameters that uniquely define the token
      [:grant,:jwt_subject,:user_name,:url_token,:api_key].inject(parts){|p,i|p.push(@params[i])}
      return IdGenerator.from_list(parts)
    end

    public

    # used to change parameter, such as scope
    attr_reader :params

    # @param options : :scope and :refresh
    def get_authorization(options={})
      # can be overriden later
      use_refresh_token=options[:refresh]
      # api scope can be overriden to get auth for other scope
      api_scope=options[:scope] || @params[:scope]
      # as it is optional in many place: create struct
      p_scope={}
      p_scope[:scope] = api_scope unless api_scope.nil?
      p_client_id_and_scope=p_scope.clone
      p_client_id_and_scope[:client_id] = @params[:client_id] if @params.has_key?(:client_id)

      # generate token identifier to use with cache
      token_id=token_cache_id(api_scope)

      # get token_data from cache (or nil), token_data is what is returned by /token
      token_data=self.class.persist_mgr.get(token_id)
      token_data=JSON.parse(token_data) unless token_data.nil?
      # Optional optimization: check if node token is expired, then force refresh
      # in case the transfer agent cannot refresh himself
      # else, anyway, faspmanager is equipped with refresh code
      if !token_data.nil?
        # TODO: use @params[:token_field] ?
        decoded_node_token = self.class.decode_token(token_data['access_token'])
        Log.dump('decoded_node_token',decoded_node_token) unless decoded_node_token.nil?
        if decoded_node_token.is_a?(Hash) and decoded_node_token['expires_at'].is_a?(String)
          expires_at=DateTime.parse(decoded_node_token['expires_at'])
          # Time.at(decoded_node_token['exp'])
          # does it seem expired, with one hour of security
          use_refresh_token=true if DateTime.now > (expires_at-ONE_HOUR_AS_DAY_FRACTION)
        end
      end

      # an API was already called, but failed, we need to regenerate or refresh
      if use_refresh_token
        if token_data.is_a?(Hash) and token_data.has_key?('refresh_token')
          # save possible refresh token, before deleting the cache
          refresh_token=token_data['refresh_token']
        end
        # delete caches
        self.class.persist_mgr.delete(token_id)
        token_data=nil
        # lets try the existing refresh token
        if !refresh_token.nil?
          Log.log.info("refresh=[#{refresh_token}]".bg_green)
          # try to refresh
          # note: admin token has no refresh, and lives by default 1800secs
          # Note: scope is mandatory in Files, and we can either provide basic auth, or client_Secret in data
          resp=create_token(www_body_params: p_client_id_and_scope.merge({
            grant_type:    'refresh_token',
            refresh_token: refresh_token}))
          if resp[:http].code.start_with?('2')
            # save only if success
            json_data=resp[:http].body
            token_data=JSON.parse(json_data)
            self.class.persist_mgr.put(token_id,json_data)
          else
            Log.log.debug("refresh failed: #{resp[:http].body}".bg_red)
          end
        end
      end

      # no cache
      if token_data.nil?
        resp=nil
        case @params[:grant]
        when :web
          # AoC Web based Auth
          check_code=SecureRandom.uuid
          auth_params=p_client_id_and_scope.merge({
            response_type: 'code',
            redirect_uri:  @params[:redirect_uri],
            state:         check_code
          })
          auth_params[:client_secret]=@params[:client_secret] if @params.has_key?(:client_secret)
          login_page_url=Rest.build_uri("#{@params[:base_url]}/#{@params[:path_authorize]}",auth_params)
          # here, we need a human to authorize on a web page
          Log.log.info("login_page_url=#{login_page_url}".bg_red.gray)
          # start a web server to receive request code
          webserver=WebAuth.new(@params[:redirect_uri])
          # start browser on login page
          OpenApplication.instance.uri(login_page_url)
          # wait for code in request
          request_params=webserver.get_request
          Log.log.error('state does not match') if !check_code.eql?(request_params['state'])
          code=request_params['code']
          # exchange code for token
          resp=create_token(www_body_params: p_client_id_and_scope.merge({
            grant_type:   'authorization_code',
            code:         code,
            redirect_uri: @params[:redirect_uri]
          }))
        when :jwt
          # https://tools.ietf.org/html/rfc7519
          # https://tools.ietf.org/html/rfc7523
          require 'jwt'
          seconds_since_epoch=Time.new.to_i
          Log.log.info("seconds=#{seconds_since_epoch}")

          payload = {
            iss: @params[:client_id],    # issuer
            sub: @params[:jwt_subject],  # subject
            aud: @params[:jwt_audience], # audience
            nbf: seconds_since_epoch-JWT_NOTBEFORE_OFFSET_SEC, # not before
            exp: seconds_since_epoch+JWT_EXPIRY_OFFSET_SEC # expiration
          }
          # Hum.. compliant ? TODO: remove when Faspex5 API is clarified
          if @params.has_key?(:f5_username)
            payload[:jti] = SecureRandom.uuid # JWT id
            payload[:iat] = seconds_since_epoch # issued at
            payload.delete(:nbf) # not used in f5
            p_scope[:redirect_uri]='https://127.0.0.1:5000/token' # used ?
            p_scope[:state]=SecureRandom.uuid
            p_scope[:client_id]=@params[:client_id]
            @token_auth_api.params[:auth]={type: :basic, username: @params[:f5_username], password: @params[:f5_password]}
          end

          # non standard, only for global ids
          payload.merge!(@params[:jwt_add]) if @params.has_key?(:jwt_add)
          Log.log.debug("JWT payload=[#{payload}]")

          rsa_private=@params[:jwt_private_key_obj]  # type: OpenSSL::PKey::RSA
          Log.log.debug("private=[#{rsa_private}]")

          assertion = JWT.encode(payload, rsa_private, 'RS256', @params[:jwt_headers]||{})
          Log.log.debug("assertion=[#{assertion}]")

          resp=create_token(www_body_params: p_scope.merge({
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion:  assertion
          }))
        when :url_token
          # AoC Public Link
          params={url_token: @params[:url_token]}
          params[:password]=@params[:password] if @params.has_key?(:password)
          resp=create_token({
            json_params: params,
            url_params:  p_scope.merge({grant_type: 'url_token'})
          })
        when :ibm_apikey
          # ATS
          resp=create_token(www_body_params: {
            grant_type:    'urn:ibm:params:oauth:grant-type:apikey',
            response_type: 'cloud_iam',
            apikey:        @params[:api_key]
          })
        when :delegated_refresh
          # COS
          resp=create_token(www_body_params: {
            grant_type:          'urn:ibm:params:oauth:grant-type:apikey',
            response_type:       'delegated_refresh_token',
            apikey:              @params[:api_key],
            receiver_client_ids: 'aspera_ats'
          })
        when :header_userpass
          # used in Faspex apiv4 and shares2
          resp=create_token(
          json_params: p_client_id_and_scope.merge({grant_type: 'password'}), #:www_body_params also works
          auth:        {
            type:     :basic,
            username: @params[:user_name],
            password: @params[:user_pass]}
          )
        when :body_userpass
          # legacy, not used
          resp=create_token(www_body_params: p_client_id_and_scope.merge({
            grant_type: 'password',
            username:   @params[:user_name],
            password:   @params[:user_pass]
          }))
        when :body_data
          # used in Faspex apiv5
          resp=create_token({
            auth:        {type: :none},
            json_params: @params[:userpass_body]
          })
        else
          if @handlers.has_key?(@params[:grant])
            resp=@handlers[@params[:grant]].call(@token_auth_api,@params)
          else
            raise "auth grant type unknown: #{@params[:grant]}"
          end
        end
        # TODO: test return code ?
        json_data=resp[:http].body
        token_data=JSON.parse(json_data)
        self.class.persist_mgr.put(token_id,json_data)
      end # if ! in_cache
      raise "API error: No such field in answer: #{@params[:token_field]}" unless token_data.has_key?(@params[:token_field])
      # ok we shall have a token here
      return 'Bearer '+token_data[@params[:token_field]]
    end

    def register_handler(id, method)
      raise 'error' unless id.is_a?(Symbol) and method.is_a?(Proc)
      @handlers[id]=method
    end
  end # OAuth
end # Aspera
