# frozen_string_literal: true

require 'aspera/cli/extended_value'

module Aspera
  module Cli
    # base class for plugins modules
    class Plugin
      # operations without id
      GLOBAL_OPS = %i[create list].freeze
      # operations with id
      INSTANCE_OPS = %i[modify delete show].freeze
      # all standard operations
      ALL_OPS = [GLOBAL_OPS, INSTANCE_OPS].flatten.freeze
      # special query parameter: max number of items for list command
      MAX_ITEMS = 'max'
      # special query parameter: max number of pages for list command
      MAX_PAGES = 'pmax'
      # special identifier format: look for this name to find where supported
      REGEX_LOOKUP_ID_BY_FIELD = /^%([^:]+):(.*)$/.freeze

      class << self
        def declare_generic_options(options)
          options.declare(:query, 'Additional filter for for some commands (list/delete)', types: Hash)
          options.declare(
            :value, 'Value for create, update, list filter', types: Hash,
            deprecation: '(4.14) Use positional value for create/modify or option: query for list/delete')
          options.declare(:property, 'Name of property to set (modify operation)')
          options.declare(:id, 'Resource identifier', deprecation: "(4.14) Use positional identifier after verb (#{INSTANCE_OPS.join(',')})")
          options.declare(:bulk, 'Bulk operation (only some)', values: :bool, default: :no)
          options.declare(:bfail, 'Bulk operation error handling', values: :bool, default: :yes)
        end
      end

      def initialize(env)
        raise 'env must be Hash' unless env.is_a?(Hash)
        @agents = env
        # check presence in descendant of mandatory method and constant
        raise StandardError, "Missing method 'execute_action' in #{self.class}" unless respond_to?(:execute_action)
        raise StandardError, 'ACTIONS shall be redefined by subclass' unless self.class.constants.include?(:ACTIONS)
        # manual header for all plugins
        options.parser.separator('')
        options.parser.separator("COMMAND: #{self.class.name.split('::').last.downcase}")
        options.parser.separator("SUBCOMMANDS: #{self.class.const_get(:ACTIONS).map(&:to_s).sort.join(' ')}")
        options.parser.separator('OPTIONS:')
      end

      # must be called AFTER the instance action, ... folder browse <call instance_identifier>
      # @param description [String] description of the identifier
      # @param as_option [Symbol] option name to use if identifier is an option
      # @param block [Proc] block to search for identifier based on attribute value
      # @return [String] identifier
      def instance_identifier(description: 'identifier', as_option: nil, &block)
        if as_option.nil?
          res_id = options.get_option(:id)
          res_id = options.get_next_argument(description) if res_id.nil?
        else
          res_id = options.get_option(as_option)
        end
        # cab be an Array
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
        is_bulk = options.get_option(:bulk)
        case values
        when :identifier
          values = instance_identifier
        when Class
          values = value_create_modify(command: command, type: values, bulk: is_bulk)
        end
        raise 'Internal error: missing block' unless block_given?
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
            result = res if param.is_a?(Hash)
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
          return {type: :object_list, data: result_list, fields: display_fields}
        else
          display_fields = fields unless fields.eql?(:default)
          return {type: :single_object, data: result_list.first, fields: display_fields}
        end
      end

      # @param command [Symbol] command to execute: create show list modify delete
      # @param rest_api [Rest] api to use
      # @param res_class_path [String] sub path in URL to resource relative to base url
      # @param display_fields [Array] fields to display by default
      # @param item_list_key [String] result is in a sub key of the json
      # @param id_as_arg [String] if set, the id is provided as url argument ?<id_as_arg>=<id>
      # @param is_singleton [Boolean] if true, res_class_path is the full path to the resource
      # @param block [Proc] block to search for identifier based on attribute value
      # @return result suitable for CLI result
      def entity_command(command, rest_api, res_class_path, display_fields: nil, item_list_key: false, id_as_arg: false, is_singleton: false, &block)
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
            rest_api.create(res_class_path, params)[:data]
          end
        when :delete
          raise 'cannot delete singleton' if is_singleton
          return do_bulk_operation(command: command, descr: 'identifier', values: one_res_id) do |one_id|
            rest_api.delete("#{res_class_path}/#{one_id}", old_query_read_delete)
            {'id' => one_id}
          end
        when :show
          return {type: :single_object, data: rest_api.read(one_res_path)[:data], fields: display_fields}
        when :list
          resp = rest_api.read(res_class_path, old_query_read_delete)
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
            return {type: :single_object, data: data, fields: display_fields}
          when Array
            return {type: :object_list, data: data, fields: display_fields} if data.empty? || data.first.is_a?(Hash)
            return {type: :value_list, data: data, name: 'id'}
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

      # query parameters in URL suitable for REST list/GET and delete/DELETE
      def query_read_delete(default: nil)
        query = options.get_option(:query)
        # dup default, as it could be frozen
        query = default.dup if query.nil?
        Log.log.debug{"Query=#{query}".bg_red}
        begin
          # check it is suitable
          URI.encode_www_form(query) unless query.nil?
        rescue StandardError => e
          raise Cli::BadArgument, "Query must be an extended value which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
        end
        return query
      end

      # TODO: when deprecation of `value` is completed: remove this method, replace with query_read_delete
      # deprecation: 4.14
      def old_query_read_delete
        query = options.get_option(:value) # legacy, deprecated, remove, one day...
        query = query_read_delete if query.nil?
        return query
      end

      # TODO: when deprecation of `value` is completed: remove this method, replace with options.get_option(:query)
      # deprecation: 4.14
      def query_option(mandatory: false, default: nil)
        option = :value
        value = options.get_option(option, mandatory: false)
        if value.nil?
          option = :query
          value = options.get_option(option, mandatory: mandatory, default: default)
        end
        return value
      end

      # Retrieves an extended value from command line, used for creation or modification of entities
      # @param command [Symbol] command name for error message
      # @param type [Class] expected type of value, either a Class, an Array of Class, or :bulk_hash
      # @param default [Object] default value if not provided
      # TODO: when deprecation of `value` is completed: remove line with :value
      def value_create_modify(command:, type: Hash, bulk: false, default: nil)
        value = options.get_option(:value)
        Log.log.warn("option `value` is deprecated. Use positional parameter for #{command}") unless value.nil?
        value = options.get_next_argument("parameters for #{command}", mandatory: default.nil?) if value.nil?
        value = default if value.nil?
        unless type.nil?
          type = [type] unless type.is_a?(Array)
          raise "Internal error, check types must be a Class, not #{type.map(&:class).join(',')}" unless type.all?(Class)
          if bulk
            raise Cli::BadArgument, "Value must be an Array of #{type.join(',')}" unless value.is_a?(Array)
            raise Cli::BadArgument, "Value must be a #{type.join(',')}, not #{value.map{|i| i.class.name}.uniq.join(',')}" unless value.all?{|v|type.include?(v.class)}
          else
            raise Cli::BadArgument, "Value must be a #{type.join(',')}, not #{value.class.name}" unless type.include?(value.class)
          end
        end
        return value
      end

      # shortcuts helpers for plugin environment
      %i[options transfer config formatter persistency].each do |name|
        define_method(name){@agents[name]}
      end
    end # Plugin
  end # Cli
end # Aspera
