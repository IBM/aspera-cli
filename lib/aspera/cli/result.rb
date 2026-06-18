# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/nagios'
require 'aspera/log'
require 'aspera/environment'
require 'aspera/uri_reader'
require 'aspera/preview/terminal'
require 'aspera/dot_container'
require 'base64'
require 'uri'
require 'pp'
require 'json'
require 'yaml'

module Aspera
  module Cli
    # Base class for all result types
    # Each result type is now a separate class instead of using a type field
    class Result
      attr_reader :data, :fields

      # @param data [Object,nil] The result data
      # @param fields [Object] Specification of fields to include
      def initialize(data: nil, fields: nil)
        @data = data
        @fields = fields
      end

      # Format this result using the provided formatter
      # This method implements the Visitor pattern, allowing each Result subclass
      # to define how it should be formatted without the Formatter needing to know
      # about all Result types.
      # Base implementation handles common formats: text, nagios, ruby, json, jsonpp, yaml
      # Subclasses should call super first, then handle their specific formats
      # @param formatter [Formatter] The formatter to use
      # @return [void]
      def format(formatter)
        # Apply field filtering once for formats that need it
        filtered_data = formatter.filter_list_on_fields(@data)
        case formatter.format_type
        when :text
          formatter.display_message(:data, @data.to_s)
        when :nagios
          Nagios.process(@data)
        when :ruby
          formatter.display_message(:data, PP.pp(filtered_data, +''))
        when :json
          formatter.display_message(:data, JSON.generate(filtered_data))
        when :jsonpp
          formatter.display_message(:data, JSON.pretty_generate(filtered_data))
        when :yaml
          formatter.display_message(:data, YAML.dump(filtered_data))
        when :image
          Aspera.assert_type(@data, String){'image: URL or blob'}
          # Check if URL
          data =
            begin
              # just validate
              URI.parse(@data)
              if Environment.instance.url_method.eql?(:text)
                UriReader.read(@data)
              else
                Environment.instance.open_uri(@data)
                formatter.display_message(:info, "Opened URL in browser: #{@data}")
                :done
              end
            rescue URI::InvalidURIError
              @data
            end
          # try base64
          data = begin
            Base64.strict_decode64(data)
          rescue
            data
          end
          # here, data is the image blob
          formatter.display_message(:data, Preview::Terminal.build(data, **formatter.image_options)) unless data.eql?(:done)
        else
          Aspera.error_unexpected_value(formatter.format_type){'format'}
        end
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

        def format(formatter)
          case formatter.format_type
          when :text, :nagios, :ruby, :json, :jsonpp, :yaml
            formatter.display_message(:data, @data.to_s)
          when :table, :csv
            if @data.eql?(:nothing)
              Log.log.debug('no result expected')
              return
            end
            formatter.display_message(:info, formatter.special_format(@data.to_s))
          else
            super
          end
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

        def format(formatter)
          data = formatter.hide_secrets? ? formatter.hide_secrets_in_string(@data) : @data
          case formatter.format_type
          when :text, :nagios, :ruby, :json, :jsonpp, :yaml
            formatter.display_message(:data, data)
          when :table, :csv
            formatter.display_message(:info, data)
          else
            super
          end
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
          Aspera.assert_type(data, String, Integer, Symbol, type: ArgumentError){'text result data'}
          super(data: data)
        end

        def format(formatter)
          data = @data.is_a?(String) && formatter.hide_secrets? ? formatter.hide_secrets_in_string(@data) : @data
          case formatter.format_type
          when :text, :nagios
            formatter.display_message(:data, data.to_s)
          when :ruby
            formatter.display_message(:data, PP.pp(data, +''))
          when :json
            formatter.display_message(:data, JSON.generate(data))
          when :jsonpp
            formatter.display_message(:data, JSON.pretty_generate(data))
          when :yaml
            formatter.display_message(:data, YAML.dump(data))
          when :table, :csv
            formatter.display_message(:data, data)
          else
            super
          end
        end
      end

      # Image result (URL or blob)
      class Image < Result
        def initialize(data)
          Aspera.assert_type(data, String){'image result data'}
          super(data: data)
        end

        def format(formatter)
          # Force image format for Image results
          formatter.set_format_type(:image)
          super
        end
      end

      # Single object result (Hash)
      class SingleObject < Result
        def initialize(data, fields: nil)
          Aspera.assert_type(data, Hash){'single object result data'}
          super(data: data, fields: fields)
        end

        def format(formatter)
          case formatter.format_type
          when :image
            # Extract single field for image display
            data_array = [@data]
            fields = formatter.compute_fields(data_array, @fields)
            Aspera.assert(fields.length == 1, type: Cli::BadArgument){'select a single field to display'}
            Aspera.assert(@data.key?(fields.first), type: Cli::BadArgument){'no such field'}
            # Create an Image result and format it
            Image.new(@data[fields.first]).format(formatter)
          when :table, :csv
            Aspera.assert_type(@data, Hash){'result'}
            if @data.empty?
              formatter.display_message(:data, formatter.special_format('empty dict'))
            else
              data = formatter.flat_hash? ? DotContainer.new(@data).to_dotted : @data
              formatter.display_table([data], formatter.compute_fields([data], @fields), single: true)
            end
          else
            super
          end
        end
      end

      # Object list result (Array of Hash)
      # @note The +total+ parameter is used to display pagination information (e.g., "Items: 10/100")
      class ObjectList < Result
        attr_reader :total

        # @param data [Array<Hash>] Array of hash objects to display
        # @param fields [Array<String>, Proc, nil] Fields to display in table/csv format
        # @param total [Integer, nil] Total number of items available (for pagination display)
        def initialize(data, fields: nil, total: nil)
          Aspera.assert_type(data, Array){'object list result data'}
          raise ArgumentError, 'Object list result requires Array of Hash' unless data.all?{ |item| item.is_a?(Hash)}
          Aspera.assert_type(total, Integer, NilClass){'total'}
          super(data: data, fields: fields)
          @total = total
        end

        def format(formatter)
          # Display item count if total is provided
          unless @total.nil?
            number = @data.length.to_i
            total = @total.to_i
            unless total.eql?(0) && number.eql?(0)
              count_msg = "Items: #{number}/#{total}"
              count_msg = count_msg.bg_red unless number.eql?(total)
              formatter.display_status(count_msg)
            end
          end
          case formatter.format_type
          when :image
            # Extract single field for image display
            Aspera.assert(@data.length == 1, type: Cli::BadArgument){'image display requires a single result'}
            SingleObject.new(@data.first).format(formatter)
          when :table, :csv
            Aspera.assert_array_all(@data, Hash){'result'}
            data = formatter.flat_hash? ? @data.map{ |obj| DotContainer.new(obj).to_dotted} : @data
            formatter.display_table(data, formatter.compute_fields(data, @fields), single: false)
          else
            super
          end
        end
      end

      # Value list result (Array of values with a name)
      class ValueList < Result
        attr_reader :name

        def initialize(data, name: 'id')
          Aspera.assert_type(data, Array){'value list result data'}
          Aspera.assert_type(name, String){'value list name'}
          super(data: data)
          @name = name
        end

        def format(formatter)
          case formatter.format_type
          when :table, :csv
            formatter.display_table(@data.map{ |i| {@name => i}}, [@name])
          else
            super
          end
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
