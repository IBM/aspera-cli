# frozen_string_literal: true

module Aspera
  module Cli
    # CLI base exception
    class Error < StandardError; end
    # Raised when an unexpected argument is provided.
    class BadArgument < Error; end
    class MissingArgument < Error; end
    class NoSuchElement < Error; end

    class BadIdentifier < Error
      def initialize(res_type, res_id, field: 'identifier', count: 0)
        msg = count.eql?(0) ? 'not found' : "found #{count}"
        super("#{res_type} with #{field}=#{res_id}: #{msg}")
      end
    end
  end
end
