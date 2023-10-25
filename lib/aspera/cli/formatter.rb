# frozen_string_literal: true

require 'aspera/secret_hider'
require 'terminal-table'
require 'yaml'
require 'pp'

module Aspera
  module Cli
    # Take care of output
    class Formatter
      # special value for option `fields` to display all fields
      FIELDS_ALL = 'ALL'
      FIELDS_DEFAULT = 'DEF'
      CSV_RECORD_SEPARATOR = "\n"
      CSV_FIELD_SEPARATOR = ','
      # supported output formats
      DISPLAY_FORMATS = %i[text nagios ruby json jsonpp yaml table csv].freeze
      # user output levels
      DISPLAY_LEVELS = %i[info data error].freeze
      CONF_OVERVIEW_KEYS = %w[config parameter value].freeze
      KEY_VALUE = %w[key value].freeze

      private_constant :FIELDS_ALL, :FIELDS_DEFAULT, :DISPLAY_FORMATS, :DISPLAY_LEVELS, :CSV_RECORD_SEPARATOR, :CSV_FIELD_SEPARATOR,
        :CONF_OVERVIEW_KEYS, :KEY_VALUE

      class << self
        # special for Aspera on Cloud display node
        # {"param" => [{"name"=>"foo","value"=>"bar"}]} will be expanded to {"param.foo" : "bar"}
        def flatten_name_value_list(hash)
          hash.keys.each do |k| # rubocop:disable Style/HashEachMethods
            v = hash[k]
            next unless v.is_a?(Array) && v.map(&:class).uniq.eql?([Hash]) && v.map(&:keys).flatten.sort.uniq.eql?(%w[name value])
            v.each do |pair|
              hash["#{k}.#{pair['name']}"] = pair['value']
            end
            hash.delete(k)
          end
        end

        def flatten_config_overview(hash_array_conf)
          r = []
          hash_array_conf.each do |config, preset|
            preset.each do |parameter, value|
              r.push(CONF_OVERVIEW_KEYS.zip([config, parameter, SecretHider.deep_remove_secret(value).to_s]).to_h)
            end
          end
          return r
        end

        def simple_hash?(h)
          raise 'internal error' unless h.is_a?(Hash)
          !(h.values.any?{|v|[Hash, Array].include?(v.class)})
        end

        # Recursive function to modify a Hash
        # @return [Hash] new hash flattened
        # @param source [Hash] to be modified
        # @param expand_last [TrueClass,FalseClass] true if last level is not
        # @param result [Hash] new hash flattened
        # @param prefix [String] true if last level is not
        def flattened_object(source, result: {}, prefix: '', expand_last: false)
          Log.log.debug{"(#{expand_last})[#{simple_hash?(source)}] -#{source.values}- \n-#{source}-"}
          source.each do |k, v|
            if v.is_a?(Hash) && !(expand_last && simple_hash?(v))
              flattened_object(v, result: result, prefix: prefix + k.to_s + '.', expand_last: expand_last)
            elsif v.is_a?(Array)
              if v.all?(String)
                result[prefix + k.to_s] = v.join("\n")
              else
                v.each_with_index do |item, index|
                  array_prefix = prefix + k.to_s + "[#{index}]"
                  if item.is_a?(Hash)
                    flattened_object(item, result: result, prefix: "#{array_prefix}.", expand_last: expand_last)
                  else
                    result[array_prefix] = item
                  end
                end
              end
            else
              result[prefix + k.to_s] = v
            end
          end
          return result
        end
      end # class

      attr_accessor :option_flat_hash, :option_transpose_single, :option_format, :option_display, :option_fields, :option_table_style,
        :option_select, :option_show_secrets

      # initialize the formatter
      def initialize
        @option_format = nil
        @option_display = nil
        @option_fields = nil
        @option_select = nil
        @option_table_style = nil
        @option_flat_hash = nil
        @option_transpose_single = nil
        @option_show_secrets = nil
      end

      def declare_options(options)
        options.declare(:format, 'Output format', values: DISPLAY_FORMATS, handler: {o: self, m: :option_format}, default: :table)
        options.declare(:display, 'Output only some information', values: DISPLAY_LEVELS, handler: {o: self, m: :option_display}, default: :info)
        options.declare(:fields, "Comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}", handler: {o: self, m: :option_fields}, default: FIELDS_DEFAULT)
        options.declare(:select, 'Select only some items in lists: column, value', types: Hash, handler: {o: self, m: :option_select})
        options.declare(:table_style, 'Table display style', handler: {o: self, m: :option_table_style}, default: ':.:')
        options.declare(:flat_hash, 'Display deep values as additional keys', values: :bool, handler: {o: self, m: :option_flat_hash}, default: true)
        options.declare(:transpose_single, 'Single object fields output vertically', values: :bool, handler: {o: self, m: :option_transpose_single}, default: true)
        options.declare(:show_secrets, 'Show secrets on command output', values: :bool, handler: {o: self, m: :option_show_secrets}, default: false)
      end

      # main output method
      # data: for requested data, not displayed if level==error
      # info: additional info, displayed if level==info
      # error: always displayed on stderr
      def display_message(message_level, message)
        case message_level
        when :data then $stdout.puts(message) unless @option_display.eql?(:error)
        when :info then $stdout.puts(message) if @option_display.eql?(:info)
        when :error then $stderr.puts(message)
        else raise "wrong message_level:#{message_level}"
        end
      end

      def display_status(status)
        display_message(:info, status)
      end

      def display_item_count(number, total)
        count_msg = "Items: #{number}/#{total}"
        count_msg = count_msg.bg_red unless number.to_i.eql?(total.to_i)
        display_status(count_msg)
      end

      def result_default_fields(results, table_rows_hash_val)
        unless results[:fields].nil?
          raise "internal error: [fields] must be Array, not #{results[:fields].class}" unless results[:fields].is_a?(Array)
          if results[:fields].first.eql?(:all_but) && !table_rows_hash_val.empty?
            filter = results[:fields][1..-1]
            return table_rows_hash_val.first.keys.reject{|i|filter.include?(i)}
          end
          return results[:fields]
        end
        return ['empty'] if table_rows_hash_val.empty?
        return table_rows_hash_val.first.keys
      end

      # get the list of all column names used in all lines, not just first one, as all lines may have different columns
      def result_all_fields(table_rows_hash_val)
        raise 'Internal error: must be Array' unless table_rows_hash_val.is_a?(Array)
        return table_rows_hash_val.each_with_object({}){|v, m|v.each_key{|c|m[c] = true}}.keys
      end

      # this method displays the results, especially the table format
      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash (got: #{results.class}: #{results})" unless results.is_a?(Hash)
        raise "INTERNAL ERROR, result must have type (#{results})" unless results.key?(:type)
        raise 'INTERNAL ERROR, result must have data' unless results.key?(:data) || %i[empty nothing].include?(results[:type])
        res_data = results[:data]
        # for config overview, it is name and value
        is_config_overview = res_data.is_a?(Array) && !res_data.empty? && res_data.first.is_a?(Hash) && res_data.first.keys.sort.eql?(CONF_OVERVIEW_KEYS)
        SecretHider.deep_remove_secret(res_data, is_name_value: is_config_overview) unless @option_show_secrets || @option_display.eql?(:data)
        # comma separated list in string format
        user_asked_fields_list_str = @option_fields
        case @option_format
        when :text
          display_message(:data, res_data.to_s)
        when :nagios
          Nagios.process(res_data)
        when :ruby
          display_message(:data, PP.pp(res_data, +''))
        when :json
          display_message(:data, JSON.generate(res_data))
        when :jsonpp
          display_message(:data, JSON.pretty_generate(res_data))
        when :yaml
          display_message(:data, res_data.to_yaml)
        when :table, :csv
          if !@option_transpose_single && results[:type].eql?(:single_object)
            results[:type] = :object_list
            res_data = [res_data]
          end
          case results[:type]
          when :object_list # goes to table display
            raise "internal error: unexpected type: #{res_data.class}, expecting Array" unless res_data.is_a?(Array)
            # :object_list is an array of hash tables, where key=colum name
            table_rows_hash_val = res_data
            final_table_columns = nil
            if @option_flat_hash
              table_rows_hash_val = table_rows_hash_val.map{|obj|self.class.flattened_object(obj, expand_last: results[:option_expand_last])}
            end
            final_table_columns =
              case user_asked_fields_list_str
              when FIELDS_DEFAULT then result_default_fields(results, table_rows_hash_val)
              when FIELDS_ALL then     result_all_fields(table_rows_hash_val)
              else
                if user_asked_fields_list_str.start_with?('+')
                  result_default_fields(results, table_rows_hash_val).push(*user_asked_fields_list_str.gsub(/^\+/, '').split(','))
                elsif user_asked_fields_list_str.start_with?('-')
                  result_default_fields(results, table_rows_hash_val).reject{|i| user_asked_fields_list_str.gsub(/^-/, '').split(',').include?(i)}
                else
                  user_asked_fields_list_str.split(',')
                end
              end
          when :single_object # goes to table display
            # :single_object is a simple hash table  (can be nested)
            raise "internal error: expecting Hash: got #{res_data.class}: #{res_data}" unless res_data.is_a?(Hash)
            final_table_columns = results[:columns] || KEY_VALUE
            if @option_flat_hash
              res_data = self.class.flattened_object(res_data, expand_last: results[:option_expand_last])
              self.class.flatten_name_value_list(res_data)
            end
            asked_fields =
              case user_asked_fields_list_str
              when FIELDS_DEFAULT then results[:fields] || res_data.keys
              when FIELDS_ALL then     res_data.keys
              else user_asked_fields_list_str.split(',')
              end
            table_rows_hash_val = asked_fields.map { |i| { final_table_columns.first => i, final_table_columns.last => res_data[i] } }
            # if only one row, and columns are key/value, then display the value only
            if table_rows_hash_val.length == 1 && final_table_columns.eql?(KEY_VALUE)
              display_message(:data, res_data.values.first)
              return
            end
          when :value_list # goes to table display
            # :value_list is a simple array of values, name of column provided in the :name
            final_table_columns = [results[:name]]
            table_rows_hash_val = res_data.map { |i| { results[:name] => i } }
          when :empty # no table
            display_message(:info, 'empty')
            return
          when :nothing # no result expected
            Log.log.debug('no result expected')
            return
          when :status # no table
            # :status displays a simple message
            display_message(:info, res_data)
            return
          when :text # no table
            # :status displays a simple message
            display_message(:data, res_data)
            return
          when :other_struct # no table
            # :other_struct is any other type of structure
            display_message(:data, PP.pp(res_data, +''))
            return
          else
            raise "unknown data type: #{results[:type]}"
          end
          # here we expect: table_rows_hash_val and final_table_columns
          raise 'no field specified' if final_table_columns.nil?
          if table_rows_hash_val.empty?
            display_message(:info, 'empty'.gray) if @option_format.eql?(:table)
            return
          end
          # convert to string with special function. here table_rows_hash_val is an array of hash
          table_rows_hash_val = results[:textify].call(table_rows_hash_val) if results.key?(:textify)
          unless @option_select.nil? || (@option_select.respond_to?(:empty?) && @option_select.empty?)
            raise CliBadArgument, "expecting hash for select, have #{@option_select.class}: #{@option_select}" unless @option_select.is_a?(Hash)
            @option_select.each{|k, v|table_rows_hash_val.select!{|i|i[k].eql?(v)}}
          end
          # convert data to string, and keep only display fields
          final_table_rows = table_rows_hash_val.map { |r| final_table_columns.map { |c| r[c].to_s } }
          # here : final_table_columns : list of column names
          # here: final_table_rows : array of list of value
          case @option_format
          when :table
            style = @option_table_style.chars
            # display the table !
            display_message(:data, Terminal::Table.new(
              headings:  final_table_columns,
              rows:      final_table_rows,
              border_x:  style[0],
              border_y:  style[1],
              border_i:  style[2]))
          when :csv
            display_message(:data, final_table_rows.map{|t| t.join(CSV_FIELD_SEPARATOR)}.join(CSV_RECORD_SEPARATOR))
          end
        end
      end
    end
  end
end
