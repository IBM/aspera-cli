# frozen_string_literal: true

# cspell:ignore jsonpp
require 'aspera/secret_hider'
require 'aspera/environment'
require 'aspera/log'
require 'aspera/assert'
require 'terminal-table'
require 'yaml'
require 'pp'

module Aspera
  module Cli
    CONF_OVERVIEW_KEYS = %w[preset parameter value].freeze
    # This class is used to transform a complex structure into a simple hash
    class Flattener
      def initialize
        @result = nil
      end

      # General method
      def flatten(something)
        assert_type(something, Hash)
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
          @result[name] = Formatter.special('empty string')
        elsif something.nil?
          @result[name] = Formatter.special('null')
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
          @result[name] = Formatter.special('empty list')
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
    end # class

    # Take care of output
    class Formatter
      FIELDS_LESS = '-'
      CSV_RECORD_SEPARATOR = "\n"
      CSV_FIELD_SEPARATOR = ','
      # supported output formats
      DISPLAY_FORMATS = %i[text nagios ruby json jsonpp yaml table csv].freeze
      # user output levels
      DISPLAY_LEVELS = %i[info data error].freeze

      private_constant :DISPLAY_FORMATS, :DISPLAY_LEVELS, :CSV_RECORD_SEPARATOR, :CSV_FIELD_SEPARATOR
      # prefix to display error messages in user messages (terminal)
      ERROR_FLASH = 'ERROR:'.bg_red.gray.blink.freeze
      WARNING_FLASH = 'WARNING:'.bg_brown.black.blink.freeze
      HINT_FLASH = 'HINT:'.bg_green.gray.blink.freeze

      class << self
        # Highlight special values
        def special(what, use_colors: $stdout.isatty)
          result = "<#{what}>"
          if use_colors
            result = if %w[null empty].any?{|s|what.include?(s)}
              result.dim
            else
              result.reverse_color
            end
          end
          return result
        end

        def all_but(list)
          list = [list] unless list.is_a?(Array)
          return list.map{|i|"#{FIELDS_LESS}#{i}"}.unshift(ExtendedValue::ALL)
        end

        def tick(yes)
          result =
            if Environment.use_unicode?
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
      end # self

      # initialize the formatter
      def initialize
        @options = {}
      end

      def option_handler(option_symbol, operation, value=nil)
        assert_values(operation, %i[set get])
        case operation
        when :set
          @options[option_symbol] = value
          if option_symbol.eql?(:output)
            $stdout = if value.eql?('-')
              STDOUT # rubocop:disable Style/GlobalStdStream
            else
              File.open(value, 'w')
            end
          end
        when :get then return @options[option_symbol]
        else error_unreachable_line
        end
        nil
      end

      def declare_options(options)
        options.declare(:format, 'Output format', values: DISPLAY_FORMATS, handler: {o: self, m: :option_handler}, default: :table)
        options.declare(:output, 'Destination for results', types: String, handler: {o: self, m: :option_handler})
        options.declare(:display, 'Output only some information', values: DISPLAY_LEVELS, handler: {o: self, m: :option_handler}, default: :info)
        options.declare(
          :fields, "Comma separated list of: fields, or #{ExtendedValue::ALL}, or #{ExtendedValue::DEF}", handler: {o: self, m: :option_handler},
          types: [String, Array, Regexp, Proc],
          default: ExtendedValue::DEF)
        options.declare(:select, 'Select only some items in lists: column, value', types: [Hash, Proc], handler: {o: self, m: :option_handler})
        options.declare(:table_style, 'Table display style', handler: {o: self, m: :option_handler}, default: ':.:')
        options.declare(:flat_hash, 'Display deep values as additional keys', values: :bool, handler: {o: self, m: :option_handler}, default: true)
        options.declare(:transpose_single, 'Single object fields output vertically', values: :bool, handler: {o: self, m: :option_handler}, default: true)
        options.declare(:show_secrets, 'Show secrets on command output', values: :bool, handler: {o: self, m: :option_handler}, default: false)
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
        else error_unexpected_value(message_level)
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

      # this method computes the list of fields to display
      # data: array of hash
      # default: list of fields to display by default (may contain special values)
      def compute_fields(data, default)
        Log.log.debug{"compute_fields: data:#{data.class} default:#{default.class} #{default}"}
        request =
          case @options[:fields]
          when NilClass then [ExtendedValue::DEF]
          when String then @options[:fields].split(',')
          when Array then @options[:fields]
          when Regexp then return all_fields(data).select{|i|i.match(@options[:fields])}
          when Proc then return all_fields(data).select{|i|@options[:fields].call(i)}
          else error_unexpected_value(@options[:fields])
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
          when ExtendedValue::ALL
            # get the list of all column names used in all lines, not just first one, as all lines may have different columns
            request.unshift(*all_fields(data))
          when ExtendedValue::DEF
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

      # this method displays a table
      # object_array: array of hash
      # fields: list of column names
      def display_table(object_array, fields)
        assert(!fields.nil?){'missing fields parameter'}
        case @options[:select]
        when Proc
          object_array.select!{|i|@options[:select].call(i)}
        when Hash
          @options[:select].each{|k, v|object_array.select!{|i|i[k].eql?(v)}}
        end
        if object_array.empty?
          # no  display for csv
          display_message(:info, Formatter.special('empty')) if @options[:format].eql?(:table)
          return
        end
        if object_array.length == 1 && fields.length == 1
          display_message(:data, object_array.first[fields.first])
          return
        end
        # Special case if only one row (it could be object_list or single_object)
        if @options[:transpose_single] && object_array.length == 1
          new_columns = %i[key value]
          single = object_array.first
          object_array = fields.map { |i| new_columns.zip([i, single[i]]).to_h }
          fields = new_columns
        end
        Log.log.debug{Log.dump(:object_array, object_array)}
        # convert data to string, and keep only display fields
        final_table_rows = object_array.map { |r| fields.map { |c| r[c].to_s } }
        # here : fields : list of column names
        case @options[:format]
        when :table
          style = @options[:table_style].chars
          # display the table !
          display_message(:data, Terminal::Table.new(
            headings:  fields,
            rows:      final_table_rows,
            border_x:  style[0],
            border_y:  style[1],
            border_i:  style[2]))
        when :csv
          display_message(:data, final_table_rows.map{|t| t.join(CSV_FIELD_SEPARATOR)}.join(CSV_RECORD_SEPARATOR))
        end
      end

      # this method displays the results, especially the table format
      def display_results(results)
        assert((results.keys - %i[type data fields name]).empty?){"result unsupported key: #{results.keys - %i[type data fields name]}"}
        # :type :data :fields :name
        assert_type(results, Hash)
        assert(results.key?(:type)){"result must have type (#{results})"}
        assert(results.key?(:data) || %i[empty nothing].include?(results[:type])){'result must have data'}
        Log.log.debug{"display_results: #{results[:data].class} #{results[:type]}"}
        SecretHider.deep_remove_secret(results[:data]) unless @options[:show_secrets] || @options[:display].eql?(:data)
        case @options[:format]
        when :text
          display_message(:data, results[:data].to_s)
        when :nagios
          Nagios.process(results[:data])
        when :ruby
          display_message(:data, PP.pp(results[:data], +''))
        when :json
          display_message(:data, JSON.generate(results[:data]))
        when :jsonpp
          display_message(:data, JSON.pretty_generate(results[:data]))
        when :yaml
          display_message(:data, results[:data].to_yaml)
        when :table, :csv
          case results[:type]
          when :config_over
            display_table(Flattener.new.config_over(results[:data]), CONF_OVERVIEW_KEYS)
          when :object_list, :single_object
            obj_list = results[:data]
            obj_list = [obj_list] if results[:type].eql?(:single_object)
            assert_type(obj_list, Array)
            assert(obj_list.all?(Hash)){"expecting Array of Hash: #{obj_list.inspect}"}
            # :object_list is an array of hash tables, where key=colum name
            obj_list = obj_list.map{|obj|Flattener.new.flatten(obj)} if @options[:flat_hash]
            display_table(obj_list, compute_fields(obj_list, results[:fields]))
          when :value_list
            # :value_list is a simple array of values, name of column provided in the :name
            display_table(results[:data].map { |i| { results[:name] => i } }, [results[:name]])
          when :empty # no table
            display_message(:info, Formatter.special('empty'))
            return
          when :nothing # no result expected
            Log.log.debug('no result expected')
          when :status # no table
            # :status displays a simple message
            display_message(:info, results[:data])
          when :text # no table
            # :status displays a simple message
            display_message(:data, results[:data])
          when :other_struct # no table
            # :other_struct is any other type of structure
            display_message(:data, PP.pp(results[:data], +''))
          else
            raise "unknown data type: #{results[:type]}"
          end
        end
      end
    end
  end
end
