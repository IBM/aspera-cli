# frozen_string_literal: true

module Aspera
  # base class for plugins modules
  module Schema
    # JSON schema reader
    class Reader
      attr_reader :current

      # Find sub path relative to current
      # Honors $ref
      def dig(*path)
        current = @current
        path.each do |p|
          if current.key?('$ref')
            ref = current['$ref']
            Aspera.assert(ref.start_with?('#/'))
            current = @root.dig(*ref[2..].split('/'))
          end
          current = current[p]
          Aspera.assert_type(current, Hash){'schema'}
        end
        Reader.new(@root, current)
      end

      def sub(current)
        Reader.new(@root, current)
      end

      # Read schema from file or from cache
      # @param root [Hash] root schema
      # @param current [Hash, nil] current position in
      # @return [Hash, nil] schema
      def initialize(root, current = nil)
        @root = root
        @current = current || root
      end
    end
  end
end
