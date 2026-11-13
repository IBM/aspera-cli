# frozen_string_literal: true

require 'aspera/oauth/client/factory'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/secret/hider'
require 'aspera/mime'
require 'date'
require 'aspera/rainbow'
using Rainbow

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
      # @param path_token     [String]  API end point to create a token from base URL
      # @param use_query      [Boolean] Provide parameters in query instead of body
      # @param token_field    [String]  Field in result that contains the token
      # @param cache_ids      [Array]   List of unique identifiers for cache id generation
      # @param **rest_params  [Hash]    Parameters for REST
      def initialize(
        params: {},
        path_token: 'token',
        use_query: false,
        token_field: Factory::TOKEN_FIELD,
        cache_ids: [],
        **rest_params
      )
        Aspera.assert_type(params, Hash)
        Aspera.assert_type(cache_ids, Array)
        # This is the OAuth API
        @api = Rest::Client.new(**rest_params)
        @params = params.dup.freeze
        @path_token = path_token
        @token_field = token_field
        @use_query = use_query
        @token_cache_id = Factory.cache_id(@api.base_url, self.class, *cache_ids, @params[:scope])
      end

      # The OAuth API Object
      attr_reader :api
      # Parameters to generate token
      attr_reader :params
      # Sub path to generate token
      attr_reader :path_token

      # Parameters for token creation call
      # @param include_secret [Boolean] Add secret in default call parameters
      # @param other_params [Hash] Other parameters to merge
      # @return [Hash] Token creation parameters
      def base_parameters(include_secret: false, **other_params)
        call_params = @params.dup
        call_params.delete(:client_secret) unless include_secret
        call_params.merge(other_params)
      end

      # Helper method to create token as per RFC
      # @param other_params [Hash] Additional parameter to base parameters
      # @return [Net::HTTPResponse] Raw HTTP response with token
      # @raise [Rest::CallError] If not 2XX code
      def create_token_base(include_secret: false, **other_params)
        Log.log.debug { 'Generating a new token'.bg(:green) }
        creation_params = base_parameters(include_secret: include_secret, **other_params)
        return @api.create(@path_token, nil, query: creation_params, ret: :resp) if @use_query
        return @api.create(@path_token, creation_params, content_type: Mime::WWW, ret: :resp)
      end

      # Get the value of the HTTP `Authorization` header for this OAuth client, i.e. `Bearer <token>`.
      # The bearer token is obtained through {#token} (cached, refreshed or generated).
      # @return [String] Value suitable for Authorization header
      def authorization
        return OAuth::Factory.bearer_authorization(token)
      end

      # Get the value of the HTTP `Authorization` header with a renewed token, i.e. `Bearer <token>`.
      # To be used when the server rejected the current token.
      # The bearer token is obtained through {#renew_token}.
      # @return [String] Value suitable for Authorization header
      def renewed_authorization
        return OAuth::Factory.bearer_authorization(renew_token)
      end

      # Get a OAuth v2 token: the cached one, unless it expires soon, else a renewed one.
      # Checking expiration in advance helps a transfer agent which cannot renew the token itself
      # (`direct` agent is equipped with renewal code).
      # If the server rejects the token (API returns 4xx), call {#renew_token}.
      # @return [String] The bearer token
      def token
        token_info = cached_token_info
        return bearer_token(token_info[:data]) unless token_info.nil? || token_info[:expired]
        Log.log.trace1 { 'Cached token expires soon' } unless token_info.nil?
        return renew_token
      end

      # Get a new OAuth v2 token, discarding the cached one.
      # Use the refresh token of the cached token, if any, else generate a new token.
      # @return [String] The bearer token
      # @raise [StandardError] Error of the generation of a new token
      def renew_token
        return bearer_token(refreshed_token_data(discard_cached_token) || created_token_data)
      end

      private

      # @return [Hash, nil] Token information from cache (see {Factory#get_token_info}), or `nil` if none
      def cached_token_info
        Factory.instance.get_token_info(@token_cache_id, token_field: @token_field)
      end

      # Delete the cached token
      # @return [String, nil] Its refresh token, or `nil` if none
      def discard_cached_token
        token_info = cached_token_info
        return if token_info.nil?
        Factory.instance.persist_mgr.delete(@token_cache_id)
        refresh_token = token_info[:data]['refresh_token']
        return refresh_token unless refresh_token.eql?('not_supported')
      end

      # Get a new token using a refresh token.
      # NOTE: AoC admin token has no refresh token, and lives by default 1800 secs
      # @param refresh_token [String, nil] Refresh token, or `nil` if none
      # @return [Hash{String => Object}, nil] Token creation response, or `nil` if no refresh token or if refresh failed
      def refreshed_token_data(refresh_token)
        return if refresh_token.nil?
        return save_token_data(create_token_base(include_secret: true, grant_type: 'refresh_token', refresh_token: refresh_token))
      rescue StandardError => e
        # Refresh token can fail: a new token will be generated
        Log.log.warn { "Refresh failed: #{e}" }
        return
      end

      # Generate a new token with the method of the subclass
      # @return [Hash{String => Object}] Token creation response
      def created_token_data
        return save_token_data(create_token)
      end

      # Cache the token creation response
      # @param http [Net::HTTPResponse] Response of the token creation (see {#create_token_base})
      # @return [Hash{String => Object}] Token creation response: `@token_field`, optional `refresh_token`, `expires_in`, ...
      def save_token_data(http)
        token_data = JSON.parse(http.body)
        Factory.instance.persist_mgr.put(@token_cache_id, http.body)
        # Logs decoded token information
        cached_token_info
        return token_data
      end

      # @param token_data [Hash{String => Object}] Token creation response
      # @return [String] The bearer token, registered as secret: hidden wherever it appears (logs, results)
      def bearer_token(token_data)
        Aspera.assert(token_data.key?(@token_field)) { "API error: No such field in answer: #{@token_field}" }
        Secret::Hider.instance.add_secret_values(token_data[@token_field], token_data['refresh_token'])
        return token_data[@token_field]
      end
    end
  end
end
