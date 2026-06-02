# frozen_string_literal: true

require 'singleton'
require 'yaml'
require 'aspera/assert'
require 'aspera/yaml'

module Aspera
  # base class for plugins modules
  class Schema
    include Singleton

    class << self
      def known?(sym)
        LOCATIONS.key?(sym)
      end
    end

    LOCATIONS = {
      spec: 'aspera/transfer/spec.schema.yaml',
      args: 'aspera/sync/args.schema.yaml',
      conf: 'aspera/sync/conf.schema.yaml',
      opts: 'aspera/cli/options.schema.yaml'
    }

    TRANSFER_INFO = 'opts:components.schemas.TransferInfo'
    TRANSFER_SPEC = 'spec'
    SYNC_CONF = 'conf'
    SYNC_ARGS = 'args'

    def initialize
      @cache = {}
      @main_folder = File.expand_path('..', __dir__)
    end

    # Read schema from file or from cache
    # @param path [String] <name>[:<path>]
    # @return [Hash, nil] schema
    def schema(path)
      name, path = path.split(':', 2)
      sym = name.to_sym
      Aspera.assert(Schema.known?(sym)){"schema: #{sym}"}
      @cache[sym] = Yaml.safe_load(File.read(File.join(@main_folder, LOCATIONS[sym]))) if !@cache.key?(sym)
      schema = @cache[sym]
      schema = schema.dig(*path.split('.')) unless path.nil? || path.empty?
      schema
    end
  end
end
