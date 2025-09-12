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
require 'csv'
require 'word_wrap'

module Aspera
  module Cli
    # Take care of CLI output
    class Formatter
      # remove a fields from the list
      FIELDS_LESS = '-'
      # supported output formats
      DISPLAY_FORMATS = %i[text nagios ruby json jsonpp yaml table csv image].freeze
      # user output levels
      DISPLAY_LEVELS = %i[info data error].freeze
      # column names for single object display in table
      SINGLE_OBJECT_COLUMN_NAMES = %i[field value].freeze

      private_constant :FIELDS_LESS, :DISPLAY_FORMATS, :DISPLAY_LEVELS, :SINGLE_OBJECT_COLUMN_NAMES
      # prefix to display error messages in user messages (terminal)
      ERROR_FLASH = 'ERROR:'.bg_red.gray.blink.freeze
      WARNING_FLASH = 'WARNING:'.bg_brown.black.blink.freeze
      HINT_FLASH = 'HINT:'.bg_green.gray.blink.freeze

      class << self
        def all_but(list)
          list = [list] unless list.is_a?(Array)
          return list.map{ |i| "#{FIELDS_LESS}#{i}"}.unshift(SpecialValues::ALL)
        end

        # nicer display for boolean
        def tick(yes, color: true)
          result =
            if Environment.terminal_supports_unicode?
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
          return result if !color
          return result.green if yes
          return result.red
        end

        # Highlight special values on terminal
        # empty values are dim
        def special_format(what)
          result = "<#{what}>"
          return %w[null empty].any?{ |s| what.include?(s)} ? result.dim : result.reverse_color
        end

        # replace empty values with a readable version
        def enhance_display_values_hash(input_hash)
          stack = [input_hash]
          until stack.empty?
            current = stack.pop
            current.each do |key, value|
              case value
              when NilClass
                current[key] = special_format('null')
              when String
                current[key] = special_format('empty string') if value.empty?
              when Array
                if value.empty?
                  current[key] = special_format('empty list')
                else
                  value.each do |item|
                    stack.push(item) if item.is_a?(Hash)
                  end
                end
              when Hash
                if value.empty?
                  current[key] = special_format('empty dict')
                else
                  stack.push(value)
                end
              end
            end
          end
        end

        # Flatten a Hash into single level hash
        def flatten_hash(input)
          Aspera.assert_type(input, Hash)
          return input if input.empty?
          flat = {}
          stack = [[nil, input]]
          until stack.empty?
            prefix, current = stack.pop
            if current.respond_to?(:empty?) && current.empty?
              flat[prefix] = current
              next
            end
            case current
            when Hash
              current.reverse_each{ |k, v| stack.push([[prefix, k].compact.join('.'), v])}
            when Array
              if current.all?(String)
                flat[prefix] = current.join("\n")
              elsif current.all?{ |i| i.is_a?(Hash) && i.keys == ['name']}
                flat[prefix] = current.map{ |i| i['name']}.join(', ')
              elsif current.all?{ |i| i.is_a?(Hash) && i.keys.sort == %w[name value]}
                stack.push([prefix, current.each_with_object({}){ |i, h| h[i['name']] = i['value']}])
              else
                current.each_with_index.reverse_each{ |v, k| stack.push([[prefix, k].compact.join('.'), v])}
              end
            else
              flat[prefix] = current
            end
          end
          flat
        end

        # for transfer spec table, build line for display
        def check_row(row)
          row.each_key do |k|
            row[k] = row[k].map{ |i| WordWrap.ww(i.to_s, 120).chomp}.join("\n") if row[k].is_a?(Array)
          end
        end
      end

      # initialize the formatter
      def initialize
        @options = {}
        @spinner = nil
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

      def declare_options(options)
        default_table_style = if Environment.terminal_supports_unicode?
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
        options.declare(:table_style, '(Table) Display style', types: [Hash], handler: {o: self, m: :option_handler}, default: default_table_style)
        options.declare(:flat_hash, '(Table) Display deep values as additional keys', values: :bool, handler: {o: self, m: :option_handler}, default: true)
        options.declare(
          :multi_single, '(Table) Control how object list is displayed as single table, or multiple objects', values: %i[no yes single],
          handler: {o: self, m: :option_handler}, default: :no)
        options.declare(:show_secrets, 'Show secrets on command output', values: :bool, handler: {o: self, m: :option_handler}, default: false)
        options.declare(:image, 'Options for image display', types: Hash, handler: {o: self, m: :option_handler}, default: {})
      end

      # method accessed by option manager
      # options are: format, output, display, fields, select, table_style, flat_hash, multi_single
      def option_handler(option_symbol, operation, value=nil)
        Aspera.assert_values(operation, %i[set get])
        case operation
        when :set
          @options[option_symbol] = value
          # special handling of some options
          case option_symbol
          when :output
            $stdout = if value.eql?('-')
              STDOUT # rubocop:disable Style/GlobalStdStream
            else
              File.open(value, 'w')
            end
          when :image
            # get list if key arguments of method
            allowed_options = Preview::Terminal.method(:build).parameters.select{ |i| i[0].eql?(:key)}.map{ |i| i[1]}
            # check that only supported options are given
            unknown_options = value.keys.map(&:to_sym) - allowed_options
            raise "Invalid parameter(s) for option image: #{unknown_options.join(', ')}, use #{allowed_options.join(', ')}" unless unknown_options.empty?
          end
        when :get then return @options[option_symbol]
        else Aspera.error_unreachable_line
        end
        nil
      end

      # main output method
      # data: for requested data, not displayed if level==error
      # info: additional info, displayed if level==info
      # error: always displayed on stderr
      def display_message(message_level, message, hide_secrets: true)
        message = SecretHider.hide_secrets_in_string(message) if hide_secrets && message.is_a?(String) && hide_secrets?
        case message_level
        when :data then $stdout.puts(message) unless @options[:display].eql?(:error)
        when :info then $stdout.puts(message) if @options[:display].eql?(:info)
        when :error then $stderr.puts(message)
        else Aspera.error_unexpected_value(message_level)
        end
      end

      def display_status(status, **kwopt)
        display_message(:info, status, **kwopt)
      end

      def display_item_count(number, total)
        number = number.to_i
        total = total.to_i
        return if total.eql?(0) && number.eql?(0)
        count_msg = "Items: #{number}/#{total}"
        count_msg = count_msg.bg_red unless number.eql?(total)
        display_status(count_msg)
      end

      def hide_secrets?
        !@options[:show_secrets] && !@options[:display].eql?(:data)
      end

      # hides secrets in Hash or Array
      def hide_secrets(data)
        SecretHider.deep_remove_secret(data) if hide_secrets?
      end

      # this method displays the results, especially the table format
      # @param type [Symbol] type of data
      # @param data [Object] data to display
      # @param total [Integer] total number of items
      # @param fields [Array<String>] list of fields to display
      # @param name [String] name of the column to display
      def display_results(type:, data: nil, total: nil, fields: nil, name: nil)
        Log.log.debug{"display_results: type=#{type} class=#{data.class}"}
        Log.log.trace1{"display_results: data=#{data}"}
        Aspera.assert_type(type, Symbol){'result must have type'}
        Aspera.assert(!data.nil? || %i[empty nothing].include?(type)){'result must have data'}
        display_item_count(data.length, total) unless total.nil?
        hide_secrets(data)
        data = SecretHider.hide_secrets_in_string(data) if data.is_a?(String) && hide_secrets?
        @options[:format] = :image if type.eql?(:image)
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
          # if object or list, then must be a single
          case type
          when :single_object, :object_list
            data = [data] if type.eql?(:single_object)
            raise BadArgument, 'image display requires a single result' unless data.length == 1
            fields = compute_fields(data, fields)
            raise BadArgument, 'select a single field to display' unless fields.length == 1
            data = data.first
            raise BadArgument, 'no such field' unless data.key?(fields.first)
            data = data[fields.first]
          end
          Aspera.assert_type(data, String){'URL or blob for image'}
          # Check if URL
          data =
            begin
              # just validate
              URI.parse(data)
              if Environment.instance.url_method.eql?(:text)
                UriReader.read(data)
              else
                Environment.instance.open_uri(data)
                'Opened Url'
              end
            rescue URI::InvalidURIError
              data
            end
          # try base64
          data = begin
            Base64.strict_decode64(data)
          rescue
            data
          end
          # here, data is the image blob
          display_message(:data, Preview::Terminal.build(data, **@options[:image].symbolize_keys))
        when :table, :csv
          case type
          when :single_object
            # :single_object is a Hash, where key=colum name
            Aspera.assert_type(data, Hash)
            if data.empty?
              display_message(:data, self.class.special_format('empty dict'))
            else
              data = self.class.flatten_hash(data) if @options[:flat_hash]
              display_table([data], compute_fields([data], fields), single: true)
            end
          when :object_list
            # :object_list is an Array of Hash, where key=colum name
            Aspera.assert_type(data, Array)
            Aspera.assert(data.all?(Hash)){"expecting Array of Hash: #{data.inspect}"}
            data = data.map{ |obj| self.class.flatten_hash(obj)} if @options[:flat_hash]
            display_table(data, compute_fields(data, fields), single: type.eql?(:single_object))
          when :value_list
            # :value_list is a simple array of values, name of column provided in `name`
            display_table(data.map{ |i| {name => i}}, [name])
          when :empty # no table
            display_message(:info, self.class.special_format('empty'))
            return
          when :nothing
            Log.log.debug('no result expected')
          when :status # no table
            # :status displays a simple message
            display_message(:info, data)
          when :text # no table
            # :status displays a simple message
            display_message(:data, data)
          else Aspera.error_unexpected_value(type){'data type'}
          end
        else Aspera.error_unexpected_value(@options[:format]){'format'}
        end
      end
      #==========================================================================================

      private

      # @return all fields of all objects in list of objects
      def all_fields(data)
        data.each_with_object({}){ |v, m| v.each_key{ |c| m[c] = true}}.keys
      end

      # @return the list of fields to display
      # @param data    [Array<Hash>]         data to display
      # @param default [Array<String>, Proc] list of fields to display by default (may contain special values)
      def compute_fields(data, default)
        Log.log.debug{"compute_fields: data:#{data.class} default:#{default.class} #{default}"}
        # the requested list of fields, but if can contain special values
        request =
          case @options[:fields]
          # when NilClass then [SpecialValues::DEF]
          when String then @options[:fields].split(',')
          when Array then @options[:fields]
          when Regexp then return all_fields(data).select{ |i| i.match(@options[:fields])}
          when Proc then return all_fields(data).select{ |i| @options[:fields].call(i)}
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
            default = all_fields(data).select{ |i| default.call(i)} if default.is_a?(Proc)
            default = all_fields(data) if default.nil?
            request.unshift(*default)
          else
            if removal
              result = result.reject{ |i| i.eql?(item)}
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
        return data.map{ |i| i[selected_fields.first]} if selected_fields.length == 1
        return data.map{ |i| i.slice(*selected_fields)}
      end

      # filter the list of items on the select option
      # @param data [Array<Hash>] list of items
      def filter_columns_on_select(data)
        case @options[:select]
        when Proc
          begin
            data.select!{ |i| @options[:select].call(i)}
          rescue Exception => e # rubocop:disable Lint/RescueException
            raise Cli::BadArgument, "Error in user-provided ruby lambda code during select: #{e.message}"
          end
        when Hash
          @options[:select].each{ |k, v| data.select!{ |i| i[k].eql?(v)}}
        end
      end

      # displays a list of objects
      # @param object_array  [Array] array of hash
      # @param fields        [Array] list of column names
      def display_table(object_array, fields, single: false)
        Aspera.assert(!fields.nil?){'missing fields parameter'}
        if object_array.empty?
          # no  display for csv
          display_message(:info, self.class.special_format('empty')) if @options[:format].eql?(:table)
          return
        end
        filter_columns_on_select(object_array)
        object_array.each{ |i| self.class.enhance_display_values_hash(i)}
        # if table has only one element, and only one field, display the value
        if object_array.length == 1 && fields.length == 1
          Log.log.debug("display_table: single element, field: #{fields.first}")
          data = object_array.first[fields.first]
          unless data.is_a?(Array) && data.all?(Hash)
            display_message(:data, data)
            return
          end
          object_array = data
          fields = all_fields(object_array)
          single = false
        end
        Log.dump(:object_array, object_array)
        # convert data to string, and keep only display fields
        final_table_rows = object_array.map{ |r| fields.map{ |c| r[c].to_s}}
        # remove empty rows
        final_table_rows.select!{ |i| !(i.is_a?(Hash) && i.empty?)}
        # here : fields : list of column names
        case @options[:format]
        when :table
          if single || @options[:multi_single].eql?(:yes) ||
              (@options[:multi_single].eql?(:single) && final_table_rows.length.eql?(1))
            # display multiple objects as multiple transposed tables
            final_table_rows.each do |row|
              display_message(:data, Terminal::Table.new(
                headings:  SINGLE_OBJECT_COLUMN_NAMES,
                rows:      fields.zip(row),
                style:     @options[:table_style].symbolize_keys))
            end
          else
            # display the table ! as single table
            display_message(:data, Terminal::Table.new(
              headings:  fields,
              rows:      final_table_rows,
              style:     @options[:table_style].symbolize_keys))
          end
        when :csv
          params = @options[:table_style].symbolize_keys
          # delete default
          params.delete(:border)
          add_headers = params.delete(:headers)
          output = CSV.generate(**params) do |csv|
            csv << fields if add_headers
            final_table_rows.each do |row|
              csv << row
            end
          end
          display_message(:data, output)
        else
          raise "not expected: #{@options[:format]}"
        end
      end
    end
  end
end
