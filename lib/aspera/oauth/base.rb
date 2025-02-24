# frozen_string_literal: true

require 'aspera/oauth/factory'
require 'aspera/log'
require 'aspera/assert'
require 'date'

module Aspera
  module OAuth
    # OAuth 2 client for the REST client
    # Generate bearer token
    # Bearer tokens are cached in memory and in a file cache for later re-use
    # https://tools.ietf.org/html/rfc6749
    class Base
      # @param **             Parameters for REST
      # @param client_id      [String, nil]
      # @param client_secret  [String, nil]
      # @param scope          [String, nil]
      # @param use_query      [bool]        Provide parameters in query instead of body
      # @param path_token     [String]      API end point to create a token
      # @param token_field    [String]      Field in result that contains the token
      # @param cache_ids      [Array, nil]  List of unique identifiers for cache id generation
      def initialize(
        client_id: nil,
        client_secret: nil,
        scope: nil,
        use_query: false,
        path_token:  'token',
        token_field: Factory::TOKEN_FIELD,
        cache_ids: nil,
        **rest_params
      )
        Aspera.assert(respond_to?(:create_token), 'create_token method must be defined', exception_class: InternalError)
        # this is the OAuth API
        @api = Rest.new(**rest_params)
        @path_token = path_token
        @token_field = token_field
        @client_id = client_id
        @client_secret = client_secret
        @use_query = use_query
        @base_cache_ids = cache_ids.clone
        @base_cache_ids = [] if @base_cache_ids.nil?
        Aspera.assert_type(@base_cache_ids, Array)
        if @api.auth_params.key?(:username)
          cache_ids.push(@api.auth_params[:username])
        end
        @base_cache_ids.freeze
        self.scope = scope
      end

      # Scope can be modified after creation, then update identifier for cache
      def scope=(scope)
        @scope = scope
        # generate token unique identifier for persistency (memory/disk cache)
        @token_cache_id = Factory.cache_id(@api.base_url, self.class, @base_cache_ids, @scope)
      end

      # helper method to create token as per RFC
      def create_token_call(creation_params)
        Log.log.debug{'Generating a new token'.bg_green}
        payload = { body_type: :www }
        if @use_query
          payload[:query] = creation_params
        else
          payload[:body] = creation_params
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
        # get token info from cache (or nil), decoded with date and expiration status
        token_info = Factory.instance.get_token_info(@token_cache_id) if cache
        token_data = nil
        unless token_info.nil?
          token_data = token_info[:data]
          # Optional optimization:
          # check if node token is expired based on decoded content then force refresh if close enough
          # might help in case the transfer agent cannot refresh himself
          # `direct` agent is equipped with refresh code
          # an API was already called, but failed, we need to regenerate or refresh
          if refresh || token_info[:expired]
            if token_data.key?('refresh_token') && token_data['refresh_token'].eql?('not_supported')
              # save possible refresh token, before deleting the cache
              refresh_token = token_data['refresh_token']
            end
            # delete cache
            Factory.instance.persist_mgr.delete(@token_cache_id)
            token_data = nil
            # lets try the existing refresh token
            if !refresh_token.nil?
              Log.log.info{"refresh=[#{refresh_token}]".bg_green}
              # NOTE: AoC admin token has no refresh, and lives by default 1800secs
              resp = create_token_call(optional_scope_client_id.merge(grant_type: 'refresh_token', refresh_token: refresh_token))
              if resp[:http].code.start_with?('2')
                # save only if success
                json_data = resp[:http].body
                token_data = JSON.parse(json_data)
                Factory.instance.persist_mgr.put(@token_cache_id, json_data)
              else
                Log.log.debug{"refresh failed: #{resp[:http].body}".bg_red}
              end
            end
          end
        end

        # no cache, nor refresh: generate a token
        if token_data.nil?
          resp = create_token
          json_data = resp[:http].body
          token_data = JSON.parse(json_data)
          Factory.instance.persist_mgr.put(@token_cache_id, json_data)
        end
        Aspera.assert(token_data.key?(@token_field)){"API error: No such field in answer: #{@token_field}"}
        # ok we shall have a token here
        return OAuth::Factory.bearer_build(token_data[@token_field])
      end
    end
  end
end
