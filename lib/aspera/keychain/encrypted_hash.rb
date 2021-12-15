require 'openssl'

module Aspera
  module Keychain
    class SimpleCipher
      def initialize(key)
        @key=Digest::SHA1.hexdigest(key)[0..23]
        @cipher = OpenSSL::Cipher.new('DES-EDE3-CBC')
      end

      def encrypt(value)
        @cipher.encrypt
        @cipher.key = @key
        s = @cipher.update(value) + @cipher.final
        s.unpack('H*').first
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
      SEPARATOR='%'
      private_constant :SEPARATOR
      def initialize(values)
        raise "values shall be Hash" unless values.is_a?(Hash)
        @all_secrets=values
      end

      def set(options)
        raise "options shall be Hash" unless options.is_a?(Hash)
        unsupported=options.keys-[:username,:url,:secret,:description]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username=options[:username]
        raise "options shall have username" if username.nil?
        url=options[:url]
        raise "options shall have username" if url.nil?
        secret=options[:secret]
        raise "options shall have secret" if secret.nil?
        key=[url,username].join(SEPARATOR)
        raise "secret #{key} already exist, delete first" if @all_secrets.has_key?(key)
        obj={username: username, url: url, secret: SimpleCipher.new(key).encrypt(secret)}
        obj[:description]=options[:description] if options.has_key?(:description)
        @all_secrets[key]=obj
        nil
      end

      def list
        result=[]
        @all_secrets.each do |k,v|
          case v
          when String
            o={username: k, url: '', description: ''}
          when Hash
            o=v.clone
            o.delete(:secret)
            o[:description]||=''
          else raise "error"
          end
          o[:description]=v[:description] if v.is_a?(Hash) and v[:description].is_a?(String)
          result.push(o)
        end
        return result
      end

      def delete(options)
        raise "options shall be Hash" unless options.is_a?(Hash)
        unsupported=options.keys-[:username,:url]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username=options[:username]
        raise "options shall have username" if username.nil?
        url=options[:url]
        key=nil
        if !url.nil?
          extk=[url,username].join(SEPARATOR)
          key=extk if @all_secrets.has_key?(extk)
        end
        # backward compatibility: TODO: remove in future ? (make url mandatory ?)
        key=username if key.nil? and @all_secrets.has_key?(username)
        raise "no such secret" if key.nil?
        @all_secrets.delete(key)
      end

      def get(options)
        raise "options shall be Hash" unless options.is_a?(Hash)
        unsupported=options.keys-[:username,:url]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username=options[:username]
        raise "options shall have username" if username.nil?
        url=options[:url]
        val=nil
        if !url.nil?
          val=@all_secrets[[url,username].join(SEPARATOR)]
        end
        # backward compatibility: TODO: remove in future ? (make url mandatory ?)
        if val.nil?
          val=@all_secrets[username]
        end
        result=options.clone
        case val
        when NilClass
          raise "no such secret"
        when String
          result.merge!({secret: val, description: ''})
        when Hash
          key=[url,username].join(SEPARATOR)
          plain=SimpleCipher.new(key).decrypt(val[:secret])
          result.merge!({secret: plain, description: val[:description]})
        else raise "error"
        end
        return result
      end
    end
  end
end
