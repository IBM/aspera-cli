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

      class << self
        # @param sym [Symbol] Key of a schema: of the gem (`LOCATIONS`) or provided by a bundle
        def known?(sym)
          LOCATIONS.key?(sym) || !bundle_schema(sym).nil?
        end

        # @param name_path [String] schema path, e.g. `opts:components.schemas.HttpOptions`
        # @return [Boolean] `true` if schema is owned by ascli (not a vendor API)
        def owned?(name_path)
          sym = name_path.split(':', 2).first.to_sym
          return OWNED.include?(sym) if LOCATIONS.key?(sym)
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

      LOCATIONS = {
        spec:         'aspera/transfer/spec.schema.yaml',
        args:         'aspera/sync/args.schema.yaml',
        conf:         'aspera/sync/conf.schema.yaml',
        opts:         'aspera/cli/options.schema.yaml',
        preview:      'aspera/preview/options.schema.yaml',
        aoc:          'aspera/schema/IBM Aspera on Cloud API-0.2.6-enhanced.yaml',
        automation:   'aspera/schema/IBM Aspera on Cloud Automation API-1.0.5-enhanced.yaml',
        faspex:       'aspera/schema/IBM Aspera Faspex API-5.0-enhanced.yaml',
        faspio:       'aspera/schema/IBM Aspera faspio Gateway API-1.0.0-enhanced.yaml',
        console:      'aspera/schema/IBM Aspera Console-enhanced.yaml',
        node:         'aspera/schema/IBM Aspera Node API-4.4.6.yaml',
        shares:       'aspera/schema/IBM_Aspera_Shares.yaml',
        orchestrator: 'aspera/schema/IBM Aspera Orchestrator API-v1-enhanced.yaml',
        async_tables: 'aspera/sync/async_tables.yaml',
        ascp_log:     'aspera/ascp/log.schema.yaml',
        manifest:     'aspera/plugin.schema.yaml'
      }.freeze

      # Schemas owned by ascli: values are validated against them (vendor API schemas are validated by the API)
      OWNED = %i[spec args conf opts preview async_tables ascp_log manifest].freeze

      OPTIONS = 'opts'
      TRANSFER_SPEC = 'spec'
      SYNC_CONF = 'conf'
      SYNC_ARGS = 'args'
      PREVIEW_OPTIONS = 'preview'
      AOC = 'aoc'
      AUTOMATION = 'automation'
      FASPEX = 'faspex'
      FASPIO = 'faspio'
      CONSOLE = 'console'
      NODE = 'node'
      ORCHESTRATOR = 'orchestrator'
      SHARES = 'shares+/api/v1'
      ASYNC_TABLES = 'async_tables'
      ASCP_LOG = 'ascp_log'
      # Manifest `plugin.yaml` of a plugin bundle, see `BundleRegistry`
      MANIFEST = 'manifest'
      LOG_OPTIONS             = "#{OPTIONS}:components.schemas.LogOptions".freeze
      UI_OPTIONS              = "#{OPTIONS}:components.schemas.UiOptions".freeze
      SECURITY_OPTIONS        = "#{OPTIONS}:components.schemas.SecurityOptions".freeze
      TEMP_OPTIONS            = "#{OPTIONS}:components.schemas.TempOptions".freeze
      DIRECT_AGENT_OPTIONS    = "#{OPTIONS}:components.schemas.DirectAgentOptions".freeze
      NODE_AGENT_OPTIONS      = "#{OPTIONS}:components.schemas.NodeAgentOptions".freeze
      NODE_EMULATOR_OPTIONS   = "#{OPTIONS}:components.schemas.NodeEmulatorOptions".freeze
      TRANSFER_AGENT_OPTIONS  = "#{OPTIONS}:components.schemas.TransferAgentOptions".freeze
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
      PACKAGE_FOLDER_OPTIONS  = "#{OPTIONS}:components.schemas.PackageFolderOptions".freeze
      WEB_SERVER_OPTIONS      = "#{OPTIONS}:components.schemas.WebServerOptions".freeze
      GATEWAY_OPTIONS         = "#{OPTIONS}:components.schemas.Faspex4GatewayOptions".freeze
      POSTPROC_OPTIONS        = "#{OPTIONS}:components.schemas.Faspex4PostProcOptions".freeze

      REQ_BODY = '.requestBody.content.application/json.schema'
      # Suffix appended to a dotted path to signal query-param extraction in reader()
      QUERY_PARAMS_SUFFIX = '.parameters'
      # Marker of a component whose `oneOf` variants are also given by the entries of an extension point of bundles, see `add_variants`
      VARIANTS = 'x-cli-variants'

      def initialize
        @cache = {}
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
        spec_file = LOCATIONS.key?(sym) ? File.join(@main_folder, LOCATIONS[sym]) : Registry.bundle_schema(sym).file
        # JSON is read with the YAML loader: it accepts the header comment added by `rake tools:openapi`
        # Read again when the entries of its variants changed (e.g. bundles of a plugin folder added since)
        @cache[spec_file] = add_variants(Yaml.safe_load(File.read(spec_file)), spec_file) unless @cache.key?(spec_file) && variants_current?(spec_file)
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

      private

      # @param spec_file [String] Schema file read in the cache
      # @return [Boolean] `true` if the entries of the extension points of its variants are the same as when it was read
      def variants_current?(spec_file)
        entries = @variant_entries.fetch(spec_file, {})
        return true if entries.empty?
        entries.all? { |point, used| BundleRegistry.instance.extensions(point).eql?(used) }
      end

      # Add the variants given by bundles to the components of `components.schemas` that have the marker `x-cli-variants`
      # (`point`: extension point, `value`: field of an entry with the value of the discriminator, `schema`: field with the schema file of the variant,
      # relative to the folder of the bundle, `suffix`: of the name of the component).
      # For each entry of the point: a component `<Value><suffix>` read from the file, a `$ref` in `oneOf`, an entry in `discriminator.mapping`.
      # An entry with the value of a variant of the document replaces it; an entry with the value of an earlier entry,
      # or whose schema file cannot be read, is skipped with a warning. The marker is removed.
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
          one_of = selector['oneOf']
          mapping = selector.dig('discriminator', 'mapping')
          Aspera.assert_type(one_of, Array) { "#{VARIANTS}: oneOf" }
          Aspera.assert_type(mapping, Hash) { "#{VARIANTS}: discriminator.mapping" }
          # Loaded on use: `bundle_registry` requires this file
          require_relative '../bundle_registry'
          added = []
          point = marker.fetch('point').to_sym
          entries = BundleRegistry.instance.extensions(point)
          @variant_entries[spec_file][point] = entries
          entries.each do |entry|
            value, file = entry.fields.values_at(marker.fetch('value'), marker.fetch('schema'))
            label = "Variant #{value} of bundle #{entry.bundle} is skipped"
            next Log.log.warn { "#{label}: no #{marker['value']} or #{marker['schema']}" } unless value.is_a?(String) && file.is_a?(String)
            next Log.log.warn { "#{label}: added by an earlier entry" } if added.include?(value)
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
