# frozen_string_literal: true

module Aspera
  module Cli
    # CLI base exception
    class Error < StandardError; end
    # Raised when an unexpected argument is provided.
    class BadArgument < Error; end
    class NoSuchElement < Error; end

    class BadIdentifier < Error
      def initialize(res_type, res_id)
        super("#{res_type} with identifier #{res_id} not found")
      end
    end
  end
end
