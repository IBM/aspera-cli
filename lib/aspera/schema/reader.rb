# frozen_string_literal: true

module Aspera
  # base class for plugins modules
  module Schema
    # JSON schema reader
    class Reader
      attr_reader :current

      class << self
        # Build a synthetic Reader from an OAS `parameters` array (entries with `in: query`).
        # Produces a JSON Schema object whose `properties` map each query param name to its schema,
        # with the OAS-level `description` and `required` merged in.
        # @param params [Array<Hash>] raw OAS parameter objects (may contain path/header params too)
        # @return [Reader]
        def from_query_params(params)
          properties = {}
          required_names = []
          params.each do |param|
            next unless param['in'] == 'query'
            name = param['name']
            prop = (param['schema'] || {}).dup
            prop['description'] = param['description'] if param['description'] && !prop.key?('description')
            properties[name] = prop
            required_names << name if param['required']
          end
          synthetic = {'type' => 'object', 'properties' => properties}
          synthetic['required'] = required_names unless required_names.empty?
          new(synthetic)
        end
      end

      # Shortcut to access current value at path
      # @param key [String] path element
      # @return [Hash, Array, String, Integer] current value at path
      def [](key)
        @current[key]
      end

      # Find sub path relative to current
      # Honors $ref
      def dig(*path)
        current = @current
        path.each do |p|
          Aspera.assert(current.key?(p)) { "schema: #{p} in #{path}" }
          current = current[p]
          Aspera.assert_type(current, Hash) { 'schema' }
          if current.key?('$ref')
            ref = current['$ref']
            Aspera.assert(ref.start_with?('#/')) { "schema $ref must start with '#/': #{ref}" }
            current = @root.dig(*ref[2..].split('/'))
          end
        end
        Reader.new(@root, current)
      end

      # Resolve a $ref string to a Reader
      def resolve_ref(ref)
        Aspera.assert(ref.start_with?('#/')) { "schema $ref must start with '#/': #{ref}" }
        Reader.new(@root, @root.dig(*ref[2..].split('/')))
      end

      # Read schema from file or from cache
      # @param root [Hash] root schema
      # @param current [Hash, nil] current position in
      # @return [Hash, nil] schema
      def initialize(root, current = nil)
        @root = root
        @current = current || root
      end

      # Recursively traverse schema properties with a block.
      # If the current node has `oneOf`, each variant is traversed in turn and
      # `on_variant` is called (if given) before each variant's properties.
      # @param prefix     [String] Prefix for property names (e.g., 'parent.child.')
      # @param on_variant [Proc, nil] Called with the variant Reader before its properties
      # @yield [property_schema, name, full_name] Yields property info to block
      # @yieldparam property_schema [Reader] Schema reader for this property
      # @yieldparam name [String] Property name
      # @yieldparam full_name [String] Full property name with prefix
      # @return [nil]
      def each_property(prefix = '', on_variant: nil, &block)
        if @current.key?('oneOf')
          # Build reverse map: $ref -> discriminant value, from discriminator.mapping if present
          discriminant_by_ref = {}
          if @current.dig('discriminator', 'mapping').is_a?(Hash)
            @current['discriminator']['mapping'].each do |value, ref|
              discriminant_by_ref[ref] = value
            end
          end
          discriminant_property = @current.dig('discriminator', 'propertyName')
          @current['oneOf'].each do |variant_node|
            ref = variant_node['$ref']
            variant_reader = ref ? resolve_ref(ref) : Reader.new(@root, variant_node)
            discriminant_value = ref ? discriminant_by_ref[ref] : nil
            on_variant&.call(variant_reader, discriminant_property, discriminant_value)
            variant_reader.each_property(prefix, on_variant: on_variant, &block)
          end
          return
        end
        if @current.key?('allOf')
          # Merge all branches: each branch contributes its properties (no variants)
          @current['allOf'].each do |branch_node|
            ref = branch_node['$ref']
            branch_reader = ref ? resolve_ref(ref) : Reader.new(@root, branch_node)
            branch_reader.each_property(prefix, on_variant: on_variant, &block)
          end
          return
        end
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
            property_schema.each_property("#{property_full_name}.", on_variant: on_variant, &block) if node['properties']
          when 'array'
            if node['items']
              array_item_schema = property_schema.dig('items')
              array_item_schema.each_property("#{property_full_name}[].", on_variant: on_variant, &block) if array_item_schema.current['properties']
            end
          end
          # allOf without explicit type: object — recurse to merge all branches
          property_schema.each_property("#{property_full_name}.", on_variant: on_variant, &block) if node['allOf']
        end
      end

      # Convert this schema to a flat array of field descriptors.
      # Returns raw semantic fields with no ANSI or formatting, suitable for
      # JSON/YAML output or MCP consumption. An AI or script can use the result
      # directly to build a valid payload.
      #
      # Each Hash entry contains:
      #   name        [String]  dot/bracket-path of the field (e.g. "recipients[].name")
      #   type        [String]  JSON type string (e.g. "string", "boolean", "Array[object]")
      #   required    [Boolean] true when the field is in its immediate parent's required list
      #   description [String]  human description (may contain Markdown **bold** / `code`)
      #   default     [Object]  (optional) default value as native Ruby type
      #   enum        [Array]   (optional) list of allowed string values
      #
      # @return [Array<Hash>]
      def to_rows
        rows = []
        collect_rows(rows, self, '')
        rows
      end

      private

      # Recursively collect rows from a schema node, passing each property's own
      # parent `required` array so that only direct-parent membership is checked.
      def collect_rows(rows, reader, prefix)
        return unless reader.current.key?('properties')
        parent_required = Set.new(Array(reader.current['required']))
        props_reader = reader.dig('properties')
        props_reader.current.each_key do |name|
          prop_reader  = props_reader.dig(name)
          node         = prop_reader.current
          full_name    = "#{prefix}#{name}"
          type_val =
            if node['type'].is_a?(Array)
              node['type'].join(', ')
            elsif node['type'].eql?('array') && node.dig('items', 'type').is_a?(String)
              "Array[#{node.dig('items', 'type')}]"
            else
              node['type'].to_s
            end
          row = {
            'name'        => full_name,
            'type'        => type_val,
            'required'    => parent_required.include?(name),
            'description' => node['description'].to_s
          }
          row['default'] = node['default'] if node.key?('default')
          row['enum']    = node['enum']    if node.key?('enum')
          rows << row
          # Recurse into nested object or array-of-objects
          case node['type']
          when 'object'
            collect_rows(rows, prop_reader, "#{full_name}.") if node['properties']
          when 'array'
            if node['items']
              item_reader = prop_reader.dig('items')
              collect_rows(rows, item_reader, "#{full_name}[].") if item_reader.current['properties']
            end
          end
          collect_rows(rows, prop_reader, "#{full_name}.") if node['allOf']
        end
      end
    end
  end
end
