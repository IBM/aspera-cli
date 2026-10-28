# frozen_string_literal: true

# https://github.com/fastlane-community/security
require 'aspera/cli/info'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/secret_store/base'

# enhance the gem to support other key chains
module Aspera
  module SecretStore
    module MacosSecurity
      # keychain based on macOS keychain, using `security` command line
      class Keychain
        # https://www.unix.com/man-page/osx/1/security/
        SECURITY_UTILITY = 'security'
        DOMAINS = %i[user system common dynamic].freeze
        LIST_OPTIONS = {
          domain: :c
        }.freeze
        KEYCHAIN_OPTIONS = {
          password: :p
        }.freeze
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
        # Exit code of `security` when the item is not found
        EXIT_ITEM_NOT_FOUND = 44
        class << self
          # Execute a `security` CLI command with given options
          # @param command   [String]                  The security sub-command
          # @param options   [Hash, nil]               Command options
          # @param supported [Hash, nil]               Mapping of option keys to CLI flags
          # @param last_opt  [String, nil]             Trailing argument (e.g. keychain path)
          # @param exception [Boolean]                 Whether to raise on non-zero exit
          # @return [Array(String, String, Process::Status)] stdout, stderr, status
          def execute(command, options = nil, supported = nil, last_opt = nil, exception: true)
            url = options&.delete(:url)
            if !url.nil?
              uri = URI.parse(url)
              Aspera.assert(uri.scheme.eql?('https'), 'only https')
              options[:protocol] = 'htps'
              Aspera.assert(!uri.host.nil?, type: Error) { 'host required in URL' }
              options[:server] = uri.host
              options[:path] = uri.path unless ['', '/'].include?(uri.path)
              options[:port] = uri.port unless uri.port.eql?(443) && !url.include?(':443/')
            end
            command_args = [SECURITY_UTILITY, command]
            options&.each do |k, v|
              Aspera.assert(supported.key?(k)) { "unknown option: #{k}" }
              next if v.nil?
              command_args.push("-#{supported[k]}")
              # No shell is involved: value is passed as is
              command_args.push(v.to_s) unless v.to_s.empty?
            end
            command_args.push(last_opt) unless last_opt.nil?
            Environment.secure_execute(*command_args, mode: :capture, exception: exception)
          end

          # Parse output of list command into Keychain objects
          # @param output [String] Raw CLI output
          # @return [Array<Keychain>] List of keychain instances
          def key_chains(output)
            output.split("\n").collect { |line| new(line.strip.gsub(/^"|"$/, '')) }
          end

          # Get the macOS default keychain
          # @return [Keychain] Default keychain instance
          def default
            key_chains(execute('default-keychain').first).first
          end

          # Get the macOS login keychain
          # @return [Keychain] Login keychain instance
          def login
            key_chains(execute('login-keychain').first).first
          end

          # List keychains in the search list or domain
          # @param options [Hash] Domain options
          # @return [Array<Keychain>] List of keychains
          def list(options = {})
            Aspera.assert_values(options[:domain], DOMAINS, type: ParameterError) { 'domain' } unless options[:domain].nil?
            key_chains(execute('list-keychains', options, LIST_OPTIONS).first)
          end

          # Find a keychain by its short name (without `.keychain-db` extension)
          # @param name [String] Keychain name
          # @return [Keychain, nil] Matching keychain or nil
          def by_name(name)
            list.find { |kc| kc.path.end_with?("/#{name}.keychain-db") }
          end

          # Create a new macOS keychain file
          # @param path     [String] File path for the new keychain
          # @param password [String] Password for the new keychain
          # @return [Keychain] Created keychain instance
          def create(path, password:)
            execute('create-keychain', {password: password}, KEYCHAIN_OPTIONS, path)
            new(path)
          end

          # Set the keychain search list
          # @param keychain_list [Array<Keychain>] Ordered list of keychains
          # @return [Array(String, String, Process::Status)] Execution result
          def search_list=(keychain_list)
            Environment.secure_execute(SECURITY_UTILITY, 'list-keychains', '-s', *keychain_list.map(&:path), mode: :capture)
          end
        end
        attr_reader :path

        # @param path [String] File path of the keychain
        def initialize(path)
          @path = path
        end

        # Decode a hexadecimal encoded string into UTF-8
        # @param string [String] Hex string
        # @return [String] Decoded string
        def decode_hex_blob(string)
          [string].pack('H*').force_encoding('UTF-8')
        end

        # Perform generic or internet password operation (add, find, delete)
        # @param operation [Symbol] :add, :find, or :delete
        # @param pass_type [Symbol] :generic or :internet
        # @param options   [Hash]   Operation options (account, service, password, label, etc.)
        # @return [Hash, nil] Parsed attributes for :find, or nil
        def password(operation, pass_type, options)
          Aspera.assert_values(operation, %i[add find delete]) { 'operation' }
          Aspera.assert_values(pass_type, %i[generic internet]) { 'pass_type' }
          Aspera.assert_type(options, Hash)
          missing = (operation.eql?(:add) ? %i[account service password] : %i[label]) - options.keys
          Aspera.assert(missing.empty?) { "missing options: #{missing}" }
          options[:getpass] = '' if operation.eql?(:find)
          stdout, stderr, status = self.class.execute("#{operation}-#{pass_type}-password", options, ADD_PASS_OPTIONS, @path, exception: false)
          unless status.success?
            return if operation.eql?(:find) && status.exitstatus.eql?(EXIT_ITEM_NOT_FOUND)
            raise Error, stderr.strip.gsub(/^.*: /, '')
          end
          return unless operation.eql?(:find)
          attributes = {}
          # Attributes are on stdout, password (option -g) is on stderr
          "#{stdout}\n#{stderr}".split("\n").each do |line|
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

        # Unlock this keychain with its password
        # @param password [String] Password of the keychain
        # @return [Array(String, String, Process::Status)] Execution result
        def unlock(password:)
          self.class.execute('unlock-keychain', {password: password}, KEYCHAIN_OPTIONS, @path)
        end

        # Lock this keychain
        # @return [Array(String, String, Process::Status)] Execution result
        def lock
          self.class.execute('lock-keychain', nil, nil, @path)
        end

        # Delete this keychain file from disk
        # @return [Array(String, String, Process::Status)] Execution result
        def delete
          self.class.execute('delete-keychain', nil, nil, @path)
        end

        # Configure settings for this keychain (lock timeout, lock on sleep)
        # @param timeout       [Integer, nil] Inactivity timeout in seconds
        # @param lock_on_sleep [Boolean]      Whether to lock when system sleeps
        # @return [Array(String, String, Process::Status)] Execution result
        def set_settings(timeout: nil, lock_on_sleep: false)
          args = [SECURITY_UTILITY, 'set-keychain-settings']
          args.push('-l') if lock_on_sleep
          args.push('-u', '-t', timeout.to_s) if timeout
          args.push(@path)
          Environment.secure_execute(*args, mode: :capture)
        end
      end
    end

    # Vault backend implementation wrapping macOS system keychain
    class MacosSystem < Base
      # Account is mandatory in keychain: used when no username is provided
      NO_ACCOUNT = 'none'
      private_constant :NO_ACCOUNT

      # @param name [String, nil] Specific keychain name, or nil for default
      def initialize(name: nil)
        super()
        @keychain_name = name.nil? ? 'default keychain' : name
        @keychain = name.nil? ? MacosSecurity::Keychain.default : MacosSecurity::Keychain.by_name(name)
        Aspera.assert(!@keychain.nil?) { "no such keychain #{name}" }
      end

      # @return [Hash] Vault information metadata
      def info
        return {
          keychain: @keychain_name
        }
      end

      # Overview of all secrets (not supported on macOS due to OS restrictions)
      # @raise [Error] Always raised
      def all
        # the only way to list is `dump-keychain` which triggers security alert
        raise Error, 'overview not implemented, use macos keychain app'
      end

      # Store a secret in the keychain
      # @param options [Hash] Secret attributes (label, password, username, description)
      # @return [Hash, nil] Result
      def set(options)
        validate_set(options)
        @keychain.password(
          :add, :generic, service: options[:label],
          account: options[:username] || NO_ACCOUNT, password: options[:password], comment: options[:description]
        )
      end

      # Retrieve a secret by label
      # @param label     [String]  Secret label identifier
      # @param exception [Boolean] Whether to raise if not found
      # @return [Hash, nil] Secret attributes or nil
      def get(label:, exception: true)
        info = @keychain.password(:find, :generic, label: label)
        if info.nil?
          raise "Secret '#{label}' not found" if exception
          return
        end
        return {
          label:       label,
          username:    (info['acct'] unless info['acct'].eql?(NO_ACCOUNT)),
          password:    info['password'],
          description: info['icmt']
        }.compact
      end

      # Delete a secret by label
      # @param label [String] Secret label identifier
      # @return [Hash, nil] Result
      def delete(label:)
        @keychain.password(:delete, :generic, label: label)
      end
    end
  end
end
