# frozen_string_literal: true

require 'aspera/oauth/factory'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/id_generator'
require 'date'

module Aspera
  module OAuth
    # Implement OAuth 2 for the REST client and generate a bearer token
    # bearer tokens are cached in memory and in a file cache for later re-use
    # https://tools.ietf.org/html/rfc6749
    class Base
      # scope can be modified after creation
      attr_writer :scope

      # [M]=mandatory [D]=has default value [O]=Optional/nil
      # @param base_url            [M] URL of authentication API
      # @param auth                [O] basic auth parameters
      # @param client_id           [O]
      # @param client_secret       [O]
      # @param scope               [O]
      # @param path_token          [D] API end point to create a token
      # @param token_field         [D] field in result that contains the token
      def initialize(
        base_url:,
        auth: nil,
        client_id: nil,
        client_secret: nil,
        scope: nil,
        use_query: false,
        path_token:  'token',       # default endpoint for /token to generate token
        token_field: 'access_token' # field with token in result of call to path_token
      )
        Aspera.assert_type(base_url, String)
        Aspera.assert(respond_to?(:create_token), 'create_token method must be defined', exception_class: InternalError)
        @base_url = base_url
        @path_token = path_token
        @token_field = token_field
        @client_id = client_id
        @client_secret = client_secret
        @scope = scope
        @use_query = use_query
        @identifiers = []
        @identifiers.push(auth[:username]) if auth.is_a?(Hash) && auth.key?(:username)
        # this is the OAuth API
        @api = Rest.new(
          base_url:     @base_url,
          redirect_max: 2,
          auth:         auth)
      end

      # helper method to create token as per RFC
      def create_token_call(creation_params)
        Log.log.debug{'Generating a new token'.bg_green}
        payload = {
          body:      creation_params,
          body_type: :www
        }
        if @use_query
          payload[:query] = creation_params
          payload[:body] = {}
        end
        return @api.call(
          operation: 'POST',
          subpath:   @path_token,
          headers:   {'Accept' => 'application/json'},
          **payload
        )
      end

      # @return Hash with optional general parameters
      def optional_scope_client_id(add_secret: false)
        call_params = {}
        call_params[:scope] = @scope unless @scope.nil?
        call_params[:client_id] = @client_id unless @client_id.nil?
        call_params[:client_secret] = @client_secret if add_secret && !@client_id.nil?
        return call_params
      end

      # get an OAuth v2 token (generated, cached, refreshed)
      # call token() to get a token.
      # if a token is expired (api returns 4xx), call again token(refresh: true)
      # @param cache set to false to disable cache
      # @param refresh set to true to force refresh or re-generation (if previous failed)
      def token(cache: true, refresh: false)
        # generate token unique identifier for persistency (memory/disk cache)
        token_id = IdGenerator.from_list(Factory.id(
          @base_url,
          Factory.class_to_id(self.class),
          @identifiers,
          @scope
        ))

        # get token_data from cache (or nil), token_data is what is returned by /token
        token_data = Factory.instance.persist_mgr.get(token_id) if cache
        token_data = JSON.parse(token_data) unless token_data.nil?
        # Optional optimization: check if node token is expired based on decoded content then force refresh if close enough
        # might help in case the transfer agent cannot refresh himself
        # `direct` agent is equipped with refresh code
        if !refresh && !token_data.nil?
          decoded_token = OAuth::Factory.instance.decode_token(token_data[@token_field])
          Log.log.debug{Log.dump('decoded_token', decoded_token)} unless decoded_token.nil?
          if decoded_token.is_a?(Hash)
            expires_at_sec =
              if    decoded_token['expires_at'].is_a?(String) then DateTime.parse(decoded_token['expires_at']).to_time
              elsif decoded_token['exp'].is_a?(Integer)       then Time.at(decoded_token['exp'])
              end
            # force refresh if we see a token too close from expiration
            refresh = true if expires_at_sec.is_a?(Time) && (expires_at_sec - Time.now) < OAuth::Factory.instance.parameters[:token_expiration_guard_sec]
            Log.log.debug{"Expiration: #{expires_at_sec} / #{refresh}"}
          end
        end

        # an API was already called, but failed, we need to regenerate or refresh
        if refresh
          if token_data.is_a?(Hash) && token_data.key?('refresh_token') && !token_data['refresh_token'].eql?('not_supported')
            # save possible refresh token, before deleting the cache
            refresh_token = token_data['refresh_token']
          end
          # delete cache
          Factory.instance.persist_mgr.delete(token_id)
          token_data = nil
          # lets try the existing refresh token
          if !refresh_token.nil?
            Log.log.info{"refresh=[#{refresh_token}]".bg_green}
            # try to refresh
            # note: AoC admin token has no refresh, and lives by default 1800secs
            resp = create_token_call(optional_scope_client_id.merge(grant_type: 'refresh_token', refresh_token: refresh_token))
            if resp[:http].code.start_with?('2')
              # save only if success
              json_data = resp[:http].body
              token_data = JSON.parse(json_data)
              Factory.instance.persist_mgr.put(token_id, json_data)
            else
              Log.log.debug{"refresh failed: #{resp[:http].body}".bg_red}
            end
          end
        end

        # no cache, nor refresh: generate a token
        if token_data.nil?
          resp = create_token
          json_data = resp[:http].body
          token_data = JSON.parse(json_data)
          Factory.instance.persist_mgr.put(token_id, json_data)
        end
        Aspera.assert(token_data.key?(@token_field)){"API error: No such field in answer: #{@token_field}"}
        # ok we shall have a token here
        return OAuth::Factory.bearer_build(token_data[@token_field])
      end
    end
  end
end
