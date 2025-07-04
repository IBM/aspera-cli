# frozen_string_literal: true

module Aspera
  module Keychain
    # Manage secrets in a Hashicorp Vault
    class Factory
      LIST = %i[file system vault].freeze
      class << self
        def create(info, name, folder, password)
          Aspera.assert_type(info, Hash)
          Aspera.assert(info.values.all?(String)){'vault info shall have only string values'}
          info = info.symbolize_keys
          vault_type = info.delete(:type)
          Aspera.assert_values(vault_type, LIST.map(&:to_s)){'vault.type'}
          case vault_type
          when 'file'
            info[:file] ||= 'vault.bin'
            info[:file] = File.join(folder, info[:file]) unless File.absolute_path?(info[:file])
            Aspera.assert(!password.nil?){'please provide password'}
            info[:password] = password
            # this module requires compilation, so it is optional
            require 'aspera/keychain/encrypted_hash'
            @vault = Keychain::EncryptedHash.new(**info)
          when 'system'
            case Environment.os
            when Environment::OS_MACOS
              info[:name] ||= name
              @vault = Keychain::MacosSystem.new(**info)
            else
              raise 'not implemented for this OS'
            end
          when 'vault'
            require 'aspera/keychain/hashicorp_vault'
            @vault = Keychain::HashicorpVault.new(**info)
          else Aspera.error_unexpected_value(vault_type)
          end
        end
      end
    end
  end
end
