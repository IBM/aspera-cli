# frozen_string_literal: true

require 'aspera/cli/version'
require 'aspera/assert'

module Aspera
  module Cli
    # Deprecation of a feature (e.g. an option).
    # @!attribute last    [String] Last released version supporting the feature without deprecation, e.g. `4.25.0`
    # @!attribute message [String] What to use instead, e.g. `use --out.level`
    Deprecation = Struct.new(:last, :message, keyword_init: true) do
      def initialize(**kwargs)
        super
        Aspera.assert_type(last, String) { 'deprecation last' }
        Aspera.assert(Gem::Version.correct?(last) && Gem::Version.new(last) < Gem::Version.new(VERSION)) do
          "deprecation: last (#{last}) must be a released version, before #{VERSION}"
        end
        Aspera.assert_type(message, String) { 'deprecation message' }
      end

      # @return [String] e.g. `deprecated after 4.25.0: use --out.level`
      def to_s = "deprecated after #{last}: #{message}"

      class << self
        # @param value [Deprecation, Hash, nil] Deprecation, or its attributes: `{last:, message:}`
        # @return [Deprecation, nil]
        def create(value)
          case value
          when nil, Deprecation then value
          when Hash then new(**value)
          else Aspera.error_unexpected_value(value.class) { 'deprecation, expect Hash {last:, message:}' }
          end
        end
      end
    end
  end
end
