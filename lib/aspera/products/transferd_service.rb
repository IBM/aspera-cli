# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'aspera/assert'
require 'aspera/yaml'
require 'aspera/schema/registry'

module Aspera
  module Products
    # Run the transfer daemon as a system service: configuration of `transferd.json`
    class TransferdService
      # Number of random bytes of a generated API key
      API_KEY_BYTES = 32
      private_constant :API_KEY_BYTES

      class << self
        # Build the content of `transferd.json`.
        # Order of precedence: values computed from `sdk_folder`, then `existing`, then `overrides`.
        # A key set to `nil` in `overrides` is removed.
        # @param existing   [Hash, nil] Content of the existing configuration file, `nil` or empty if none
        # @param overrides  [Hash]      Values given by the user (section `config` of the user parameter)
        # @param sdk_folder [String]    Folder of the SDK, used for `fasp_runtime`
        # @param file       [String,nil] Path of the existing file, for error messages
        # @return [Hash] Validated configuration, with String keys
        # @raise [ParameterError] if the result does not conform to the schema of the daemon
        def config(existing, overrides, sdk_folder, file: nil)
          Aspera.assert_type(existing, Hash, NilClass) { 'existing' }
          Aspera.assert_type(overrides, Hash) { 'overrides' }
          Aspera.assert_type(sdk_folder, String) { 'sdk_folder' }
          existing = json_hash(existing || {})
          computed = {
            'fasp_runtime' => {
              'use_embedded' => false,
              'user_defined' => {'bin' => sdk_folder, 'etc' => sdk_folder}
            }
          }
          result = merge(merge(computed, existing), json_hash(overrides))
          auth = result['authentication']
          auth['api_key'] = SecureRandom.hex(API_KEY_BYTES) if auth.is_a?(Hash) && auth['enabled'].eql?(true) && !auth.key?('api_key')
          errors = validate(result, existing, file)
          Aspera.assert(errors.empty?, type: ParameterError) { "Invalid transferd configuration:\n#{errors.join("\n")}" }
          return result
        end

        private

        # @param value [Object] Value with Symbol or String keys
        # @return [Object] JSON view of value: String keys
        def json_hash(value)
          JSON.parse(JSON.generate(value))
        end

        # Deep merge, entries set to `nil` in `over` are removed
        # @param base [Hash] Initial values
        # @param over [Hash] Values to apply
        # @return [Hash] New Hash
        def merge(base, over)
          over.each_with_object(base.dup) do |(key, value), result|
            if value.nil?
              result.delete(key)
            elsif value.is_a?(Hash)
              result[key] = merge(result[key].is_a?(Hash) ? result[key] : {}, value)
            else
              result[key] = value
            end
          end
        end

        # @return [JSONSchemer::Schema] compiled schema of `transferd.json`
        def schema
          @schema ||=
            begin
              require 'json_schemer'
              # JSON is read with the YAML loader: it accepts the header comment added by `rake tools:openapi`
              path = File.join(File.expand_path('../..', __dir__), Schema::Registry::LOCATIONS[:transferd])
              JSONSchemer.schema(Yaml.safe_load(File.read(path)))
            end
        end

        # @param config   [Hash]        Configuration to validate
        # @param existing [Hash]        Content of the existing file
        # @param file     [String, nil] Path of the existing file
        # @return [Array<String>] error messages, empty if valid
        def validate(config, existing, file)
          schema.validate(config).map do |error|
            # tell the user when the faulty value comes from a file that was not written by this call
            path = error['data_pointer'].to_s.split('/').drop(1)
            origin = file && in_hash?(existing, path) ? " (existing file: #{file})" : ''
            "#{error['error']}#{origin}"
          end
        end

        # @param hash [Hash]  Hash to look into
        # @param path [Array] Keys of nested Hashes
        # @return [Boolean] `true` if the path exists in hash
        def in_hash?(hash, path)
          return false if path.empty?
          path.reduce(hash) do |node, key|
            return false unless node.is_a?(Hash) && node.key?(key)
            node[key]
          end
          true
        end
      end
    end
  end
end
