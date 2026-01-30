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
    # OAuth 2.0 Authorization Framework: https://tools.ietf.org/html/rfc6749
    # Bearer Token Usage: https://tools.ietf.org/html/rfc6750
    class Base
      Aspera.require_method!(:create_token)
      # @param params         [Hash]    Parameters for token creation (client_id, client_secret, scope, etc...)
      # @param use_query      [Boolean] Provide parameters in query instead of body
      # @param path_token     [String]  API end point to create a token from base URL
      # @param token_field    [String]  Field in result that contains the token
      # @param cache_ids      [Array]   List of unique identifiers for cache id generation
      # @param **rest_params  [Hash]    Parameters for REST
      def initialize(
        params: {},
        use_query: false,
        path_token:  'token',
        token_field: Factory::TOKEN_FIELD,
        cache_ids: [],
        **rest_params
      )
        Aspera.assert_type(params, Hash)
        Aspera.assert_type(cache_ids, Array)
        # This is the OAuth API
        @api = Rest.new(**rest_params)
        @params = params.dup.freeze
        @path_token = path_token
        @token_field = token_field
        @use_query = use_query
        # TODO: :username and :scope shall be done in class, using cache_ids
        @token_cache_id = Factory.cache_id(@api.base_url, self.class, cache_ids, rest_params[:username], @params[:scope])
      end

      # The OAuth API Object
      attr_reader :api
      # Sub path to generate token
      attr_reader :path_token
      # Parameters to generate token
      attr_reader :params

      # Helper method to create token as per RFC
      # @return [HTTPResponse]
      # @raise RestError if not 2XX code
      def create_token_call(creation_params)
        Log.log.debug{'Generating a new token'.bg_green}
        return @api.create(@path_token, nil, query: creation_params, ret: :resp) if @use_query
        return @api.create(@path_token, creation_params, content_type: Rest::MIME_WWW, ret: :resp)
      end

      # Create base parameters for token creation calls
      # @param add_secret [Boolean] Add secret in default call parameters
      # @return [Hash] Optional general parameters
      def base_params(add_secret: false)
        call_params = @params.dup
        call_params.delete(:client_secret) unless add_secret
        return call_params
      end

      # @return [String] value suitable for Authorization header
      def authorization(**kwargs)
        return OAuth::Factory.bearer_authorization(token(**kwargs))
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
          # Check if token is expired based on decoded content then force refresh if close enough
          # might help in case the transfer agent cannot refresh himself
          # `direct` agent is equipped with refresh code
          # an API was already called, but failed, we need to regenerate or refresh
          if refresh || token_info[:expired]
            Log.log.trace1{"refresh: #{refresh} expired: #{token_info[:expired]}"}
            refresh_token = nil
            if token_data.key?('refresh_token') && !token_data['refresh_token'].eql?('not_supported')
              # save possible refresh token, before deleting the cache
              refresh_token = token_data['refresh_token']
            end
            # delete cache
            Factory.instance.persist_mgr.delete(@token_cache_id)
            token_data = nil
            # lets try the existing refresh token
            # NOTE: AoC admin token has no refresh, and lives by default 1800secs
            if !refresh_token.nil?
              Log.log.debug{"refresh token=[#{refresh_token}]"}
              begin
                http = create_token_call(base_params(add_secret: true).merge(grant_type: 'refresh_token', refresh_token: refresh_token))
                # Save only if success
                json_data = http.body
                token_data = JSON.parse(json_data)
                Factory.instance.persist_mgr.put(@token_cache_id, json_data)
              rescue => e
                # Refresh token can fail.
                Log.log.warn{"Refresh failed: #{e}"}
              end
            end
          end
        end

        # no cache, nor refresh: generate a token
        if token_data.nil?
          # Call the method-specific token creation
          # which returns the result of create_token_call
          json_data = create_token.body
          token_data = JSON.parse(json_data)
          Factory.instance.persist_mgr.put(@token_cache_id, json_data)
        end
        Aspera.assert(token_data.key?(@token_field)){"API error: No such field in answer: #{@token_field}"}
        # ok we shall have a token here
        return token_data[@token_field]
      end
    end
  end
end
