# frozen_string_literal: true

require 'aspera/hash_ext'
require 'symmetric_encryption/core'
require 'yaml'

module Aspera
  module Keychain
    # Manage secrets in a simple Hash
    class EncryptedHash
      CIPHER_NAME='aes-256-cbc'
      CONTENT_KEYS = %i[label username password url description].freeze
      def initialize(path,current_password)
        @path=path
        self.password=current_password
        raise 'path to vault file shall be String' unless @path.is_a?(String)
        @all_secrets=File.exist?(@path) ? YAML.load_stream(@cipher.decrypt(File.read(@path))).first : {}
      end

      def password=(new_password)
        key_bytes=CIPHER_NAME.split('-')[1].to_i/8
        # derive key from passphrase
        key="#{new_password}#{"\x0"*key_bytes}"[0..(key_bytes-1)]
        Log.log.debug("key=[#{key}],#{key.length}")
        SymmetricEncryption.cipher=@cipher = SymmetricEncryption::Cipher.new(cipher_name: CIPHER_NAME,key: key,encoding: :none)
      end

      def save
        File.write(@path, @cipher.encrypt(YAML.dump(@all_secrets)),encoding: 'BINARY')
      end

      def set(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - CONTENT_KEYS
        options.values.each {|v| raise 'value must be String' unless v.is_a?(String)}
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        label = options.delete(:label)
        raise "secret #{label} already exist, delete first" if @all_secrets.has_key?(label)
        @all_secrets[label] = options.symbolize_keys
        save
      end

      def list
        result = []
        @all_secrets.each do |label,values|
          normal = values.symbolize_keys
          normal[:label] = label
          CONTENT_KEYS.each{|k|normal[k] = '' unless normal.has_key?(k)}
          result.push(normal)
        end
        return result
      end

      def delete(label:)
        @all_secrets.delete(label)
        save
      end

      def get(label:, exception: true)
        raise "Label not found: #{label}" unless @all_secrets.has_key?(label) || !exception
        result=@all_secrets[label].clone
        result[:label]=label if result.is_a?(Hash)
        return result
      end
    end
  end
end
