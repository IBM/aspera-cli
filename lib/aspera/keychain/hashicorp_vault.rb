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
      SECRET_PATH = 'secret/data/'

      private_constant :SECRET_PATH

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

      def list
        metadata_path = SECRET_PATH.sub('/data/', '/metadata/')
        return Vault.logical.list(metadata_path).filter_map do |label|
          get(label: label).merge(label: label)
        end
      end

      # Set a secret
      # @param options [Hash] with keys :label, :username, :password, :url, :description
      def set(options)
        validate_set(options)
        label = options.fetch(:label)
        data = {
          username:    options[:username],
          password:    options[:password],
          url:         options[:url],
          description: options[:description]
        }.compact
        Vault.logical.write(path(label), data: data)
      end

      def get(label:, exception: true)
        secret = Vault.logical.read(path(label))
        if secret.nil?
          raise "Secret '#{label}' not found" if exception
          return nil
        end
        return secret.data[:data]
      end

      def delete(label:)
        path = path(label)
        Vault.logical.delete(path)
      end

      private

      def path(label)
        "#{SECRET_PATH}#{label}"
      end
    end
  end
end
