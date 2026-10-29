# frozen_string_literal: true

module Aspera
  module Secret
    module Store
      # Factory to create vault instances
      class Factory
        LIST = %i[file system vault 1password].freeze
        class << self
          # Create a vault instance
          # @param info     [Hash]   vault options
          # @param name     [String] name of the vault
          # @param folder   [String] folder to store the vault (if needed)
          # @param password [String] password to open the vault
          def create(info, name, folder, password)
            info = info.symbolize_keys
            vault_type = info.delete(:type)
            # Only `approle` of type `vault` is a structure
            Aspera.assert_hash_all(vault_type.eql?('vault') ? info.except(:approle) : info, Symbol, String) { 'vault info shall have only string values' }
            case vault_type
            when 'file'
              # `name` (or `file`), default: `vault.bin`
              info[:file] = info.delete(:name) || info[:file] || 'vault.bin'
              info[:file] = File.join(folder, info[:file]) unless File.absolute_path?(info[:file])
              Aspera.assert(!password.nil?, 'please provide password')
              info[:password] = password
              # this module requires compilation, so it is optional
              require 'aspera/secret/store/encrypted_hash'
              Secret::Store::EncryptedHash.new(**info)
            when 'system'
              case Environment.instance.os
              when Environment::OS_MACOS
                info[:name] ||= name
                Secret::Store::MacosSystem.new(**info)
              else
                raise Error, 'not implemented for this OS'
              end
            when 'vault'
              require 'aspera/secret/store/hashicorp_vault'
              info[:token] ||= password unless info.key?(:approle)
              Secret::Store::HashicorpVault.new(**info)
            when '1password'
              source = info.delete(:source) || 'api'
              case source
              when 'api'
                require 'aspera/secret/store/one_password_api'
                info[:token] ||= password
                Secret::Store::OnePasswordApi.new(**info)
              when 'cli'
                require 'aspera/secret/store/one_password_cli'
                Secret::Store::OnePasswordCli.new(**info)
              else Aspera.error_unexpected_value(source, type: ParameterError) { 'vault.source' }
              end
            else Aspera.error_unexpected_value(vault_type, type: ParameterError) { 'vault.type' }
            end
          end
        end
      end
    end
  end
end
