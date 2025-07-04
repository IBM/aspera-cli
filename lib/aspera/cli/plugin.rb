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
      REGEX_LOOKUP_ID_BY_FIELD = /^%([^:]+):(.*)$/.freeze

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

      # must be called AFTER the instance action, ... folder browse <call instance_identifier>
      # @param description [String] description of the identifier
      # @param as_option [Symbol] option name to use if identifier is an option
      # @param block [Proc] block to search for identifier based on attribute value
      # @return [String, Array] identifier or list of ids
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
      # @param command [Symbol] operation: :create, :delete, ...
      # @param descr [String] description of the value
      # @param values [Object] the value(s), or the type of value to get from user
      # @param id_result [String] key in result hash to use as identifier
      # @param fields [Array] fields to display
      def do_bulk_operation(command:, descr:, values: Hash, id_result: 'id', fields: :default)
        Aspera.assert(block_given?){'missing block'}
        is_bulk = options.get_option(:bulk)
        case values
        when :identifier
          values = instance_identifier
        when Class
          values = value_create_modify(command: command, type: values, bulk: is_bulk)
        end
        # if not bulk, there is a single value
        params = is_bulk ? values : [values]
        Log.log.warn('Empty list given for bulk operation') if params.empty?
        Log.log.debug{Log.dump(:bulk_operation, params)}
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

      # @param command [Symbol] command to execute: create show list modify delete
      # @param rest_api [Rest] api to use
      # @param res_class_path [String] sub path in URL to resource relative to base url
      # @param display_fields [Array] fields to display by default
      # @param item_list_key [String] result is in a sub key of the json
      # @param id_as_arg [String] if set, the id is provided as url argument ?<id_as_arg>=<id>
      # @param is_singleton [Boolean] if true, res_class_path is the full path to the resource
      # @param delete_style [String] if set, the delete operation by array in payload
      # @param block [Proc] block to search for identifier based on attribute value
      # @return result suitable for CLI result
      def entity_command(command, rest_api, res_class_path,
        display_fields: nil,
        item_list_key: false,
        id_as_arg: false,
        is_singleton: false,
        delete_style: nil,
        &block)
        if is_singleton
          one_res_path = res_class_path
        elsif INSTANCE_OPS.include?(command)
          one_res_id = instance_identifier(&block)
          one_res_path = "#{res_class_path}/#{one_res_id}"
          one_res_path = "#{res_class_path}?#{id_as_arg}=#{one_res_id}" if id_as_arg
        end

        case command
        when :create
          raise 'cannot create singleton' if is_singleton
          return do_bulk_operation(command: command, descr: 'data', fields: display_fields) do |params|
            rest_api.create(res_class_path, params)
          end
        when :delete
          raise 'cannot delete singleton' if is_singleton
          if !delete_style.nil?
            one_res_id = [one_res_id] unless one_res_id.is_a?(Array)
            Aspera.assert_type(one_res_id, Array, exception_class: Cli::BadArgument)
            rest_api.call(
              operation:    'DELETE',
              subpath:      res_class_path,
              content_type: Rest::MIME_JSON,
              body:         {delete_style => one_res_id},
              headers:      {'Accept' => Rest::MIME_JSON}
            )
            return Main.result_status('deleted')
          end
          return do_bulk_operation(command: command, descr: 'identifier', values: one_res_id) do |one_id|
            rest_api.delete("#{res_class_path}/#{one_id}", query_read_delete)
            {'id' => one_id}
          end
        when :show
          return Main.result_single_object(rest_api.read(one_res_path), fields: display_fields)
        when :list
          resp = rest_api.call(operation: 'GET', subpath: res_class_path, headers: {'Accept' => Rest::MIME_JSON}, query: query_read_delete)
          return Main.result_empty if resp[:http].code == '204'
          data = resp[:data]
          # TODO: not generic : which application is this for ?
          if resp[:http]['Content-Type'].start_with?('application/vnd.api+json')
            Log.log.debug{'is vnd.api'}
            data = data[res_class_path]
          end
          if item_list_key
            item_list = data[item_list_key]
            total_count = data['total_count']
            formatter.display_item_count(item_list.length, total_count) unless total_count.nil?
            data = item_list
          end
          case data
          when Hash
            return Main.result_single_object(data, fields: display_fields)
          when Array
            return Main.result_object_list(data, fields: display_fields) if data.empty? || data.first.is_a?(Hash)
            return Main.result_value_list(data, name: 'id')
          else
            raise "An error occurred: unexpected result type for list: #{data.class}"
          end
        when :modify
          parameters = value_create_modify(command: command)
          property = options.get_option(:property)
          parameters = {property => parameters} unless property.nil?
          rest_api.update(one_res_path, parameters)
          return Main.result_status('modified')
        else
          raise "unknown action: #{command}"
        end
      end

      # implement generic rest operations on given resource path
      def entity_action(rest_api, res_class_path, **opts, &block)
        # res_name=res_class_path.gsub(%r{^.*/},'').gsub(%r{s$},'').gsub('_',' ')
        command = options.get_next_command(ALL_OPS)
        return entity_command(command, rest_api, res_class_path, **opts, &block)
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
          "parameters for #{command}#{description.nil? ? '' : " (#{description})"}", mandatory: default.nil?,
          validation: bulk ? Array : type)
        value = default if value.nil?
        unless type.nil?
          type = [type] unless type.is_a?(Array)
          Aspera.assert(type.all?(Class)){"check types must be a Class, not #{type.map(&:class).join(',')}"}
          if bulk
            Aspera.assert_type(value, Array, exception_class: Cli::BadArgument)
            value.each do |v|
              Aspera.assert_values(v.class, type, exception_class: Cli::BadArgument)
            end
          else
            Aspera.assert_values(value.class, type, exception_class: Cli::BadArgument)
          end
        end
        return value
      end
    end
  end
end
