# frozen_string_literal: true

require 'singleton'
require 'aspera/yaml'
require 'aspera/schema/reader'

module Aspera
  # base class for plugins modules
  module Schema
    # @!method self.instance
    #   Returns the singleton instance of Registry
    #   @return [Registry] the singleton instance
    class Registry
      include Singleton

      class << self
        def known?(sym)
          LOCATIONS.key?(sym)
        end

        # Get path to request body schema, no check if it exists
        # @param component [String] registry key (e.g. 'faspex', 'aoc')
        # @param endpoint  [String] endpoint path without leading slash (e.g. 'packages.post')
        # @return [String] schema path usable in schema: keyword
        def req_body(component, endpoint)
          "#{component}:paths./#{endpoint}.requestBody.content.application/json.schema"
        end

        # Get path to query parameters for a GET endpoint
        # @param component [String] registry key (e.g. 'faspex', 'aoc')
        # @param endpoint  [String] resource path without leading slash (e.g. 'packages')
        # @param method    [String] HTTP method (default: 'get')
        # @return [String] schema path usable in query_schema: keyword
        def query_params(component, endpoint, method: 'get')
          "#{component}:paths./#{endpoint}.#{method}#{QUERY_PARAMS_SUFFIX}"
        end
      end

      LOCATIONS = {
        spec:         'aspera/transfer/spec.schema.yaml',
        args:         'aspera/sync/args.schema.yaml',
        conf:         'aspera/sync/conf.schema.yaml',
        opts:         'aspera/cli/options.schema.yaml',
        aoc:          'aspera/schema/IBM Aspera on Cloud API-0.2.6-enhanced.yaml',
        faspex:       'aspera/schema/IBM Aspera Faspex API-5.0-enhanced.yaml',
        node:         'aspera/schema/IBM Aspera Node API-4.4.6.yaml',
        async_tables: 'aspera/schema/async_tables.yaml'
      }

      OPTIONS = 'opts'
      TRANSFER_SPEC = 'spec'
      SYNC_CONF = 'conf'
      SYNC_ARGS = 'args'
      AOC = 'aoc'
      FASPEX = 'faspex'
      NODE = 'node'
      ASYNC_TABLES = 'async_tables'
      LOG_OPTIONS             = "#{OPTIONS}:components.schemas.LogOptions"
      DIRECT_AGENT_OPTIONS    = "#{OPTIONS}:components.schemas.DirectAgentOptions"
      NODE_AGENT_OPTIONS      = "#{OPTIONS}:components.schemas.NodeAgentOptions"
      HTTPGW_AGENT_OPTIONS    = "#{OPTIONS}:components.schemas.HttpgwAgentOptions"
      TRANSFERD_AGENT_OPTIONS = "#{OPTIONS}:components.schemas.TransferdAgentOptions"
      TRANSFER_AGENT_OPTIONS  = "#{OPTIONS}:components.schemas.TransferAgentOptions"
      SMTP_OPTIONS            = "#{OPTIONS}:components.schemas.SmtpOptions"
      HTTP_OPTIONS            = "#{OPTIONS}:components.schemas.HttpOptions"
      VAULT_OPTIONS           = "#{OPTIONS}:components.schemas.VaultOptions"
      IMAGE_OPTIONS           = "#{OPTIONS}:components.schemas.ImageOptions"
      PACKAGE_FOLDER_OPTIONS  = "#{OPTIONS}:components.schemas.PackageFolderOptions"

      REQ_BODY = '.requestBody.content.application/json.schema'
      # Suffix appended to a dotted path to signal query-param extraction in reader()
      QUERY_PARAMS_SUFFIX = '.parameters'

      def initialize
        @cache = {}
        @main_folder = File.expand_path('../..', __dir__)
      end

      # Read schema from file or from cache.
      # When name_path ends with QUERY_PARAMS_SUFFIX, the OAS `parameters` array at that path
      # is synthesised into an object schema via Reader.from_query_params instead of navigating
      # into the tree.
      # @param name_path [String] registry key with optional colon-separated dotted path suffix,
      #   e.g. "faspex:paths./packages.get.parameters" or "faspex:paths./packages.post.requestBody..."
      # @return [Reader] schema reader
      def reader(name_path)
        name, path = name_path.split(':', 2)
        sym = name.to_sym
        Aspera.assert(Registry.known?(sym)){"schema: #{sym}"}
        spec_file = File.join(@main_folder, LOCATIONS[sym])
        @cache[sym] = Yaml.safe_load(File.read(spec_file)) if spec_file.end_with?('.yaml') && !@cache.key?(sym)
        @cache[sym] = JSON.parse(File.read(spec_file)) if spec_file.end_with?('.json') && !@cache.key?(sym)
        # Query-params path: strip the suffix, navigate to the operation node, extract parameters
        if path&.end_with?(QUERY_PARAMS_SUFFIX)
          parent_path = path.delete_suffix(QUERY_PARAMS_SUFFIX)
          node = @cache[sym].dig(*parent_path.split('.'))
          return Reader.from_query_params(node&.fetch('parameters', []) || [])
        end
        reader = Reader.new(@cache[sym])
        return reader unless path
        reader.dig(*path.split('.'))
      end
    end
  end
end
