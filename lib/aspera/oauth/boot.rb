# frozen_string_literal: true

require 'aspera/oauth/base'
require 'aspera/assert'
require 'json'

module Aspera
  module OAuth
    # Token provider bootstrapped from an existing cookie (e.g. AoC browser cookie).
    # Injects the bearer token and optional refresh token directly into the cache.
    # Never generates a new token from scratch — raises if cache+refresh are both exhausted.
    class Boot < Base
      # @param cookie   [String, nil] Raw cookie string (--password), nil to rely on existing cache
      # @param username [String, nil] Expected subject; if provided, must match token's `sub` claim
      # @param **base_params          Forwarded to Base (base_url:, params: {client_id:, scope:}, etc.)
      def initialize(cookie: nil, username: nil, **base_params)
        if cookie.nil?
          # No cookie: rely on existing cache, identified by username if provided
          Aspera.assert(username, 'Provide --password (cookie) on first use, or --username for cache lookup', type: ParameterError)
          super(**base_params, cache_ids: [username])
        else
          cookies = cookie.split('; ').map{ |p| p.split('=', 2)}.to_h
          Aspera.assert(cookies.key?('aoc.token'), '--password cookie does not contain aoc.token', type: ParameterError)
          token = cookies['aoc.token']
          decoded = Factory.instance.decode_token(token)
          Aspera.assert(decoded.is_a?(Hash)){'Boot: token is not a decodable JWT'}
          sub = decoded['sub']
          Aspera.assert(username.nil? || username.eql?(sub)){"Boot: --username #{username} does not match token subject #{sub}"}
          super(**base_params, cache_ids: [sub])
          token_data = {Factory::TOKEN_FIELD => token}
          token_data['refresh_token'] = cookies['aoc.refresh'] if cookies.key?('aoc.refresh')
          Factory.instance.persist_mgr.put(@token_cache_id, JSON.generate(token_data))
        end
      end

      # Should never be reached: if cache and refresh are both exhausted, re-authenticate via browser
      def create_token
        Aspera.assert(false){'Boot: token expired and no refresh available — re-authenticate in browser'}
      end
    end
    Factory.instance.register_token_creator(Boot)
  end
end
