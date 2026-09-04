# frozen_string_literal: true

require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/keychain/base'
require 'aspera/yaml'
require 'symmetric_encryption/core'
require 'openssl'
require 'yaml'

module Aspera
  module Keychain
    # Manage secrets in a simple Hash
    class EncryptedHash < Base
      LEGACY_CIPHER_NAME = 'aes-256-cbc'
      DEFAULT_CIPHER_NAME = 'aes-256-cbc'
      FILE_TYPE = 'encrypted_hash_vault'
      FILE_KEYS = %w[version type cipher data].sort.freeze
      FILE_KEYS_KDF = (%w[kdf] + FILE_KEYS).sort.freeze
      # PBKDF2 parameters for new vaults
      KDF_ITERATIONS = 200_000
      KDF_DIGEST = 'SHA256'
      KDF_SALT_BYTES = 16
      private_constant :LEGACY_CIPHER_NAME, :DEFAULT_CIPHER_NAME, :FILE_TYPE, :FILE_KEYS, :FILE_KEYS_KDF,
        :KDF_ITERATIONS, :KDF_DIGEST, :KDF_SALT_BYTES

      def initialize(file:, password:)
        super()
        Aspera.assert_type(file, String){'path to vault file'}
        @path = file
        @all_secrets = {}
        @cipher_name = DEFAULT_CIPHER_NAME
        @kdf_params = nil
        vault_encrypted_data = nil
        if File.exist?(@path)
          vault_file = File.read(@path)
          if vault_file.start_with?('---')
            vault_info = YAML.parse(vault_file).to_ruby
            sorted_keys = vault_info.keys.sort
            Aspera.assert(sorted_keys == FILE_KEYS || sorted_keys == FILE_KEYS_KDF, 'Invalid vault file')
            @cipher_name = vault_info['cipher']
            @kdf_params  = vault_info['kdf']
            vault_encrypted_data = vault_info['data']
          else
            # legacy vault file
            @cipher_name = LEGACY_CIPHER_NAME
            vault_encrypted_data = File.read(@path, mode: 'rb')
          end
        end
        # setting password also creates the cipher
        @cipher = cipher(password)
        @all_secrets = Yaml.safe_load(@cipher.decrypt(vault_encrypted_data)) || {} if !vault_encrypted_data.nil?
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
        Aspera.assert(!@all_secrets.key?(label)){"secret #{label} already exist, delete first"}
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
        # Generate new KDF params so a password change also re-salts the vault
        @kdf_params = nil
        @cipher = cipher(password)
        save
      end

      private

      # Derive an AES key from +new_password+.
      # When @kdf_params is nil (new vault or password change) a fresh PBKDF2 salt
      # is generated and stored in @kdf_params so it is persisted with the vault.
      # When @kdf_params is already set (existing vault being opened) it is reused.
      def cipher(new_password)
        key_bytes = @cipher_name.split('-')[1].to_i / Environment::BITS_PER_BYTE
        if @kdf_params.nil?
          # New vault or password change: generate a fresh salt
          salt = OpenSSL::Random.random_bytes(KDF_SALT_BYTES)
          @kdf_params = {
            'algo'       => 'PBKDF2',
            'digest'     => KDF_DIGEST,
            'iterations' => KDF_ITERATIONS,
            'salt'       => [salt].pack('m0') # base64, no newlines
          }
        end
        salt = @kdf_params['salt'].unpack1('m0')
        key  = OpenSSL::KDF.pbkdf2_hmac(
          new_password,
          salt:       salt,
          iterations: @kdf_params['iterations'],
          length:     key_bytes,
          hash:       @kdf_params['digest']
        )
        SymmetricEncryption.cipher = SymmetricEncryption::Cipher.new(cipher_name: @cipher_name, key: key, encoding: :none)
      end

      # save current data to file with format
      def save
        vault_info = {
          'version' => '1.0.0',
          'type'    => FILE_TYPE,
          'cipher'  => @cipher_name,
          'kdf'     => @kdf_params,
          'data'    => @cipher.encrypt(YAML.dump(@all_secrets))
        }
        File.write(@path, YAML.dump(vault_info))
      end
    end
  end
end
