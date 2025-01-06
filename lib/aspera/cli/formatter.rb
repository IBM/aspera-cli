# frozen_string_literal: true

# cspell:ignore jsonpp
require 'aspera/cli/special_values'
require 'aspera/preview/terminal'
require 'aspera/secret_hider'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'terminal-table'
require 'tty-spinner'
require 'yaml'
require 'pp'

module Aspera
  module Cli
    CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze
    # This class is used to transform a complex structure into a simple hash
    class Flattener
      def initialize(formatter)
        @result = nil
        @formatter = formatter
      end

      # General method
      def flatten(something)
        Aspera.assert_type(something, Hash)
        @result = {}
        flatten_any(something, '')
        return @result
      end

      # Special method for configuration overview
      def config_over(something)
        @result = []
        something.each do |config, preset|
          preset.each do |parameter, value|
            @result.push(CONF_OVERVIEW_KEYS.zip([config, parameter, value]).to_h)
          end
        end
        return @result
      end

      private

      # Recursive function to flatten any type
      # @param something [Object] to be flattened
      # @param name [String] name of englobing key
      def flatten_any(something, name)
        if something.is_a?(Hash)
          flattened_hash(something, name)
        elsif something.is_a?(Array)
          flatten_array(something, name)
        elsif something.is_a?(String) && something.empty?
          @result[name] = @formatter.special_format('empty string')
        elsif something.nil?
          @result[name] = @formatter.special_format('null')
        # elsif something.eql?(true) || something.eql?(false)
        #  @result[name] = something
        else
          @result[name] = something
        end
      end

      # Recursive function to flatten an array
      # @param array [Array] to be flattened
      # @param name [String] name of englobing key
      def flatten_array(array, name)
        if array.empty?
          @result[name] = @formatter.special_format('empty list')
        elsif array.all?(String)
          @result[name] = array.join("\n")
        elsif array.all?{|i| i.is_a?(Hash) && i.keys.eql?(%w[name])}
          @result[name] = array.map(&:values).join(', ')
        elsif array.all?{|i| i.is_a?(Hash) && i.keys.sort.eql?(%w[name value])}
          flattened_hash(array.each_with_object({}){|i, h|h[i['name']] = i['value']}, name)
        else
          array.each_with_index { |item, index| flatten_any(item, "#{name}.#{index}")}
        end
        nil
      end

      # Recursive function to flatten a Hash
      # @param hash [Hash] to be flattened
      # @param name [String] name of englobing key
      def flattened_hash(hash, name)
        prefix = name.empty? ? '' : "#{name}."
        hash.each do |k, v|
          flatten_any(v, "#{prefix}#{k}")
        end
      end
    end

    # Take care of output
    class Formatter
      # remove a fields from the list
      FIELDS_LESS = '-'
      CSV_RECORD_SEPARATOR = "\n"
      CSV_FIELD_SEPARATOR = ','
      # supported output formats
      DISPLAY_FORMATS = %i[text nagios ruby json jsonpp yaml table csv image].freeze
      # user output levels
      DISPLAY_LEVELS = %i[info data error].freeze
      FIELD_VALUE_HEADINGS = %i[key value].freeze

      private_constant :DISPLAY_FORMATS, :DISPLAY_LEVELS, :CSV_RECORD_SEPARATOR, :CSV_FIELD_SEPARATOR, :FIELD_VALUE_HEADINGS
      # prefix to display error messages in user messages (terminal)
      ERROR_FLASH = 'ERROR:'.bg_red.gray.blink.freeze
      WARNING_FLASH = 'WARNING:'.bg_brown.black.blink.freeze
      HINT_FLASH = 'HINT:'.bg_green.gray.blink.freeze

      class << self
        def all_but(list)
          list = [list] unless list.is_a?(Array)
          return list.map{|i|"#{FIELDS_LESS}#{i}"}.unshift(SpecialValues::ALL)
        end

        def tick(yes)
          result =
            if Environment.instance.terminal_supports_unicode?
              if yes
                "\u2713"
              else
                "\u2717"
              end
            elsif yes
              'Y'
            else
              ' '
            end
          return result.green if yes
          return result.red
        end

        def auto_type(data)
          result = {type: :other_struct, data: data}
          result[:type] = :single_object if result[:data].is_a?(Hash)
          if result[:data].is_a?(Array)
            if result[:data].all?(Hash)
              result[:type] = :object_list
            end
          end
          return result
        end
      end

      # initialize the formatter
      def initialize
        @options = {}
        @spinner = nil
      end

      # Highlight special values
      def special_format(what)
        result = "<#{what}>"
        return %w[null empty].any?{|s|what.include?(s)} ? result.dim : result.reverse_color
      end

      # call this after REST calls if several api calls are expected
      def long_operation_running(title = '')
        return unless Environment.terminal?
        if @spinner.nil?
          @spinner = TTY::Spinner.new('[:spinner] :title', format: :classic)
          @spinner.start
        end
        @spinner.update(title: title)
        @spinner.spin
      end

      def long_operation_terminated
        @spinner&.stop
        @spinner = nil
      end

      # options are: format, output, display, fields, select, table_style, flat_hash, transpose_single
      def option_handler(option_symbol, operation, value=nil)
        Aspera.assert_values(operation, %i[set get])
        case operation
        when :set
          @options[option_symbol] = value
          case option_symbol
          when :output
            $stdout = if value.eql?('-')
              STDOUT # rubocop:disable Style/GlobalStdStream
            else
              File.open(value, 'w')
            end
          when :image
            allowed_options = Preview::Terminal.method(:build).parameters.select{|i|i[0].eql?(:key)}.map{|i|i[1]}
            unknown_options = value.keys.map(&:to_sym) - allowed_options
            raise "Invalid parameter(s) for option image: #{unknown_options.join(', ')}, use #{allowed_options.join(', ')}" unless unknown_options.empty?
          end
        when :get then return @options[option_symbol]
        else Aspera.error_unreachable_line
        end
        nil
      end

      def declare_options(options)
        default_table_style = if Environment.instance.terminal_supports_unicode?
          {border: :unicode_round}
        else
          {}
        end
        options.declare(:format, 'Output format', values: DISPLAY_FORMATS, handler: {o: self, m: :option_handler}, default: :table)
        options.declare(:output, 'Destination for results', types: String, handler: {o: self, m: :option_handler})
        options.declare(:display, 'Output only some information', values: DISPLAY_LEVELS, handler: {o: self, m: :option_handler}, default: :info)
        options.declare(
          :fields, "Comma separated list of: fields, or #{SpecialValues::ALL}, or #{SpecialValues::DEF}", handler: {o: self, m: :option_handler},
          types: [String, Array, Regexp, Proc],
          default: SpecialValues::DEF)
        options.declare(:select, 'Select only some items in lists: column, value', types: [Hash, Proc], handler: {o: self, m: :option_handler})
        options.declare(:table_style, 'Table display style', types: [Hash], handler: {o: self, m: :option_handler}, default: default_table_style)
        options.declare(:flat_hash, '(Table) Display deep values as additional keys', values: :bool, handler: {o: self, m: :option_handler}, default: true)
        options.declare(:transpose_single, '(Table) Single object fields output vertically', values: :bool, handler: {o: self, m: :option_handler}, default: true)
        options.declare(:multi_table, '(Table) Each element of a table are displayed as a table', values: :bool, handler: {o: self, m: :option_handler}, default: false)
        options.declare(:show_secrets, 'Show secrets on command output', values: :bool, handler: {o: self, m: :option_handler}, default: false)
        options.declare(:image, 'Options for image display', types: Hash, handler: {o: self, m: :option_handler}, default: {})
      end

      # main output method
      # data: for requested data, not displayed if level==error
      # info: additional info, displayed if level==info
      # error: always displayed on stderr
      def display_message(message_level, message)
        case message_level
        when :data then $stdout.puts(message) unless @options[:display].eql?(:error)
        when :info then $stdout.puts(message) if @options[:display].eql?(:info)
        when :error then $stderr.puts(message)
        else Aspera.error_unexpected_value(message_level)
        end
      end

      def display_status(status)
        display_message(:info, status)
      end

      def display_item_count(number, total)
        number = number.to_i
        total = total.to_i
        return if total.eql?(0) && number.eql?(0)
        count_msg = "Items: #{number}/#{total}"
        count_msg = count_msg.bg_red unless number.eql?(total)
        display_status(count_msg)
      end

      def all_fields(data)
        data.each_with_object({}){|v, m|v.each_key{|c|m[c] = true}}.keys
      end

      # @return the list of fields to display
      # @param data [Array<Hash>] data to display
      # @param default [Array<String>, Proc] list of fields to display by default (may contain special values)
      def compute_fields(data, default)
        Log.log.debug{"compute_fields: data:#{data.class} default:#{default.class} #{default}"}
        # the requested list of fields, but if can contain special values
        request =
          case @options[:fields]
          # when NilClass then [SpecialValues::DEF]
          when String then @options[:fields].split(',')
          when Array then @options[:fields]
          when Regexp then return all_fields(data).select{|i|i.match(@options[:fields])}
          when Proc then return all_fields(data).select{|i|@options[:fields].call(i)}
          else Aspera.error_unexpected_value(@options[:fields])
          end
        result = []
        until request.empty?
          item = request.shift
          removal = false
          if item[0].eql?(FIELDS_LESS)
            removal = true
            item = item[1..-1]
          end
          case item
          when SpecialValues::ALL
            # get the list of all column names used in all lines, not just first one, as all lines may have different columns
            request.unshift(*all_fields(data))
          when SpecialValues::DEF
            default = all_fields(data).select{|i|default.call(i)} if default.is_a?(Proc)
            default = all_fields(data) if default.nil?
            request.unshift(*default)
          else
            if removal
              result = result.reject{|i|i.eql?(item)}
            else
              result.push(item)
            end
          end
        end
        return result
      end

      # filter the list of items on the fields option
      def filter_list_on_fields(data)
        # by default, keep all data intact
        return data if @options[:fields].eql?(SpecialValues::DEF) && @options[:select].nil?
        Aspera.assert_type(data, Array){'Filtering fields or select requires result is an Array of Hash'}
        Aspera.assert(data.all?(Hash)){'Filtering fields or select requires result is an Array of Hash'}
        filter_columns_on_select(data)
        return data if @options[:fields].eql?(SpecialValues::DEF)
        selected_fields = compute_fields(data, @options[:fields])
        return data.map{|i|i[selected_fields.first]} if selected_fields.length == 1
        return data.map{|i|i.select{|k, _|selected_fields.include?(k)}}
      end

      # filter the list of items on the select option
      # @param data [Array<Hash>] list of items
      def filter_columns_on_select(data)
        case @options[:select]
        when Proc
          data.select!{|i|@options[:select].call(i)}
        when Hash
          @options[:select].each{|k, v|data.select!{|i|i[k].eql?(v)}}
        end
      end

      # this method displays a table
      # object_array: array of hash
      # fields: list of column names
      def display_table(object_array, fields)
        Aspera.assert(!fields.nil?){'missing fields parameter'}
        filter_columns_on_select(object_array)
        if object_array.empty?
          # no  display for csv
          display_message(:info, special_format('empty')) if @options[:format].eql?(:table)
          return
        end
        # if table has only one element, and only one field, display the value
        if object_array.length == 1 && fields.length == 1
          display_message(:data, object_array.first[fields.first])
          return
        end
        single_transposed = @options[:transpose_single] && object_array.length == 1
        # Special case if only one row (it could be object_list or single_object)
        if single_transposed
          single = object_array.first
          object_array = fields.map { |i| FIELD_VALUE_HEADINGS.zip([i, single[i]]).to_h }
          fields = FIELD_VALUE_HEADINGS
        end
        Log.log.debug{Log.dump(:object_array, object_array)}
        # convert data to string, and keep only display fields
        final_table_rows = object_array.map { |r| fields.map { |c| r[c].to_s } }
        # remove empty rows
        final_table_rows.select!{|i| !(i.is_a?(Hash) && i.empty?)}
        # here : fields : list of column names
        case @options[:format]
        when :table
          if @options[:multi_table] && !single_transposed
            final_table_rows.each do |row|
              Log.log.debug{Log.dump(:row, row)}
              display_message(:data, Terminal::Table.new(
                headings:  FIELD_VALUE_HEADINGS,
                rows:      fields.zip(row),
                style:     @options[:table_style]&.symbolize_keys))
            end
          else
            # display the table !
            display_message(:data, Terminal::Table.new(
              headings:  fields,
              rows:      final_table_rows,
              style:     @options[:table_style]&.symbolize_keys))
          end
        when :csv
          display_message(:data, final_table_rows.map{|t| t.join(CSV_FIELD_SEPARATOR)}.join(CSV_RECORD_SEPARATOR))
        else
          raise "not expected: #{@options[:format]}"
        end
      end

      # @return text suitable to display an image from url
      def status_image(blob)
        begin
          raise URI::InvalidURIError, 'not uri' if !(blob =~ /\A#{URI::RFC2396_PARSER.make_regexp}\z/)
          # it's a url
          url = blob
          unless Environment.instance.url_method.eql?(:text)
            Environment.instance.open_uri(url)
            return ''
          end
          # remote_image = Rest.new(base_url: url).read('')
          # mime = remote_image[:http]['content-type']
          # blob = remote_image[:http].body
          # Log.log.warn("Image ? #{remote_image[:http]['content-type']}") unless mime.include?('image/')
          blob = UriReader.read(url)
        rescue URI::InvalidURIError
          nil
        end
        # try base64
        begin
          blob = Base64.strict_decode64(blob)
        rescue
          nil
        end
        return Preview::Terminal.build(blob, **@options[:image].symbolize_keys)
      end

      # this method displays the results, especially the table format
      # @param type [Symbol] type of data
      # @param data [Object] data to display
      # @param total [Integer] total number of items
      # @param fields [Array<String>] list of fields to display
      # @param name [String] name of the column to display
      def display_results(type:, data: nil, total: nil, fields: nil, name: nil)
        Log.log.debug{"display_results: #{type} class=#{data.class} data=#{data}"}
        Aspera.assert_type(type, Symbol){'result must have type'}
        Aspera.assert(!data.nil? || %i[empty nothing].include?(type)){'result must have data'}
        display_item_count(data.length, total) unless total.nil?
        SecretHider.deep_remove_secret(data) unless @options[:show_secrets] || @options[:display].eql?(:data)
        case @options[:format]
        when :text
          display_message(:data, data.to_s)
        when :nagios
          Nagios.process(data)
        when :ruby
          display_message(:data, PP.pp(filter_list_on_fields(data), +''))
        when :json
          display_message(:data, JSON.generate(filter_list_on_fields(data)))
        when :jsonpp
          display_message(:data, JSON.pretty_generate(filter_list_on_fields(data)))
        when :yaml
          display_message(:data, YAML.dump(filter_list_on_fields(data)))
        when :image
          # assume it is an url
          url = data
          case type
          when :single_object, :object_list
            url = [url] if type.eql?(:single_object)
            raise 'image display requires a single result' unless url.length == 1
            fields = compute_fields(url, fields)
            raise 'select a field to display' unless fields.length == 1
            url = url.first
            raise 'no such field' unless url.key?(fields.first)
            url = url[fields.first]
          end
          raise "not url: #{url.class} #{url}" unless url.is_a?(String)
          display_message(:data, status_image(url))
        when :table, :csv
          case type
          when :config_over
            display_table(Flattener.new(self).config_over(data), CONF_OVERVIEW_KEYS)
          when :object_list, :single_object
            obj_list = data
            obj_list = [obj_list] if type.eql?(:single_object)
            Aspera.assert_type(obj_list, Array)
            Aspera.assert(obj_list.all?(Hash)){"expecting Array of Hash: #{obj_list.inspect}"}
            # :object_list is an array of hash tables, where key=colum name
            obj_list = obj_list.map{|obj|Flattener.new(self).flatten(obj)} if @options[:flat_hash]
            display_table(obj_list, compute_fields(obj_list, fields))
          when :value_list
            # :value_list is a simple array of values, name of column provided in the :name
            display_table(data.map { |i| { name => i } }, [name])
          when :empty # no table
            display_message(:info, special_format('empty'))
            return
          when :nothing # no result expected
            Log.log.debug('no result expected')
          when :status # no table
            # :status displays a simple message
            display_message(:info, data)
          when :text # no table
            # :status displays a simple message
            display_message(:data, data)
          when :other_struct # no table
            # :other_struct is any other type of structure
            display_message(:data, PP.pp(data, +''))
          else
            raise "unknown data type: #{type}"
          end
        else
          raise "not expected: #{@options[:format]}"
        end
      end
    end
  end
end
