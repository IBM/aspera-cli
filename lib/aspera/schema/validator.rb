# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'registry'
require 'singleton'
require 'json'

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
        # Compiled documents, key: [registry key, partial], value: [document of the registry, compiled document]
        @documents = {}
      end

      # Validate a value against a schema.
      # @param value   [Object]  value to validate
      # @param path    [String]  schema path, e.g. `opts:components.schemas.HttpOptions`
      # @param partial [Boolean] `true`: value may be incomplete, `required` is not enforced, the selector of variants (`discriminator`) may be missing
      # @param ignore_null [Boolean] `true`: `null` values (removal of an entry) are ignored, as if absent
      # @return [Array<String>] error messages, empty if valid or schema not validated
      def errors(value, path, partial: false, ignore_null: partial)
        return [] unless path.is_a?(String) && Registry.owned?(path)
        key, dotted = path.split(':', 2)
        schema = document(key, partial)
        schema = schema.ref("#/#{dotted.split('.').map { |s| s.gsub('~', '~0').gsub('/', '~1') }.join('/')}") if dotted
        # JSON view of value: symbol keys and values become strings
        data = JSON.parse(JSON.generate(value))
        data = without_null(data) if ignore_null
        results = schema.validate(data).to_a
        results.reject { |error| unreliable_unevaluated?(error, results) }.filter_map { |error| message(error, partial) }
      end

      private

      # @param key     [String]  registry key
      # @param partial [Boolean] remove `required` from schema
      # @return [JSONSchemer::Schema] compiled schema document, compiled again when the registry reads the document again (see `Registry#reader`)
      def document(key, partial)
        source = Registry.instance.reader(key).current
        compiled_source, compiled = @documents[[key, partial]]
        return compiled if compiled_source.equal?(source)
        require 'json_schemer'
        root = partial ? without_required(source) : source
        meta =
          case root['openapi']
          when /^3\.0\./ then JSONSchemer.openapi30
          when /^3\.1\./ then JSONSchemer.openapi31
          end
        compiled = meta ? JSONSchemer.schema(root, meta_schema: meta) : JSONSchemer.schema(root)
        @documents[[key, partial]] = [source, compiled]
        compiled
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

      # A key refused by `unevaluatedProperties` is unknown only if the variants of the object are evaluated without error.
      # Else (selector of variants missing or invalid, or error in the variant), no key of the variant is evaluated, and all are refused.
      # @param error   [Hash]        json_schemer error
      # @param results [Array<Hash>] All errors of the validation
      # @return [Boolean] `true` if the error is a key refused by `unevaluatedProperties` while the object has another error
      def unreliable_unevaluated?(error, results)
        return false unless error['schema_pointer'].end_with?('/unevaluatedProperties')
        object = error['data_pointer'].sub(%r{/[^/]*\z}, '')
        results.any? do |other|
          !other['schema_pointer'].eql?(error['schema_pointer']) &&
            (other['data_pointer'].eql?(object) || other['data_pointer'].start_with?("#{object}/"))
        end
      end

      # @param error   [Hash]    json_schemer error
      # @param partial [Boolean] partial validation
      # @return [String, nil] message, or nil if error is ignored
      def message(error, partial)
        # Same message for both ways of refusing other keys
        return "object property at `#{error['data_pointer']}` is a disallowed additional property" if error['schema_pointer'].end_with?('/unevaluatedProperties')
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
