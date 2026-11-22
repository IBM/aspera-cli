# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'assert'
require_relative 'log'
require_relative 'yaml'
require_relative 'string_ext'
require_relative 'schema/registry'
require_relative 'schema/validator'
require 'singleton'

module Aspera
  # Registry of plugins: single files `<name>.rb` and bundles `<name>/plugin.yaml` of the plugin folders (sources).
  # Reads the manifests of bundles (data only): the code of a plugin is loaded on use, after the check of the security level of its source,
  # of its availability (manifest, dependencies) and of its gems.
  # Usable without the CLI: the default source is the folder of the bundles of the gem; the CLI adds its folders.
  #
  # @!method self.instance
  #   Returns the singleton instance of BundleRegistry
  #   @return [BundleRegistry] the singleton instance
  class BundleRegistry
    include Singleton

    # A plugin cannot be loaded: invalid manifest, dependency missing or unavailable, missing gem
    class Unavailable < Error; end

    # Folder of the built-in bundles of the gem
    GEM_FOLDER = File.join(__dir__, 'plugins')
    # Manifest of a bundle, in its folder
    MANIFEST = 'plugin.yaml'
    # Module of the constants of bundles: `Aspera::Plugins::<Name>::<Constant>`
    BUNDLE_MODULE = 'Aspera::Plugins'
    # Extension of a single file
    RB_EXT = '.rb'

    # Folder of plugins
    # @!attribute folder   [String]        Absolute path
    # @!attribute security [Symbol, nil]   Most restrictive security level at which the code of its plugins is used, `nil` for all levels
    # @!attribute ignore   [Array<Symbol>] Names of single files that are not plugins (e.g. base classes)
    Source = Data.define(:folder, :security, :ignore)

    # Plugin found in a source
    # @!attribute name     [Symbol]       Name of the plugin
    # @!attribute form     [Symbol]       `:single` (file `<name>.rb`: commands only) or `:bundle` (folder `<name>/` with a manifest)
    # @!attribute path     [String]       File of a single file, folder of a bundle
    # @!attribute security [Symbol, nil]  Security level of its source
    # @!attribute manifest [Hash]         Manifest of a bundle (empty if invalid); for a single file: `name` and `commands`
    # @!attribute error    [String, nil]  Why the manifest is invalid, `nil` if valid
    Plugin = Data.define(:name, :form, :path, :security, :manifest, :error) do
      # @return [Boolean] `true` for a bundle
      def bundle? = form.eql?(:bundle)
      # @return [String, nil] Title of a bundle
      def title = manifest['title']
      # @return [Boolean] `true` if the plugin provides a top level command
      def commands? = manifest['commands'].eql?(true)
      # @return [Array<Symbol>] Bundles referenced by this one
      def depends = manifest.fetch('depends', []).map(&:to_sym)
      # @return [Array<String>] Gems required by the code
      def gems = manifest.fetch('gems', [])
    end

    # @param builtin [Boolean] `true`: the folder of the bundles of the gem is a source
    def initialize(builtin: true)
      @sources = []
      # Registered plugins, by name
      @plugins = {}
      # Cache of `unavailable_reason`, by name
      @reasons = {}
      @security_allowed = ->(_level) { true }
      @security_check = ->(_level, _what) {}
      add_source(GEM_FOLDER) if builtin
    end

    # Set the checks of the security level of sources, injected by the user of the registry (the CLI gives the methods of `Cli::Security`).
    # By default, everything is allowed.
    # @param allowed [#call] `(level)`: `true` if a source of this level is scanned at the current level
    # @param check   [#call] `(level, what)`: raises if code of a source of this level may not be loaded at the current level
    # @return [nil]
    def security_checks(allowed:, check:)
      @security_allowed = allowed
      @security_check = check
      nil
    end

    # @return [Array<String>] Folders of the sources, the first one with priority
    def folders = @sources.map(&:folder)

    # Add a folder to the sources: a name found in several sources is the plugin of the first one.
    # A folder already added keeps its place, with the new security level.
    # @param folder   [String]        Folder (absolute, as `require` resolves a relative path against `$LOAD_PATH`)
    # @param security [Symbol, nil]   Most restrictive security level at which plugins of this folder are used, `nil` for all levels (folder of the gem).
    #   A folder that a user or a client can write is `:low`: a file written there would be loaded as code.
    # @param ignore   [Array<Symbol>] Names of files `<name>.rb` that are not plugins
    # @param last     [Boolean]       `false`: before the other sources, `true`: after them
    # @return [nil]
    def add_source(folder, security: nil, ignore: [], last: false)
      source = Source.new(folder: File.expand_path(folder), security: security, ignore: ignore)
      index = folders.index(source.folder)
      if index
        @sources[index] = source
      elsif last
        @sources.push(source)
      else
        @sources.unshift(source)
      end
      nil
    end

    # Register the plugins of the sources that are not registered yet.
    # A registered plugin stays, even if its source is not scanned anymore (e.g. at a higher security level).
    # Reads the manifests of bundles: never loads code. An unavailable plugin is logged with the reason.
    # @return [nil]
    def scan
      added = []
      @sources.each do |source|
        next unless File.directory?(source.folder)
        # Plugins registered at start (level low) stay, but files that appear later are not
        next unless @security_allowed.call(source.security)
        singles, bundles = children(source)
        (bundles.keys | singles.keys).each do |name|
          next if @plugins.key?(name)
          @plugins[name] =
            if bundles.key?(name)
              Log.log.warn { "Plugin #{name}: bundle #{bundles[name]} is used, not #{singles[name]}" } if singles.key?(name)
              read_bundle(name, bundles[name], source)
            else
              Plugin.new(name: name, form: :single, path: singles[name], security: source.security, manifest: {'name' => name.to_s, 'commands' => true}, error: nil)
            end
          added.push(name)
        end
      end
      return if added.empty?
      @reasons.clear
      added.each do |name|
        reason = unavailable_reason(name)
        Log.log.warn { "Plugin #{name} is unavailable: #{reason}" } unless reason.nil?
      end
      nil
    end

    # @return [Array<Symbol>] Names of registered plugins, available or not, sorted
    def names = @plugins.keys.sort

    # @param name [Symbol] Plugin name
    # @return [Plugin, nil] Registered plugin, `nil` if none
    def [](name) = @plugins[name]

    # @param name [Symbol] Name of a registered plugin
    # @return [String, nil] Why the plugin is unavailable (invalid manifest, dependency missing or unavailable), `nil` if available
    def unavailable_reason(name)
      Aspera.assert(@plugins.key?(name), type: EntityNotFound) { "plugin not found: #{name}" }
      @reasons[name] = dependency_reason(name, []) unless @reasons.key?(name)
      @reasons[name]
    end

    # Load a file of the code of a plugin: checks the security level of its source, its availability and its gems.
    # @param name [Symbol]      Name of a registered plugin
    # @param file [String, nil] File relative to the folder of a bundle, `nil` for a single file
    # @return [nil]
    # @raise [Unavailable] If the plugin is unavailable or a gem is missing
    def require_code(name, file = nil)
      plugin = @plugins[name]
      Aspera.assert(!plugin.nil?, type: EntityNotFound) { "plugin not found: #{name}" }
      Aspera.assert(file.nil?.eql?(!plugin.bundle?)) { "plugin #{name}: file #{file.inspect} for a #{plugin.form}" }
      # A plugin registered at start can be replaced by a file written since: it is code
      @security_check.call(plugin.security, "plugin #{name}")
      reason = unavailable_reason(name)
      raise Unavailable, "plugin #{name} is unavailable: #{reason}" unless reason.nil?
      missing = plugin.gems.reject { |gem| gem_installed?(gem) }
      raise Unavailable, "plugin #{name} requires gem #{missing.join(', ')}: gem install #{missing.join(' ')}" unless missing.empty?
      require(file.nil? ? plugin.path : File.join(plugin.path, file))
      nil
    end

    # Load a file of a bundle and get a constant it defines, see `require_code`
    # @param name     [Symbol] Name of a registered bundle
    # @param file     [String] File relative to the folder of the bundle
    # @param constant [String] Constant relative to `Aspera::Plugins::<Name>`
    # @return [Class, Module] The constant
    # @raise [Unavailable] If the bundle is unavailable or a gem is missing
    def load_constant(name, file, constant)
      require_code(name, file)
      Object.const_get("#{BUNDLE_MODULE}::#{name.to_s.snake_to_capital}::#{constant}")
    end

    private

    # @param source [Source] Source to scan
    # @return [Array(Hash, Hash)] Single files and folders of bundles, by name
    def children(source)
      singles = {}
      bundles = {}
      Dir.children(source.folder).each do |child|
        path = File.join(source.folder, child)
        if child.end_with?(RB_EXT)
          name = File.basename(child, RB_EXT).to_sym
          singles[name] = path unless source.ignore.include?(name)
        elsif File.file?(File.join(path, MANIFEST))
          bundles[child.to_sym] = path
        end
      end
      [singles, bundles]
    end

    # @param name   [Symbol] Name of the bundle: name of its folder
    # @param folder [String] Folder of the bundle
    # @param source [Source] Source of the bundle
    # @return [Plugin] The bundle, with the reason if its manifest is invalid
    def read_bundle(name, folder, source)
      # Manifests of the gem are validated by a spec: `json_schemer` is not loaded on each start
      manifest, error = read_manifest(File.join(folder, MANIFEST), name, validate: !source.folder.eql?(GEM_FOLDER))
      Plugin.new(name: name, form: :bundle, path: folder, security: source.security, manifest: manifest, error: error)
    end

    # @param file     [String]  Manifest file
    # @param name     [Symbol]  Name of the bundle: name of its folder
    # @param validate [Boolean] `true`: validate with the schema
    # @return [Array(Hash, String)] Manifest (empty if invalid) and why it is invalid (`nil` if valid)
    def read_manifest(file, name, validate:)
      manifest = Yaml.safe_load(File.read(file))
      return [{}, "invalid manifest #{file}: not a mapping"] unless manifest.is_a?(Hash)
      errors = validate ? Schema::Validator.instance.errors(manifest, Schema::Registry::MANIFEST) : []
      errors.push("name #{manifest['name']} is not the name of the folder #{name}") if errors.empty? && !manifest['name'].eql?(name.to_s)
      return [manifest, nil] if errors.empty?
      [{}, "invalid manifest #{file}: #{errors.join('; ')}"]
    rescue Psych::Exception, AssertError, SystemCallError => e
      [{}, "invalid manifest #{file}: #{e.message}"]
    end

    # @param name  [Symbol]        Name of a registered plugin
    # @param chain [Array<Symbol>] Plugins that depend on it, to detect a cycle
    # @return [String, nil] Why the plugin is unavailable, `nil` if available
    def dependency_reason(name, chain)
      plugin = @plugins[name]
      return plugin.error unless plugin.error.nil?
      chain += [name]
      plugin.depends.each do |dependency|
        return "dependency cycle: #{(chain + [dependency]).join(' → ')}" if chain.include?(dependency)
        return "dependency #{dependency} is missing" unless @plugins.key?(dependency)
        reason = dependency_reason(dependency, chain)
        return "dependency #{dependency} is unavailable: #{reason}" unless reason.nil?
      end
      nil
    end

    # @param name [String] Name of a gem
    # @return [Boolean] `true` if the gem is installed (in the bundle, with Bundler)
    def gem_installed?(name) = !Gem::Specification.find_all_by_name(name).empty?
  end
end
