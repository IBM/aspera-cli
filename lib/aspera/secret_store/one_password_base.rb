# frozen_string_literal: true

require 'aspera/keychain/base'

module Aspera
  module Keychain
    # Shared field constants and item_to_secret conversion for 1Password backends.
    # Both the REST (Connect) and CLI (`op`) backends use the same JSON item schema.
    module OnePasswordBase
      FIELD_USERNAME = 'username'
      FIELD_PASSWORD = 'password'
      FIELD_URL      = 'url'
      FIELD_NOTES_ID = 'notesPlain'
      ITEM_CATEGORY  = 'Login'

      private_constant :FIELD_USERNAME, :FIELD_PASSWORD, :FIELD_URL, :FIELD_NOTES_ID, :ITEM_CATEGORY

      private

      # Convert a 1Password item JSON object to a keychain secret Hash.
      # Same JSON schema for API Connect and CLI items.
      # Built-in fields are found by `id`, custom fields (generated `id`) by `label`.
      # URL is the website of the item, or a custom field `url` (created by previous versions).
      def item_to_secret(item)
        fields = Array(item['fields'])
        by_id = fields.to_h { |f| [f['id'], f['value']] }
        by_label = fields.to_h { |f| [f['label'], f['value']] }
        urls = Array(item['urls'])
        values = {
          username:    by_id[FIELD_USERNAME] || by_label[FIELD_USERNAME],
          password:    by_id[FIELD_PASSWORD] || by_label[FIELD_PASSWORD],
          url:         (urls.find { |u| u['primary'] } || urls.first)&.[]('href') || by_id[FIELD_URL] || by_label[FIELD_URL],
          description: by_id[FIELD_NOTES_ID] || by_label[FIELD_NOTES_ID]
        }
        return {label: item['title']}.merge(values.compact)
      end
    end
  end
end
