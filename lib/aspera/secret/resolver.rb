# frozen_string_literal: true

require 'aspera/secret/reference'
require 'aspera/secret/store/hashicorp_vault'
require 'aspera/secret/store/encrypted_hash'
require 'aspera/secret/hider'

module Aspera
  module Secret
    # Reads the values of references from named stores, with a cache.
    #
    # Configuration (e.g. from a YAML file):
    # - `cache_ttl`: time in seconds a value is kept in memory (default: 60, 0: no cache)
    # - `stores`: name of store → parameters of store, with `type` (see `register_type`), parameters: `REFERENCE_PARAMETERS` of class of type
    #
    # Bootstrap secrets of stores (token, password) are read from files (`*_file` keys), not given in configuration.
    # Error messages give the reference, never a value.
    class Resolver
      DEFAULT_CACHE_TTL = 60
      CONFIG_KEYS = %w[cache_ttl stores].freeze
      STORE_NAME = /\A[A-Za-z0-9_.-]+\z/
      private_constant :CONFIG_KEYS, :STORE_NAME

      # Types of store: name → class
      @types = {
        'vault' => Store::HashicorpVault,
        'file'  => Store::EncryptedHash
      }

      class << self
        # Add a type of store, e.g. from the host application
        # @param name  [String] Value of `type` in configuration
        # @param klass [Class]  Subclass of `Store::Base` with `REFERENCE_PARAMETERS`, created with parameters of store as keyword arguments
        def register_type(name, klass)
          Aspera.assert(klass <= Store::Base) { "#{klass} shall be a subclass of #{Store::Base}" }
          @types[name.to_s] = klass
          nil
        end

        # @return [Hash<String,Class>] Types of store
        def types
          @types.dup
        end
      end

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
        @stores = stores.to_h { |name, params| [name.to_s, create_store(name.to_s, params)] }.freeze
        # Key of reference → [value, monotonic time of expiry]
        @cache = {}
        @lock = Mutex.new
      end

      # @return [Array<String>] Names of stores
      def store_names
        @stores.keys
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

      # @return [Store::Base] New store from its parameters
      def create_store(name, params)
        raise Error, 'invalid name' unless STORE_NAME.match?(name)
        raise Error, 'expecting a Hash' unless params.is_a?(Hash)
        params = params.transform_keys(&:to_sym)
        type = params.delete(:type).to_s
        klass = self.class.types[type]
        raise Error, "type: #{type.empty? ? 'missing' : "unknown #{type}"}, use one of: #{self.class.types.keys.join(', ')}" if klass.nil?
        klass.check_reference_parameters(params)
        klass.new(**params)
      rescue StandardError => e
        raise Error, "secret references configuration: store #{name}: #{e.message}"
      end

      # Checks reference and calls block with its store
      # @yieldparam store [Store::Base]
      # @return [Object] Value of block
      def access(ref)
        store = @stores[ref.store]
        raise Error, "unknown store #{ref.store}" if store.nil?
        store.check_reference(ref)
        yield(store)
      rescue StandardError => e
        raise Error, "secret reference #{ref.text}: #{reason(e)}"
      end

      # @return [String] Reason of failure, without secret
      def reason(error)
        case error
        when Error then error.message
        when ::Vault::HTTPError then "Vault: #{error.code}#{" #{error.errors.join(', ')}" unless error.errors.empty?}"
        when ::Vault::HTTPConnectionError then "Vault: cannot connect to #{error.address}: #{error.original_exception.message}"
        else Secret::Hider.instance.hide_secrets_in_string("#{error.class}: #{error.message}", all: true)
        end
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
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
