# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative '../log'
require_relative '../yaml'
require_relative '../string_ext'
require_relative 'reader'
require 'singleton'

module Aspera
  # base class for plugins modules
  module Schema
    # @!method self.instance
    #   Returns the singleton instance of Registry
    #   @return [Registry] the singleton instance
    class Registry
      include Singleton

      # Schemas added by the libraries that read them (`register`), by key: `file`, `doc_options`
      @registered = {}

      class << self
        # Add a schema of a library that uses the registry, e.g. the domain library: called by the file that reads it.
        # The schema is owned (values are validated against it).
        # @param key         [Symbol, String] Key of the schema
        # @param file        [String]         Absolute path of the schema file
        # @param doc_options [Proc, nil]      Called without argument: options of `Documentation` for the whole schema (e.g. annotations of properties)
        # @return [nil]
        def register(key, file, doc_options: nil)
          key = key.to_sym
          Aspera.assert(!LOCATIONS.key?(key)) { "schema #{key} is a built-in schema" }
          Aspera.assert(!@registered.key?(key) || @registered[key][:file].eql?(file)) { "schema #{key} is registered with another file: #{@registered[key][:file]}" }
          # A reserved key cannot be claimed by a bundle (`built_in?`): no need to look at the bundles, which keeps the load of the domain files cheap
          unless RESERVED.include?(key)
            claimed = bundle_schema(key)
            Aspera.assert(claimed.nil?) { "schema #{key} is registered with #{file} and provided by plugin #{claimed.bundle} (#{claimed.file})" }
          end
          Aspera.assert_type(doc_options, Proc, NilClass) { 'doc_options' }
          @registered[key] = {file: file, doc_options: doc_options}.freeze
          nil
        end

        # @param sym [Symbol] Key of a schema
        # @return [Hash, nil] Schema added by `register`: `file`, `doc_options`, `nil` if none
        def registered(sym)
          @registered[sym]
        end

        # @param sym [Symbol] Key of a schema: of the gem (`LOCATIONS`), added by a library (`register`) or provided by a bundle
        def known?(sym)
          LOCATIONS.key?(sym) || @registered.key?(sym) || !bundle_schema(sym).nil?
        end

        # @param sym [Symbol] Key of a schema
        # @return [Boolean] `true` if the key is a schema of the gem, reserved for a library (even if its file is not loaded yet) or added by a library: a bundle cannot use it
        def built_in?(sym)
          LOCATIONS.key?(sym) || RESERVED.include?(sym) || @registered.key?(sym)
        end

        # @param name_path [String] schema path, e.g. `opts:components.schemas.HttpOptions`
        # @return [Boolean] `true` if schema is owned by ascli (not a vendor API)
        def owned?(name_path)
          sym = name_path.split(':', 2).first.to_sym
          return OWNED.include?(sym) if LOCATIONS.key?(sym)
          return true if @registered.key?(sym)
          bundle_schema(sym)&.owned || false
        end

        # @param sym [Symbol] Key of a schema
        # @return [BundleRegistry::SchemaFile, nil] Schema provided by an available bundle (its folder, declared in its manifest), `nil` if none
        def bundle_schema(sym)
          # Loaded on use: `bundle_registry` requires this file
          require_relative '../bundle_registry'
          BundleRegistry.instance.schema(sym)
        end

        # Split a component string into registry key and optional path prefix.
        # Syntax: 'key' or 'key+/prefix' (e.g. 'shares+/api/v1')
        # @param component [String] registry key with optional '+/prefix'
        # @return [Array(String, String)] [key, prefix] where prefix may be ''
        def split_component(component)
          key, prefix = component.split('+', 2)
          [key, prefix || '']
        end

        # Get path to request body schema, no check if it exists
        # @param component [String] registry key, optionally with path prefix (e.g. 'shares+/api/v1')
        # @param endpoint  [String] endpoint path without leading slash (e.g. 'data/shares.post')
        # @return [String] schema path usable in schema: keyword
        def req_body(component, endpoint)
          key, prefix = split_component(component)
          "#{key}:paths.#{prefix}/#{endpoint}.requestBody.content.application/json.schema"
        end

        # Get path to query parameters for a GET endpoint
        # @param component [String] registry key, optionally with path prefix (e.g. 'shares+/api/v1')
        # @param endpoint  [String] resource path without leading slash (e.g. 'data/shares')
        # @param method    [String] HTTP method (default: 'get')
        # @return [String] schema path usable in query_schema: keyword
        def query_params(component, endpoint, method: 'get')
          key, prefix = split_component(component)
          "#{key}:paths.#{prefix}/#{endpoint}.#{method}#{QUERY_PARAMS_SUFFIX}"
        end
      end

      # Schemas of the framework, relative to `lib`: the other ones are added by the libraries that use them (`register`) and by bundles (manifest)
      LOCATIONS = {
        opts:     'aspera/cli/options.schema.yaml',
        manifest: 'aspera/plugin.schema.yaml'
      }.freeze

      # Schemas owned by ascli: values are validated against them (vendor API schemas are validated by the API)
      OWNED = %i[opts manifest].freeze

      OPTIONS = 'opts'
      # Keys of the schemas of the domain library, added by their files (`register`)
      TRANSFER_SPEC = 'spec'
      SYNC_CONF = 'conf'
      SYNC_ARGS = 'args'
      ASYNC_TABLES = 'async_tables'
      ASCP_LOG = 'ascp_log'
      # Keys reserved for the domain library: a bundle cannot claim them, whether or not their file is loaded (plain data: the framework does not require the domain files)
      RESERVED = [TRANSFER_SPEC, SYNC_CONF, SYNC_ARGS, ASYNC_TABLES, ASCP_LOG].map(&:to_sym).freeze
      # Manifest `plugin.yaml` of a plugin bundle, see `BundleRegistry`
      MANIFEST = 'manifest'
      LOG_OPTIONS             = "#{OPTIONS}:components.schemas.LogOptions".freeze
      UI_OPTIONS              = "#{OPTIONS}:components.schemas.UiOptions".freeze
      SECURITY_OPTIONS        = "#{OPTIONS}:components.schemas.SecurityOptions".freeze
      TEMP_OPTIONS            = "#{OPTIONS}:components.schemas.TempOptions".freeze
      SMTP_OPTIONS            = "#{OPTIONS}:components.schemas.SmtpOptions".freeze
      HTTP_OPTIONS            = "#{OPTIONS}:components.schemas.HttpOptions".freeze
      VAULT_OPTIONS           = "#{OPTIONS}:components.schemas.VaultOptions".freeze
      VAULT_SECRET            = "#{OPTIONS}:components.schemas.VaultSecret".freeze
      VAULT_STORE             = "#{OPTIONS}:components.schemas.VaultStore".freeze
      VAULT_STORES            = "#{OPTIONS}:components.schemas.VaultStores".freeze
      DETECT_OPTIONS          = "#{OPTIONS}:components.schemas.DetectOptions".freeze
      PRESET_LOOKUP_CRITERIA  = "#{OPTIONS}:components.schemas.PresetLookupCriteria".freeze
      WIZARD_OPTIONS          = "#{OPTIONS}:components.schemas.WizardOptions".freeze
      IMAGE_OPTIONS           = "#{OPTIONS}:components.schemas.ImageOptions".freeze
      OUT_OPTIONS             = "#{OPTIONS}:components.schemas.OutOptions".freeze
      POLL_OPTIONS            = "#{OPTIONS}:components.schemas.PollOptions".freeze
      WEB_SERVER_OPTIONS      = "#{OPTIONS}:components.schemas.WebServerOptions".freeze

      REQ_BODY = '.requestBody.content.application/json.schema'
      # Suffix appended to a dotted path to signal query-param extraction in reader()
      QUERY_PARAMS_SUFFIX = '.parameters'
      # Marker of a component whose `oneOf` variants are also given by the entries of an extension point of bundles, see `add_variants`
      VARIANTS = 'x-cli-variants'
      # `$ref` to a node of another schema of the registry: `<key>:#/<path>`, see `add_references`
      EXTERNAL_REF = %r{\A([a-z][a-z0-9_]*):#/(.+)\z}

      def initialize
        @cache = {}
        # Schema files being read (see `add_references`)
        @loading = []
        # Entries of the extension points used for the variants of a document, by file and by point (see `add_variants`)
        @variant_entries = {}
        @main_folder = File.expand_path('../..', __dir__)
      end

      # Read schema from file or from cache.
      # When name_path ends with QUERY_PARAMS_SUFFIX, the OAS `parameters` array at that path
      # is synthesized into an object schema via Reader.from_query_params instead of navigating
      # into the tree.
      # @param name_path [String] registry key with optional colon-separated dotted path suffix,
      #   e.g. "faspex:paths./packages.get.parameters" or "faspex:paths./packages.post.requestBody..."
      # @return [Reader] schema reader
      def reader(name_path)
        name, path = name_path.split(':', 2)
        sym = name.to_sym
        Aspera.assert(Registry.known?(sym)) { "schema: #{sym}" }
        spec_file = schema_file(sym)
        # JSON is read with the YAML loader: it accepts the header comment added by `rake tools:openapi`
        # Read again when the entries of its variants changed (e.g. bundles of a plugin folder added since)
        load_document(spec_file, sym) unless @cache.key?(spec_file) && variants_current?(spec_file)
        # Query-params path: strip the suffix, navigate to the operation node, extract parameters
        if path&.end_with?(QUERY_PARAMS_SUFFIX)
          parent_path = path.delete_suffix(QUERY_PARAMS_SUFFIX)
          node = @cache[spec_file].dig(*parent_path.split('.'))
          # Parameters may be references to components.parameters
          params = (node&.fetch('parameters', []) || []).map do |param|
            param.key?('$ref') ? @cache[spec_file].dig(*param['$ref'].delete_prefix('#/').split('/')) : param
          end
          return Reader.from_query_params(params.compact)
        end
        reader = Reader.new(@cache[spec_file])
        return reader unless path
        reader.dig(*path.split('.'))
      end

      # @param name_path [String] Schema path: key, and optional path in the schema (`<key>:<path>`)
      # @return [Hash] Options of `Documentation` for the schema, given when its key was added (`register`): only for the whole schema (no path); empty if none
      def doc_options(name_path)
        name, path = name_path.split(':', 2)
        doc_options = Registry.registered(name.to_sym)&.fetch(:doc_options)
        return {} if !path.nil? || doc_options.nil?
        doc_options.call
      end

      private

      # Read a schema file in the cache, with the references to other schemas and the variants of bundles added
      # @param spec_file [String] Schema file
      # @param sym       [Symbol] Key of the schema
      # @return [nil]
      def load_document(spec_file, sym)
        Aspera.assert(!@loading.include?(spec_file)) { "schema #{sym}: circular reference between schemas" }
        @loading.push(spec_file)
        @cache[spec_file] = add_variants(add_references(Yaml.safe_load(File.read(spec_file)), sym), spec_file)
        nil
      ensure
        @loading.delete(spec_file)
      end

      # @param sym [Symbol] Key of a known schema
      # @return [String] Absolute path of its file
      def schema_file(sym)
        return File.join(@main_folder, LOCATIONS[sym]) if LOCATIONS.key?(sym)
        return Registry.registered(sym)[:file] if Registry.registered(sym)
        Registry.bundle_schema(sym).file
      end

      # Replace each `$ref` to a node of another schema of the registry (`<key>:#/<path>`) with a copy of that node:
      # the readers and the validator see one document, with local references only. The node may not contain references.
      # @param node [Object] Document read from a schema file, or a node of it: modified in place
      # @param sym  [Symbol] Key of the document
      # @return [Object] The node, with the references replaced (the same object, unless it is a reference)
      def add_references(node, sym)
        case node
        when Hash
          match = node['$ref'].is_a?(String) ? EXTERNAL_REF.match(node['$ref']) : nil
          if match.nil?
            # replaced in place (the document was just read): no copy of the nodes without reference
            node.each { |key, value| node[key] = add_references(value, sym) }
            return node
          end
          Aspera.assert(node.keys.eql?(['$ref'])) { "schema #{sym}: #{node['$ref']}: a reference to another schema has no sibling keys" }
          Aspera.assert(!match[1].to_sym.eql?(sym)) { "schema #{sym}: #{node['$ref']}: use a local reference" }
          target = reader(match[1]).current.dig(*match[2].split('/'))
          Aspera.assert_type(target, Hash) { "schema #{sym}: #{node['$ref']}" }
          Aspera.assert(!reference?(target)) { "schema #{sym}: #{node['$ref']}: the referenced node may not contain references" }
          Marshal.load(Marshal.dump(target))
        when Array then node.map! { |value| add_references(value, sym) }
        else node
        end
      end

      # @param node [Object] Node of a schema
      # @return [Boolean] `true` if the node contains a `$ref`
      def reference?(node)
        case node
        when Hash then node.key?('$ref') || node.each_value.any? { |value| reference?(value) }
        when Array then node.any? { |value| reference?(value) }
        else false
        end
      end

      # @param spec_file [String] Schema file read in the cache
      # @return [Boolean] `true` if the entries of the extension points of its variants are the same as when it was read
      def variants_current?(spec_file)
        entries = @variant_entries.fetch(spec_file, {})
        return true if entries.empty?
        entries.all? { |point, used| BundleRegistry.instance.extensions(point).eql?(used) }
      end

      # Add the variants given by bundles to the components of `components.schemas` that have the marker `x-cli-variants`
      # (`point`: extension point, `value`: field of an entry with the value of the discriminator, `schema`: field with the schema file of the variant,
      # relative to the folder of the bundle, `suffix`: of the name of the component, optional `unique`: field whose value is unique among the variants).
      # For each entry of the point: a component `<Value><suffix>` read from the file, a `$ref` in `oneOf`, an entry in `discriminator.mapping`
      # (both created if the document has none).
      # An entry with the value of a variant of the document replaces it; an entry with the value of an earlier entry,
      # with the `unique` field of an earlier entry, or whose schema file cannot be read, is skipped with a warning. The marker is removed.
      # The entries used are kept: the document is read again when they change (see `variants_current?`).
      # @param document  [Object] Document read from a schema file
      # @param spec_file [String] Schema file of the document
      # @return [Object] The document, with the variants added
      def add_variants(document, spec_file)
        @variant_entries[spec_file] = {}
        schemas = document.dig('components', 'schemas') if document.is_a?(Hash) && document['components'].is_a?(Hash)
        return document unless schemas.is_a?(Hash)
        schemas.values.select { |schema| schema.is_a?(Hash) && schema.key?(VARIANTS) }.each do |selector|
          marker = selector.delete(VARIANTS)
          # A document without variants of its own has no `oneOf` nor `discriminator.mapping`: created
          one_of = selector['oneOf'] ||= []
          discriminator = selector['discriminator']
          Aspera.assert_type(discriminator, Hash) { "#{VARIANTS}: discriminator" }
          mapping = discriminator['mapping'] ||= {}
          Aspera.assert_type(one_of, Array) { "#{VARIANTS}: oneOf" }
          Aspera.assert_type(mapping, Hash) { "#{VARIANTS}: discriminator.mapping" }
          # Loaded on use: `bundle_registry` requires this file
          require_relative '../bundle_registry'
          added = []
          # Value of the field `unique` taken, by value of the variant
          taken = {}
          unique = marker['unique']
          point = marker.fetch('point').to_sym
          entries = BundleRegistry.instance.extensions(point)
          @variant_entries[spec_file][point] = entries
          entries.each do |entry|
            value, file = entry.fields.values_at(marker.fetch('value'), marker.fetch('schema'))
            label = "Variant #{value} of bundle #{entry.bundle} is skipped"
            next Log.log.warn { "#{label}: no #{marker['value']} or #{marker['schema']}" } unless value.is_a?(String) && file.is_a?(String)
            next Log.log.warn { "#{label}: added by an earlier entry" } if added.include?(value)
            owner = taken.key(entry.fields[unique]) unless unique.nil?
            next Log.log.warn { "#{label}: #{unique} #{entry.fields[unique]} is taken by #{owner}" } unless owner.nil?
            component = "#{value.snake_to_capital}#{marker.fetch('suffix')}"
            ref = "#/components/schemas/#{component}"
            next Log.log.warn { "#{label}: component #{component} exists" } if schemas.key?(component) && !mapping[value].eql?(ref)
            path = File.join(BundleRegistry.instance[entry.bundle].path, file)
            variant = read_variant(path)
            next Log.log.warn { "#{label}: cannot read #{path}: #{variant}" } if variant.is_a?(String)
            schemas[component] = variant
            index = one_of.index { |item| item['$ref'].eql?(mapping[value]) } if mapping.key?(value)
            if index.nil?
              one_of.push({'$ref' => ref})
            else
              one_of[index] = {'$ref' => ref}
            end
            mapping[value] = ref
            added.push(value)
            taken[value] = entry.fields[unique] unless unique.nil?
          end
        end
        document
      end

      # @param path [String] Schema file of a variant (YAML or JSON)
      # @return [Hash, String] The schema, or why it cannot be read
      def read_variant(path)
        variant = Yaml.safe_load(File.read(path))
        variant.is_a?(Hash) ? variant : 'not a mapping'
      rescue Psych::Exception, AssertError, SystemCallError => e
        e.message
      end
    end
  end
end
