# frozen_string_literal: true

require 'aspera/rest'
require 'aspera/keychain/one_password_base'

module Aspera
  module Keychain
    # Manage secrets using the 1Password Connect REST API
    # https://developer.1password.com/docs/connect/connect-api-reference/
    class OnePasswordApi < Base
      include OnePasswordBase

      # @param url      [String] Base URL of the 1Password Connect server (e.g. http://localhost:8080)
      # @param token    [String] Bearer token (Connect token or service-account token)
      # @param vault_id [String] ID of the 1Password vault to operate on
      def initialize(url:, token:, vault_id:)
        super()
        @vault_id = vault_id
        @api = Rest.new(
          base_url: url,
          headers:  {'Authorization' => "Bearer #{token}"}
        )
      end

      def info
        {
          url:      @api.base_url,
          vault_id: @vault_id
        }
      end

      def all
        items = @api.read("v1/vaults/#{@vault_id}/items")
        return items.map do |item|
          item_to_secret(@api.read("v1/vaults/#{@vault_id}/items/#{item['id']}")).merge(id: item['id'])
        end
      end

      def ids
        @api.read("v1/vaults/#{@vault_id}/items").map{ |item| {id: item['id'], label: item['title']}}
      end

      def set(options)
        validate_set(options)
        @api.create("v1/vaults/#{@vault_id}/items", build_item(options))
        nil
      end

      def get(label:, id: nil, exception: true)
        iid = id || resolve_id(label, exception: exception)
        return if iid.nil?
        return item_to_secret(@api.read("v1/vaults/#{@vault_id}/items/#{iid}")).merge(id: iid)
      end

      def delete(label:, id: nil)
        iid = id || resolve_id(label, exception: true)
        @api.delete("v1/vaults/#{@vault_id}/items/#{iid}")
        nil
      end

      private

      # Resolve an item id from its title; raises if ambiguous or missing
      def resolve_id(label, exception: true)
        items = @api.read("v1/vaults/#{@vault_id}/items", {filter: "title eq \"#{label}\""})
        raise "Multiple secrets found with label '#{label}': use id to disambiguate" if items.length > 1
        raise "Secret '#{label}' not found" if items.empty? && exception
        items.first&.fetch('id')
      end

      def build_item(options)
        fields = []
        fields << {'id' => FIELD_USERNAME, 'type' => 'STRING',    'value' => options[:username]}    if options[:username]
        fields << {'id' => FIELD_PASSWORD, 'type' => 'CONCEALED', 'value' => options[:password]}    if options[:password]
        fields << {'id' => FIELD_URL,      'type' => 'URL',       'value' => options[:url]}         if options[:url]
        fields << {'id' => FIELD_NOTES_ID, 'type' => 'STRING',    'value' => options[:description]} if options[:description]
        {
          'title'    => options[:label],
          'category' => ITEM_CATEGORY.upcase,
          'vault'    => {'id' => @vault_id},
          'fields'   => fields
        }
      end
    end
  end
end
