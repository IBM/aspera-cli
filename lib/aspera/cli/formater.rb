#require 'text-table'
require 'terminal-table'

#require 'fileutils'
require 'yaml'
require 'pp'

module Aspera
  module Cli
    # Take care of output
    class Formater
      FIELDS_ALL='ALL'
      FIELDS_DEFAULT='DEF'
      # supported output formats
      DISPLAY_FORMATS=[:table,:ruby,:json,:jsonpp,:yaml,:csv,:nagios]
      # user output levels
      DISPLAY_LEVELS=[:info,:data,:error]
      CSV_RECORD_SEPARATOR="\n"
      CSV_FIELD_SEPARATOR=','

      private_constant :FIELDS_ALL,:FIELDS_DEFAULT,:DISPLAY_FORMATS,:DISPLAY_LEVELS,:CSV_RECORD_SEPARATOR,:CSV_FIELD_SEPARATOR
      attr_accessor :option_flat_hash,:option_transpose_single

      def initialize(opt_mgr)
        @option_flat_hash=true
        @option_transpose_single=true
        @opt_mgr=opt_mgr
        @opt_mgr.set_obj_attr(:flat_hash,self,:option_flat_hash)
        @opt_mgr.set_obj_attr(:transpose_single,self,:option_transpose_single)
        @opt_mgr.add_opt_list(:format,DISPLAY_FORMATS,'output format')
        @opt_mgr.add_opt_list(:display,DISPLAY_LEVELS,'output only some information')
        @opt_mgr.add_opt_simple(:fields,"comma separated list of fields, or #{FIELDS_ALL}, or #{FIELDS_DEFAULT}")
        @opt_mgr.add_opt_simple(:select,'select only some items in lists, extended value: hash (column, value)')
        @opt_mgr.add_opt_simple(:table_style,'table display style')
        @opt_mgr.add_opt_boolean(:flat_hash,'display hash values as additional keys')
        @opt_mgr.add_opt_boolean(:transpose_single,'single object fields output vertically')
        @opt_mgr.set_option(:format,:table)
        @opt_mgr.set_option(:display,:info)
        @opt_mgr.set_option(:fields,FIELDS_DEFAULT)
        @opt_mgr.set_option(:table_style,':.:')
      end

      # main output method
      def display_message(message_level,message)
        display_level=@opt_mgr.get_option(:display,:mandatory)
        case message_level
        when :info then STDOUT.puts(message) if display_level.eql?(:info)
        when :data then STDOUT.puts(message) unless display_level.eql?(:error)
        when :error then STDERR.puts(message)
        else raise "wrong message_level:#{message_level}"
        end
      end

      def display_status(status)
        display_message(:info,status)
      end

      # @param source [Hash] hash to modify
      # @param keep_last [bool]
      def self.flatten_object(source,keep_last)
        newval={}
        flatten_sub_hash_rec(source,keep_last,'',newval)
        source.clear
        source.merge!(newval)
      end

      # recursive function to modify a hash
      # @param source [Hash] to be modified
      # @param keep_last [bool] truer if last level is not
      # @param prefix [String] true if last level is not
      # @param dest [Hash] new hash flattened
      def self.flatten_sub_hash_rec(source,keep_last,prefix,dest)
        #is_simple_hash=source.is_a?(Hash) and source.values.inject(true){|m,v| xxx=!v.respond_to?(:each) and m;puts("->#{xxx}>#{v.respond_to?(:each)} #{v}-");xxx}
        is_simple_hash=false
        Log.log.debug("(#{keep_last})[#{is_simple_hash}] -#{source.values}- \n-#{source}-")
        return source if keep_last and is_simple_hash
        source.each do |k,v|
          if v.is_a?(Hash) and (!keep_last or !is_simple_hash)
            flatten_sub_hash_rec(v,keep_last,prefix+k.to_s+'.',dest)
          else
            dest[prefix+k.to_s]=v
          end
        end
        return nil
      end

      # special for Aspera on Cloud display node
      # {"param" => [{"name"=>"foo","value"=>"bar"}]} will be expanded to {"param.foo" : "bar"}
      def self.flatten_name_value_list(hash)
        hash.keys.each do |k|
          v=hash[k]
          if v.is_a?(Array) and v.map{|i|i.class}.uniq.eql?([Hash]) and v.map{|i|i.keys}.flatten.sort.uniq.eql?(['name', 'value'])
            v.each do |pair|
              hash["#{k}.#{pair['name']}"]=pair['value']
            end
            hash.delete(k)
          end
        end
      end

      def result_default_fields(results,table_rows_hash_val)
        if results.has_key?(:fields) and !results[:fields].nil?
          final_table_columns=results[:fields]
        else
          if !table_rows_hash_val.empty?
            final_table_columns=table_rows_hash_val.first.keys
          else
            final_table_columns=['empty']
          end
        end
        return final_table_columns
      end

      def result_all_fields(results,table_rows_hash_val)
        raise 'internal error: must be array' unless table_rows_hash_val.is_a?(Array)
        # get the list of all column names used in all lines, not just frst one, as all lines may have different columns
        return table_rows_hash_val.inject({}){|m,v|v.keys.each{|c|m[c]=true};m}.keys
      end

      # this method displays the results, especially the table format
      def display_results(results)
        raise "INTERNAL ERROR, result must be Hash (got: #{results.class}: #{results})" unless results.is_a?(Hash)
        raise 'INTERNAL ERROR, result must have type' unless results.has_key?(:type)
        raise 'INTERNAL ERROR, result must have data' unless results.has_key?(:data) or [:empty,:nothing].include?(results[:type])
        res_data=results[:data]
        # comma separated list in string format
        user_asked_fields_list_str=@opt_mgr.get_option(:fields,:mandatory)
        display_format=@opt_mgr.get_option(:format,:mandatory)
        case display_format
        when :nagios
          Nagios.process(res_data)
        when :ruby
          display_message(:data,PP.pp(res_data,''))
        when :json
          display_message(:data,JSON.generate(res_data))
        when :jsonpp
          display_message(:data,JSON.pretty_generate(res_data))
        when :yaml
          display_message(:data,res_data.to_yaml)
        when :table,:csv
          if !@option_transpose_single and results[:type].eql?(:single_object)
            results[:type]=:object_list
            res_data=[res_data]
          end
          case results[:type]
          when :object_list # goes to table display
            raise "internal error: unexpected type: #{res_data.class}, expecting Array" unless res_data.is_a?(Array)
            # :object_list is an array of hash tables, where key=colum name
            table_rows_hash_val = res_data
            final_table_columns=nil
            if @option_flat_hash
              table_rows_hash_val.each do |obj|
                self.class.flatten_object(obj,results[:option_expand_last])
              end
            end
            final_table_columns=
            case user_asked_fields_list_str
            when FIELDS_DEFAULT then result_default_fields(results,table_rows_hash_val)
            when FIELDS_ALL then     result_all_fields(results,table_rows_hash_val)
            else
              if user_asked_fields_list_str.start_with?('+')
                result_default_fields(results,table_rows_hash_val).push(*user_asked_fields_list_str.gsub(/^\+/,'').split(','))
              elsif user_asked_fields_list_str.start_with?('-')
                result_default_fields(results,table_rows_hash_val).select{|i| !user_asked_fields_list_str.gsub(/^\-/,'').split(',').include?(i)}
              else
                user_asked_fields_list_str.split(',')
              end
            end
          when :single_object # goes to table display
            # :single_object is a simple hash table  (can be nested)
            raise "internal error: expecting Hash: got #{res_data.class}: #{res_data}" unless res_data.is_a?(Hash)
            final_table_columns = results[:columns] || ['key','value']
            if @option_flat_hash
              self.class.flatten_object(res_data,results[:option_expand_last])
              self.class.flatten_name_value_list(res_data)
            end
            asked_fields=
            case user_asked_fields_list_str
            when FIELDS_DEFAULT then results[:fields]||res_data.keys
            when FIELDS_ALL then     res_data.keys
            else user_asked_fields_list_str.split(',')
            end
            table_rows_hash_val=asked_fields.map { |i| { final_table_columns.first => i, final_table_columns.last => res_data[i] } }
          when :value_list # goes to table display
            # :value_list is a simple array of values, name of column provided in the :name
            final_table_columns = [results[:name]]
            table_rows_hash_val=res_data.map { |i| { results[:name] => i } }
          when :empty # no table
            display_message(:info,'empty')
            return
          when :nothing # no result expected
            Log.log.debug('no result expected')
            return
          when :status # no table
            # :status displays a simple message
            display_message(:info,res_data)
            return
          when :text # no table
            # :status displays a simple message
            display_message(:data,res_data)
            return
          when :other_struct # no table
            # :other_struct is any other type of structure
            display_message(:data,PP.pp(res_data,''))
            return
          else
            raise "unknown data type: #{results[:type]}"
          end
          # here we expect: table_rows_hash_val and final_table_columns
          raise 'no field specified' if final_table_columns.nil?
          if table_rows_hash_val.empty?
            display_message(:info,'empty'.gray) unless display_format.eql?(:csv)
            return
          end
          # convert to string with special function. here table_rows_hash_val is an array of hash
          table_rows_hash_val=results[:textify].call(table_rows_hash_val) if results.has_key?(:textify)
          filter=@opt_mgr.get_option(:select,:optional)
          unless filter.nil? or (filter.respond_to?('empty?') and filter.empty?)
            raise CliBadArgument,"expecting hash for select, have #{filter.class}: #{filter}" unless filter.is_a?(Hash)
            filter.each{|k,v|table_rows_hash_val.select!{|i|i[k].eql?(v)}}
          end

          # convert data to string, and keep only display fields
          final_table_rows=table_rows_hash_val.map { |r| final_table_columns.map { |c| r[c].to_s } }
          # here : final_table_columns : list of column names
          # here: final_table_rows : array of list of value
          case display_format
          when :table
            style=@opt_mgr.get_option(:table_style,:mandatory).split('')
            # display the table !
            #display_message(:data,Text::Table.new(
            #head:  final_table_columns,
            #rows:  final_table_rows,
            #horizontal_boundary:    style[0],
            #vertical_boundary:      style[1],
            #boundary_intersection:  style[2]))
            display_message(:data,Terminal::Table.new(
            headings:  final_table_columns,
            rows:      final_table_rows,
            border_x:  style[0],
            border_y:  style[1],
            border_i:  style[2]))
          when :csv
            display_message(:data,final_table_rows.map{|t| t.join(CSV_FIELD_SEPARATOR)}.join(CSV_RECORD_SEPARATOR))
          end
        end
      end
    end
  end
end
