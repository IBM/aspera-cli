# frozen_string_literal: true

require 'aspera/assert'

module Aspera
  # Convert dotted-path to/from nested Hash/Array container
  class DotContainer
    class << self
      # Insert extended value `value` into struct `result` at `path`
      # @param path   [String] Dotted path in container
      # @param value  [String] Last value to insert
      # @param result [NilClass, Hash, Array] current value
      # @return [Hash, Array]
      def dotted_to_container(path, value, result = nil)
        # Typed keys
        keys = path.split(OPTION_DOTTED_SEPARATOR).map{ |k| int_or_string(k)}
        # Create, or re-use first level container
        current = (result ||= new_hash_or_array_from_key(keys.first))
        # walk the path, and create sub-containers if necessary
        keys.each_cons(2) do |k, next_k|
          array_requires_integer_index!(current, k)
          current = (current[k] ||= new_hash_or_array_from_key(next_k))
        end
        # Assign value at last index
        array_requires_integer_index!(current, keys.last)
        current[keys.last] = value
        result
      end

      private

      # Convert `String` to `Integer`, or keep `String` if not `Integer`
      def int_or_string(value)
        Integer(value, exception: false) || value
      end

      # Assert that if `container` is an `Array`, then `index` is an `Integer`
      # @param container [Hash, Array]
      # @param index     [String, Integer]
      def array_requires_integer_index!(container, index)
        Aspera.assert(container.is_a?(Hash) || index.is_a?(Integer)){'Using String index when Integer index used previously'}
      end

      # Create a new `Hash` or `Array` depending on type of `key`
      def new_hash_or_array_from_key(key)
        key.is_a?(Integer) ? [] : {}
      end
    end

    # @param [Hash,Array] Container object
    def initialize(container)
      Aspera.assert_type(container, Hash)
      # tail (pop,push) contains the next element to display
      # elements are [path, value]
      @stack = container.empty? ? [] : [[[], container]]
    end

    # Convert nested Hash/Array container to dotted-path Hash
    # @return [Hash] Dotted-path Hash
    def to_dotted
      result = {}
      until @stack.empty?
        path, current = @stack.pop
        # empty things will be displayed as such
        if current.respond_to?(:empty?) && current.empty?
          result[path] = current
          next
        end
        insert = nil
        case current
        when Hash
          add_elements(path, current)
        when Array
          # Array has no nested structures -> list of Strings
          if current.none?{ |i| i.is_a?(Array) || i.is_a?(Hash)}
            insert = current.map(&:to_s)
          # Array of Hashes with only 'name' keys -> list of Strings
          elsif current.all?{ |i| i.is_a?(Hash) && i.keys == ['name']}
            insert = current.map{ |i| i['name']}
          # Array of Hashes with only 'name' and 'value' keys -> Hash of key/values
          elsif current.all?{ |i| i.is_a?(Hash) && i.keys.sort == %w[name value]}
            add_elements(path, current.each_with_object({}){ |i, h| h[i['name']] = i['value']})
          else
            add_elements(path, current.each_with_index.map{ |v, i| [i, v]})
          end
        else
          insert = current
        end
        result[path.map(&:to_s).join(OPTION_DOTTED_SEPARATOR)] = insert unless insert.nil?
      end
      result
    end

    private

    # Add elements of enumerator to the @stack, in reverse order
    def add_elements(path, enum)
      enum.reverse_each do |key, value|
        @stack.push([path + [key], value])
      end
    end

    # "."
    OPTION_DOTTED_SEPARATOR = '.'
    private_constant :OPTION_DOTTED_SEPARATOR
  end
end
