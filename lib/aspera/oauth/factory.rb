# frozen_string_literal: true

require 'aspera/id_generator'
require 'aspera/assert'
require 'singleton'
require 'base64'
module Aspera
  module OAuth
    # Factory to create tokens and manage their cache
    #
    # @!method self.instance
    #   Returns the singleton instance of Factory
    #   @return [Factory] the singleton instance
    class Factory
      include Singleton

      # prefix for persistency of tokens (simplify garbage collect)
      PERSIST_CATEGORY_TOKEN = 'token'
      # prefix for bearer authorization when in header
      SPACE_BEARER_AUTH_SCHEME = 'Bearer '
      TOKEN_FIELD = 'access_token'

      private_constant :PERSIST_CATEGORY_TOKEN, :SPACE_BEARER_AUTH_SCHEME

      class << self
        # Format a token for use in Authorization header
        # @param token [String] The token alone
        # @return [String] Value suitable for Authorization header
        def bearer_authorization(token)
          return "#{SPACE_BEARER_AUTH_SCHEME}#{token}"
        end

        # Check if the authorization contains a bearer token
        # @param authorization [String] The authorization header value
        # @return [Boolean] true if the authorization contains a bearer token, i.e. auth scheme is bearer
        def bearer_auth?(authorization)
          return authorization.start_with?(SPACE_BEARER_AUTH_SCHEME)
        end

        # Extract only token from Authorization (remove scheme)
        # @param authorization [String] The authorization header value
        # @return [String] The bearer token without the scheme prefix
        def bearer_token(authorization)
          Aspera.assert(bearer_auth?(authorization)){'not a bearer token, wrong prefix scheme'}
          return authorization.delete_prefix(SPACE_BEARER_AUTH_SCHEME)
        end

        # Generate a unique cache id for a token creator
        # @param url           [String] Base URL of the OAuth server
        # @param creator_class [Class]  Class of the token creator
        # @param params        [Array]  List of parameters (can be nested) to uniquely identify the token
        # @return [String] a unique cache identifier
        def cache_id(url, creator_class, *params)
          return IdGenerator.from_list(PERSIST_CATEGORY_TOKEN, url, Factory.class_to_id(creator_class), params)
        end

        # Convert a class name to snake_case symbol
        # @param creator_class [Class] The class to convert
        # @return [Symbol] snake_case version of class name
        def class_to_id(creator_class)
          return creator_class.name.split('::').last.capital_to_snake.to_sym
        end
      end

      private

      # Initialize the factory with default parameters and empty collections
      def initialize
        # persistency manager
        @persist = nil
        # token creation methods
        @token_type_classes = {}
        # list of lambda
        @decoders = []
        # default parameters, others can be added by handlers
        @parameters = {
          # tokens older than this duration in sec. will be discarded from cache
          token_cache_max_age:     1800,
          # tokens valid for less than this duration in sec. will be regenerated
          token_refresh_threshold: 120
        }
      end

      public

      attr_reader :parameters

      # Set the persistence manager for token caching
      # @param manager [Object] The persistence manager instance
      def persist_mgr=(manager)
        @persist = manager
        # cleanup expired tokens
        @persist.garbage_collect(PERSIST_CATEGORY_TOKEN, @parameters[:token_cache_max_age])
      end

      # Get or initialize the persistence manager
      # @return [Object] The persistence manager instance
      def persist_mgr
        if @persist.nil?
          # use OAuth::Factory.instance.persist_mgr=PersistencyFolder.new)
          Log.log.debug('Not using persistency')
          # create NULL persistency class
          @persist = Class.new do
            def get(_x); nil; end; def delete(_x); nil; end; def put(_x, _y); nil; end; def garbage_collect(_x, _y); nil; end # rubocop:disable Style/Semicolon
          end.new
        end
        return @persist
      end

      # Delete all existing tokens in cache
      # @return [void]
      def flush_tokens
        persist_mgr.garbage_collect(PERSIST_CATEGORY_TOKEN)
      end

      # Retrieve all persisted tokens with their decoded information
      # @return [Array<Hash>] Array of token information hashes
      def persisted_tokens
        data = persist_mgr.current_items(PERSIST_CATEGORY_TOKEN)
        data.each.map do |k, v|
          info = {id: k}
          begin; info.merge!(JSON.parse(v)); rescue StandardError; nil; end
          d = decode_token(info.delete(TOKEN_FIELD))
          info.merge(d) if d
          info
        end
      end

      # Get token information from cache
      # @param id [String] identifier of token
      # @return [Hash] token internal information , including Date object for `expiration_date`
      def get_token_info(id)
        token_raw_string = persist_mgr.get(id)
        return if token_raw_string.nil?
        token_data = JSON.parse(token_raw_string)
        Aspera.assert_type(token_data, Hash)
        decoded_token = decode_token(token_data[TOKEN_FIELD])
        info = {data: token_data}
        if decoded_token.is_a?(Hash)
          info[:decoded] = decoded_token
          # TODO: move date decoding to token decoder ?
          expiration_date =
            if    decoded_token['expires_at'].is_a?(String) then Time.parse(decoded_token['expires_at']).to_time
            elsif decoded_token['exp'].is_a?(Integer)       then Time.at(decoded_token['exp'])
            end
          unless expiration_date.nil?
            info[:expiration] = expiration_date
            info[:ttl_sec] = expiration_date - Time.now
            info[:expired] = info[:ttl_sec] < @parameters[:token_refresh_threshold]
          end
        end
        Log.dump(:token_info, info)
        return info
      end

      # Register a bearer token decoder for inspecting token properties
      # @param method [Proc] The decoder lambda/proc to register
      # @return [void]
      def register_decoder(method)
        @decoders.push(method)
      end

      # Decode a token using all registered decoders
      # @param token [String] The token to decode
      # @return [Hash, nil] Decoded token data or nil if no decoder succeeded
      def decode_token(token)
        @decoders.each do |decoder|
          result = begin; decoder.call(token); rescue StandardError; nil; end
          return result unless result.nil?
        end
        return
      end

      # Register a token creation method
      # @param creator_class [Class] The token creator class to register
      # @return [void]
      def register_token_creator(creator_class)
        Aspera.assert_type(creator_class, Class)
        id = Factory.class_to_id(creator_class)
        Log.log.debug{"registering creator for #{id}"}
        @token_type_classes[id] = creator_class
      end

      # Create a token creator instance for the specified grant method
      # @param parameters [Hash] Parameters including :grant_method and creator-specific options
      # @return [Object] An instance of the registered token creator class
      def create(**parameters)
        Aspera.assert_type(parameters, Hash)
        id = parameters[:grant_method]
        Aspera.assert(@token_type_classes.key?(id)){"token grant method unknown: '#{id}'"}
        create_parameters = parameters.reject{ |k, _v| k.eql?(:grant_method)}
        @token_type_classes[id].new(**create_parameters)
      end
    end
    # JSON Web Signature (JWS) compact serialization: https://datatracker.ietf.org/doc/html/rfc7515
    Factory.instance.register_decoder(lambda{ |token| parts = token.split('.'); Aspera.assert_values(parts.length, [3]){'JWS token parts'}; JSON.parse(Base64.decode64(parts[1]))}) # rubocop:disable Style/Semicolon
  end
end
