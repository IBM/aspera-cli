# frozen_string_literal: true

module Aspera
  # base class for plugins modules
  module Schema
    # JSON schema reader
    class Reader
      attr_reader :current

      # Shortcut to access current value at path
      # @param x [String] path element
      # @return [Hash, Array, String, Integer] current value at path
      def [](x)
        @current[x]
      end

      # Find sub path relative to current
      # Honors $ref
      def dig(*path)
        current = @current
        path.each do |p|
          current = current[p]
          Aspera.assert_type(current, Hash){'schema'}
          if current.key?('$ref')
            ref = current['$ref']
            Aspera.assert(ref.start_with?('#/'))
            current = @root.dig(*ref[2..].split('/'))
          end
        end
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

      # Recursively traverse schema properties with a block
      # Handles nested objects and arrays automatically
      # @param prefix [String] Prefix for property names (e.g., 'parent.child.')
      # @yield [property_schema, name, full_name] Yields property info to block
      # @yieldparam property_schema [Reader] Schema reader for this property (use .current to get node hash)
      # @yieldparam name [String] Property name
      # @yieldparam full_name [String] Full property name with prefix
      # @return [nil]
      def each_property(prefix = '', &block)
        properties = dig('properties')
        properties.current.each_key do |name|
          property_full_name = "#{prefix}#{name}"
          property_schema = properties.dig(name)
          node = property_schema.current

          # Yield current property to block
          yield(property_schema, name, property_full_name)

          # Recursively process nested structures
          case node['type']
          when 'object'
            property_schema.each_property("#{property_full_name}.", &block) if node['properties']
          when 'array'
            if node['items']
              array_item_schema = property_schema.dig('items')
              array_item_schema.each_property("#{property_full_name}[].", &block) if array_item_schema.current['properties']
            end
          end
        end
      end
    end
  end
end
