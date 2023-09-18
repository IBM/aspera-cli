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
      ALL_OPS = [GLOBAL_OPS, INSTANCE_OPS].flatten.freeze
      # max number of items for list command
      MAX_ITEMS = 'max'
      # max number of pages for list command
      MAX_PAGES = 'pmax'
      # used when all resources are selected
      VAL_ALL = 'ALL'
      # look for this name to find where supported
      REGEX_LOOKUP_ID_BY_FIELD = /^%([^:]+):(.*)$/.freeze

      # global for inherited classes
      @@options_created = false # rubocop:disable Style/ClassVars

      def initialize(env)
        raise 'must be Hash' unless env.is_a?(Hash)
        # env.each_key {|k| raise "wrong agent key #{k}" unless AGENTS.include?(k)}
        @agents = env
        # check presence in descendant of mandatory method and constant
        raise StandardError, "missing method 'execute_action' in #{self.class}" unless respond_to?(:execute_action)
        raise StandardError, 'ACTIONS shall be redefined by subclass' unless self.class.constants.include?(:ACTIONS)
        options.parser.separator('')
        options.parser.separator("COMMAND: #{self.class.name.split('::').last.downcase}")
        options.parser.separator("SUBCOMMANDS: #{self.class.const_get(:ACTIONS).map(&:to_s).sort.join(' ')}")
        options.parser.separator('OPTIONS:')
        return if @@options_created
        options.declare(:query, 'Additional filter for for some commands (list/delete)', types: Hash)
        options.declare(
          :value, 'Value for create, update, list filter', types: Hash,
          deprecation: 'Use positional value for create/modify or option: query for list/delete')
        options.declare(:property, 'Name of property to set')
        options.declare(:id, 'Resource identifier', deprecation: "Use identifier after verb (#{INSTANCE_OPS.join(',')})")
        options.declare(:bulk, 'Bulk operation (only some)', values: :bool, default: :no)
        options.declare(:bfail, 'Bulk operation error handling', values: :bool, default: :yes)
        options.parse_options!
        @@options_created = true # rubocop:disable Style/ClassVars
      end

      # must be called AFTER the instance action, ... folder browse <call instance_identifier>
      # @param block [Proc] block to search for identifier based on attribute value
      def instance_identifier(description: 'identifier', &block)
        res_id = options.get_option(:id)
        res_id = options.get_next_argument(description) if res_id.nil?
        if block && (m = res_id.match(REGEX_LOOKUP_ID_BY_FIELD))
          res_id = yield(m[1], ExtendedValue.instance.evaluate(m[2]))
        end
        return res_id
      end

      # For create and delete operations: execute one actin or multiple if bulk is yes
      # @param single_or_array [Object] single hash, or array of hash for bulk
      # @param success_msg deleted or created
      # @param id_result [String] key in result hash to use as identifier
      # @param fields [Array] fields to display
      def do_bulk_operation(single_or_array, success_msg, id_result: 'id', fields: :default)
        raise 'programming error: missing block' unless block_given?
        params = options.get_option(:bulk) ? single_or_array : [single_or_array]
        raise 'expecting Array for bulk operation' unless params.is_a?(Array)
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
            result = res if param.is_a?(Hash)
            result['status'] = success_msg
          rescue StandardError => e
            raise e if options.get_option(:bfail)
            result['status'] = e.to_s
          end
          result_list.push(result)
        end
        display_fields = [id_result, 'status']
        if options.get_option(:bulk)
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
      # @param id_default [String] default identifier to use for existing entity commands (show, modify)
      # @param item_list_key [String] result is in a sub key of the json
      # @param id_as_arg [String] if set, the id is provided as url argument ?<id_as_arg>=<id>
      # @param is_singleton [Boolean] if true, res_class_path is the full path to the resource
      # @return result suitable for CLI result
      def entity_command(command, rest_api, res_class_path, display_fields: nil, id_default: nil, item_list_key: false, id_as_arg: false, is_singleton: false, &block)
        if is_singleton
          one_res_path = res_class_path
        elsif INSTANCE_OPS.include?(command)
          begin
            one_res_id = instance_identifier(&block)
          rescue StandardError => e
            raise e if id_default.nil?
            one_res_id = id_default
          end
          one_res_path = "#{res_class_path}/#{one_res_id}"
          one_res_path = "#{res_class_path}?#{id_as_arg}=#{one_res_id}" if id_as_arg
        end

        case command
        when :create
          raise 'cannot create singleton' if is_singleton
          return do_bulk_operation(value_create_modify(command: command, type: :bulk_hash), 'created', fields: display_fields) do |params|
            raise 'expecting Hash' unless params.is_a?(Hash)
            rest_api.create(res_class_path, params)[:data]
          end
        when :delete
          raise 'cannot delete singleton' if is_singleton
          return do_bulk_operation(one_res_id, 'deleted') do |one_id|
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
          parameters = value_create_modify(command: command, type: Hash)
          property = options.get_option(:property)
          parameters = {property => parameters} unless property.nil?
          rest_api.update(one_res_path, parameters)
          return Main.result_status('modified')
        else
          raise "unknown action: #{command}"
        end
      end

      # implement generic rest operations on given resource path
      def entity_action(rest_api, res_class_path, **opts)
        # res_name=res_class_path.gsub(%r{^.*/},'').gsub(%r{s$},'').gsub('_',' ')
        command = options.get_next_command(ALL_OPS)
        return entity_command(command, rest_api, res_class_path, **opts)
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
          raise CliBadArgument, "Query must be an extended value which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
        end
        return query
      end

      # TODO: when deprecation of `value` is completed: remove this method, replace with query_read_delete
      def old_query_read_delete
        query = options.get_option(:value) # legacy, deprecated, remove, one day...
        query = query_read_delete if query.nil?
        return query
      end

      # TODO: when deprecation of `value` is completed: remove this method, replace with options.get_option(:query)
      def value_or_query(mandatory: false, allowed_types: nil)
        value = options.get_option(:value, mandatory: mandatory, allowed_types: allowed_types)
        value = options.get_option(:query, mandatory: mandatory, allowed_types: allowed_types) if value.nil?
        return value
      end

      # Retrieves an extended value from command line, used for creation or modification of entities
      # @param default [Object] default value if not provided
      # @param command [String] command name for error message
      # @param type [Class] expected type of value
      # TODO: when deprecation of `value` is completed: remove line with :value
      def value_create_modify(default: nil, command: 'command', type: nil)
        value = options.get_option(:value)
        value = options.get_next_argument("parameters for #{command}", mandatory: default.nil?) if value.nil?
        value = default if value.nil?
        if type.nil?
          # nothing to do
        elsif type.is_a?(Class)
          raise CliBadArgument, "Value must be a #{type}" unless value.is_a?(type)
        elsif type.is_a?(Array)
          raise CliBadArgument, "Value must be one of #{type.join(', ')}" unless type.any?{|t| value.is_a?(t)}
        elsif type.eql?(:bulk_hash)
          raise CliBadArgument, 'Value must be a Hash or Array of Hash' unless value.is_a?(Hash) || (value.is_a?(Array) && value.all?(Hash))
        else
          raise "Internal error: #{type}"
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
