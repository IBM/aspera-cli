# frozen_string_literal: true
require 'security'

# enhance the gem to support other keychains
module Security
  class Keychain
    class << self
      def by_name(name)
        keychains_from_output('security list-keychains').select{|kc|kc.filename.end_with?("/#{name}.keychain-db")}.first
      end
    end
  end

  class Password
    class << self
      # add some login to original method
      alias orig_flags_for_options flags_for_options
      def flags_for_options(options = {})
        keychain=options.delete(:keychain)
        url=options.delete(:url)
        if !url.nil?
          uri=URI.parse(url)
          raise 'only https' unless uri.scheme.eql?('https')
          options[:r]='htps'
          raise 'host required in URL' if uri.host.nil?
          options[:s]=uri.host
          options[:p]=uri.path unless ['','/'].include?(uri.path)
          options[:P]=uri.port unless uri.port.eql?(443) && !url.include?(':443/')
        end
        flags=[orig_flags_for_options(options)]
        flags.push(keychain.filename) unless keychain.nil?
        flags.join(' ')
      end
    end
  end
end

module Aspera
  module Keychain
    # keychain based on macOS keychain, using `security` cmmand line
    class MacosSecurity
      def initialize(name=nil)
        @keychain=name.nil? ? Security::Keychain.default_keychain : Security::Keychain.by_name(name)
        raise "no such keychain #{name}" if @keychain.nil?
      end

      def set(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported=options.keys-[:username,:url,:secret,:description]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username=options[:username]
        raise 'options shall have username' if username.nil?
        url=options[:url]
        raise 'options shall have url' if url.nil?
        secret=options[:secret]
        raise 'options shall have secret' if secret.nil?
        raise 'set not implemented'
      end

      def get(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported=options.keys-[:username,:url]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username=options[:username]
        raise 'options shall have username' if username.nil?
        url=options[:url]
        raise 'options shall have url' if url.nil?
        info=Security::InternetPassword.find(keychain: @keychain, url: url, account: username)
        raise 'not found' if info.nil?
        result=options.clone
        result.merge!({secret: info.password, description: info.attributes['icmt']})
        return result
      end

      def list
        raise 'list not implemented'
      end

      def delete(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported=options.keys-[:username,:url]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        username=options[:username]
        raise 'options shall have username' if username.nil?
        url=options[:url]
        raise "delete not implemented #{url}"
      end
    end
  end
end
