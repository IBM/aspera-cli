# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'factory'
require_relative '../../log'
require_relative '../../assert'
require_relative '../../secret/hider'
require_relative '../../mime'
require_relative '../../rainbow'
require 'date'
require 'time'
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
      # Parameters of a token request that are credentials, but whose names do not denote a secret (see `Secret::Hider#secret?`)
      CREDENTIAL_PARAMS = %w[assertion code code_verifier].freeze
      private_constant :CREDENTIAL_PARAMS
      class << self
        # @param path [String] Path of an end point
        # @return [Boolean] `true` if `path` is an absolute URL (`http` or `https`)
        def absolute_url?(path) = path.match?(%r{\Ahttps?://}i)
      end
      # @param params         [Hash]    Parameters for token creation (client_id, client_secret, scope, etc...)
      # @param path_token     [String]  API end point to create a token: path from base URL, or absolute URL (`http` or `https`), e.g. on another host
      # @param use_query      [Boolean] Provide parameters in query instead of body
      # @param token_field    [String]  Field in result that contains the token, or dot-separated path of a nested field (e.g. `authed_user.access_token`)
      # @param cache_ids      [Array]   List of unique identifiers for cache id generation
      # @param rest_params    [Hash]    Parameters for REST
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

      # URL of an end point of the OAuth server
      # @param path [String] Path from the base URL, or absolute URL (`http` or `https`), used as is
      # @return [String] URL of the end point
      def endpoint_url(path)
        Base.absolute_url?(path) ? path : "#{@api.base_url}/#{path}"
      end

      # API and subpath to call an end point of the OAuth server
      # An absolute URL (e.g. token on another host than authorization) gets its own API, same parameters.
      # The token cache id does not depend on it: it uses the base URL.
      # @param path [String] Path from the base URL, or absolute URL (`http` or `https`)
      # @return [Array(Rest::Client, String)] API and subpath
      def endpoint_api(path)
        return [@api, path] unless Base.absolute_url?(path)
        [Rest::Client.new(**@api.params.merge(base_url: path)), '']
      end

      # Parameters for token creation call
      # @param include_secret [Boolean] Add secret in default call parameters
      # @param other_params [Hash] Other parameters to merge
      # @return [Hash] Token creation parameters
      def base_parameters(include_secret: false, **other_params)
        (include_secret ? @params : @params.except(:client_secret)).merge(other_params)
      end

      # Helper method to create token as per RFC
      # @param include_secret [Boolean] Add secret in call parameters
      # @param other_params [Hash] Additional parameter to base parameters
      # @return [Net::HTTPResponse] Raw HTTP response with token
      # @raise [Rest::CallError] If not 2XX code
      def create_token_base(include_secret: false, **other_params)
        Log.log.debug { 'Generating a new token'.bg(:green) }
        creation_params = base_parameters(include_secret: include_secret, **other_params)
        # Credentials of the request are hidden wherever they appear, e.g. logs of its body or URL
        Secret::Hider.instance.add_secrets_in(creation_params)
        Secret::Hider.instance.add_secret_values(*creation_params.filter_map { |k, v| v if CREDENTIAL_PARAMS.include?(k.to_s) })
        token_api, subpath = endpoint_api(@path_token)
        return token_api.create(subpath, nil, query: creation_params, ret: :resp) if @use_query
        token_api.create(subpath, creation_params, content_type: Mime::WWW, ret: :resp)
      end

      # Get the value of the HTTP `Authorization` header for this OAuth client, i.e. `Bearer <token>`.
      # The bearer token is obtained through {#token} (cached, refreshed or generated).
      # @return [String] Value suitable for Authorization header
      def authorization
        OAuth::Factory.bearer_authorization(token)
      end

      # Get the value of the HTTP `Authorization` header with a renewed token, i.e. `Bearer <token>`.
      # To be used when the server rejected the current token.
      # The bearer token is obtained through {#renew_token}.
      # @return [String] Value suitable for Authorization header
      def renewed_authorization
        OAuth::Factory.bearer_authorization(renew_token)
      end

      # Get a OAuth v2 token: the cached one, unless it expires soon, else a renewed one.
      # Checking expiration in advance helps a transfer agent which cannot renew the token itself
      # (`direct` agent is equipped with renewal code).
      # If the server rejects the token (API returns 4xx), call {#renew_token}.
      # @return [String] The bearer token
      def token
        token_info = cached_token_info
        unless token_info.nil?
          return bearer_token(token_info[:data]) unless token_info[:expired]
          Log.log.trace1 { 'Cached token expires soon' }
        end
        renew_token
      end

      # Get a new OAuth v2 token, discarding the cached one.
      # Use the refresh token of the cached token, if any, else generate a new token.
      # @return [String] The bearer token
      # @raise [StandardError] Error of the generation of a new token
      def renew_token
        bearer_token(refreshed_token_data(discard_cached_token) || save_token_data(create_token))
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
        refresh_token unless refresh_token.eql?('not_supported')
      end

      # Get a new token using a refresh token.
      # NOTE: AoC admin token has no refresh token, and lives by default 1800 secs
      # @param refresh_token [String, nil] Refresh token, or `nil` if none
      # @return [Hash{String => Object}, nil] Token creation response, or `nil` if no refresh token or if refresh failed
      def refreshed_token_data(refresh_token)
        return if refresh_token.nil?
        save_token_data(create_token_base(include_secret: true, grant_type: 'refresh_token', refresh_token: refresh_token))
      rescue StandardError => e
        # Refresh token can fail: a new token will be generated
        Log.log.warn { "Refresh failed: #{e}" }
        nil
      end

      # Cache the token creation response
      # Adds `obtained_at` and, if the server gives `expires_in`, `expires_at` (expiration of an opaque token)
      # @param http [Net::HTTPResponse] Response of the token creation (see {#create_token_base})
      # @return [Hash{String => Object}] Token creation response: `@token_field`, optional `refresh_token`, `expires_in`, ...
      def save_token_data(http)
        token_data = JSON.parse(http.body)
        now = Time.now
        token_data[Factory::OBTAINED_AT_FIELD] = now.utc.iso8601
        lifetime = Integer(token_data['expires_in'], exception: false)
        token_data[Factory::EXPIRES_AT_FIELD] = (now + lifetime).utc.iso8601 if lifetime && !token_data.key?(Factory::EXPIRES_AT_FIELD)
        Factory.instance.persist_mgr.put(@token_cache_id, JSON.generate(token_data))
        # Logs decoded token information
        cached_token_info
        token_data
      end

      # @param token_data [Hash{String => Object}] Token creation response
      # @return [String] The bearer token, registered as secret: hidden wherever it appears (logs, results)
      def bearer_token(token_data)
        token_value = Factory.token_value(token_data, @token_field)
        Aspera.assert(!token_value.nil?) { "API error: No such field in answer: #{@token_field}" }
        Secret::Hider.instance.add_secret_values(token_value, token_data['refresh_token'])
        token_value
      end
    end
  end
end
