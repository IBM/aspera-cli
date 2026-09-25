# frozen_string_literal: true

require 'singleton'
require 'json'
require 'aspera/schema/registry'

module Aspera
  module Schema
    # Validate values against the JSON schemas of the registry.
    # Only schemas owned by ascli are validated: vendor API schemas are checked by the API itself.
    # @!method self.instance
    #   Returns the singleton instance of Validator
    #   @return [Validator] the singleton instance
    class Validator
      include Singleton

      def initialize
        # compiled documents, key: [registry key, partial]
        @documents = {}
      end

      # Validate a value against a schema.
      # @param value   [Object]  value to validate
      # @param path    [String]  schema path, e.g. `opts:components.schemas.HttpOptions`
      # @param partial [Boolean] `true`: value may be incomplete, `required` is not enforced, `null` values (removal) are ignored
      # @return [Array<String>] error messages, empty if valid or schema not validated
      def errors(value, path, partial: false)
        return [] unless path.is_a?(String) && Registry.owned?(path)
        key, dotted = path.split(':', 2)
        schema = document(key, partial)
        schema = schema.ref("#/#{dotted.split('.').map { |s| s.gsub('~', '~0').gsub('/', '~1') }.join('/')}") if dotted
        # JSON view of value: symbol keys and values become strings
        data = JSON.parse(JSON.generate(value))
        data = without_null(data) if partial
        schema.validate(data).filter_map { |error| message(error, partial) }
      end

      private

      # @param key     [String]  registry key
      # @param partial [Boolean] remove `required` from schema
      # @return [JSONSchemer::Schema] compiled schema document
      def document(key, partial)
        @documents[[key, partial]] ||=
          begin
            require 'json_schemer'
            root = Registry.instance.reader(key).current
            root = without_required(root) if partial
            meta =
              case root['openapi']
              when /^3\.0\./ then JSONSchemer.openapi30
              when /^3\.1\./ then JSONSchemer.openapi31
              end
            meta ? JSONSchemer.schema(root, meta_schema: meta) : JSONSchemer.schema(root)
          end
      end

      # @param node [Object] schema node
      # @return [Object] copy of node without `required` lists
      def without_required(node)
        case node
        when Hash then node.each_with_object({}) { |(k, v), h| h[k] = without_required(v) unless k.eql?('required') && v.is_a?(Array) }
        when Array then node.map { |e| without_required(e) }
        else node
        end
      end

      # @param node [Object] JSON value
      # @return [Object] copy of node without Hash entries whose value is `null` (entry removal requested by user)
      def without_null(node)
        case node
        when Hash then node.each_with_object({}) { |(k, v), h| h[k] = without_null(v) unless v.nil? }
        when Array then node.map { |e| without_null(e) }
        else node
        end
      end

      # @param error   [Hash]    json_schemer error
      # @param partial [Boolean] partial validation
      # @return [String, nil] message, or nil if error is ignored
      def message(error, partial)
        return error['error'] unless error['type'].eql?('discriminator')
        property = error['schema'].dig('discriminator', 'propertyName')
        object = error['data']
        # Partial value: selector may come from another source or a default
        return if partial && object.is_a?(Hash) && !object.key?(property)
        allowed = error['schema'].dig('discriminator', 'mapping')&.keys
        "value at `#{error['data_pointer']}/#{property}` is not one of: #{allowed}"
      end
    end
  end
end
