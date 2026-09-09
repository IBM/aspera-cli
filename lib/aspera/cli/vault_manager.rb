# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/log'
require 'aspera/assert'
require 'json'

module Aspera
  module Cli
    # Mixin providing vault/keychain functionality to Plugin::Config.
    # Depends on `options` and `context.main_folder` being available in the including class.
    module VaultManager
      def action_vault_show(label:, id: nil, **)
        v = vault_required
        kwargs = id && v.method(:get).parameters.any?{ |_t, n| n == :id} ? {id: id} : {}
        Result::SingleObject.new(v.get(label: label, **kwargs))
      end

      def action_vault_create(info:, **)
        vault_required.set(info.symbolize_keys)
        Result::Status.new('Secret added')
      end

      # Import secrets from a JSON array; skips entries missing :label
      def action_vault_import(secrets:, **)
        is_bulk = options.get_option(:bulk)
        bfail   = options.get_option(:bfail)
        Result.bulk(secrets, is_bulk: is_bulk, command: :import, id_result: 'label', bfail: bfail) do |entry|
          vault_required.set(entry.symbolize_keys)
          {'label' => entry['label'] || entry[:label]}
        end
      end

      def action_vault_delete(label:, id: nil, **)
        v = vault_required
        kwargs = id && v.method(:delete).parameters.any?{ |_t, n| n == :id} ? {id: id} : {}
        v.delete(label: label, **kwargs)
        Result::Status.new("Secret deleted: #{label}")
      end

      def action_vault_password(new_password:, **)
        Aspera.assert(vault_required.respond_to?(:change_password), 'Vault does not support password change')
        vault_required.change_password(new_password)
        Result::Status.new('Vault password updated')
      end

      # @return [Keychain::Base] vault instance, raises if not configured
      def vault_required
        Aspera.assert(!vault.nil?, type: Cli::BadArgument){'Missing mandatory option: vault'}
        vault
      end

      # @return [String] value from vault matching <name>.<param>
      def vault_value(name)
        m = name.split('.')
        Aspera.assert(m.length.eql?(2), type: BadArgument){'vault name shall match <name>.<param>'}
        info = vault_required.get(label: m[0])
        value = info[m[1].to_sym]
        raise "no such entry value: #{m[1]}" if value.nil?
        return value
      end

      # @return [Keychain::Base, nil] vault instance, lazily created from options, or nil if not configured
      def vault
        return @vault_instance if @vault_instance_initialized
        @vault_instance_initialized = true
        info = options.get_option(:vault, mandatory: false)
        return @vault_instance = nil if info.nil? || (info.is_a?(Hash) && info.empty?)
        info = info.symbolize_keys
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
