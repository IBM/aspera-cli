# frozen_string_literal: true

require 'aspera/hash_ext'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/secret/store/base'
require 'aspera/yaml'
require 'openssl'
require 'yaml'

module Aspera
  module Secret
    module Store
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
        PARAMETERS = %i[file password].freeze

        class << self
          # `password` is the value, or `@file:<path>`
          def arguments(params)
            params.merge(password: Bootstrap.new('password', params[:password]))
          end
        end

        # The vault file is read when used, and again when it, or the file of the password, is modified.
        # It is created by the first `set`.
        # @param file     [String]            Vault file
        # @param password [String, Bootstrap] Password of vault file: the value, or a `Bootstrap`
        def initialize(file:, password:)
          super()
          Aspera.assert_type(file, String) { 'path to vault file' }
          @path = file
          @password = password.is_a?(Bootstrap) ? password : Bootstrap.new('password', password)
          # Modification times of vault file (`nil` if absent) and file of password, when read, `nil` before
          @mtimes = nil
          @lock = Mutex.new
          Log.dump(:vault_file, File.expand_path(@path))
        end

        def info
          return {
            file: @path
          }
        end

        def all
          result = []
          secrets.each do |label, values|
            normal = values.symbolize_keys
            normal[:label] = label
            CONTENT_KEYS.each { |k| normal[k] = '' unless normal.key?(k) }
            result.push(normal)
          end
          return result
        end

        # set a secret
        # @param options [Hash] with keys :label, :username, :password, :url, :description
        def set(options)
          validate_set(options)
          label = options.delete(:label)
          assert_new_label(label)
          secrets[label] = options.symbolize_keys
          save
        end

        def get(label:, exception: true)
          Aspera.assert(secrets.key?(label)) { "Label not found: #{label}" } if exception
          result = secrets[label].clone
          result[:label] = label if result.is_a?(Hash)
          return result
        end

        def delete(label:)
          Aspera.assert(secrets.key?(label)) { "Label not found: #{label}" }
          secrets.delete(label)
          save
        end

        def change_password(password)
          secrets
          # Generate new KDF params so a password change also re-salts the vault
          # (and migrates a legacy vault to PBKDF2)
          @legacy_key = false
          @kdf_params = nil
          @cipher = cipher(password)
          @password = Bootstrap.new('password', password)
          save
        end

        # Modification time of vault file
        def read_reference(ref)
          raise Error, "no vault file: #{@path}" unless File.exist?(@path)
          super.merge(updated_time: @mtimes&.first)
        end

        private

        # @return [Hash] Secrets: label → fields
        def secrets
          @lock.synchronize do
            mtimes = current_mtimes
            unless mtimes.eql?(@mtimes)
              load_file(@password.value)
              @mtimes = mtimes
            end
          end
          @all_secrets
        rescue SystemCallError => e
          raise Error, e.message
        end

        # @return [Array<Time, nil>] Modification times of vault file (`nil` if absent) and file of password (`nil` for a value)
        def current_mtimes
          [File.exist?(@path) ? File.mtime(@path) : nil, @password.mtime]
        end

        # Read and decrypt vault file, if it exists
        # @param password [String] Password of vault file
        def load_file(password)
          @all_secrets = {}
          @cipher_name = DEFAULT_CIPHER_NAME
          @kdf_params = nil
          # true when the vault was created by v4.26.0 (password padded with zeros, no KDF)
          @legacy_key = false
          vault_encrypted_data = nil
          if File.exist?(@path)
            vault_file = File.read(@path)
            if vault_file.start_with?('---')
              vault_info = Yaml.safe_load(vault_file)
              Aspera.assert_type(vault_info, Hash) { "Invalid vault file: #{@path}" }
              sorted_keys = vault_info.keys.sort
              Aspera.assert(sorted_keys == FILE_KEYS || sorted_keys == FILE_KEYS_KDF) { "Invalid vault file: #{@path}: #{sorted_keys}" }
              @cipher_name = vault_info['cipher']
              @kdf_params  = vault_info['kdf']
              # vault created before PBKDF2 was introduced (v4.26.0 format: no kdf field)
              @legacy_key = @kdf_params.nil?
              vault_encrypted_data = vault_info['data']
            else
              # legacy vault file (binary, pre-YAML format)
              @cipher_name = LEGACY_CIPHER_NAME
              @legacy_key = true
              vault_encrypted_data = File.read(@path, mode: 'rb')
            end
          end
          # setting password also creates the cipher
          @cipher = cipher(password)
          @all_secrets = decrypt(vault_encrypted_data) unless vault_encrypted_data.nil?
        end

        # @param data [String] Encrypted secrets
        # @return [Hash] Secrets
        # @raise [Error] Wrong password
        def decrypt(data)
          Yaml.safe_load(@cipher.decrypt(data)) || {}
        rescue OpenSSL::Cipher::CipherError, Psych::Exception
          # Psych: rarely, a wrong key gives valid padding, then garbage
          raise Error, "cannot decrypt #{@path} (password?)"
        end

        # Minimal cipher wrapper using OpenSSL, compatible with the SymmetricEncryption
        # binary format: a 6-byte header "@EnC\x00\x00" followed by AES ciphertext
        # produced with a zero IV (encoding: :none, no random IV in header).
        class OsslCipher
          HEADER = "@EnC\x00\x00".b.freeze
          HEADER_SIZE = HEADER.bytesize

          def initialize(cipher_name, key)
            @cipher_name = cipher_name
            @key         = key
          end

          def encrypt(plaintext)
            c = OpenSSL::Cipher.new(@cipher_name)
            c.encrypt
            c.key = @key
            c.iv  = "\x00".b * c.iv_len
            HEADER + c.update(plaintext.b) + c.final
          end

          def decrypt(ciphertext)
            body = ciphertext.b[HEADER_SIZE..]
            c = OpenSSL::Cipher.new(@cipher_name)
            c.decrypt
            c.key = @key
            c.iv  = "\x00".b * c.iv_len
            (c.update(body) + c.final).force_encoding(Encoding::UTF_8)
          end
        end

        # Derive an AES key from `new_password`.
        # @legacy_key is true for vaults created by v4.26.0 or earlier (no kdf field):
        #   key = password truncated/zero-padded to key_bytes (same as symmetric-encryption did).
        # Otherwise PBKDF2 is used. When @kdf_params is nil (new vault or password change)
        # a fresh salt is generated; when already set (existing vault) it is reused.
        def cipher(new_password)
          key_bytes = @cipher_name.split('-')[1].to_i / Environment::BITS_PER_BYTE
          key =
            if @legacy_key
              # Replicate the v4.26.0 key derivation: password + NUL padding, truncated to key_bytes
              (new_password + ("\x00" * key_bytes))[0, key_bytes]
            else
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
              OpenSSL::KDF.pbkdf2_hmac(
                new_password,
                salt:       salt,
                iterations: @kdf_params['iterations'],
                length:     key_bytes,
                hash:       @kdf_params['digest']
              )
            end
          OsslCipher.new(@cipher_name, key)
        end

        # save current data to file with format
        def save
          vault_info = {
            'version' => '1.1.0',
            'type'    => FILE_TYPE,
            'cipher'  => @cipher_name,
            'kdf'     => @kdf_params,
            'data'    => @cipher.encrypt(YAML.dump(@all_secrets))
          }
          Environment.write_file_restricted(@path, force: true) { YAML.dump(vault_info) }
          # Secrets in memory are those of the file
          @mtimes = current_mtimes
        end
      end
    end
  end
end
