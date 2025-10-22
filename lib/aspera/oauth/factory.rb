# frozen_string_literal: true

require 'aspera/id_generator'
require 'aspera/assert'
require 'singleton'
require 'base64'
module Aspera
  module OAuth
    # Factory to create tokens and manage their cache
    class Factory
      include Singleton

      # a prefix for persistency of tokens (simplify garbage collect)
      PERSIST_CATEGORY_TOKEN = 'token'
      # prefix for bearer authorization when in header
      SPACE_BEARER_AUTH_SCHEME = 'Bearer '
      TOKEN_FIELD = 'access_token'

      private_constant :PERSIST_CATEGORY_TOKEN, :SPACE_BEARER_AUTH_SCHEME

      class << self
        # @param token [String] The token alone
        # @return [String] Value suitable for Authorization header
        def bearer_authorization(token)
          return "#{SPACE_BEARER_AUTH_SCHEME}#{token}"
        end

        # @return true if the authorization contains a bearer token , i.e. auth scheme is bearer
        def bearer_auth?(authorization)
          return authorization.start_with?(SPACE_BEARER_AUTH_SCHEME)
        end

        # Extract only token from Authorization (remove scheme)
        def bearer_token(authorization)
          Aspera.assert(bearer_auth?(authorization)){'not a bearer token, wrong prefix scheme'}
          return authorization[SPACE_BEARER_AUTH_SCHEME.length..-1]
        end

        # @return a unique cache identifier
        def cache_id(url, creator_class, *params)
          return IdGenerator.from_list([
            PERSIST_CATEGORY_TOKEN,
            url,
            Factory.class_to_id(creator_class)
          ] +
            params)
        end

        # @return snake version of class name
        def class_to_id(creator_class)
          return creator_class.name.split('::').last.capital_to_snake.to_sym
        end
      end

      private

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

      def persist_mgr=(manager)
        @persist = manager
        # cleanup expired tokens
        @persist.garbage_collect(PERSIST_CATEGORY_TOKEN, @parameters[:token_cache_max_age])
      end

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

      # delete all existing tokens
      def flush_tokens
        persist_mgr.garbage_collect(PERSIST_CATEGORY_TOKEN)
      end

      def persisted_tokens
        data = persist_mgr.current_items(PERSIST_CATEGORY_TOKEN)
        data.each.map do |k, v|
          info = {id: k}
          info.merge!(JSON.parse(v)) rescue nil
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

      # register a bearer token decoder, mainly to inspect expiry date
      def register_decoder(method)
        @decoders.push(method)
      end

      # decode token using all registered decoders
      def decode_token(token)
        @decoders.each do |decoder|
          result = decoder.call(token) rescue nil
          return result unless result.nil?
        end
        return
      end

      # register a token creation method
      # @param id creation type from field :grant_method in constructor
      # @param lambda_create called to create token
      # @param id_create called to generate unique id for token, for cache
      def register_token_creator(creator_class)
        Aspera.assert_type(creator_class, Class)
        id = Factory.class_to_id(creator_class)
        Log.log.debug{"registering token creator #{id}"}
        @token_type_classes[id] = creator_class
      end

      # @return one of the registered creators for the given create type
      def create(**parameters)
        Aspera.assert_type(parameters, Hash)
        id = parameters[:grant_method]
        Aspera.assert(@token_type_classes.key?(id)){"token grant method unknown: '#{id}'"}
        create_parameters = parameters.reject{ |k, _v| k.eql?(:grant_method)}
        @token_type_classes[id].new(**create_parameters)
      end
    end
    # JSON Web Signature (JWS) compact serialization: https://datatracker.ietf.org/doc/html/rfc7515
    Factory.instance.register_decoder(lambda{ |token| parts = token.split('.'); Aspera.assert(parts.length.eql?(3)){'not JWS token'}; JSON.parse(Base64.decode64(parts[1]))}) # rubocop:disable Style/Semicolon
  end
end
