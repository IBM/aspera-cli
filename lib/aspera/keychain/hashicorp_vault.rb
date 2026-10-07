# frozen_string_literal: true

require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/keychain/base'
require 'vault'

module Aspera
  module Keychain
    # Manage secrets in a Hashicorp Vault
    class HashicorpVault < Base
      STORE_PATH = 'secret/data/'

      private_constant :STORE_PATH

      def initialize(url:, token:)
        super()
        Vault.configure do |config|
          config.address = url
          config.token = token
        end
      end

      def info
        {
          url:      Vault.address,
          password: Vault.auth_token
        }
      end

      def all
        metadata_path = STORE_PATH.sub('/data/', '/metadata/')
        return Vault.logical.list(metadata_path).filter_map do |label|
          # KV v2: deleted secrets are still listed in metadata
          get(label: label, exception: false)&.merge(label: label)
        end
      end

      # Set a secret
      # @param options [Hash] with keys :label, :username, :password, :url, :description
      def set(options)
        validate_set(options)
        label = options.fetch(:label)
        assert_new_label(label)
        data = {
          username:    options[:username],
          password:    options[:password],
          url:         options[:url],
          description: options[:description]
        }.compact
        Vault.logical.write(path(label), data: data)
      end

      def get(label:, exception: true)
        # KV v2: a deleted secret may have metadata but no data
        data = Vault.logical.read(path(label))&.data&.[](:data)
        if data.nil?
          raise "Secret '#{label}' not found" if exception
          return
        end
        return data
      end

      def delete(label:)
        path = path(label)
        Vault.logical.delete(path)
      end

      private

      def path(label)
        "#{STORE_PATH}#{label}"
      end
    end
  end
end
