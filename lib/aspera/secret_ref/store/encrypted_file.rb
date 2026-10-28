# frozen_string_literal: true

require 'aspera/secret_ref/store/base'
require 'aspera/keychain/encrypted_hash'
require 'openssl'

module Aspera
  module SecretRef
    module Store
      # Secrets in an encrypted file of `ascli` (vault of type `file`, `config vault create`).
      # Reference: `secret://<store>/<label>#<field>`, field default: `password`.
      # The file is read again when it is modified, or its password file.
      class EncryptedFile < Base
        DEFAULT_FIELD = 'password'
        private_constant :DEFAULT_FIELD

        # @param name          [String] Name of store in configuration
        # @param file          [String] Encrypted file
        # @param password_file [String] File with password of encrypted file
        def initialize(name:, file:, password_file:)
          super(name: name)
          @file = file
          @password_file = password_file
          # Modification times of files, and decrypted file
          @mtimes = nil
          @keychain = nil
          @lock = Mutex.new
        end

        private

        def read(ref)
          keychain, mtime = current_keychain
          entry = keychain.get(label: ref.path, exception: false)
          raise Error, "no label: #{ref.path}" if entry.nil?
          {value: field_value(entry, ref, default: DEFAULT_FIELD), version: nil, updated_time: mtime}
        end

        # @return [Array] Keychain and modification time of encrypted file
        def current_keychain
          @lock.synchronize do
            mtimes = [@file, @password_file].map { |f| File.mtime(f) }
            unless mtimes.eql?(@mtimes)
              @keychain = Keychain::EncryptedHash.new(file: @file, password: SecretRef.read_file_secret(@password_file))
              @mtimes = mtimes
            end
            [@keychain, @mtimes.first]
          end
        rescue SystemCallError => e
          raise Error, e.message
        rescue OpenSSL::Cipher::CipherError, Psych::Exception
          # Psych: rarely, a wrong key gives valid padding, then garbage
          raise Error, "cannot decrypt #{@file} (password?)"
        end
      end
    end
  end
end
