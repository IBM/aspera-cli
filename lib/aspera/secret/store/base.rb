# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/secret/reference'

module Aspera
  module Secret
    module Store
      # Base class of stores of secrets, created by `Factory` from parameters: management by label, and read by reference (`Secret::Resolver`).
      # For references, errors are raised with the reason only, `Resolver` adds the reference.
      class Base
        CONTENT_KEYS = %i[label username password url description].freeze
        # Parameters of store: keyword arguments of `new`.
        # Secrets to access the store: the value, or `@file:<path>` (`Secret::Bootstrap`), when the type supports it.
        PARAMETERS = [].freeze
        # Options accepted in references
        REFERENCE_OPTIONS = [].freeze
        # Field of secret when the reference has none
        DEFAULT_FIELD = 'password'
        private_constant :DEFAULT_FIELD

        class << self
          # Checks the parameters of store
          # @param params [Hash] Parameters, Symbol keys
          # @raise [Error] Unsupported parameter
          def check_parameters(params)
            unsupported = params.keys - self::PARAMETERS
            raise Error, "unsupported keys: #{unsupported.join(', ')}" unless unsupported.empty?
          end

          # @param params [Hash] Parameters of store, checked, Symbol keys
          # @return [Hash] Keyword arguments of `new`
          # @raise [Error] Invalid parameter
          def arguments(params)
            params
          end

          # @param _error [StandardError] Error raised by the store
          # @return [String, nil] Reason of failure without secret, `nil` if the error is not specific to the type
          def error_reason(_error)
            nil
          end
        end

        # Returns a lightweight list: one Hash per secret with :label (and :id if the backend has one).
        # Override in subclasses that can provide this cheaply without fetching full item details.
        def ids
          all.map { |s| s.slice(:id, :label).compact }
        end

        def validate_set(options)
          Aspera.assert_type(options, Hash) { 'options' }
          unsupported = options.keys - CONTENT_KEYS
          Aspera.assert(unsupported.empty?) { "unsupported options: #{unsupported}, use #{CONTENT_KEYS.join(', ')}" }
          options.each_pair do |k, v|
            Aspera.assert_type(v, String) { k.to_s }
          end
          Aspera.assert(options.key?(:label), 'label is required')
        end

        # Labels are unique: `set` does not overwrite an existing secret
        def assert_new_label(label)
          Aspera.assert(get(label: label, exception: false).nil?) { "secret #{label} already exist, delete first" }
        end

        # Checks before access: options of reference, paths allowed by configuration
        # @param ref [Reference]
        # @raise [Error] Reference not allowed
        def check_reference(ref)
          unsupported = ref.options.keys - self.class::REFERENCE_OPTIONS
          raise Error, "unsupported options: #{unsupported.join(', ')}" unless unsupported.empty?
        end

        # Read a secret by reference: the path is the label, the field is `password` by default
        # @param ref [Reference]
        # @return [Hash] `value` (`String`), `version` (`nil` if store has no version), `updated_time` (`Time` or `nil`)
        def read_reference(ref)
          entry = get(label: ref.path, exception: false)
          raise Error, "no label: #{ref.path}" if entry.nil?
          {value: field_value(entry, ref, default: DEFAULT_FIELD), version: nil, updated_time: nil}
        end

        # Write a new secret by reference.
        # Subclasses that support writing must override this method.
        # @param _ref    [Reference]          Reference (field is nil)
        # @param _fields [Hash<String,String>] Field name → value
        # @return [Hash] `version` (`Integer` or `nil`), `updated_time` (`Time` or `nil`)
        # @raise [Error] Always — writing is not supported by this store type
        def write_reference(_ref, _fields)
          raise Error, 'writing not supported by store type'
        end

        private

        # @param data    [Hash]        Fields of secret, keys String or Symbol
        # @param ref     [Reference]   Reference with field
        # @param default [String, nil] Field when reference has none, `nil`: field required
        # @return [String] Value of field
        def field_value(data, ref, default: nil)
          field = ref.field || default
          raise Error, 'field required: #<field>' if field.nil?
          value = data.key?(field.to_sym) ? data[field.to_sym] : data[field]
          case value
          when nil then raise Error, "no field: #{field}"
          when String then value
          when Numeric, true, false then value.to_s
          else raise Error, "field #{field} is not a string"
          end
        end
      end
    end
  end
end
