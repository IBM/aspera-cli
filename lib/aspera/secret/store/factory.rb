# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/secret/reference'
require 'aspera/secret/store/base'

module Aspera
  module Secret
    module Store
      # Creates stores of secrets from their parameters: `type`, and parameters of the class of type (`PARAMETERS`).
      # Types: `file`, `vault`, `system` (macOS), `1password` (`source`: `api` or `cli`), and types added with `register_type`.
      class Factory
        BUILTIN_TYPES = %w[file vault system 1password].freeze
        ONE_PASSWORD_SOURCES = %w[api cli].freeze
        private_constant :BUILTIN_TYPES, :ONE_PASSWORD_SOURCES

        # Types added by the application: name → class
        @types = {}

        class << self
          # Add a type of store, e.g. from the host application
          # @param name  [String] Value of `type` in parameters
          # @param klass [Class]  Subclass of `Base` with `PARAMETERS`, created with parameters of store as keyword arguments
          def register_type(name, klass)
            Aspera.assert(klass.is_a?(Class) && klass <= Base) { "#{klass} shall be a subclass of #{Base}" }
            @types[name.to_s] = klass
            nil
          end

          # @return [Array<String>] Names of types
          def types
            (BUILTIN_TYPES + @types.keys).uniq
          end

          # Checks the type and the names of parameters, without creating the store
          # @param params [Hash] `type` and parameters of store, keys String or Symbol
          # @raise [Error] Unknown type, or unsupported parameter
          def check(params)
            checked(params)
            nil
          end

          # @param params [Hash] `type` and parameters of store, keys String or Symbol
          # @return [Base] New store
          # @raise [Error] Invalid parameters
          def create(params)
            klass, params = checked(params)
            klass.new(**klass.arguments(params))
          end

          private

          # @param params [Hash] `type` and parameters of store
          # @return [Array(Class, Hash)] Class of store, and its parameters (Symbol keys, without `type`, and `source` of `1password`)
          def checked(params)
            raise Error, 'expecting a Hash' unless params.is_a?(Hash)
            params = params.transform_keys(&:to_sym)
            type = params.delete(:type).to_s
            source = params.delete(:source) if type.eql?('1password')
            klass = store_class(type, source)
            klass.check_parameters(params)
            [klass, params]
          end

          # @param type   [String]      Type of store
          # @param source [String, nil] Source of `1password`
          # @return [Class] Class of store, its file is required
          def store_class(type, source)
            return @types[type] if @types.key?(type)
            case type
            when 'file'
              # this module requires compilation, so it is optional
              require 'aspera/secret/store/encrypted_hash'
              EncryptedHash
            when 'vault'
              require 'aspera/secret/store/hashicorp_vault'
              HashicorpVault
            when 'system'
              require 'aspera/secret/store/macos_security'
              MacosSystem
            when '1password'
              source ||= 'api'
              raise Error, "source: unknown #{source}, use one of: #{ONE_PASSWORD_SOURCES.join(', ')}" unless ONE_PASSWORD_SOURCES.include?(source)
              require "aspera/secret/store/one_password_#{source}"
              source.eql?('api') ? OnePasswordApi : OnePasswordCli
            else raise Error, "type: #{type.empty? ? 'missing' : "unknown #{type}"}, use one of: #{types.join(', ')}"
            end
          end
        end
      end
    end
  end
end
