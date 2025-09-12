# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/assert'

module Aspera
  module Cli
    # Base class for plugins
    class Plugin
      # operations without id
      GLOBAL_OPS = %i[create list].freeze
      # operations with id
      INSTANCE_OPS = %i[modify delete show].freeze
      # all standard operations
      ALL_OPS = (GLOBAL_OPS + INSTANCE_OPS).freeze
      # special query parameter: max number of items for list command
      MAX_ITEMS = 'max'
      # special query parameter: max number of pages for list command
      MAX_PAGES = 'pmax'
      # special identifier format: look for this name to find where supported
      REGEX_LOOKUP_ID_BY_FIELD = /^%([^:]+):(.*)$/
      PER_PAGE_DEFAULT = 1000
      private_constant :PER_PAGE_DEFAULT

      class << self
        def declare_generic_options(options)
          options.declare(:query, 'Additional filter for for some commands (list/delete)', types: [Hash, Array])
          options.declare(:property, 'Name of property to set (modify operation)')
          options.declare(:bulk, 'Bulk operation (only some)', values: :bool, default: :no)
          options.declare(:bfail, 'Bulk operation error handling', values: :bool, default: :yes)
        end
      end

      def options; @broker.options; end
      def transfer; @broker.transfer; end
      def config; @broker.config; end
      def formatter; @broker.formatter; end
      def persistency; @broker.persistency; end

      def initialize(broker:, man_header: true)
        # check presence in descendant of mandatory method and constant
        Aspera.assert(respond_to?(:execute_action)){"Missing method 'execute_action' in #{self.class}"}
        Aspera.assert(self.class.constants.include?(:ACTIONS)){"Missing constant 'ACTIONS' in #{self.class}"}
        @broker = broker
        add_manual_header if man_header
      end

      def add_manual_header(has_options = true)
        # manual header for all plugins
        options.parser.separator('')
        options.parser.separator("COMMAND: #{self.class.name.split('::').last.downcase}")
        options.parser.separator("SUBCOMMANDS: #{self.class.const_get(:ACTIONS).map(&:to_s).sort.join(' ')}")
        options.parser.separator('OPTIONS:') if has_options
      end

      # @return a hash of instance variables
      def init_params
        return {broker: @broker}
      end

      # Must be called AFTER the instance action:
      # ... folder browse _call_instance_identifier
      #
      # @param description [String] description of the identifier
      # @param as_option   [Symbol] option name to use if identifier is an option
      # @param block       [Proc] block to search for identifier based on attribute value
      # @return   [String, Array] identifier or list of ids
      def instance_identifier(description: 'identifier', as_option: nil, &block)
        if as_option.nil?
          res_id = options.get_next_argument(description, multiple: options.get_option(:bulk)) if res_id.nil?
        else
          res_id = options.get_option(as_option)
        end
        # can be an Array
        if res_id.is_a?(String) && (m = res_id.match(REGEX_LOOKUP_ID_BY_FIELD))
          if block
            res_id = yield(m[1], ExtendedValue.instance.evaluate(m[2]))
          else
            raise Cli::BadArgument, "Percent syntax for #{description} not supported in this context"
          end
        end
        return res_id
      end

      # For create and delete operations: execute one actin or multiple if bulk is yes
      # @param command   [Symbol] operation: :create, :delete, ...
      # @param descr     [String] description of the value
      # @param values    [Object] the value(s), or the type of value to get from user
      # @param id_result [String] key in result hash to use as identifier
      # @param fields    [Array]  fields to display
      # @param &block    [Proc]   block to execute for each value
      def do_bulk_operation(command:, descr: nil, values: Hash, id_result: 'id', fields: :default)
        Aspera.assert(block_given?){'missing block'}
        is_bulk = options.get_option(:bulk)
        case values
        when :identifier
          values = instance_identifier(description: descr)
        when Class
          values = value_create_modify(command: command, description: descr, type: values, bulk: is_bulk)
        end
        # if not bulk, there is a single value
        params = is_bulk ? values : [values]
        Log.log.warn('Empty list given for bulk operation') if params.empty?
        Log.dump(:bulk_operation, params)
        result_list = []
        params.each do |param|
          # init for delete
          result = {id_result => param}
          begin
            # execute custom code
            res = yield(param)
            # if block returns a hash, let's use this (create)
            result = res if res.is_a?(Hash)
            # TODO: remove when faspio gw api fixes this
            result = res.first if res.is_a?(Array) && res.first.is_a?(Hash)
            # create -> created
            result['status'] = "#{command}#{'e' unless command.to_s.end_with?('e')}d".gsub(/yed$/, 'ied')
          rescue StandardError => e
            raise e if options.get_option(:bfail)
            result['status'] = e.to_s
          end
          result_list.push(result)
        end
        display_fields = [id_result, 'status']
        if is_bulk
          return Main.result_object_list(result_list, fields: display_fields)
        else
          display_fields = fields unless fields.eql?(:default)
          return Main.result_single_object(result_list.first, fields: display_fields)
        end
      end

      # Operations: Create, Delete, Show, List, Modify
      # @param api            [Rest]    api to use
      # @param entity         [String]  sub path in URL to resource relative to base url
      # @param command        [Symbol]  command to execute: create show list modify delete
      # @param display_fields [Array]   fields to display by default
      # @param items_key      [String]  result is in a sub key of the json
      # @param delete_style   [String]  if set, the delete operation by array in payload
      # @param id_as_arg      [String]  if set, the id is provided as url argument ?<id_as_arg>=<id>
      # @param is_singleton   [Boolean] if true, entity is the full path to the resource
      # @param tclo           [Bool]    if set, :list use paging with total_count, limit, offset
      # @param block          [Proc]    block to search for identifier based on attribute value
      # @return result suitable for CLI result
      def entity_execute(
        api:,
        entity:,
        command: nil,
        display_fields: nil,
        items_key: nil,
        delete_style: nil,
        id_as_arg: false,
        is_singleton: false,
        list_query: nil,
        tclo: false,
        &block
      )
        command = options.get_next_command(ALL_OPS) if command.nil?
        if is_singleton
          one_res_path = entity
        elsif INSTANCE_OPS.include?(command)
          one_res_id = instance_identifier(&block)
          one_res_path = "#{entity}/#{one_res_id}"
          one_res_path = "#{entity}?#{id_as_arg}=#{one_res_id}" if id_as_arg
        end

        case command
        when :create
          raise BadArgument, 'cannot create singleton' if is_singleton
          return do_bulk_operation(command: command, descr: 'data', fields: display_fields) do |params|
            api.create(entity, params)
          end
        when :delete
          raise BadArgument, 'cannot delete singleton' if is_singleton
          if !delete_style.nil?
            one_res_id = [one_res_id] unless one_res_id.is_a?(Array)
            Aspera.assert_type(one_res_id, Array, type: Cli::BadArgument)
            api.call(
              operation:    'DELETE',
              subpath:      entity,
              content_type: Rest::MIME_JSON,
              body:         {delete_style => one_res_id},
              headers:      {'Accept' => Rest::MIME_JSON}
            )
            return Main.result_status('deleted')
          end
          return do_bulk_operation(command: command, values: one_res_id) do |one_id|
            api.delete("#{entity}/#{one_id}", query_read_delete)
            {'id' => one_id}
          end
        when :show
          return Main.result_single_object(api.read(one_res_path), fields: display_fields)
        when :list
          if tclo
            data, total = list_entities_limit_offset_total_count(api: api, entity:, items_key: items_key, query: list_query)
            return Main.result_object_list(data, total: total, fields: display_fields)
          end
          resp = api.call(operation: 'GET', subpath: entity, headers: {'Accept' => Rest::MIME_JSON}, query: query_read_delete)
          return Main.result_empty if resp[:http].code == '204'
          data = resp[:data]
          # TODO: not generic : which application is this for ?
          if resp[:http]['Content-Type'].start_with?('application/vnd.api+json')
            Log.log.debug('is vnd.api')
            data = data[entity]
          end
          data = data[items_key] if items_key
          case data
          when Hash
            return Main.result_single_object(data, fields: display_fields)
          when Array
            return Main.result_object_list(data, fields: display_fields) if data.empty? || data.first.is_a?(Hash)
            return Main.result_value_list(data, 'id')
          else
            raise "An error occurred: unexpected result type for list: #{data.class}"
          end
        when :modify
          parameters = value_create_modify(command: command)
          property = options.get_option(:property)
          parameters = {property => parameters} unless property.nil?
          api.update(one_res_path, parameters)
          return Main.result_status('modified')
        else
          raise "unknown action: #{command}"
        end
      end

      # query parameters in URL suitable for REST: list/GET and delete/DELETE
      def query_read_delete(default: nil)
        query = options.get_option(:query)
        # dup default, as it could be frozen
        query = default.dup if query.nil?
        Log.log.debug{"query_read_delete=#{query}".bg_red}
        begin
          # check it is suitable
          URI.encode_www_form(query) unless query.nil?
        rescue StandardError => e
          raise Cli::BadArgument, "Query must be an extended value (Hash, Array) which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
        end
        return query
      end

      # Retrieves an extended value from command line, used for creation or modification of entities
      # @param command [Symbol] command name for error message
      # @param type [Class] expected type of value, either a Class, an Array of Class
      # @param bulk [Boolean] if true, value must be an Array of <type>
      # @param default [Object] default value if not provided
      def value_create_modify(command:, description: nil, type: Hash, bulk: false, default: nil)
        value = options.get_next_argument(
          "parameters for #{command}#{" (#{description})" unless description.nil?}", mandatory: default.nil?,
          validation: bulk ? Array : type)
        value = default if value.nil?
        unless type.nil?
          type = [type] unless type.is_a?(Array)
          Aspera.assert(type.all?(Class)){"check types must be a Class, not #{type.map(&:class).join(',')}"}
          if bulk
            Aspera.assert_type(value, Array, type: Cli::BadArgument)
            value.each do |v|
              Aspera.assert_values(v.class, type, type: Cli::BadArgument)
            end
          else
            Aspera.assert_values(value.class, type, type: Cli::BadArgument)
          end
        end
        return value
      end

      # Get a (full or partial) list of all entities of a given type with query: offset/limit
      # @param `api`       [Rest]          the API object
      # @param `entity`    [String,Symbol] the API endpoint of entity to list
      # @param `items_key` [String]        key in the result to get the list of items
      # @param `query`     [Hash,nil]      additional query parameters
      # @return [Array] items, total_count
      def list_entities_limit_offset_total_count(
        api:,
        entity:,
        items_key: nil,
        query: nil
      )
        entity = entity.to_s if entity.is_a?(Symbol)
        items_key = entity.split('/').last if items_key.nil?
        query = {} if query.nil?
        Aspera.assert_type(entity, String)
        Aspera.assert_type(items_key, String)
        Aspera.assert_type(query, Hash)
        Log.log.debug{"list_entities t=#{entity} k=#{items_key} q=#{query}"}
        result = []
        offset = 0
        max_items = query.delete(MAX_ITEMS)
        remain_pages = query.delete(MAX_PAGES)
        # merge default parameters, by default 100 per page
        query = {'limit'=> PER_PAGE_DEFAULT}.merge(query)
        total_count = nil
        loop do
          query['offset'] = offset
          page_result = api.read(entity, query)
          Aspera.assert_type(page_result[items_key], Array)
          result.concat(page_result[items_key])
          # reach the limit set by user ?
          if !max_items.nil? && (result.length >= max_items)
            result = result.slice(0, max_items)
            break
          end
          total_count ||= page_result['total_count']
          break if result.length >= total_count
          remain_pages -= 1 unless remain_pages.nil?
          break if remain_pages == 0
          offset += page_result[items_key].length
          formatter.long_operation_running
        end
        formatter.long_operation_terminated
        return result, total_count
      end

      # Lookup an entity id from its name
      # @param entity    [String] the type of entity to lookup, by default it is the path, and it is also the field name in result
      # @param value     [String] the value to lookup
      # @param field     [String] the field to match, by default it is 'name'
      # @param items_key [String] key in the result to get the list of items (override entity)
      # @param query     [Hash]   additional query parameters
      def lookup_entity_by_field(api:, entity:, value:, field: 'name', items_key: nil, query: :default)
        if query.eql?(:default)
          Aspera.assert(field.eql?('name')){'Default query is on name only'}
          query = {'q'=> value}
        end
        found = list_entities_limit_offset_total_count(api: api, entity: entity, items_key: items_key, query: query).first.select{ |i| i[field].eql?(value)}
        case found.length
        when 0 then raise "No #{entity} with #{field} = #{value}"
        when 1 then return found.first
        else raise "Found #{found.length} #{entity} with #{field} = #{value}"
        end
      end
    end
  end
end
