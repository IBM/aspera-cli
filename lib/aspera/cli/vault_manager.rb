# frozen_string_literal: true

require 'aspera/cli/error'
require 'aspera/cli/info'
require 'aspera/cli/security'
require 'aspera/secret/reference'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  module Cli
    # Secrets of the vault, shared in `Context#vault`: read by `@vault:`, managed by `config vault`, written by presets.
    # - `<label>.<field>`: store of option `vault` (unlocked with option `vault_password`), managed by label
    # - `//<store>/<path>[?<options>][#<field>]`: reference to a store of option `vault_references` (`Secret::Resolver`), read only
    #
    # Values `@file:<path>` in these options (e.g. `token`) are read by `Secret::Bootstrap`, not by `ExtendedValue`:
    # they are checked here as extended value `@file:`, so that option `security` applies (e.g. in MCP server mode).
    class VaultManager
      # Beginning of a reference after `@vault:`, `secret://` without `secret:`
      REFERENCE_PREFIX = '//'

      # @param options     [Parser] Options `vault`, `vault_password` and `vault_references`
      # @param main_folder [String] Folder of relative paths of vault files
      def initialize(options, main_folder)
        @options = options
        @main_folder = main_folder
        @store = nil
        @resolver = nil
      end

      # Store of option `vault`, opened when first used.
      # Not kept when not configured: options may be set later (e.g. by the global preset).
      # @param mandatory [Boolean] Raise if not configured
      # @return [Secret::Store::Base, nil] Store, `nil` if not configured
      def store(mandatory: false)
        @store ||= open_store
        Aspera.assert(!mandatory || !@store.nil?, type: BadArgument) { 'Missing mandatory option: vault' }
        @store
      end

      # Value of `@vault:`
      # @param name [String] `<label>.<field>` or `//<store>/<path>[?<options>][#<field>]`
      # @return [String] Value of secret
      def value(name)
        return resolver.resolve(reference_text(name)) if name.start_with?(REFERENCE_PREFIX)
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
        resolver.metadata(reference_text(name))
      end

      private

      # @return [Secret::Store::Base, nil] Store of option `vault`, `nil` if not configured
      def open_store
        info = @options.get_option(:vault, mandatory: false)
        return if info.nil? || (info.is_a?(Hash) && info.empty?)
        info = info.transform_keys(&:to_sym)
        info[:type] ||= 'file'
        password = @options.get_option(:vault_password)
        check_file_values(:vault, info)
        # Token of type `vault` when not in `vault`
        check_file_values(:vault_password, password)
        require 'aspera/secret/store/factory'
        Secret::Store::Factory.create(info, Info::CMD_NAME, @main_folder, password)
      end

      # @return [Secret::Resolver] Resolver of option `vault_references`, created when first used
      def resolver
        return @resolver unless @resolver.nil?
        config = @options.get_option(:vault_references, mandatory: false)
        Aspera.assert(config.is_a?(Hash) && !config.empty?, type: BadArgument) { 'Missing mandatory option: vault_references' }
        check_file_values(:vault_references, config)
        require 'aspera/secret/resolver'
        @resolver = Secret::Resolver.new(resolver_config(config))
      end

      # Relative paths of stores of type `file` are relative to the configuration folder, as for option `vault`
      # @param config [Hash] Value of option `vault_references`
      # @return [Hash] Configuration of `Secret::Resolver`
      def resolver_config(config)
        config = config.transform_keys(&:to_s)
        return config unless config['stores'].is_a?(Hash)
        stores = config['stores'].transform_values do |params|
          next params unless params.is_a?(Hash)
          params = params.transform_keys(&:to_s)
          file = params['file']
          next params unless params['type'].to_s.eql?('file') && file.is_a?(String) && !File.absolute_path?(file)
          params.merge('file' => File.join(@main_folder, file))
        end
        config.merge('stores' => stores)
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
