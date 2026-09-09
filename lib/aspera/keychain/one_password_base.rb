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
      # Accepts both API Connect items (field keyed by 'id') and CLI items
      # (field keyed by 'id' falling back to 'label').
      def item_to_secret(item)
        fields = Array(item['fields']).to_h{ |f| [f['id'] || f['label'], f['value']]}
        secret = {label: item['title']}
        secret[:username]    = fields[FIELD_USERNAME] unless fields[FIELD_USERNAME].nil?
        secret[:password]    = fields[FIELD_PASSWORD] unless fields[FIELD_PASSWORD].nil?
        secret[:url]         = fields[FIELD_URL]      unless fields[FIELD_URL].nil?
        secret[:description] = fields[FIELD_NOTES_ID] unless fields[FIELD_NOTES_ID].nil?
        return secret
      end
    end
  end
end
