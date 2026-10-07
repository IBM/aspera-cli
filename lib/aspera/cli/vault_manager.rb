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
      # Import secrets from a JSON array; skips entries missing :label
      def action_vault_import(secrets:, **)
        bulk_result(secrets, command: :import, id_result: 'label') do |entry|
          vault_required.set(entry.symbolize_keys)
          {'label' => entry['label'] || entry[:label]}
        end
      end

      def action_vault_delete(label:, id: nil, **)
        v = vault_required
        kwargs = id && v.method(:delete).parameters.any? { |_t, n| n == :id } ? {id: id} : {}
        v.delete(label: label, **kwargs)
        Result::Status.new("Secret deleted: #{label}")
      end

      # @return [Keychain::Base] vault instance, raises if not configured
      def vault_required
        Aspera.assert(!vault.nil?, type: Cli::BadArgument) { 'Missing mandatory option: vault' }
        vault
      end

      # @return [String] value from vault matching <name>.<param>
      def vault_value(name)
        # Label may contain dots (e.g. preset name)
        label, _, param = name.rpartition('.')
        Aspera.assert(!label.empty? && !param.empty?, type: BadArgument) { 'vault name shall match <name>.<param>' }
        info = vault_required.get(label: label)
        value = info[param.to_sym]
        raise "no such entry value: #{param}" if value.nil?
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
