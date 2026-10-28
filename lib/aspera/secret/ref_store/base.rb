# frozen_string_literal: true

require 'aspera/secret/reference'

module Aspera
  module Secret
    module RefStore
      # Base class of stores of secrets.
      # A subclass implements `read`, and may extend `check!` and `OPTIONS`.
      # Errors are raised with the reason only, `Resolver` adds the reference.
      class Base
        # Options accepted in references
        OPTIONS = [].freeze

        # @return [String] Name of store in configuration
        attr_reader :name

        # @param name [String] Name of store in configuration
        def initialize(name:)
          @name = name
        end

        # Checks before access: options of reference, paths allowed by configuration
        # @param ref [Reference]
        # @raise [Error] Reference not allowed
        def check!(ref)
          unsupported = ref.options.keys - self.class::OPTIONS
          raise Error, "unsupported options: #{unsupported.join(', ')}" unless unsupported.empty?
        end

        # @param ref [Reference]
        # @return [String] Value of secret
        def fetch(ref)
          read(ref)[:value]
        end

        # @param ref [Reference]
        # @return [Hash] `version` (`nil` if store has no version), `updated_time` (`Time` or `nil`): checks that the secret can be read, no value
        def metadata(ref)
          read(ref).except(:value)
        end

        private

        # @param ref [Reference]
        # @return [Hash] `value` (`String`), `version`, `updated_time`
        def read(ref)
          raise NotImplementedError, "#{self.class}: read"
        end

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
