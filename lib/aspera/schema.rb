# frozen_string_literal: true

require 'singleton'
require 'yaml'
require 'aspera/assert'
require 'aspera/yaml'

module Aspera
  # base class for plugins modules
  module Schema
    include Singleton

    LOCATIONS = {
      spec: 'aspera/transfer/spec.schema.yaml',
      args: 'aspera/sync/args.schema.yaml',
      conf: 'aspera/sync/conf.schema.yaml'
    }

    def initialize
      @cache = {}
      @main_folder = File.expand_path('..', __dir__)
    end

    # Read schema from file or from cache
    # @param sym [Symbol] :spec, :args, :conf
    # @return [Hash] schema
    def schema(sym)
      return @cache[sym] if @cache.key?(sym)
      Aspera.assert(LOCATIONS[sym])
      @cache[sym] = Yaml.safe_load(File.join(@main_folder, LOCATIONS[sym]))
    end
  end
end
