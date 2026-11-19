# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'extended_value'
require_relative 'vault_manager'
require_relative '../dot_container'
require_relative 'version'
require_relative 'info'
require_relative '../environment'
require_relative '../log'
require_relative '../assert'
require_relative '../secret/hider'
require_relative '../yaml'
require_relative '../rainbow'
require 'digest'
require 'fileutils'
require 'yaml'
using Rainbow

module Aspera
  module Cli
    # Manages the YAML config file and all preset-related operations.
    # Extracted from Plugins::Config so it can be referenced independently
    # via Context#presets without coupling to the plugin machinery.
    class PresetManager
      # Reserved keys in the YAML config file
      module Key
        # Section of the config file itself (holds its version)
        CONFIG      = 'config'
        # Key of the version of the config file, in section CONFIG
        VERSION     = 'version'
        # Section that maps a plugin name to its default preset name
        DEFAULTS    = 'default'
        # Name of the global default preset, when none is declared
        GLOBAL      = 'global_common_defaults'
        # Prefix for comment/meta keys ignored during preset parsing (e.g. _comment)
        META_PREFIX = '_'
        # Key of the free text describing a preset (ignored when the preset is applied)
        COMMENT     = "#{META_PREFIX}comment".freeze
      end

      # Preset name given on command line to designate the global default preset
      GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
      # Plugin name under which the global default preset is declared in section DEFAULTS
      CONF_GLOBAL_SYM        = :config
      # Separator for dot-notation digging into presets
      PRESET_DIG_SEPARATOR = '.'

      private_constant :PRESET_DIG_SEPARATOR

      # Load the config file (created in memory if it does not exist).
      # @param config_file         [String]  Absolute path to the YAML config file
      # @param use_plugin_defaults [Boolean] `false`: plugin default presets are not applied (see #plugin_default_name)
      def initialize(config_file:, use_plugin_defaults: true)
        @config_file         = config_file
        @use_plugin_defaults = use_plugin_defaults
        @config_presets      = {}
        @checksum_on_disk    = nil
        read_config_file
      end

      attr_reader :config_file, :config_presets, :use_plugin_defaults
      attr_writer :use_plugin_defaults

      # ------------------------------------------------------------------
      # File I/O
      # ------------------------------------------------------------------

      # Checksum of the presets in memory, compared to the one of the file to save only when changed.
      # @return [String] SHA256 hex digest of the in-memory presets
      def checksum
        Digest::SHA256.hexdigest(JSON.generate(@config_presets))
      end

      # Read and validate the YAML config file.
      # Sets @config_presets and @checksum_on_disk, and declares the secrets found in presets to the secret hider.
      # A file that cannot be read (YAML error, duplicate keys, access) is left untouched: it shall be fixed.
      # A file with an unexpected structure is renamed for manual conversion, and a new one is created next time.
      # @return [void]
      # @raise [Psych::SyntaxError] YAML syntax error in config file
      # @raise [Cli::Error] Config file cannot be read, or has an unexpected structure
      def read_config_file
        Log.log.debug { "config file is: #{@config_file}".red }
        if File.exist?(@config_file)
          Log.log.debug { "loading #{@config_file}" }
          begin
            # Before checksum: the conversion alone does not save the file
            @config_presets = self.class.stringify_secrets(nil, Yaml.safe_load(File.read(@config_file)))
          rescue Psych::SyntaxError
            Log.log.error { "YAML error in config file: #{@config_file}" }
            raise
          rescue StandardError => e
            raise Cli::Error, "Config file #{@config_file}: #{e.message}"
          end
          @checksum_on_disk = checksum
        else
          Log.log.warn { "No config file found. New configuration file: #{@config_file}" }
          @config_presets = {Key::CONFIG => {Key::VERSION => 'new file'}}
          # @checksum_on_disk remains nil: will be saved on first write
        end
        begin
          validate_config_presets!
        rescue StandardError => e
          Log.log.debug { "-> #{e.class.name} : #{e}" }
          if File.exist?(@config_file)
            new_name = "#{@config_file}.pre#{Cli::VERSION}.manual_conversion_needed"
            File.rename(@config_file, new_name)
            Log.log.warn { "Renamed config file to #{new_name}." }
            Log.log.warn('Manual Conversion is required. Next time, a new empty file will be created.')
          end
          raise Cli::Error, e.to_s
        end
        # Hidden wherever they appear (logs, results), also when copied under another key name
        Secret::Hider.instance.add_secrets_in(@config_presets)
      end

      # Save to disk only if content changed since last load/save.
      # @return [Boolean] true if actually written
      def save_if_needed
        Aspera.assert(!@config_presets.nil?, type: Cli::Error) { 'no configuration loaded' }
        current = checksum
        return false if @checksum_on_disk.eql?(current)
        FileUtils.mkdir_p(File.dirname(@config_file))
        Environment.restrict_file_access(File.dirname(@config_file))
        Log.log.info { "Saving config file: #{@config_file}" }
        Environment.write_file_restricted(@config_file, force: true) { @config_presets.to_yaml }
        @checksum_on_disk = current
        true
      end

      # ------------------------------------------------------------------
      # Preset read/write helpers
      # ------------------------------------------------------------------

      # Name of the default preset declared for a plugin in the `default` section.
      # @param plugin_name_sym [Symbol] Plugin name (e.g. `:aoc`), or CONF_GLOBAL_SYM for the global default
      # @return [String, nil] Name of the default preset, or `nil` if none, or if plugin defaults are disabled
      # @raise [Cli::Error] The default preset is declared but does not exist, or is not a Hash
      def plugin_default_name(plugin_name_sym)
        Aspera.assert(!@config_presets.nil?, 'config_presets shall be defined')
        return unless @use_plugin_defaults
        return unless @config_presets.key?(Key::DEFAULTS)
        Aspera.assert_type(@config_presets[Key::DEFAULTS], Hash) { 'default section' }
        return unless @config_presets[Key::DEFAULTS].key?(plugin_name_sym.to_s)
        default_name = @config_presets[Key::DEFAULTS][plugin_name_sym.to_s]
        unless @config_presets.key?(default_name)
          Log.log.error do
            "Default config name [#{default_name}] specified for plugin [#{plugin_name_sym}], but it does not exist in config file.\n" \
              "Please fix: either create preset:\n" \
              "#{Info::CMD_NAME} config preset set #{default_name} @: url=...\n" \
              "or remove default:\n#{Info::CMD_NAME} config preset set #{Key::DEFAULTS} #{plugin_name_sym} @none:"
          end
          raise Cli::Error, "No such preset: #{default_name}"
        end
        Aspera.assert_type(@config_presets[default_name], Hash, type: Cli::Error) { 'preset type' }
        default_name
      end

      # Resolve and return a deep-cloned, extended copy of a named preset.
      # Supports dot-notation (e.g. "outer.inner").
      # Meta keys (prefix `_`) are removed, extended values are evaluated, and a secret read alone is declared to the secret hider.
      # @param config_name  [String]        Preset name, optionally followed by dot-separated sub keys
      # @param include_path [Array<String>] Names already being resolved, to detect include loops
      # @return [Hash, String, Object] Copy of the preset, or of the selected sub value
      # @raise [Cli::Error] Unknown preset or sub key, or include loop
      def by_name(config_name, include_path = [])
        Aspera.assert(!include_path.include?(config_name), type: Cli::Error) { 'loop in include' }
        include_path = include_path.clone
        current = @config_presets
        # A preset name may contain a dot (e.g. a host name): the longest name of an existing preset is used
        parts = config_name.split(PRESET_DIG_SEPARATOR)
        count = parts.length.downto(1).find { |n| @config_presets.key?(parts.first(n).join(PRESET_DIG_SEPARATOR)) } || 1
        names = [parts.first(count).join(PRESET_DIG_SEPARATOR)] + parts.drop(count)
        names.each do |name|
          Aspera.assert_type(current, Hash, type: Cli::Error) { "sub key: #{include_path}" }
          include_path.push(name)
          current = current[name]
          Aspera.assert(!current.nil?, type: Cli::Error) { "Unknown config preset: #{include_path}" }
        end
        current = self.class.deep_clone(current) unless current.is_a?(String)
        current.delete_if { |k, _| k.to_s.start_with?(Key::META_PREFIX) } if current.is_a?(Hash)
        current = ExtendedValue.instance.evaluate(current, context: 'preset')
        # A secret read alone has no key name: declared, so that it is hidden wherever it appears
        Secret::Hider.instance.add_secret_values(current) if Secret::Hider.instance.secret?(names.last, current)
        current
      end

      # Set a single key in a preset hash (creates the preset if absent).
      # If param_name contains dots, it is treated as a dot-path and deep-merged into the preset.
      # If param_value is nil, the key is deleted instead.
      # Numeric secrets are converted to String (see .stringify_secrets).
      # @param preset      [String]         Name of preset
      # @param param_name  [String, Symbol] Key name, or dot-path of the key in the preset
      # @param param_value [Object, nil]    Value to set, or `nil` to delete the key
      # @return [nil]
      def set_key(preset, param_name, param_value)
        Aspera.assert_type(param_name, String, Symbol) { 'parameter' }
        param_name = param_name.to_s
        param_value = self.class.stringify_secrets(param_name.split(DotContainer::SEPARATOR).last, param_value)
        selected = @config_presets[preset]
        if selected.nil?
          Log.log.debug { "Unknown preset name: #{preset}, initializing" }
          selected = @config_presets[preset] = {}
        end
        Aspera.assert_type(selected, Hash) { "#{preset}.#{param_name}" }
        if param_name.include?(DotContainer::SEPARATOR)
          keys = param_name.split(DotContainer::SEPARATOR)
          # Navigate to the parent hash
          parent = keys[0..-2].reduce(selected) do |h, k|
            break nil unless h.is_a?(Hash)
            h[k]
          end
          if param_value.nil?
            parent&.delete(keys.last)
            Log.log.info("Deleted: #{preset}: #{param_name}")
          else
            # dot-path: build nested hash and deep-merge into existing preset
            nested = DotContainer.dotted_to_container(keys, param_value)
            self.class.deep_merge!(selected, nested)
            Log.log.info("Updated: #{preset}: #{param_name} <- #{param_value}")
          end
        elsif param_value.nil?
          selected.delete(param_name)
          Log.log.info("Deleted: #{preset}: #{param_name}")
        else
          if selected.key?(param_name)
            if selected[param_name].eql?(param_value)
              Log.log.warn { "keeping same value for #{preset}: #{param_name}: #{param_value}" }
              return
            end
            Log.log.warn { "overwriting value for #{param_name}: #{selected[param_name]}" }
          end
          selected[param_name] = param_value
          Log.log.info("Updated: #{preset}: #{param_name} <- #{param_value}")
        end
        nil
      end

      # Name of the global default preset: declared in `default` under `config`, else `global_common_defaults`.
      # @param create [Boolean] `true`: declare and create the global default preset if needed (to write in it)
      # @return [String] name of the global default preset
      def global_default_preset(create: true)
        result = plugin_default_name(CONF_GLOBAL_SYM)
        if result.nil?
          result = Key::GLOBAL
          if create
            set_key(Key::DEFAULTS, CONF_GLOBAL_SYM, result)
            # A default declaration requires the preset to exist
            @config_presets[result] ||= {}
          end
        end
        result
      end

      # @param preset_name [String] Name of preset
      # @return [Boolean] true if `preset_name` is declared as the global default preset (does not create it)
      def global_preset?(preset_name)
        defaults = @config_presets[Key::DEFAULTS]
        defaults.is_a?(Hash) && defaults[CONF_GLOBAL_SYM.to_s].eql?(preset_name)
      end

      # Set a parameter in the global default preset (created if needed).
      # @param key   [String, Symbol] Key name, or dot-path of the key
      # @param value [Object, nil]    Value to set, or `nil` to delete the key
      # @return [nil]
      def set_global_default(key, value)
        set_key(global_default_preset, key, value)
      end

      # Create or overwrite a preset, and optionally set it as default for the plugin (used by the wizard).
      # @param plugin_name_sym [Symbol]  Plugin name (e.g. `:aoc`)
      # @param preset_name     [String]  Name of preset to create
      # @param preset_values   [Hash]    Content of preset
      # @param option_default  [Boolean] `true`: set the preset as default for the plugin
      # @param option_override [Boolean] `true`: replace an existing preset or plugin default
      # @return [Hash] preset_values
      # @raise [Cli::Error] The preset, or the plugin default, already exists, and option_override is `false`
      def defaults_set(plugin_name_sym, preset_name, preset_values, option_default, option_override)
        @config_presets[Key::DEFAULTS] ||= {}
        raise Cli::Error, "A default configuration already exists for plugin '#{plugin_name_sym}' (use wizard key override=yes or default=no)" \
          if !option_override && option_default && @config_presets[Key::DEFAULTS].key?(plugin_name_sym.to_s)
        raise Cli::Error, "Preset already exists: #{preset_name}  (use wizard key override=yes or provide alternate preset name)" \
          if !option_override && @config_presets.key?(preset_name)
        if option_default
          Log.log.info("Setting config preset as default for #{plugin_name_sym}")
          @config_presets[Key::DEFAULTS][plugin_name_sym.to_s] = preset_name
        end
        @config_presets[preset_name] = preset_values
      end

      # Find the first preset whose url and username match (URLs compared without trailing `/` and default port 443).
      # @param url      [String] URL of server
      # @param username [String] User name
      # @return [Hash, nil] Copy of the preset, or `nil` if none matches
      def lookup_preset(url:, username:)
        url = canonical_url(url)
        Log.log.debug { "Lookup preset for #{username}@#{url}" }
        @config_presets.each_value do |v|
          next unless v.is_a?(Hash)
          conf_url = v['url'].is_a?(String) ? canonical_url(v['url']) : nil
          return self.class.deep_clone(v) if conf_url.eql?(url) && v['username'].eql?(username)
        end
        nil
      end

      # ------------------------------------------------------------------
      # Class helpers
      # ------------------------------------------------------------------

      class << self
        # Deep copy of a value (containers included).
        # @param val [Object] Value to copy
        # @return [Object] Copy of val
        def deep_clone(val)
          Marshal.load(Marshal.dump(val))
        end

        # Recursively merge src into dst in place (src wins on scalar conflicts).
        # @param dst [Hash] destination (modified in place)
        # @param src [Hash] source
        # @return [Hash] dst
        def deep_merge!(dst, src)
          src.each do |k, v|
            if dst.key?(k) && dst[k].is_a?(Hash) && v.is_a?(Hash)
              deep_merge!(dst[k], v)
            else
              dst[k] = v
            end
          end
          dst
        end

        # A secret is a String: a number under a secret key name (e.g. password `12345678`, unquoted in YAML or set on command line)
        # is converted, else it is not identified as a secret, and is shown in results
        # @param key   [String, nil] Key name of value
        # @param value [Object]      Value: containers are modified in place
        # @return [Object] Value, or its String if it is a secret
        def stringify_secrets(key, value)
          case value
          when Hash then value.each { |k, v| value[k] = stringify_secrets(k, v) }
          when Array then value.map! { |v| stringify_secrets(nil, v) }
          when Numeric then value = value.to_s if Secret::Hider.instance.secret?(key, value.to_s)
          end
          value
        end
      end

      private

      # Normalize a URL for comparison: no trailing `/`, no default HTTPS port.
      # @param url [String] URL
      # @return [String] Normalized URL
      def canonical_url(url)
        url.chomp('/').sub(%r{^(https://[^/]+):443$}, '\1')
      end

      # Structural validation and compatibility fixes on @config_presets, stamped with the current version.
      # @return [void]
      # @raise [Cli::Error, StandardError] Unexpected structure
      def validate_config_presets!
        Log.dump(:available_presets, @config_presets, level: :trace1)
        Aspera.assert_type(@config_presets, Hash) { 'config file YAML' }
        Aspera.assert(@config_presets.key?(Key::CONFIG)) { "Cannot find key: #{Key::CONFIG}" }
        version = @config_presets[Key::CONFIG][Key::VERSION]
        Aspera.assert(!version.nil?, type: Cli::Error) { 'No version found in config section.' }
        Log.log.debug { "conf version: #{version}" }
        # Fix bug in 4.4 (creating key "true" in "default" preset)
        @config_presets[Key::DEFAULTS].delete(true) if @config_presets[Key::DEFAULTS].is_a?(Hash)
        # Migrate deprecated vault format in presets if present
        migrate_vault_configs!
        # Stamp with current version
        @config_presets[Key::CONFIG][Key::VERSION] = Cli::VERSION
      end

      # Migrates deprecated vault options in presets to the new format (stores and default)
      # and saves a backup of the original config file.
      # @return [void]
      def migrate_vault_configs!
        migrated = false
        @config_presets.each_value do |preset|
          next unless preset.is_a?(Hash)
          vault_config = preset['vault'] || preset[:vault]
          next unless vault_config.is_a?(Hash)
          converted = VaultManager.convert_option(vault_config)
          if converted != vault_config
            preset['vault'] = converted
            preset.delete(:vault) if preset.key?(:vault)
            migrated = true
          end
        end
        return unless migrated && File.exist?(@config_file)
        backup_file = "#{@config_file}.pre#{Cli::VERSION}.bak"
        FileUtils.cp(@config_file, backup_file)
        Environment.restrict_file_access(backup_file)
        Log.log.warn { "Migrated vault option in #{@config_file} (backup saved to #{backup_file})" }
        Environment.write_file_restricted(@config_file, force: true) { @config_presets.to_yaml }
        @checksum_on_disk = checksum
      end
    end
  end
end
