# frozen_string_literal: true

module Aspera
  module Cli
    # base class for plugins modules
    class Plugin
      # operations without id
      GLOBAL_OPS = %i[create list].freeze
      # operations with id
      INSTANCE_OPS = %i[modify delete show].freeze
      ALL_OPS = [].concat(GLOBAL_OPS, INSTANCE_OPS).freeze
      # max number of items for list command
      MAX_ITEMS = 'max'
      # max number of pages for list command
      MAX_PAGES = 'pmax'
      # used when all resources are selected
      VAL_ALL = 'ALL'

      # AGENTS=%i[options transfer config formater persistency].freeze

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
        options.add_opt_simple(:query, 'additional filter for API calls (extended value) (some commands)')
        options.add_opt_simple(:value, 'extended value for create, update, list filter')
        options.add_opt_simple(:property, 'name of property to set')
        options.add_opt_simple(:id, "resource identifier (#{INSTANCE_OPS.join(',')})")
        options.add_opt_boolean(:bulk, 'Bulk operation (only some)')
        options.add_opt_boolean(:bfail, 'Bulk operation error handling')
        options.set_option(:bulk, :no)
        options.set_option(:bfail, :yes)
        options.parse_options!
        @@options_created = true # rubocop:disable Style/ClassVars
      end

      # must be called AFTER the instance action
      def instance_identifier
        res_id = options.get_option(:id)
        res_id = options.get_next_argument('identifier') if res_id.nil?
        return res_id
      end

      # TODO
      # def get_next_id_command(instance_ops: INSTANCE_OPS,global_ops: GLOBAL_OPS)
      #  return get_next_argument('command',expected: command_list)
      # end

      # For create and delete operations: execute one actin or multiple if bulk is yes
      # @param params either single id or hash, or array for bulk
      # @param success_msg deleted or created
      def do_bulk_operation(single_or_array, success_msg, id_result: 'id', fields: :default)
        raise 'programming error: missing block' unless block_given?
        params = options.get_option(:bulk) ? single_or_array : [single_or_array]
        raise 'expecting Array for bulk operation' unless params.is_a?(Array)
        Log.log.warn('Empty list given for bulk operation') if params.empty?
        Log.dump(:bulk_create, params)
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
      # @param item_list_key [String] result is in a subkey of the json
      # @return result suitable for CLI result
      def entity_command(command, rest_api, res_class_path, display_fields: nil, id_default: nil, item_list_key: false)
        if INSTANCE_OPS.include?(command)
          begin
            one_res_id = instance_identifier
          rescue StandardError => e
            raise e if id_default.nil?
            one_res_id = id_default
          end
          one_res_path = "#{res_class_path}/#{one_res_id}"
        end
        # parameters mandatory for create/modify
        if %i[create modify].include?(command)
          parameters = options.get_option(:value, is_type: :mandatory)
        end
        # parameters optional for list
        if [:list].include?(command)
          parameters = options.get_option(:value)
        end
        case command
        when :create
          return do_bulk_operation(parameters, 'created', fields: display_fields) do |params|
            raise 'expecting Hash' unless params.is_a?(Hash)
            rest_api.create(res_class_path, params)[:data]
          end
        when :delete
          return do_bulk_operation(one_res_id, 'deleted') do |one_id|
            rest_api.delete("#{res_class_path}/#{one_id}")
            {'id' => one_id}
          end
        when :show
          return {type: :single_object, data: rest_api.read(one_res_path)[:data], fields: display_fields}
        when :list
          resp = rest_api.read(res_class_path, parameters)
          data = resp[:data]
          # TODO: not generic : which application is this for ?
          if resp[:http]['Content-Type'].start_with?('application/vnd.api+json')
            data = data[res_class_path]
          end
          if item_list_key
            item_list = data[item_list_key]
            total_count = data['total_count']
            if !total_count.nil?
              count_msg = "Items: #{item_list.length}/#{total_count}"
              count_msg = count_msg.bg_red unless item_list.length.eql?(total_count.to_i)
              self.format.display_status(count_msg)
            end
            data = item_list
          end
          return {type: :object_list, data: data, fields: display_fields} if data.empty? || data.first.is_a?(Hash)
          return {type: :value_list, data: data, name: 'id'}
        when :modify
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

      # query for list operation
      def option_url_query(default)
        query = options.get_option(:query)
        query = default if query.nil?
        Log.log.debug{"Query=#{query}".bg_red}
        begin
          # check it is suitable
          URI.encode_www_form(query) unless query.nil?
        rescue StandardError => e
          raise CliBadArgument, "query must be an extended value which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
        end
        return query
      end

      # shortcuts helpers for plugin environment
      def options; return @agents[:options]; end

      def transfer; return @agents[:transfer]; end

      def config; return @agents[:config]; end

      def format; return @agents[:formater]; end

      def persistency; return @agents[:persistency]; end
    end # Plugin
  end # Cli
end # Aspera
