# frozen_string_literal: true

require 'aspera/open_application'
require 'aspera/web_auth'
require 'aspera/id_generator'
require 'aspera/log'
require 'aspera/assert'
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
    # OAuth methods supported by default
    STD_AUTH_TYPES = %i[web jwt].freeze
    # default endpoint for /authorize, used for code exchange
    WEB_DEFAULT_GRANT_OPTIONS = {path_authorize: 'authorize'}

    @@globals = { # rubocop:disable Style/ClassVars
      # remove 5 minutes to account for time offset between client and server (TODO: configurable?)
      jwt_accepted_offset_sec:    300,
      # one hour validity (TODO: configurable?)
      jwt_expiry_offset_sec:      3600,
      # tokens older than 30 minutes will be discarded from cache
      token_cache_expiry_sec:     1800,
      # tokens valid for less than this duration will be regenerated
      token_expiration_guard_sec: 120
    }

    # a prefix for persistency of tokens (simplify garbage collect)
    PERSIST_CATEGORY_TOKEN = 'token'
    # prefix for bearer token when in header
    BEARER_PREFIX = 'Bearer '

    private_constant :PERSIST_CATEGORY_TOKEN, :BEARER_PREFIX, :WEB_DEFAULT_GRANT_OPTIONS

    # persistency manager
    @persist = nil
    # token creation methods
    @create_handlers = {}
    # token unique identifiers from oauth parameters
    @id_handlers = {}

    class << self
      def bearer_build(token)
        return BEARER_PREFIX + token
      end

      def bearer_extract(token)
        Aspera.assert(bearer?(token)){'not a bearer token, wrong prefix'}
        return token[BEARER_PREFIX.length..-1]
      end

      def bearer?(token)
        return token.start_with?(BEARER_PREFIX)
      end

      def persist_mgr=(manager)
        @persist = manager
        # cleanup expired tokens
        @persist.garbage_collect(PERSIST_CATEGORY_TOKEN, @@globals[:token_cache_expiry_sec])
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
        Log.log.debug{"registering token creator #{id}"}
        Aspera.assert_type(id, Symbol)
        Aspera.assert_type(lambda_create, Proc)
        Aspera.assert_type(id_create, Proc)
        @create_handlers[id] = lambda_create
        @id_handlers[id] = id_create
      end

      # @return one of the registered creators for the given create type
      def token_creator(id)
        Aspera.assert(@create_handlers.key?(id)){"token grant method unknown: '#{id}' (#{id.class})"}
        @create_handlers[id]
      end

      # list of identifiers found in creation parameters that can be used to uniquely identify the token
      def id_creator(id)
        Aspera.assert(@id_handlers.key?(id)){"id creator type unknown: #{id}/#{id.class}"}
        @id_handlers[id]
      end
    end # self

    # JSON Web Signature (JWS) compact serialization: https://datatracker.ietf.org/doc/html/rfc7515
    register_decoder lambda { |token| parts = token.split('.'); Aspera.assert(parts.length.eql?(3)){'not aoc token'}; JSON.parse(Base64.decode64(parts[1]))} # rubocop:disable Style/Semicolon, Layout/LineLength

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
      Aspera.assert(random_state.eql?(received_params['state'])){'wrong received state'}
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
      Aspera.assert(oauth.specific_parameters[:payload].is_a?(Hash)){'missing JWT payload'}
      jwt_payload = {
        exp: seconds_since_epoch + @@globals[:jwt_expiry_offset_sec], # expiration time
        nbf: seconds_since_epoch - @@globals[:jwt_accepted_offset_sec], # not before
        iat: seconds_since_epoch - @@globals[:jwt_accepted_offset_sec] + 1, # issued at (we tell a little in the past so that server always accepts)
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

    attr_reader :path_token, :specific_parameters, :api
    attr_accessor :grant_method, :scope, :redirect_uri

    private

    # [M]=mandatory [D]=has default value [O]=Optional/nil
    # @param base_url            [M] URL of authentication API
    # @param grant_method        [M] :generic, :web, :jwt, [custom types]
    # @param grant_options       [O] Hash, depending on grant_method
    # @param auth                [O]
    # @param client_id           [O]
    # @param client_secret       [O]
    # @param scope               [O]
    # @param path_token          [D] API end point to create a token
    # @param token_field         [D] field in result that contains the token
    # @param g_o:private_key_obj [M] for type :jwt
    # @param g_o:payload         [M] for type :jwt
    # @param g_o:headers         [0] for type :jwt
    # @param g_o:redirect_uri    [M] for type :web
    # @param g_o:path_authorize  [D] for type :web
    def initialize(
      base_url:,
      grant_method:,
      grant_options: nil,
      auth: nil,
      client_id: nil,
      client_secret: nil,
      scope: nil,
      path_token:  'token',       # default endpoint for /token to generate token
      token_field: 'access_token' # field with token in result of call to path_token
    )
      Aspera.assert_type(base_url, String)
      Aspera.assert_type(grant_method, Symbol)
      @base_url = base_url
      @path_token = path_token
      @token_field = token_field
      @client_id = client_id
      @client_secret = client_secret
      @scope = scope
      @grant_method = grant_method
      @specific_parameters = grant_options
      @specific_parameters = WEB_DEFAULT_GRANT_OPTIONS if @grant_method.eql?(:web) && @specific_parameters.nil?
      # check that type is known
      self.class.token_creator(@grant_method)
      # specific parameters for the creation type
      if @grant_method.eql?(:web) && @specific_parameters.key?(:redirect_uri)
        uri = URI.parse(@specific_parameters[:redirect_uri])
        Aspera.assert(%w[http https].include?(uri.scheme)){'redirect_uri scheme must be http or https'}
        Aspera.assert(!uri.port.nil?){'redirect_uri must have a port'}
        # TODO: we could check that host is localhost or local address
      end
      # this is the OAuth API
      @api = Rest.new(
        base_url:     @base_url,
        redirect_max: 2,
        auth:         auth)
    end

    public

    # helper method to create token as per RFC
    def create_token(www_params)
      Log.log.debug{'Generating a new token'.bg_green}
      return @api.call({
        operation:       'POST',
        subpath:         @path_token,
        headers:         {'Accept' => 'application/json'},
        www_body_params: www_params})
    end

    # @return Hash with optional general parameters
    def optional_scope_client_id(add_secret: false)
      call_params = {}
      call_params[:scope] = @scope unless @scope.nil?
      call_params[:client_id] = @client_id unless @client_id.nil?
      call_params[:client_secret] = @client_secret if add_secret && !@client_id.nil?
      return call_params
    end

    # Oauth v2 token generation
    # @param use_refresh_token set to true to force refresh or re-generation (if previous failed)
    def get_authorization(use_refresh_token: false, use_cache: true)
      # generate token unique identifier for persistency (memory/disk cache)
      token_id = IdGenerator.from_list([
        PERSIST_CATEGORY_TOKEN,
        @base_url,
        @grant_method,
        self.class.id_creator(@grant_method).call(self), # array, so we flatten later
        @scope,
        @api.params.dig(*%i[auth username])
      ].flatten)

      # get token_data from cache (or nil), token_data is what is returned by /token
      token_data = self.class.persist_mgr.get(token_id) if use_cache
      token_data = JSON.parse(token_data) unless token_data.nil?
      # Optional optimization: check if node token is expired based on decoded content then force refresh if close enough
      # might help in case the transfer agent cannot refresh himself
      # `direct` agent is equipped with refresh code
      if !use_refresh_token && !token_data.nil?
        decoded_token = self.class.decode_token(token_data[@token_field])
        Log.log.debug{Log.dump('decoded_token', decoded_token)} unless decoded_token.nil?
        if decoded_token.is_a?(Hash)
          expires_at_sec =
            if    decoded_token['expires_at'].is_a?(String) then DateTime.parse(decoded_token['expires_at']).to_time
            elsif decoded_token['exp'].is_a?(Integer)       then Time.at(decoded_token['exp'])
            end
          # force refresh if we see a token too close from expiration
          use_refresh_token = true if expires_at_sec.is_a?(Time) && (expires_at_sec - Time.now) < @@globals[:token_expiration_guard_sec]
          Log.log.debug{"Expiration: #{expires_at_sec} / #{use_refresh_token}"}
        end
      end

      # an API was already called, but failed, we need to regenerate or refresh
      if use_refresh_token
        if token_data.is_a?(Hash) && token_data.key?('refresh_token') && !token_data['refresh_token'].eql?('not_supported')
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
        resp = self.class.token_creator(@grant_method).call(self)
        json_data = resp[:http].body
        token_data = JSON.parse(json_data)
        self.class.persist_mgr.put(token_id, json_data)
      end # if ! in_cache
      Aspera.assert(token_data.key?(@token_field)){"API error: No such field in answer: #{@token_field}"}
      # ok we shall have a token here
      return self.class.bearer_build(token_data[@token_field])
    end
  end # OAuth
end # Aspera
