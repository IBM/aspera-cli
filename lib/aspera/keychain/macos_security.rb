# frozen_string_literal: true

# https://github.com/fastlane-community/security
require 'aspera/cli/info'

# enhance the gem to support other keychains
module Aspera
  module Keychain
    module MacosSecurity
      # keychain based on macOS keychain, using `security` cmmand line
      class Keychain
        DOMAINS = %i[user system common dynamic].freeze
        LIST_OPTIONS={
          domain: :c
        }
        ADD_PASS_OPTIONS={
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
          def execute(command, options=nil, supported=nil, lastopt=nil)
            url = options&.delete(:url)
            if !url.nil?
              uri = URI.parse(url)
              raise 'only https' unless uri.scheme.eql?('https')
              options[:protocol] = 'htps'
              raise 'host required in URL' if uri.host.nil?
              options[:server] = uri.host
              options[:path] = uri.path unless ['', '/'].include?(uri.path)
              options[:port] = uri.port unless uri.port.eql?(443) && !url.include?(':443/')
            end
            cmd=['security', command]
            options&.each do |k, v|
              raise "unknown option: #{k}" unless supported.has_key?(k)
              next if v.nil?
              cmd.push("-#{supported[k]}")
              cmd.push(v.shellescape) unless v.empty?
            end
            cmd.push(lastopt) unless lastopt.nil?
            Log.log.debug{"executing>>#{cmd.join(' ')}"}
            result=%x(#{cmd.join(' ')} 2>&1)
            Log.log.debug{"result>>[#{result}]"}
            return result
          end

          def keychains(output)
            output.split("\n").collect { |line| new(line.strip.gsub(/^"|"$/, '')) }
          end

          def default
            keychains(execute('default-keychain')).first
          end

          def login
            keychains(execute('login-keychain')).first
          end

          def list(options={})
            raise ArgumentError, "Invalid domain #{options[:domain]}, expected one of: #{DOMAINS}" unless options[:domain].nil? || DOMAINS.include?(options[:domain])
            keychains(execute('list-keychains', options, LIST_OPTIONS))
          end

          def by_name(name)
            list.find{|kc|kc.path.end_with?("/#{name}.keychain-db")}
          end
        end
        attr_reader :path

        def initialize(path)
          @path = path
        end

        def decode_hex_blob(string)
          [string].pack('H*').force_encoding('UTF-8')
        end

        def password(operation, passtype, options)
          raise "wrong operation: #{operation}" unless %i[add find delete].include?(operation)
          raise "wrong passtype: #{passtype}" unless %i[generic internet].include?(passtype)
          raise 'options shall be Hash' unless options.is_a?(Hash)
          missing=(operation.eql?(:add) ? %i[account service password] : %i[label])-options.keys
          raise "missing options: #{missing}" unless missing.empty?
          options[:getpass]='' if operation.eql?(:find)
          output=self.class.execute("#{operation}-#{passtype}-password", options, ADD_PASS_OPTIONS, @path)
          raise output.gsub(/^.*: /, '') if output.start_with?('security: ')
          return nil unless operation.eql?(:find)
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

    class MacosSystem
      def initialize(name=nil, password=nil)
        @keychain = name.nil? ? MacosSecurity::Keychain.default_keychain : MacosSecurity::Keychain.by_name(name)
        raise "no such keychain #{name}" if @keychain.nil?
      end

      def set(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - %i[label username password url description]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        @keychain.password(
          :add, :generic, service: options[:label],
          account: options[:username] || 'none', password: options[:password], comment: options[:description])
      end

      def get(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - %i[label]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        info = @keychain.password(:find, :generic, label: options[:label])
        raise 'not found' if info.nil?
        result = options.clone
        result[:secret] = info['password']
        result[:description] = info['icmt']
        return result
      end

      def list
        # the only way to list is `dump-keychain` which triggers security alert
        raise 'list not implemented, use macos keychain app'
      end

      def delete(options)
        raise 'options shall be Hash' unless options.is_a?(Hash)
        unsupported = options.keys - %i[label]
        raise "unsupported options: #{unsupported}" unless unsupported.empty?
        raise 'delete not implemented, use macos keychain app'
      end
    end
  end
end
