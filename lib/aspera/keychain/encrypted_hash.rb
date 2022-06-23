# frozen_string_literal: true

require 'aspera/hash_ext'
require 'openssl'

module Aspera
  module Keychain
    class SimpleCipher
      def initialize(key)
        @key = Digest::SHA1.hexdigest(key+('*'*23))[0..23]
        @cipher = OpenSSL::Cipher.new('DES-EDE3-CBC')
      end

      def encrypt(value)
        @cipher.encrypt
        @cipher.key = @key
        s = @cipher.update(value) + @cipher.final
        s.unpack1('H*')
      end

      def decrypt(value)
        @cipher.decrypt
        @cipher.key = @key
        s = [value].pack('H*').unpack('C*').pack('c*')
        @cipher.update(s) + @cipher.final
      end
    end

    # Manage secrets in a simple Hash
    class EncryptedHash
      SEPARATOR = '%'
      ACCEPTED_KEYS = %i[username url secret description].freeze
      private_constant :SEPARATOR
      attr_reader :legacy_detected
      def initialize(values)
        raise 'values shall be Hash' unless values.is_a?(Hash)
        @all_secrets = values
      end

      def identifier(options)
        return options[:username] if options[:url].to_s.empty?
        %i[url username].map{|s|options[s]}.join(SEPARATOR)
      end

      def set(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - ACCEPTED_KEYS
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username = options[:username]
        raise 'options shall have username' if username.nil?
        url = options[:url]
        raise 'options shall have username' if url.nil?
        secret = options[:secret]
        raise 'options shall have secret' if secret.nil?
        key = identifier(options)
        raise "secret #{key} already exist, delete first" if @all_secrets.has_key?(key)
        obj = {username: username, url: url, secret: SimpleCipher.new(key).encrypt(secret)}
        obj[:description] = options[:description] if options.has_key?(:description)
        @all_secrets[key] = obj.stringify_keys
        nil
      end

      def list
        result = []
        legacy_detected=false
        @all_secrets.each do |name,value|
          normal = # normalized version
            case value
            when String
              legacy_detected=true
              {username: name, url: '', secret: value}
            when Hash then value.symbolize_keys
            else raise 'error secret must be String (legacy) or Hash (new)'
            end
          normal[:description] = '' unless normal.has_key?(:description)
          extraneous_keys=normal.keys - ACCEPTED_KEYS
          Log.log.error("wrongs keys in secret hash: #{extraneous_keys.map(&:to_s).join(',')}") unless extraneous_keys.empty?
          result.push(normal)
        end
        Log.log.warn('Legacy vault format detected in config file, please refer to documentation to convert to new format.') if legacy_detected
        return result
      end

      def delete(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - %i[username url]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username = options[:username]
        raise 'options shall have username' if username.nil?
        url = options[:url]
        key = nil
        if !url.nil?
          extk = identifier(options)
          key = extk if @all_secrets.has_key?(extk)
        end
        # backward compatibility: TODO: remove in future ? (make url mandatory ?)
        key = username if key.nil? && @all_secrets.has_key?(username)
        raise 'no such secret' if key.nil?
        @all_secrets.delete(key)
      end

      def get(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - %i[username url]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username = options[:username]
        raise 'options shall have username' if username.nil?
        url = options[:url]
        info = nil
        if !url.nil?
          info = @all_secrets[identifier(options)]
        end
        # backward compatibility: TODO: remove in future ? (make url mandatory ?)
        if info.nil?
          info = @all_secrets[username]
        end
        result = options.clone
        case info
        when NilClass
          raise "no such secret: [#{url}|#{username}] in #{@all_secrets.keys.join(',')}"
        when String
          result[:secret] = info
          result[:description] = ''
        when Hash
          info=info.symbolize_keys
          key = identifier(options)
          plain = SimpleCipher.new(key).decrypt(info[:secret]) rescue info[:secret]
          result[:secret] = plain
          result[:description] = info[:description]
        else raise "#{info.class} is not an expected type"
        end
        return result
      end
    end
  end
end
