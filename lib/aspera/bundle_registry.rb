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
  # Gives the hooks of bundles as data: entries of extension points (`extensions`), modules mounted on a plugin (`mounts`), services (`service`);
  # their code is loaded by `load_entry`.
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

    # Entry of an extension point, from manifest `extensions` of the bundle that provides it: data, its code is loaded by `load_entry`
    # @!attribute bundle   [Symbol] Name of the bundle that provides the entry
    # @!attribute point    [Symbol] Name of the extension point
    # @!attribute fields   [Hash]   Fields of the entry defined by the schema of the point: all but `file` and `class`
    # @!attribute file     [String] File of the code, relative to the folder of the bundle
    # @!attribute constant [String] Class defined by the file, relative to `Aspera::Plugins::<Name>`
    Extension = Data.define(:bundle, :point, :fields, :file, :constant)

    # Module added to the command tree of another plugin, from manifest `mounts`
    # @!attribute bundle   [Symbol] Name of the bundle that provides the module
    # @!attribute target   [Symbol] Name of the plugin that includes the module
    # @!attribute file     [String] File of the module, relative to the folder of the bundle
    # @!attribute constant [String] Module defined by the file, relative to `Aspera::Plugins::<Name>`
    Mount = Data.define(:bundle, :target, :file, :constant)

    # Object shared through the context of the CLI, from manifest `services`
    # @!attribute bundle   [Symbol] Name of the bundle that provides the service
    # @!attribute name     [Symbol] Name of the service
    # @!attribute file     [String] File of the class, relative to the folder of the bundle
    # @!attribute constant [String] Class defined by the file, relative to `Aspera::Plugins::<Name>`
    Service = Data.define(:bundle, :name, :file, :constant)

    # Schema file of a bundle, added to `Schema::Registry`
    # @!attribute bundle [Symbol]      Name of the bundle that provides the schema
    # @!attribute key    [Symbol]      Key of the schema in `Schema::Registry`
    # @!attribute file   [String]      Absolute path of the schema file
    # @!attribute owned  [Boolean]     `true`: schema of ascli, values are validated against it
    # @!attribute source [Hash, nil]   Origin of a downloaded schema: `url` and optionally `version`
    SchemaFile = Data.define(:bundle, :key, :file, :owned, :source)

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
      # @return [Hash{Symbol => String}] Schema file of an entry, relative to the folder of the bundle, by name of the extension points it declares
      def extension_points = manifest.fetch('extension_points', []).to_h { |point| [point['name'].to_sym, point['schema']] }

      # @return [Array<Extension>] Entries of this bundle for extension points, in the order of the manifest
      def extensions
        manifest.fetch('extensions', {}).flat_map do |point, entries|
          entries.map do |entry|
            Extension.new(bundle: name, point: point.to_sym, fields: entry.except('file', 'class').freeze, file: entry['file'], constant: entry['class'])
          end
        end
      end

      # @return [Array<Mount>] Modules mounted by this bundle, in the order of the manifest
      def mounts = manifest.fetch('mounts', []).map { |mount| Mount.new(bundle: name, target: mount['target'].to_sym, file: mount['file'], constant: mount['module']) }
      # @return [Array<Service>] Services provided by this bundle, in the order of the manifest
      def services = manifest.fetch('services', []).map { |service| Service.new(bundle: name, name: service['name'].to_sym, file: service['file'], constant: service['class']) }

      # @return [Array<Array(Symbol, Symbol)>] Names declared by this bundle, in the order of the manifest, with repetitions:
      #   `[:service, <name>]`, `[:extension_point, <name>]` and `[:schema, <name>]`
      def declared
        services.map { |service| [:service, service.name] }
          .concat(manifest.fetch('extension_points', []).map { |point| [:extension_point, point['name'].to_sym] })
          .concat(schemas.map { |schema| [:schema, schema.key] })
      end

      # @return [Array<SchemaFile>] Schemas of this bundle, in the order of the manifest
      def schemas
        manifest.fetch('schemas', []).map do |schema|
          SchemaFile.new(bundle: name, key: schema['key'].to_sym, file: File.join(path, schema['file']), owned: schema.fetch('owned', false), source: schema['source'])
        end
      end
    end

    # @param builtin [Boolean] `true`: the folder of the bundles of the gem is a source
    def initialize(builtin: true)
      @sources = []
      # Registered plugins, by name
      @plugins = {}
      # Cache of `unavailable_reason`, by name
      @reasons = {}
      # Source folder of each registered plugin, by name
      @origins = {}
      # `true` if the sources were scanned since the last change of sources or of security checks
      @scanned = false
      # Cache of `claims`
      @claims = nil
      # Cache of `extensions`, by point: emptied when plugins, sources or security checks change
      @extensions_cache = {}
      # Compiled schemas of extension points, by file
      @point_schemas = {}
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
      @scanned = false
      @extensions_cache.clear
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
      @scanned = false
      @extensions_cache.clear
      if index
        @sources[index] = source
        # Plugins already registered from this folder get the new level
        @origins.each { |name, origin| @plugins[name] = @plugins[name].with(security: security) if origin.eql?(source.folder) }
        @reasons.clear
      elsif last
        @sources.push(source)
      else
        @sources.unshift(source)
      end
      nil
    end

    # Register the plugins of the sources that are not registered yet.
    # A registered plugin stays, even if its source is not scanned anymore (e.g. at a higher security level),
    # unless a source added since, with more priority, provides a plugin of the same name.
    # Reads the manifests of bundles: never loads code. An unavailable plugin is logged with the reason.
    # @return [nil]
    def scan
      added = []
      @scanned = true
      @sources.each_with_index do |source, rank|
        next unless File.directory?(source.folder)
        # Plugins registered at start (level low) stay, but files that appear later are not
        next unless @security_allowed.call(source.security)
        singles, bundles = children(source)
        (bundles.keys | singles.keys).each do |name|
          origin = @origins[name]
          next if origin && folders.index(origin) <= rank
          @origins[name] = source.folder
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
      @extensions_cache.clear
      @claims = nil
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
    # @return [String, nil] Why the plugin is unavailable, `nil` if available: invalid manifest, name of a service, extension point or schema already declared by a plugin registered before,
    #   dependency missing or unavailable, extension of a point not declared by a dependency or invalid for the schema of the point
    def unavailable_reason(name)
      Aspera.assert(@plugins.key?(name), type: EntityNotFound) { "plugin not found: #{name}" }
      @reasons[name] = dependency_reason(name, []) unless @reasons.key?(name)
      @reasons[name]
    end

    # @param name [Symbol] Name of a registered plugin
    # @return [Array<String>] Gems of the plugin that are not installed
    def missing_gems(name)
      Aspera.assert(@plugins.key?(name), type: EntityNotFound) { "plugin not found: #{name}" }
      @plugins[name].gems.reject { |gem| gem_installed?(gem) }
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
      missing = missing_gems(name)
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

    # Load the code of an entry of a bundle, see `load_constant`
    # @param entry [Extension, Mount, Service] Entry given by `extensions`, `mounts` or `service`
    # @return [Class, Module] The class or module of the entry
    # @raise [Unavailable] If the bundle is unavailable or a gem is missing
    def load_entry(entry) = load_constant(entry.bundle, entry.file, entry.constant)

    # @param name [Symbol] Name of a registered plugin
    # @return [Boolean] `true` if the security level of the source of the plugin allows to load its code at the current level
    def allowed?(name)
      plugin = @plugins[name]
      Aspera.assert(!plugin.nil?, type: EntityNotFound) { "plugin not found: #{name}" }
      @security_allowed.call(plugin.security)
    end

    # Entries of an extension point, from the available bundles, data only: the code of an entry is loaded by `load_entry`.
    # A bundle that extends a point depends on the bundle that declares it, its entries are valid for the schema of the point (else it is unavailable).
    # Registers the plugins of the sources first if it was not done.
    # @param point [Symbol] Name of the extension point
    # @return [Array<Extension>] Entries, by name of bundle, then in the order of the manifest; empty if no available bundle declares the point.
    #   The same frozen Array is returned until the plugins, the sources or the security checks change.
    def extensions(point)
      Aspera.assert_type(point, Symbol)
      scan unless @scanned
      @extensions_cache[point] ||= available_plugins.flat_map { |plugin| plugin.extensions.select { |extension| extension.point.eql?(point) } }.freeze
    end

    # Modules mounted on a plugin, from the available bundles, data only: the code of a module is loaded by `load_entry`.
    # Registers the plugins of the sources first if it was not done (e.g. `config` includes its mounts when it is loaded).
    # @param target [Symbol] Name of the plugin that includes the modules
    # @return [Array<Mount>] Mounts, by name of bundle, then in the order of the manifest
    def mounts(target)
      Aspera.assert_type(target, Symbol)
      scan unless @scanned
      available_plugins.flat_map { |plugin| plugin.mounts.select { |mount| mount.target.eql?(target) } }
    end

    # Service of the bundle that declares it, data only: its class is loaded by `load_entry`.
    # Registers the plugins of the sources first if it was not done.
    # @param name [Symbol] Name of the service
    # @return [Service] The service
    # @raise [Unavailable] If no plugin declares the service, or if the plugin that declares it is unavailable
    def service(name)
      Aspera.assert_type(name, Symbol)
      scan unless @scanned
      provider = claims[[:service, name]]
      raise Unavailable, "no plugin provides service #{name}" if provider.nil?
      reason = unavailable_reason(provider)
      raise Unavailable, "service #{name}: plugin #{provider} is unavailable: #{reason}" unless reason.nil?
      @plugins[provider].services.find { |service| service.name.eql?(name) }
    end

    # Schemas of the available bundles, data only: the file is read by `Schema::Registry`.
    # Registers the plugins of the sources first if it was not done.
    # @return [Array<SchemaFile>] Schemas, by name of bundle, then in the order of the manifest
    def schemas
      scan unless @scanned
      available_plugins.flat_map(&:schemas)
    end

    # @param key [Symbol] Key of a schema
    # @return [SchemaFile, nil] The schema, `nil` if no available bundle provides it
    def schema(key)
      Aspera.assert_type(key, Symbol)
      schemas.find { |schema| schema.key.eql?(key) }
    end

    private

    # @return [Array<Plugin>] Available plugins, by name
    def available_plugins = names.select { |name| unavailable_reason(name).nil? }.map { |name| @plugins[name] }

    # Names of services, extension points and schemas, by the plugin that declares them: the first one registered with a valid manifest.
    # @return [Hash{Array(Symbol, Symbol) => Symbol}] Name of the plugin, by `[:service, <name>]`, `[:extension_point, <name>]` and `[:schema, <name>]`
    def claims
      @claims ||= @plugins.each_value.each_with_object({}) do |plugin, result|
        next unless plugin.error.nil?
        plugin.declared.each { |claim| result[claim] ||= plugin.name }
      end
    end

    # @param plugin [Plugin] Registered plugin
    # @return [String, nil] Why a service, extension point or schema of the plugin is declared twice by it, is a built-in schema or is declared by another plugin, `nil` if none
    def claim_reason(plugin)
      declared = plugin.declared
      declared.each do |kind, name|
        label = "#{kind.to_s.tr('_', ' ')} #{name}"
        return "#{label} is declared twice" if declared.count([kind, name]) > 1
        return "#{label} is a built-in schema" if kind.eql?(:schema) && Schema::Registry::LOCATIONS.key?(name)
        owner = claims[[kind, name]]
        return "#{label} is declared by plugin #{owner}" unless owner.eql?(plugin.name)
      end
      nil
    end

    # Entries of a bundle for extension points: each point is declared by a dependency, and, for a bundle that is not in the gem, each entry is valid for its schema.
    # The manifests of the gem are validated by a spec: `json_schemer` is not loaded on each start.
    # @param plugin [Plugin] Registered plugin, with available dependencies
    # @return [String, nil] Why an entry is not valid, `nil` if all are valid
    def extensions_reason(plugin)
      plugin.extensions.group_by(&:point).each do |point, extensions|
        declaring = plugin.depends.find { |dependency| @plugins[dependency].extension_points.key?(point) }
        return "extension point #{point} is not declared by a dependency" if declaring.nil?
        next if File.dirname(plugin.path).eql?(GEM_FOLDER)
        schema_file = File.join(@plugins[declaring].path, @plugins[declaring].extension_points[point])
        extensions.each_with_index do |extension, index|
          errors = point_errors(extension.fields, schema_file)
          return "invalid extension #{point} #{index + 1}: #{errors.join('; ')}" unless errors.empty?
        end
      end
      nil
    end

    # @param fields      [Hash]   Fields of an extension entry
    # @param schema_file [String] Schema of an entry of the extension point (JSON or YAML)
    # @return [Array<String>] Errors of validation, empty if valid
    def point_errors(fields, schema_file)
      require 'json_schemer'
      @point_schemas[schema_file] ||=
        begin
          schema = Yaml.safe_load(File.read(schema_file))
          Aspera.assert_type(schema, Hash) { "schema #{schema_file}" }
          JSONSchemer.schema(schema)
        end
      @point_schemas[schema_file].validate(fields).map { |error| error['error'] }
    rescue Psych::Exception, AssertError, SystemCallError => e
      ["schema of the extension point: #{e.message}"]
    end

    # @param source [Source] Source to scan
    # @return [Array(Hash, Hash)] Single files and folders of bundles, by name, sorted: plugins are registered in a stable order (see `claims`)
    def children(source)
      singles = {}
      bundles = {}
      Dir.children(source.folder).sort.each do |child|
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
      reason = claim_reason(plugin)
      return reason unless reason.nil?
      chain += [name]
      plugin.depends.each do |dependency|
        return "dependency cycle: #{(chain + [dependency]).join(' → ')}" if chain.include?(dependency)
        return "dependency #{dependency} is missing" unless @plugins.key?(dependency)
        reason = dependency_reason(dependency, chain)
        return "dependency #{dependency} is unavailable: #{reason}" unless reason.nil?
      end
      extensions_reason(plugin)
    end

    # @param name [String] Name of a gem
    # @return [Boolean] `true` if the gem is installed (in the bundle, with Bundler)
    def gem_installed?(name) = !Gem::Specification.find_all_by_name(name).empty?
  end
end
