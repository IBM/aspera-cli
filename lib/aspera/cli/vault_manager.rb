# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/cli/info'
require 'aspera/cli/security'
require 'aspera/cli/deprecation'
require 'aspera/secret/reference'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # Secrets of the vault, shared in `Context#vault`: read by `@vault:`, managed by `config vault`, written by presets.
    # Option `vault`: named stores (`stores`), the name of the default store (`default`) and the cache of references (`cache_ttl`), see `Secret::Resolver`.
    # - `<label>.<field>`: secret of the default store, unlocked with option `vault_password`, managed by label
    # - `//<store>/<path>[?<options>][#<field>]`: reference to a secret of a store, read only
    #
    # Values `@file:<path>` in these options (e.g. `token`) are read by `Secret::Bootstrap`, not by `ExtendedValue`:
    # they are checked here as extended value `@file:`, so that option `security` applies (e.g. in MCP server mode).
    class VaultManager
      # Beginning of a reference after `@vault:`, `secret://` without `secret:`
      REFERENCE_PREFIX = '//'
      # File of type `file`, in the configuration folder
      DEFAULT_FILE = 'vault.bin'
      # Name of the default store, not given to `Secret::Resolver`
      DEFAULT_KEY = 'default'
      STORES_KEY = 'stores'
      # Keys of option `vault`, others are parameters of a store (deprecated form)
      OPTION_KEYS = [DEFAULT_KEY, 'cache_ttl', STORES_KEY].freeze
      private_constant :DEFAULT_FILE, :DEFAULT_KEY, :STORES_KEY, :OPTION_KEYS

      class << self
        # Value of option `vault` when set (`convert` of option): the parameters of one store (deprecated) are
        # a store named after its type, which is the default store.
        # @param value [Hash] Value of option `vault`
        # @return [Hash] Value with `stores`
        def convert_option(value)
          value = value.transform_keys(&:to_s)
          params = value.except(*OPTION_KEYS)
          return value if params.empty?
          params['type'] ||= 'file'
          name = params['type'].to_s
          Log.log.warn do
            "option vault: parameters of one store are #{Deprecation.new(last: '4.28.0', message: "set a store in #{STORES_KEY}, and its name in #{DEFAULT_KEY}: {\"#{DEFAULT_KEY}\":\"#{name}\",\"#{STORES_KEY}\":{\"#{name}\":{...}}}")}"
          end
          value.slice(*OPTION_KEYS).merge(DEFAULT_KEY => name, STORES_KEY => (value[STORES_KEY] || {}).merge(name => params))
        end
      end

      # @param options     [Parser] Options `vault` and `vault_password`
      # @param main_folder [String] Folder of relative paths of vault files
      def initialize(options, main_folder)
        @options = options
        @main_folder = main_folder
        @resolver = nil
        # Name of the default store, `nil` if none
        @default = nil
      end

      # Default store, opened when first used.
      # @param mandatory [Boolean] Raise if not configured
      # @return [Secret::Store::Base, nil] Store, `nil` if not configured
      def store(mandatory: false)
        return if resolver(mandatory: mandatory).nil?
        Aspera.assert(!mandatory || !@default.nil?, type: BadArgument) { "option vault: no default store: set #{DEFAULT_KEY}" }
        @resolver.store(@default) unless @default.nil?
      end

      # Value of `@vault:`
      # @param name [String] `<label>.<field>` or `//<store>/<path>[?<options>][#<field>]`
      # @return [String] Value of secret
      def value(name)
        return resolver(mandatory: true).resolve(reference_text(name)) if name.start_with?(REFERENCE_PREFIX)
        # Label may contain dots (e.g. preset name)
        label, _, param = name.rpartition('.')
        Aspera.assert(!label.empty? && !param.empty?, type: BadArgument) { 'vault name shall match <name>.<param>' }
        info = store(mandatory: true).get(label: label)
        value = info[param.to_sym]
        raise "no such entry value: #{param}" if value.nil?
        value
      end

      # Checks that a reference can be read, without its value
      # @param name [String] `//<store>/<path>[?<options>][#<field>]`
      # @return [Hash] `store`, `version`, `updated_time`
      def metadata(name)
        Aspera.assert(name.start_with?(REFERENCE_PREFIX), type: BadArgument) { "expecting a reference: @vault:#{REFERENCE_PREFIX}<store>/<path>[?<options>][#<field>]" }
        resolver(mandatory: true).metadata(reference_text(name))
      end

      private

      # Resolver of the stores of option `vault`, created when first used.
      # Not kept when not configured: options may be set later (e.g. by the global preset).
      # @param mandatory [Boolean] Raise if not configured
      # @return [Secret::Resolver, nil] Resolver, `nil` if not configured
      def resolver(mandatory: false)
        @resolver ||= create_resolver
        Aspera.assert(!mandatory || !@resolver.nil?, type: BadArgument) { 'Missing mandatory option: vault' }
        @resolver
      end

      # @return [Secret::Resolver, nil] Resolver of option `vault`, `nil` if not configured
      def create_resolver
        config = @options.get_option(:vault, mandatory: false)
        return if config.nil? || (config.is_a?(Hash) && config.empty?)
        Aspera.assert_type(config, Hash, type: BadArgument) { 'option vault' }
        config = config.transform_keys(&:to_s)
        stores = config[STORES_KEY]
        Aspera.assert_type(stores, Hash, type: BadArgument) { "option vault: #{STORES_KEY}" }
        stores = stores.to_h { |name, params| [name.to_s, store_parameters(params)] }
        default = config.delete(DEFAULT_KEY)&.to_s
        Aspera.assert(default.nil? || stores.key?(default), type: BadArgument) { "option vault: #{DEFAULT_KEY}: no store #{default}" }
        check_file_values(:vault, stores)
        add_vault_password(stores[default]) unless default.nil?
        require 'aspera/secret/resolver'
        resolver = Secret::Resolver.new(config.merge(STORES_KEY => stores))
        @default = default
        resolver
      end

      # Parameters of a store, with the defaults of `ascli`
      # @param params [Hash] Parameters of a store of option `vault`
      # @return [Hash] Parameters of `Secret::Store::Factory`, Symbol keys
      def store_parameters(params)
        Aspera.assert_type(params, Hash, type: BadArgument) { 'option vault: store' }
        params = params.transform_keys(&:to_sym)
        case params[:type]
        when 'file'
          # `name`: same as `file`, for compatibility
          file = params.delete(:name) || params[:file] || DEFAULT_FILE
          params[:file] = file.is_a?(String) && !File.absolute_path?(file) ? File.join(@main_folder, file) : file
        when 'system'
          params[:name] ||= Info::CMD_NAME
        end
        params
      end

      # Option `vault_password` is the secret of the default store, if not in its parameters
      # @param params [Hash] Parameters of the default store, modified
      def add_vault_password(params)
        key =
          case params[:type]
          when 'file' then :password
          when 'vault' then :token unless params.key?(:approle)
          when '1password' then :token unless params[:source].eql?('cli')
          end
        return if key.nil? || params.key?(key)
        password = @options.get_option(:vault_password)
        Aspera.assert(!password.nil? || !params[:type].eql?('file'), type: BadArgument) { 'Missing mandatory option: vault_password' }
        return if password.nil?
        check_file_values(:vault_password, password)
        params[key] = password
      end

      # Values `@file:<path>` are read like extended value `@file:`, see `Security`
      # @param option [Symbol] Name of option, for errors
      # @param value  [Object] Value of option
      # @raise [BadArgument] Reading a file is refused at current security level
      def check_file_values(option, value)
        file_paths(value).each do |path|
          Security.instance.check_extended_value(:file)
          Security.instance.readable_path(path)
        end
      rescue BadArgument => e
        raise BadArgument, "option #{option}: #{e.message}"
      end

      # @param value [Object] Value of option
      # @return [Array<String>] Paths of values `@file:<path>`, also in nested values
      def file_paths(value)
        case value
        when Hash then value.values.flat_map { |v| file_paths(v) }
        when Array then value.flat_map { |v| file_paths(v) }
        when String then value.start_with?(Secret::Bootstrap::FILE_PREFIX) ? [value.delete_prefix(Secret::Bootstrap::FILE_PREFIX)] : []
        else []
        end
      end

      # @return [String] Reference `secret://...` of value of `@vault://...`
      def reference_text(name)
        "#{Secret::SCHEME}#{name.delete_prefix(REFERENCE_PREFIX)}"
      end
    end
  end
end
