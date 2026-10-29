# frozen_string_literal: true

require 'aspera/secret/reference'
require 'aspera/secret/store/factory'
require 'aspera/secret/hider'

module Aspera
  module Secret
    # Reads the values of references from named stores, with a cache.
    #
    # Configuration (e.g. from a YAML file):
    # - `cache_ttl`: time in seconds a value is kept in memory (default: 60, 0: no cache)
    # - `stores`: name of store → parameters of store, with `type` (see `Store::Factory`)
    #
    # The type and the names of parameters are checked by `new`, a store is created when first used:
    # a store not used (e.g. its secret is not available) is not an error.
    # Bootstrap secrets of stores (`password` of type `file`, `token` and `secret_id` of type `vault`): the value, or `@file:<path>` (`Bootstrap`).
    # Error messages give the reference, never a value.
    class Resolver
      DEFAULT_CACHE_TTL = 60
      CONFIG_KEYS = %w[cache_ttl stores].freeze
      STORE_NAME = /\A[A-Za-z0-9_.-]+\z/
      private_constant :CONFIG_KEYS, :STORE_NAME

      # @param config [Hash] Configuration, keys String or Symbol
      # @raise [Error] Invalid configuration
      def initialize(config)
        raise Error, 'secret references configuration: expecting a Hash' unless config.is_a?(Hash)
        config = config.transform_keys(&:to_s)
        unsupported = config.keys - CONFIG_KEYS
        raise Error, "secret references configuration: unsupported keys: #{unsupported.join(', ')}" unless unsupported.empty?
        @cache_ttl = config.fetch('cache_ttl', DEFAULT_CACHE_TTL)
        raise Error, 'secret references configuration: cache_ttl: expecting a number >= 0' unless @cache_ttl.is_a?(Numeric) && !@cache_ttl.negative?
        stores = config.fetch('stores', nil) || {}
        raise Error, 'secret references configuration: stores: expecting a Hash' unless stores.is_a?(Hash)
        # Name of store → parameters, checked
        @parameters = stores.to_h { |name, params| [name.to_s, check_store(name.to_s, params)] }.freeze
        # Name of store → store, created when first used
        @stores = {}
        # Key of reference → [value, monotonic time of expiry]
        @cache = {}
        @lock = Mutex.new
      end

      # @return [Array<String>] Names of stores
      def store_names
        @parameters.keys
      end

      # @param name [String] Name of store
      # @return [Store::Base] Store, created when first used, e.g. to manage its secrets by label
      # @raise [Error] Unknown store, or invalid parameter
      def store(name)
        params = @parameters.fetch(name) { raise Error, "unknown store #{name}" }
        @lock.synchronize { @stores[name] ||= create_store(name, params) }
      end

      # @param text [String] Reference
      # @return [String] Value of secret, from cache if not expired
      # @raise [Error] Invalid reference, not allowed, or not readable
      def resolve(text)
        ref = Secret.parse_reference(text)
        access(ref) do |store|
          key = ref.to_h.except(:text)
          cached(key) || cache(key, ref.store, store.read_reference(ref)[:value])
        end
      end

      # Checks that a secret can be read, without its value
      # @param text [String] Reference
      # @return [Hash] `store`, `version` (`nil` if store has no version), `updated_time` (`Time` or `nil`)
      # @raise [Error] Invalid reference, not allowed, or not readable
      def metadata(text)
        ref = Secret.parse_reference(text)
        access(ref) { |store| {store: ref.store}.merge(store.read_reference(ref).except(:value)) }
      end

      # Remove values from cache, e.g. after a rotation
      # @param store_name [String, nil] Name of store, `nil`: all stores
      def invalidate(store_name = nil)
        @lock.synchronize do
          store_name.nil? ? @cache.clear : @cache.delete_if { |_, entry| entry[:store].eql?(store_name) }
        end
        nil
      end

      private

      # @return [Hash] Parameters of store, checked
      def check_store(name, params)
        raise Error, 'invalid name' unless STORE_NAME.match?(name)
        Store::Factory.check(params)
        params
      rescue StandardError => e
        raise Error, "secret references configuration: store #{name}: #{e.message}"
      end

      # @return [Store::Base] New store from its parameters
      def create_store(name, params)
        Store::Factory.create(params)
      rescue StandardError => e
        raise Error, "store #{name}: #{e.message}"
      end

      # Checks reference and calls block with its store
      # @yieldparam store [Store::Base]
      # @return [Object] Value of block
      def access(ref)
        found = store(ref.store)
        found.check_reference(ref)
        yield(found)
      rescue StandardError => e
        raise Error, "secret reference #{ref.text}: #{reason(e, found)}"
      end

      # @param error [StandardError]   Error
      # @param store [Store::Base, nil] Store that raised the error
      # @return [String] Reason of failure, without secret
      def reason(error, store)
        return error.message if error.is_a?(Error)
        store&.class&.error_reason(error) || Secret::Hider.instance.hide_secrets_in_string("#{error.class}: #{error.message}", all: true)
      end

      # @return [String, nil] Value from cache, `nil` if absent or expired
      def cached(key)
        @lock.synchronize do
          entry = @cache[key]
          next if entry.nil?
          next entry[:value] if monotonic_time < entry[:expiry]
          @cache.delete(key)
          nil
        end
      end

      # @return [String] Value, after cache and declaration to `Secret::Hider`
      def cache(key, store_name, value)
        Secret::Hider.instance.add_secret_values(value)
        @lock.synchronize { @cache[key] = {value: value, store: store_name, expiry: monotonic_time + @cache_ttl} } if @cache_ttl.positive?
        value
      end

      def monotonic_time
        ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
      end
    end
  end
end
