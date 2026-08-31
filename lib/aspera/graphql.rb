# frozen_string_literal: true

require 'aspera/rest_call_error'

module Aspera
  # Helper to execute GraphQL queries via a Rest object.
  # Follows the GraphQL-over-HTTP convention: POST {query, variables} to endpoint,
  # parse top-level `data` key, raise on top-level `errors` array.
  module GraphQL
    QUERIES_FOLDER = File.join(__dir__, 'api', 'queries')
    private_constant :QUERIES_FOLDER

    class << self
      # Execute a GraphQL query loaded from a .graphql file in lib/aspera/api/queries/
      # @param rest      [Rest]   API object pointing at the GraphQL endpoint
      # @param name      [String] Base filename without extension (e.g. 'my_query')
      # @param variables [Hash]   GraphQL variables
      # @return [Hash]   The `data` object from the response
      # @raise [RestCallError] if the response contains GraphQL errors
      def execute(rest, name, variables = {})
        query = load_query(name)
        response = rest.create(nil, {query: query, variables: variables})
        errors = response['errors']
        raise RestCallError, errors.map{ |e| e['message']}.join("\n") if errors.is_a?(Array) && !errors.empty?
        response['data']
      end

      private

      def load_query(name)
        File.read(File.join(QUERIES_FOLDER, "#{name}.graphql"))
      end
    end
  end
end
