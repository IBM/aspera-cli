# frozen_string_literal: true

require 'singleton'
require 'aspera/yaml'
require 'aspera/schema/reader'

module Aspera
  # base class for plugins modules
  module Schema
    class Registry
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
        opts: 'aspera/cli/options.schema.yaml',
        aoc:  'aspera/schema/IBM Aspera on Cloud API-0.2.6-enhanced.yaml'
      }

      TRANSFER_INFO = 'opts:components.schemas.TransferInfo'
      TRANSFER_SPEC = 'spec'
      SYNC_CONF = 'conf'
      SYNC_ARGS = 'args'
      AOC = 'aoc'

      def initialize
        @cache = {}
        @main_folder = File.expand_path('../..', __dir__)
      end

      # Read schema from file or from cache
      # @param name_path [String] one of the keys in LOCATIONS, with optional :<path> suffix
      # @return [Reader] schema
      def reader(name_path)
        name, path = name_path.split(':', 2)
        sym = name.to_sym
        Aspera.assert(Registry.known?(sym)){"schema: #{sym}"}
        @cache[sym] = Yaml.safe_load(File.read(File.join(@main_folder, LOCATIONS[sym]))) unless @cache.key?(sym)
        reader = Reader.new(@cache[sym])
        return reader unless path
        reader.dig(*path.split('.'))
      end
    end
  end
end
