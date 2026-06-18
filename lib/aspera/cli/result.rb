# frozen_string_literal: true

require 'aspera/assert'

module Aspera
  module Cli
    # Base class for all result types
    # Each result type is now a separate class instead of using a type field
    class Result
      attr_reader :data, :fields, :total, :name

      def initialize(data: nil, fields: nil, total: nil, name: nil)
        Aspera.assert_type(total, Integer){'total'} unless total.nil?
        Aspera.assert_type(name, String){'name'} unless name.nil?
        @data = data
        @fields = fields
        @total = total
        @name = name
      end
    end

    # Special result types - each has its own class
    class Result
      # Base class for special results
      # The type is automatically derived from the class name
      class Special < Result
        def initialize
          # Convert class name to symbol: Empty -> :empty, Nothing -> :nothing
          type = self.class.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
          super(data: type)
        end
      end

      # Empty list result
      class Empty < Special
      end

      # Nothing expected result
      class Nothing < Special
      end

      # Null result
      class Null < Special
      end

      # Status result (success, complete, etc.)
      class Status < Result
        def initialize(data)
          Aspera.assert_type(data, String){'status result data'}
          super(data: data)
        end
      end

      # Success status result
      class Success < Status
        def initialize
          super('complete')
        end
      end

      # Text result
      class Text < Result
        def initialize(data)
          raise ArgumentError, "Text result requires String, Integer or Symbol, got #{data.class}" unless [String, Integer, Symbol].any?{ |t| data.is_a?(t)}
          super(data: data)
        end
      end

      # Image result (URL or blob)
      class Image < Result
        def initialize(data)
          Aspera.assert_type(data, String){'image result data'}
          super(data: data)
        end
      end

      # Single object result (Hash)
      class SingleObject < Result
        def initialize(data, fields: nil)
          Aspera.assert_type(data, Hash){'single object result data'}
          super(data: data, fields: fields)
        end
      end

      # Object list result (Array of Hash)
      class ObjectList < Result
        def initialize(data, fields: nil, total: nil)
          Aspera.assert_type(data, Array){'object list result data'}
          raise ArgumentError, 'Object list result requires Array of Hash' unless data.all?{ |item| item.is_a?(Hash)}
          super(data: data, fields: fields, total: total)
        end
      end

      # Value list result (Array of values with a name)
      class ValueList < Result
        def initialize(data, name: 'id')
          Aspera.assert_type(data, Array){'value list result data'}
          Aspera.assert_type(name, String){'value list name'}
          super(data: data, name: name)
        end
      end

      # Class method to automatically determine result type from data
      # @param data [Object] the data to analyze and format
      # @return [Result]
      def self.auto(data)
        case data
        when NilClass
          Null.new
        when Hash
          SingleObject.new(data)
        when Array
          all_types = data.map(&:class).uniq
          return ObjectList.new(data) if all_types.eql?([Hash])

          scalar_types = [String, Integer, Symbol]
          unsupported_types = all_types - scalar_types
          return ValueList.new(data, name: 'list') if unsupported_types.empty?

          Aspera.error_unexpected_value(unsupported_types){'list item types'}
        when String, Integer, Symbol
          Text.new(data)
        else
          Aspera.error_unexpected_value(data.class.name){'result type'}
        end
      end
    end
  end
end
