# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # Mixin providing vault/keychain functionality to Plugin::Config.
    # Depends on `options` and `context.main_folder` being available in the including class.
    module VaultManager
      def action_vault_show(label:, **)
        Result::SingleObject.new(vault.get(label: label))
      end

      def action_vault_create(info:, **)
        vault.set(info.symbolize_keys)
        Result::Status.new('Secret added')
      end

      def action_vault_delete(label:, **)
        vault.delete(label: label)
        Result::Status.new("Secret deleted: #{label}")
      end

      def action_vault_password(new_password:, **)
        Aspera.assert(vault.respond_to?(:change_password), 'Vault does not support password change')
        vault.change_password(new_password)
        Result::Status.new('Vault password updated')
      end

      # @return [String] value from vault matching <name>.<param>
      def vault_value(name)
        m = name.split('.')
        raise BadArgument, 'vault name shall match <name>.<param>' unless m.length.eql?(2)
        info = vault.get(label: m[0])
        value = info[m[1].to_sym]
        raise "no such entry value: #{m[1]}" if value.nil?
        return value
      end

      # @return [Keychain::Base] vault instance, lazily created from options
      def vault
        return @vault_instance unless @vault_instance.nil?
        info = options.get_option(:vault, mandatory: true).symbolize_keys
        info[:type] ||= 'file'
        require 'aspera/keychain/factory'
        @vault_instance = Keychain::Factory.create(
          info,
          Info::CMD_NAME,
          context.main_folder,
          options.get_option(:vault_password)
        )
      end
    end
  end
end
