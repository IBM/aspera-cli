# frozen_string_literal: true

module Aspera
  module Cli
    # CLI base exception
    class Error < StandardError; end
    # Raised when an unexpected argument is provided.
    class BadArgument < Error; end
    class MissingArgument < Error; end
    class NoSuchElement < Error; end

    # Raised when a lookup for a specific entity fails to return exactly one result.
    #
    # Provides a formatted message indicating whether the entity was missing
    # or if multiple matches were found (ambiguity).
    class BadIdentifier < Error
      # @param res_type [String] The type of entity being looked up (e.g., 'user').
      # @param res_id   [String] The value of the identifier that failed.
      # @param field    [String] The name of the field used for lookup (defaults to 'identifier').
      # @param count    [Integer] The number of matches found (0 for not found, >1 for ambiguous).
      def initialize(res_type, res_id, field: 'identifier', count: 0)
        msg = count.eql?(0) ? 'not found' : "found #{count}"
        super("#{res_type} with #{field}=#{res_id}: #{msg}")
      end
    end
  end
end
