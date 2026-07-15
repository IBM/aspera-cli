# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/version'
require 'aspera/cli/info'
require 'aspera/log'
require 'aspera/assert'
require 'digest'
require 'yaml'

module Aspera
  module Cli
    # Manages the YAML config file and all preset-related operations.
    # Extracted from Plugins::Config so it can be referenced independently
    # via Context#presets without coupling to the plugin machinery.
    class PresetManager
      # Reserved preset / section names
      CONF_PRESET_CONFIG   = 'config'
      CONF_PRESET_VERSION  = 'version'
      CONF_PRESET_DEFAULTS = 'default'
      CONF_PRESET_GLOBAL   = 'global_common_defaults'
      GLOBAL_DEFAULT_KEYWORD = 'GLOBAL'
      CONF_GLOBAL_SYM      = :config
      # Separator for dot-notation digging into presets
      PRESET_DIG_SEPARATOR = '.'

      private_constant :CONF_PRESET_CONFIG,
        :CONF_PRESET_VERSION,
        :CONF_PRESET_DEFAULTS,
        :CONF_PRESET_GLOBAL,
        :PRESET_DIG_SEPARATOR

      # @param config_file [String]       absolute path to the YAML config file
      # @param use_plugin_defaults [Boolean] if false, skip default preset lookup
      def initialize(config_file:, use_plugin_defaults: true)
        @config_file         = config_file
        @use_plugin_defaults = use_plugin_defaults
        @config_presets      = {}
        @checksum_on_disk    = nil
        read_config_file
      end

      attr_reader :config_presets, :use_plugin_defaults
      attr_writer :use_plugin_defaults

      # ------------------------------------------------------------------
      # File I/O
      # ------------------------------------------------------------------

      # @return [String] SHA1 of current in-memory presets
      def checksum
        Digest::SHA1.hexdigest(JSON.generate(@config_presets))
      end

      # Read and validate the YAML config file.
      # Sets @config_presets and @checksum_on_disk.
      def read_config_file
        Log.log.debug{"config file is: #{@config_file}".red}
        if File.exist?(@config_file)
          Log.log.debug{"loading #{@config_file}"}
          @config_presets   = YAML.load_file(@config_file)
          @checksum_on_disk = checksum
        else
          Log.log.warn{"No config file found. New configuration file: #{@config_file}"}
          @config_presets = {CONF_PRESET_CONFIG => {CONF_PRESET_VERSION => 'new file'}}
          # @checksum_on_disk remains nil → will be saved on first write
        end
        validate_config_presets!
      rescue Psych::SyntaxError => e
        Log.log.error('YAML error in config file')
        raise e
      rescue StandardError => e
        Log.log.debug{"-> #{e.class.name} : #{e}"}
        if File.exist?(@config_file)
          new_name = "#{@config_file}.pre#{Cli::VERSION}.manual_conversion_needed"
          File.rename(@config_file, new_name)
          Log.log.warn{"Renamed config file to #{new_name}."}
          Log.log.warn('Manual Conversion is required. Next time, a new empty file will be created.')
        end
        raise Cli::Error, e.to_s
      end

      # Save to disk only if content changed since last load/save.
      # @return [Boolean] true if actually written
      def save_if_needed
        raise Cli::Error, 'no configuration loaded' if @config_presets.nil?
        current = checksum
        return false if @checksum_on_disk.eql?(current)
        FileUtils.mkdir_p(File.dirname(@config_file))
        Environment.restrict_file_access(File.dirname(@config_file))
        Log.log.info{"Saving config file: #{@config_file}"}
        Environment.write_file_restricted(@config_file, force: true){ @config_presets.to_yaml }
        @checksum_on_disk = current
        true
      end

      # ------------------------------------------------------------------
      # Preset read/write helpers
      # ------------------------------------------------------------------

      # @return [String, nil] name of the default preset for a plugin, or nil
      def plugin_default_name(plugin_name_sym)
        Aspera.assert(!@config_presets.nil?, 'config_presets shall be defined')
        return nil unless @use_plugin_defaults
        return nil unless @config_presets.key?(CONF_PRESET_DEFAULTS)
        Aspera.assert_type(@config_presets[CONF_PRESET_DEFAULTS], Hash){'default section'}
        return nil unless @config_presets[CONF_PRESET_DEFAULTS].key?(plugin_name_sym.to_s)
        default_name = @config_presets[CONF_PRESET_DEFAULTS][plugin_name_sym.to_s]
        unless @config_presets.key?(default_name)
          Log.log.error do
            "Default config name [#{default_name}] specified for plugin [#{plugin_name_sym}], but it does not exist in config file.\n" \
              "Please fix: either create preset:\n" \
              "#{Info::CMD_NAME} config id #{default_name} init @json:'{}'\n" \
              "or remove default:\n#{Info::CMD_NAME} config id default remove #{plugin_name_sym}"
          end
          raise Cli::Error, "No such preset: #{default_name}"
        end
        Aspera.assert_type(@config_presets[default_name], Hash, type: Cli::Error){'preset type'}
        default_name
      end

      # Resolve and return a deep-cloned, extended copy of a named preset.
      # Supports dot-notation (e.g. "outer.inner").
      # @param config_name [String]
      # @param include_path [Array] guard against include loops
      def by_name(config_name, include_path = [])
        raise Cli::Error, 'loop in include' if include_path.include?(config_name)
        include_path = include_path.clone
        current = @config_presets
        config_name.split(PRESET_DIG_SEPARATOR).each do |name|
          Aspera.assert_type(current, Hash, type: Cli::Error){"sub key: #{include_path}"}
          include_path.push(name)
          current = current[name]
          raise Cli::Error, "Unknown config preset: #{include_path}" if current.nil?
        end
        current = self.class.deep_clone(current) unless current.is_a?(String)
        ExtendedValue.instance.evaluate(current, context: 'preset')
      end

      # Set a single key in a preset hash (creates the preset if absent).
      def set_key(preset, param_name, param_value)
        Aspera.assert_type(param_name, String, Symbol){'parameter'}
        param_name = param_name.to_s
        selected = @config_presets[preset]
        if selected.nil?
          Log.log.debug{"Unknown preset name: #{preset}, initializing"}
          selected = @config_presets[preset] = {}
        end
        Aspera.assert_type(selected, Hash){"#{preset}.#{param_name}"}
        if selected.key?(param_name)
          if selected[param_name].eql?(param_value)
            Log.log.warn{"keeping same value for #{preset}: #{param_name}: #{param_value}"}
            return
          end
          Log.log.warn{"overwriting value for #{param_name}: #{selected[param_name]}"}
        end
        selected[param_name] = param_value
        Log.log.info("Updated: #{preset}: #{param_name} <- #{param_value}")
        nil
      end

      # @return [String] name of the global default preset, creating it if needed
      def global_default_preset
        result = plugin_default_name(CONF_GLOBAL_SYM)
        if result.nil?
          result = CONF_PRESET_GLOBAL
          set_key(CONF_PRESET_DEFAULTS, CONF_GLOBAL_SYM, result)
        end
        result
      end

      # Set param in the global defaults preset
      def set_global_default(key, value)
        set_key(global_default_preset, key, value)
      end

      # Create / overwrite a preset and optionally set it as plugin default.
      def defaults_set(plugin_name, preset_name, preset_values, option_default, option_override)
        @config_presets[CONF_PRESET_DEFAULTS] ||= {}
        raise Cli::Error, "A default configuration already exists for plugin '#{plugin_name}' (use --override=yes or --default=no)" \
          if !option_override && option_default && @config_presets[CONF_PRESET_DEFAULTS].key?(plugin_name)
        raise Cli::Error, "Preset already exists: #{preset_name}  (use --override=yes or provide alternate name on command line)" \
          if !option_override && @config_presets.key?(preset_name)
        if option_default
          Log.log.info("Setting config preset as default for #{plugin_name}")
          @config_presets[CONF_PRESET_DEFAULTS][plugin_name.to_s] = preset_name
        end
        @config_presets[preset_name] = preset_values
      end

      # Find the first preset whose url+username match
      # @return [Hash, nil]
      def lookup_preset(url:, username:)
        url = canonical_url(url)
        Log.log.debug{"Lookup preset for #{username}@#{url}"}
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
        def deep_clone(val)
          Marshal.load(Marshal.dump(val))
        end
      end

      private

      # Normalise a URL for comparison
      def canonical_url(url)
        url.chomp('/').sub(%r{^(https://[^/]+):443$}, '\1')
      end

      # Structural validation + compatibility fixes on @config_presets
      def validate_config_presets!
        Log.dump(:available_presets, @config_presets, level: :trace1)
        Aspera.assert_type(@config_presets, Hash){'config file YAML'}
        Aspera.assert(@config_presets.key?(CONF_PRESET_CONFIG)){"Cannot find key: #{CONF_PRESET_CONFIG}"}
        version = @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION]
        raise Cli::Error, 'No version found in config section.' if version.nil?
        Log.log.debug{"conf version: #{version}"}
        # Fix bug in 4.4 (creating key "true" in "default" preset)
        @config_presets[CONF_PRESET_DEFAULTS].delete(true) if @config_presets[CONF_PRESET_DEFAULTS].is_a?(Hash)
        # Stamp with current version
        @config_presets[CONF_PRESET_CONFIG][CONF_PRESET_VERSION] = Cli::VERSION
      end
    end
  end
end
