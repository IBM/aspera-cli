# frozen_string_literal: true

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
  # https://tools.ietf.org/html/rfc6749
  class Oauth
    DEFAULT_CREATE_PARAMS = {
      path_token:  'token', # default endpoint for /token to generate token
      token_field: 'access_token', # field with token in result of call to path_token
      web:         {path_authorize: 'authorize'} # default endpoint for /authorize, used for code exchange
    }.freeze

    # OAuth methods supported by default
    STD_AUTH_TYPES = %i[web jwt].freeze

    # remove 5 minutes to account for time offset between client and server (TODO: configurable?)
    JWT_ACCEPTED_OFFSET_SEC = 300
    # one hour validity (TODO: configurable?)
    JWT_EXPIRY_OFFSET_SEC = 3600
    # tokens older than 30 minutes will be discarded from cache
    TOKEN_CACHE_EXPIRY_SEC = 1800
    # tokens valid for less than this duration will be regenerated
    TOKEN_EXPIRATION_GUARD_SEC = 120
    # a prefix for persistency of tokens (simplify garbage collect)
    PERSIST_CATEGORY_TOKEN = 'token'

    private_constant :JWT_ACCEPTED_OFFSET_SEC, :JWT_EXPIRY_OFFSET_SEC, :TOKEN_CACHE_EXPIRY_SEC, :PERSIST_CATEGORY_TOKEN, :TOKEN_EXPIRATION_GUARD_SEC

    # persistency manager
    @persist = nil
    # token creation methods
    @create_handlers = {}
    # token unique identifiers from oauth parameters
    @id_handlers = {}

    class << self
      def persist_mgr=(manager)
        @persist = manager
        # cleanup expired tokens
        @persist.garbage_collect(PERSIST_CATEGORY_TOKEN, TOKEN_CACHE_EXPIRY_SEC)
      end

      def persist_mgr
        if @persist.nil?
          Log.log.debug('Not using persistency') # (use Aspera::Oauth.persist_mgr=Aspera::PersistencyFolder.new)
          # create NULL persistency class
          @persist = Class.new do
            def get(_x); nil; end; def delete(_x); nil; end; def put(_x, _y); nil; end; def garbage_collect(_x, _y); nil; end # rubocop:disable Layout/EmptyLineBetweenDefs, Style/Semicolon, Layout/LineLength
          end.new
        end
        return @persist
      end

      # delete all existing tokens
      def flush_tokens
        persist_mgr.garbage_collect(PERSIST_CATEGORY_TOKEN, nil)
      end

      # register a bearer token decoder, mainly to inspect expiry date
      def register_decoder(method)
        @decoders ||= []
        @decoders.push(method)
      end

      # decode token using all registered decoders
      def decode_token(token)
        @decoders.each do |decoder|
          result = decoder.call(token) rescue nil
          return result unless result.nil?
        end
        return nil
      end

      # register a token creation method
      # @param id creation type from field :grant_method in constructor
      # @param lambda_create called to create token
      # @param id_create called to generate unique id for token, for cache
      def register_token_creator(id, lambda_create, id_create)
        raise 'ERROR: requites Symbol and 2 lambdas' unless id.is_a?(Symbol) && lambda_create.is_a?(Proc) && id_create.is_a?(Proc)
        @create_handlers[id] = lambda_create
        @id_handlers[id] = id_create
      end

      # @return one of the registered creators for the given create type
      def token_creator(id)
        raise "token grant method unknown: #{id}/#{id.class}" unless @create_handlers.key?(id)
        @create_handlers[id]
      end

      # list of identifiers found in creation parameters that can be used to uniquely identify the token
      def id_creator(id)
        raise "id creator type unknown: #{id}/#{id.class}" unless @id_handlers.key?(id)
        @id_handlers[id]
      end
    end # self

    # JSON Web Signature (JWS) compact serialization: https://datatracker.ietf.org/doc/html/rfc7515
    register_decoder lambda { |token| parts = token.split('.'); raise 'not aoc token' unless parts.length.eql?(3); JSON.parse(Base64.decode64(parts[1]))} # rubocop:disable Style/Semicolon, Layout/LineLength

    # generic token creation, parameters are provided in :generic
    register_token_creator :generic, lambda { |oauth|
      return oauth.create_token(oauth.specific_parameters)
    }, lambda { |oauth|
      return [
        oauth.specific_parameters[:grant_type]&.split(':')&.last,
        oauth.specific_parameters[:apikey],
        oauth.specific_parameters[:response_type]
      ]
    }

    # Authentication using Web browser
    register_token_creator :web, lambda { |oauth|
      random_state = SecureRandom.uuid # used to check later
      login_page_url = Rest.build_uri(
        "#{oauth.api.params[:base_url]}/#{oauth.specific_parameters[:path_authorize]}",
        oauth.optional_scope_client_id.merge(response_type: 'code', redirect_uri: oauth.specific_parameters[:redirect_uri], state: random_state))
      # here, we need a human to authorize on a web page
      Log.log.info{"login_page_url=#{login_page_url}".bg_red.gray}
      # start a web server to receive request code
      web_server = WebAuth.new(oauth.specific_parameters[:redirect_uri])
      # start browser on login page
      OpenApplication.instance.uri(login_page_url)
      # wait for code in request
      received_params = web_server.received_request
      raise 'wrong received state' unless random_state.eql?(received_params['state'])
      # exchange code for token
      return oauth.create_token(oauth.optional_scope_client_id(add_secret: true).merge(
        grant_type:   'authorization_code',
        code:         received_params['code'],
        redirect_uri: oauth.specific_parameters[:redirect_uri]))
    }, lambda { |_oauth|
      return []
    }

    # Authentication using private key
    register_token_creator :jwt, lambda { |oauth|
      # https://tools.ietf.org/html/rfc7523
      # https://tools.ietf.org/html/rfc7519
      require 'jwt'
      seconds_since_epoch = Time.new.to_i
      Log.log.info{"seconds=#{seconds_since_epoch}"}
      raise 'missing JWT payload' unless oauth.specific_parameters[:payload].is_a?(Hash)
      jwt_payload = {
        exp: seconds_since_epoch + JWT_EXPIRY_OFFSET_SEC, # expiration time
        nbf: seconds_since_epoch - JWT_ACCEPTED_OFFSET_SEC, # not before
        iat: seconds_since_epoch - JWT_ACCEPTED_OFFSET_SEC + 1, # issued at (we tell a little in the past so that server always accepts)
        jti: SecureRandom.uuid # JWT id
      }.merge(oauth.specific_parameters[:payload])
      Log.log.debug{"JWT jwt_payload=[#{jwt_payload}]"}
      rsa_private = oauth.specific_parameters[:private_key_obj] # type: OpenSSL::PKey::RSA
      Log.log.debug{"private=[#{rsa_private}]"}
      assertion = JWT.encode(jwt_payload, rsa_private, 'RS256', oauth.specific_parameters[:headers] || {})
      Log.log.debug{"assertion=[#{assertion}]"}
      return oauth.create_token(oauth.optional_scope_client_id.merge(grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: assertion))
    }, lambda { |oauth|
      return [oauth.specific_parameters.dig(:payload, :sub)]
    }

    attr_reader :generic_parameters, :specific_parameters, :api

    private

    # [M]=mandatory [D]=has default value [0]=accept nil
    # :base_url            [M]  URL of authentication API
    # :auth
    # :grant_method        [M]  :generic, :web, :jwt, custom
    # :client_id           [0]
    # :client_secret       [0]
    # :scope               [0]
    # :path_token          [D]  API end point to create a token
    # :token_field         [D]  field in result that contains the token
    # :jwt:private_key_obj [M] for type :jwt
    # :jwt:payload         [M] for type :jwt
    # :jwt:headers         [0] for type :jwt
    # :web:redirect_uri    [M] for type :web
    # :web:path_authorize  [D] for type :web
    # :generic             [M] for type :generic
    def initialize(a_params)
      Log.log.debug{"auth=#{a_params}"}
      # replace default values
      @generic_parameters = DEFAULT_CREATE_PARAMS.deep_merge(a_params)
      # legacy
      @generic_parameters[:grant_method] ||= @generic_parameters.delete(:crtype) if @generic_parameters.key?(:crtype)
      # check that type is known
      self.class.token_creator(@generic_parameters[:grant_method])
      # specific parameters for the creation type
      @specific_parameters = @generic_parameters[@generic_parameters[:grant_method]]
      if @generic_parameters[:grant_method].eql?(:web) && @specific_parameters.key?(:redirect_uri)
        uri = URI.parse(@specific_parameters[:redirect_uri])
        raise 'redirect_uri scheme must be http or https' unless %w[http https].include?(uri.scheme)
        raise 'redirect_uri must have a port' if uri.port.nil?
        # TODO: we could check that host is localhost or local address
      end
      rest_params = {
        base_url:     @generic_parameters[:base_url],
        redirect_max: 2
      }
      rest_params[:auth] = a_params[:auth] if a_params.key?(:auth)
      @api = Rest.new(rest_params)
      # if needed use from api
      @generic_parameters.delete(:base_url)
      @generic_parameters.delete(:auth)
      @generic_parameters.delete(@generic_parameters[:grant_method])
      Log.dump(:generic_parameters, @generic_parameters)
      Log.dump(:specific_parameters, @specific_parameters)
    end

    public

    # helper method to create token as per RFC
    def create_token(www_params)
      Log.log.debug{'Generating a new token'.bg_green}
      return @api.call({
        operation:       'POST',
        subpath:         @generic_parameters[:path_token],
        headers:         {'Accept' => 'application/json'},
        www_body_params: www_params})
    end

    # @return Hash with optional general parameters
    def optional_scope_client_id(add_secret: false)
      call_params = {}
      call_params[:scope] = @generic_parameters[:scope] unless @generic_parameters[:scope].nil?
      call_params[:client_id] = @generic_parameters[:client_id] unless @generic_parameters[:client_id].nil?
      call_params[:client_secret] = @generic_parameters[:client_secret] if add_secret && !@generic_parameters[:client_id].nil?
      return call_params
    end

    # Oauth v2 token generation
    # @param use_refresh_token set to true to force refresh or re-generation (if previous failed)
    def get_authorization(use_refresh_token: false, use_cache: true)
      # generate token unique identifier for persistency (memory/disk cache)
      token_id = IdGenerator.from_list([
        PERSIST_CATEGORY_TOKEN,
        @api.params[:base_url],
        @generic_parameters[:grant_method],
        self.class.id_creator(@generic_parameters[:grant_method]).call(self), # array, so we flatten later
        @generic_parameters[:scope],
        @api.params.dig(%i[auth username])
      ].flatten)

      # get token_data from cache (or nil), token_data is what is returned by /token
      token_data = self.class.persist_mgr.get(token_id) if use_cache
      token_data = JSON.parse(token_data) unless token_data.nil?
      # Optional optimization: check if node token is expired based on decoded content then force refresh if close enough
      # might help in case the transfer agent cannot refresh himself
      # `direct` agent is equipped with refresh code
      if !use_refresh_token && !token_data.nil?
        decoded_token = self.class.decode_token(token_data[@generic_parameters[:token_field]])
        Log.dump('decoded_token', decoded_token) unless decoded_token.nil?
        if decoded_token.is_a?(Hash)
          expires_at_sec =
            if    decoded_token['expires_at'].is_a?(String) then DateTime.parse(decoded_token['expires_at']).to_time
            elsif decoded_token['exp'].is_a?(Integer)       then Time.at(decoded_token['exp'])
            end
          # force refresh if we see a token too close from expiration
          use_refresh_token = true if expires_at_sec.is_a?(Time) && (expires_at_sec - Time.now) < TOKEN_EXPIRATION_GUARD_SEC
          Log.log.debug{"Expiration: #{expires_at_sec} / #{use_refresh_token}"}
        end
      end

      # an API was already called, but failed, we need to regenerate or refresh
      if use_refresh_token
        if token_data.is_a?(Hash) && token_data.key?('refresh_token')
          # save possible refresh token, before deleting the cache
          refresh_token = token_data['refresh_token']
        end
        # delete cache
        self.class.persist_mgr.delete(token_id)
        token_data = nil
        # lets try the existing refresh token
        if !refresh_token.nil?
          Log.log.info{"refresh=[#{refresh_token}]".bg_green}
          # try to refresh
          # note: AoC admin token has no refresh, and lives by default 1800secs
          resp = create_token(optional_scope_client_id.merge(grant_type: 'refresh_token', refresh_token: refresh_token))
          if resp[:http].code.start_with?('2')
            # save only if success
            json_data = resp[:http].body
            token_data = JSON.parse(json_data)
            self.class.persist_mgr.put(token_id, json_data)
          else
            Log.log.debug{"refresh failed: #{resp[:http].body}".bg_red}
          end
        end
      end

      # no cache, nor refresh: generate a token
      if token_data.nil?
        resp = self.class.token_creator(@generic_parameters[:grant_method]).call(self)
        json_data = resp[:http].body
        token_data = JSON.parse(json_data)
        self.class.persist_mgr.put(token_id, json_data)
      end # if ! in_cache
      raise "API error: No such field in answer: #{@generic_parameters[:token_field]}" unless token_data.key?(@generic_parameters[:token_field])
      # ok we shall have a token here
      return 'Bearer ' + token_data[@generic_parameters[:token_field]]
    end
  end # OAuth
end # Aspera
