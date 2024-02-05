# frozen_string_literal: true

require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'symmetric_encryption/core'
require 'yaml'

module Aspera
  module Keychain
    # Manage secrets in a simple Hash
    class EncryptedHash
      LEGACY_CIPHER_NAME = 'aes-256-cbc'
      DEFAULT_CIPHER_NAME = 'aes-256-cbc'
      FILE_TYPE = 'encrypted_hash_vault'
      CONTENT_KEYS = %i[label username password url description].freeze
      FILE_KEYS = %w[version type cipher data].sort.freeze
      def initialize(path, current_password)
        assert_type(path, String){'path to vault file'}
        @path = path
        @all_secrets = {}
        vault_encrypted_data = nil
        if File.exist?(@path)
          vault_file = File.read(@path)
          if vault_file.start_with?('---')
            vault_info = YAML.parse(vault_file).to_ruby
            assert(vault_info.keys.sort == FILE_KEYS){'Invalid vault file'}
            @cipher_name = vault_info['cipher']
            vault_encrypted_data = vault_info['data']
          else
            # legacy vault file
            @cipher_name = LEGACY_CIPHER_NAME
            vault_encrypted_data = File.read(@path, mode: 'rb')
          end
        end
        # setting password also creates the cipher
        self.password = current_password
        if !vault_encrypted_data.nil?
          @all_secrets = YAML.load_stream(@cipher.decrypt(vault_encrypted_data)).first
        end
      end

      # set the password and cipher
      def password=(new_password)
        # number of bits in second position
        key_bytes = DEFAULT_CIPHER_NAME.split('-')[1].to_i / Environment::BITS_PER_BYTE
        # derive key from passphrase, add trailing zeros
        key = "#{new_password}#{"\x0" * key_bytes}"[0..(key_bytes - 1)]
        Log.log.trace1{"secret=[#{key}],#{key.length}"}
        @cipher = SymmetricEncryption.cipher = SymmetricEncryption::Cipher.new(cipher_name: DEFAULT_CIPHER_NAME, key: key, encoding: :none)
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

      # set a secret
      # @param options [Hash] with keys :label, :username, :password, :url, :description
      def set(options)
        assert_type(options, Hash){'options'}
        unsupported = options.keys - CONTENT_KEYS
        assert(unsupported.empty?){"unsupported options: #{unsupported}"}
        options.each_pair do |k, v|
          assert_type(v, String){k.to_s}
        end
        label = options.delete(:label)
        raise "secret #{label} already exist, delete first" if @all_secrets.key?(label)
        @all_secrets[label] = options.symbolize_keys
        save
      end

      def list
        result = []
        @all_secrets.each do |label, values|
          normal = values.symbolize_keys
          normal[:label] = label
          CONTENT_KEYS.each{|k|normal[k] = '' unless normal.key?(k)}
          result.push(normal)
        end
        return result
      end

      def delete(label:)
        @all_secrets.delete(label)
        save
      end

      def get(label:, exception: true)
        assert(@all_secrets.key?(label)){"Label not found: #{label}"} if exception
        result = @all_secrets[label].clone
        result[:label] = label if result.is_a?(Hash)
        return result
      end
    end
  end
end
