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
      CIPHER_NAME = 'aes-256-cbc'
      CONTENT_KEYS = %i[label username password url description].freeze
      def initialize(path, current_password)
        @path = path
        self.password = current_password
        assert_type(@path, String){'path to vault file'}
        @all_secrets = File.exist?(@path) ? YAML.load_stream(@cipher.decrypt(File.read(@path))).first : {}
      end

      def password=(new_password)
        # number of bits in second position
        key_bytes = CIPHER_NAME.split('-')[1].to_i / Environment::BITS_PER_BYTE
        # derive key from passphrase, add trailing zeros
        key = "#{new_password}#{"\x0" * key_bytes}"[0..(key_bytes - 1)]
        Log.log.debug{"key=[#{key}],#{key.length}"}
        SymmetricEncryption.cipher = @cipher = SymmetricEncryption::Cipher.new(cipher_name: CIPHER_NAME, key: key, encoding: :none)
      end

      def save
        File.write(@path, @cipher.encrypt(YAML.dump(@all_secrets)), encoding: 'BINARY')
      end

      def set(options)
        assert_type(options, Hash){'options'}
        unsupported = options.keys - CONTENT_KEYS
        options.each_value do |v|
          assert_type(v, String){'value'}
        end
        assert(unsupported.empty?){"unsupported options: #{unsupported}"}
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
