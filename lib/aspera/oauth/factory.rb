# frozen_string_literal: true

require 'singleton'
require 'aspera/assert'
require 'base64'
module Aspera
  module OAuth
    class Factory
      include Singleton
      # a prefix for persistency of tokens (simplify garbage collect)
      PERSIST_CATEGORY_TOKEN = 'token'
      # prefix for bearer token when in header
      BEARER_PREFIX = 'Bearer '

      private_constant :PERSIST_CATEGORY_TOKEN, :BEARER_PREFIX

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

        def id(*params)
          return [PERSIST_CATEGORY_TOKEN, *params].flatten
        end

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
        @decoders = []
        @globals = {
          # remove 5 minutes to account for time offset between client and server (TODO: configurable?)
          jwt_accepted_offset_sec:    300,
          # one hour validity (TODO: configurable?)
          jwt_expiry_offset_sec:      3600,
          # tokens older than 30 minutes will be discarded from cache
          token_cache_expiry_sec:     1800,
          # tokens valid for less than this duration will be regenerated
          token_expiration_guard_sec: 120
        }
      end

      public

      attr_reader :globals

      def persist_mgr=(manager)
        @persist = manager
        # cleanup expired tokens
        @persist.garbage_collect(PERSIST_CATEGORY_TOKEN, @globals[:token_cache_expiry_sec])
      end

      def persist_mgr
        if @persist.nil?
          # use OAuth::Factory.instance.persist_mgr=PersistencyFolder.new)
          Log.log.debug('Not using persistency')
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
      def register_token_creator(creator_class)
        Aspera.assert_type(creator_class, Class)
        id = self.class.class_to_id(creator_class)
        Log.log.debug{"registering token creator #{id}"}
        @token_type_classes[id] = creator_class
      end

      # @return one of the registered creators for the given create type
      def create(**parameters)
        Aspera.assert_type(parameters, Hash)
        id = parameters[:grant_method]
        Aspera.assert(@token_type_classes.key?(id)){"token grant method unknown: '#{id}'"}
        create_parameters = parameters.reject { |k, _v| k.eql?(:grant_method) }
        @token_type_classes[id].new(**create_parameters)
      end
    end
    # JSON Web Signature (JWS) compact serialization: https://datatracker.ietf.org/doc/html/rfc7515
    Factory.instance.register_decoder(lambda { |token| parts = token.split('.'); Aspera.assert(parts.length.eql?(3)){'not aoc token'}; JSON.parse(Base64.decode64(parts[1]))}) # rubocop:disable Style/Semicolon, Layout/LineLength
  end
end
