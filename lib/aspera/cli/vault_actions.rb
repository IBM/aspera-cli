# frozen_string_literal: true

require 'aspera/cli/result'
require 'aspera/assert'

module Aspera
  module Cli
    # Mixin for Config plugin: `config vault` actions, on the default store of `context.vault` (`VaultManager`)
    module VaultActions
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

      # Checks a reference to a store of option `vault`, without its value
      # @param reference [String] `@vault://<store>/<path>[?<options>][#<field>]`, or without `@vault:`
      def action_vault_check(reference:, **)
        Result::SingleObject.new(context.vault.metadata(reference.delete_prefix('@vault:')))
      end

      # @return [Secret::Store::Base, nil] Default store of option `vault`, `nil` if not configured
      def vault
        context.vault.store
      end

      # @return [Secret::Store::Base] Default store of option `vault`, raises if not configured
      def vault_required
        context.vault.store(mandatory: true)
      end
    end
  end
end
