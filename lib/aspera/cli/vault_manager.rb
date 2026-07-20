# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # Mixin providing vault/keychain functionality to Plugin::Config.
    # Depends on `options` and `@main_folder` being available in the including class.
    module VaultManager
      # @return [Result] result of vault sub-command
      def execute_vault
        command = options.get_next_command(%i[info list show create delete password])
        case command
        when :info
          return Result::SingleObject.new(vault.info)
        when :list
          return Result::ObjectList.new(vault.list)
        when :show
          return Result::SingleObject.new(vault.get(label: options.get_next_argument('label')))
        when :create
          vault.set(options.get_next_argument('info', validation: Hash).symbolize_keys)
          return Result::Status.new('Secret added')
        when :delete
          label_to_delete = options.get_next_argument('label')
          vault.delete(label: label_to_delete)
          return Result::Status.new("Secret deleted: #{label_to_delete}")
        when :password
          Aspera.assert(vault.respond_to?(:change_password), 'Vault does not support password change')
          vault.change_password(options.get_next_argument('new_password'))
          return Result::Status.new('Vault password updated')
        end
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
        info = options.get_option(:vault).symbolize_keys
        info[:type] ||= 'file'
        require 'aspera/keychain/factory'
        @vault_instance = Keychain::Factory.create(
          info,
          Info::CMD_NAME,
          @main_folder,
          options.get_option(:vault_password)
        )
      end
    end
  end
end
