# frozen_string_literal: true

# https://github.com/fastlane-community/security
require 'aspera/cli/info'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/keychain/base'

# enhance the gem to support other key chains
module Aspera
  module Keychain
    module MacosSecurity
      # keychain based on macOS keychain, using `security` command line
      class Keychain
        # https://www.unix.com/man-page/osx/1/security/
        SECURITY_UTILITY = 'security'
        DOMAINS = %i[user system common dynamic].freeze
        LIST_OPTIONS = {
          domain: :c
        }
        ADD_PASS_OPTIONS = {
          account:  :a,
          creator:  :c,
          type:     :C,
          domain:   :d,
          kind:     :D,
          value:    :G,
          comment:  :j,
          label:    :l,
          path:     :p,
          port:     :P,
          protocol: :r,
          server:   :s,
          service:  :s,
          auth:     :t,
          password: :w,
          getpass:  :g
        }.freeze
        class << self
          def execute(command, options=nil, supported=nil, last_opt=nil)
            url = options&.delete(:url)
            if !url.nil?
              uri = URI.parse(url)
              Aspera.assert(uri.scheme.eql?('https')){'only https'}
              options[:protocol] = 'htps' # cspell: disable-line
              raise 'host required in URL' if uri.host.nil?
              options[:server] = uri.host
              options[:path] = uri.path unless ['', '/'].include?(uri.path)
              options[:port] = uri.port unless uri.port.eql?(443) && !url.include?(':443/')
            end
            command_args = [command]
            options&.each do |k, v|
              Aspera.assert(supported.key?(k)){"unknown option: #{k}"}
              next if v.nil?
              command_args.push("-#{supported[k]}")
              command_args.push(v.shellescape) unless v.empty?
            end
            command_args.push(last_opt) unless last_opt.nil?
            return Environment.secure_capture(exec: SECURITY_UTILITY, args: command_args)
          end

          def key_chains(output)
            output.split("\n").collect{ |line| new(line.strip.gsub(/^"|"$/, ''))}
          end

          def default
            key_chains(execute('default-keychain')).first
          end

          def login
            key_chains(execute('login-keychain')).first
          end

          def list(options={})
            Aspera.assert_values(options[:domain], DOMAINS, type: ArgumentError){'domain'} unless options[:domain].nil?
            key_chains(execute('list-keychains', options, LIST_OPTIONS))
          end

          def by_name(name)
            list.find{ |kc| kc.path.end_with?("/#{name}.keychain-db")}
          end
        end
        attr_reader :path

        def initialize(path)
          @path = path
        end

        def decode_hex_blob(string)
          [string].pack('H*').force_encoding('UTF-8')
        end

        def password(operation, pass_type, options)
          Aspera.assert_values(operation, %i[add find delete]){'operation'}
          Aspera.assert_values(pass_type, %i[generic internet]){'pass_type'}
          Aspera.assert_type(options, Hash)
          missing = (operation.eql?(:add) ? %i[account service password] : %i[label]) - options.keys
          Aspera.assert(missing.empty?){"missing options: #{missing}"}
          options[:getpass] = '' if operation.eql?(:find)
          output = self.class.execute("#{operation}-#{pass_type}-password", options, ADD_PASS_OPTIONS, @path)
          raise output.gsub(/^.*: /, '') if output.start_with?('security: ')
          return unless operation.eql?(:find)
          attributes = {}
          output.split("\n").each do |line|
            case line
            when /^keychain: "(.+)"/
              # ignore
            when /0x00000007 .+="(.+)"/
              attributes['label'] = Regexp.last_match(1)
            when /"(\w{4})".+="(.+)"/
              attributes[Regexp.last_match(1)] = Regexp.last_match(2)
            when /"(\w{4})"<blob>=0x([[:xdigit:]]+)/
              attributes[Regexp.last_match(1)] = decode_hex_blob(Regexp.last_match(2))
            when /^password: "(.+)"/
              attributes['password'] = Regexp.last_match(1)
            when /^password: 0x([[:xdigit:]]+)/
              attributes['password'] = decode_hex_blob(Regexp.last_match(1))
            end
          end
          return attributes
        end
      end
    end

    class MacosSystem < Base
      def initialize(name: nil)
        super()
        @keychain_name = name.nil? ? 'default keychain' : name
        @keychain = name.nil? ? MacosSecurity::Keychain.default : MacosSecurity::Keychain.by_name(name)
        raise "no such keychain #{name}" if @keychain.nil?
      end

      def info
        return {
          keychain: @keychain_name
        }
      end

      def list
        # the only way to list is `dump-keychain` which triggers security alert
        raise 'list not implemented, use macos keychain app'
      end

      def set(options)
        validate_set(options)
        @keychain.password(
          :add, :generic, service: options[:label],
          account: options[:username] || 'none', password: options[:password], comment: options[:description])
      end

      def get(options)
        Aspera.assert_type(options, Hash){'options'}
        unsupported = options.keys - %i[label]
        Aspera.assert(unsupported.empty?){"unsupported options: #{unsupported}"}
        info = @keychain.password(:find, :generic, label: options[:label])
        raise 'not found' if info.nil?
        result = options.clone
        result[:secret] = info['password']
        result[:description] = info['icmt'] # cspell: disable-line
        return result
      end

      def delete(options)
        Aspera.assert_type(options, Hash){'options'}
        unsupported = options.keys - %i[label]
        Aspera.assert(unsupported.empty?){"unsupported options: #{unsupported}"}
        raise 'delete not implemented, use macos keychain app'
      end
    end
  end
end
