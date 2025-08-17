# frozen_string_literal: true

require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/keychain/base'
require 'symmetric_encryption/core'
require 'yaml'

module Aspera
  module Keychain
    # Manage secrets in a simple Hash
    class EncryptedHash < Base
      LEGACY_CIPHER_NAME = 'aes-256-cbc'
      DEFAULT_CIPHER_NAME = 'aes-256-cbc'
      FILE_TYPE = 'encrypted_hash_vault'
      FILE_KEYS = %w[version type cipher data].sort.freeze
      private_constant :LEGACY_CIPHER_NAME, :DEFAULT_CIPHER_NAME, :FILE_TYPE, :FILE_KEYS
      def initialize(file:, password:)
        super()
        Aspera.assert_type(file, String){'path to vault file'}
        @path = file
        @all_secrets = {}
        @cipher_name = DEFAULT_CIPHER_NAME
        vault_encrypted_data = nil
        if File.exist?(@path)
          vault_file = File.read(@path)
          if vault_file.start_with?('---')
            vault_info = YAML.parse(vault_file).to_ruby
            Aspera.assert(vault_info.keys.sort == FILE_KEYS){'Invalid vault file'}
            @cipher_name = vault_info['cipher']
            vault_encrypted_data = vault_info['data']
          else
            # legacy vault file
            @cipher_name = LEGACY_CIPHER_NAME
            vault_encrypted_data = File.read(@path, mode: 'rb')
          end
        end
        # setting password also creates the cipher
        @cipher = cipher(password)
        if !vault_encrypted_data.nil?
          @all_secrets = YAML.load_stream(@cipher.decrypt(vault_encrypted_data)).first
        end
      end

      def info
        return {
          file: @path
        }
      end

      def list
        result = []
        @all_secrets.each do |label, values|
          normal = values.symbolize_keys
          normal[:label] = label
          CONTENT_KEYS.each{ |k| normal[k] = '' unless normal.key?(k)}
          result.push(normal)
        end
        return result
      end

      # set a secret
      # @param options [Hash] with keys :label, :username, :password, :url, :description
      def set(options)
        validate_set(options)
        label = options.delete(:label)
        raise "secret #{label} already exist, delete first" if @all_secrets.key?(label)
        @all_secrets[label] = options.symbolize_keys
        save
      end

      def get(label:, exception: true)
        Aspera.assert(@all_secrets.key?(label)){"Label not found: #{label}"} if exception
        result = @all_secrets[label].clone
        result[:label] = label if result.is_a?(Hash)
        return result
      end

      def delete(label:)
        @all_secrets.delete(label)
        save
      end

      def change_password(password)
        @cipher = cipher(password)
        save
      end

      private

      # set the password and cipher
      def cipher(new_password)
        # number of bits in second position
        key_bytes = @cipher_name.split('-')[1].to_i / Environment::BITS_PER_BYTE
        # derive key from passphrase, add trailing zeros
        key = "#{new_password}#{"\x0" * key_bytes}"[0..(key_bytes - 1)]
        Log.log.trace1{"secret=[#{key}],#{key.length}"}
        SymmetricEncryption.cipher = SymmetricEncryption::Cipher.new(cipher_name: @cipher_name, key: key, encoding: :none)
      end

      # save current data to file with format
      def save
        vault_info = {
          'version' => '1.0.0',
          'type'    => FILE_TYPE,
          'cipher'  => @cipher_name,
          'data'    => @cipher.encrypt(YAML.dump(@all_secrets))
        }
        File.write(@path, YAML.dump(vault_info))
      end
    end
  end
end
