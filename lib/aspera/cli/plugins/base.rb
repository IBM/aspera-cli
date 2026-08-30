# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/options'
require 'aspera/assert'
require 'aspera/cli/result'
require 'aspera/cli/command_registry'

module Aspera
  module Cli
    module Plugins
      # Base class for command plugins
      class Base
        module Operations
          # Operations without id: `create` `list`
          GLOBAL = %i[create list].freeze
          # Operations on singleton: `modify` `show`
          SINGLETON = %i[modify show].freeze
          # Operations with id: `modify` `show` `delete`
          INSTANCE = (SINGLETON + %i[delete]).freeze
          # All standard operations: `create` `list` `modify` `show` `delete`
          ALL = (GLOBAL + INSTANCE).freeze
        end
        class << self
          # Per-class DSL registry (not inherited: each subclass gets its own instance).
          # @return [CommandRegistry]
          def command_registry
            @command_registry ||= CommandRegistry.new
          end

          # DSL class method: register a command in this plugin's registry.
          # Inherits parent from the enclosing commands_under block when parent: is omitted.
          # @param id [Symbol]
          # @param kwargs [Hash] forwarded to CommandSpec
          def command(id, **kwargs)
            kwargs[:parent] = @current_parent if kwargs[:parent].nil? && @current_parent
            command_registry.register(CommandSpec.new(id: id, **kwargs))
          end

          # DSL class method: scope block that sets a default parent for nested command() calls.
          # Fully re-entrant: blocks may be nested for multi-level parent paths.
          # @param parent [Symbol, Array<Symbol>] parent path applied to every command() inside
          # @yieldreturn [void]
          def commands_under(parent)
            previous = @current_parent
            @current_parent = parent
            yield
          ensure
            @current_parent = previous
          end

          # DSL class method: declare an option in this plugin's registry.
          # Metadata is stored as an OptionSpec at class-load time; the actual
          # options.declare call happens in Base#initialize once the instance exists.
          #
          # Raises ArgumentError at class-load time if the same option name is already
          # declared by any ancestor class, preventing silent shadowing.
          #
          # handler: accepts two forms:
          #   Symbol      — resolved to {o: <plugin instance>, m: <symbol>} at runtime (Category B)
          #   Hash        — {o: <object>, m: <method>} used as-is (Category A: singletons / constants)
          #
          # @param name        [Symbol]
          # @param description [String, nil]
          # @param short       [String, nil]   single-char short form (without leading '-')
          # @param allowed     [Array, nil]
          # @param default     [Object, nil]
          # @param handler     [Symbol, Hash, nil]
          # @param deprecation [String, nil]
          # @param schema      [String, nil]
          def option(name, description = nil,
            short: nil, allowed: nil, default: nil,
            handler: nil, deprecation: nil, schema: nil)
            ancestor_owner = ancestors.drop(1).find do |klass|
              klass.is_a?(Class) && klass <= Base &&
                klass.instance_variable_defined?(:@command_registry) &&
                klass.command_registry.option_specs.key?(name)
            end
            raise ArgumentError, "#{self}: option :#{name} already declared in ancestor #{ancestor_owner}" if ancestor_owner
            command_registry.register_option(
              OptionSpec.new(
                name:        name,
                description: description,
                short:       short,
                allowed:     allowed,
                default:     default,
                handler:     handler,
                deprecation: deprecation,
                schema:      schema
              )
            )
          end

          # DSL class method: declare a setup method to run once before root dispatch.
          # The method is called before any command is consumed, and its return value
          # (a Hash) is merged into the initial ctx. This is useful when conditions
          # on root commands depend on state built during setup (e.g. @connection_type).
          # @param method_name [Symbol]
          def root_setup(method_name)
            @root_setup_method = method_name
          end

          # @return [Symbol, nil]
          attr_reader :root_setup_method

          # DSL class method: declare the human-readable application name shown in wizards.
          # When called with an argument, sets the name. When called with no argument, returns it.
          # Falls back to the last component of the class name if never set.
          # @param name [String, nil]
          # @return [String]
          def application_name(name = nil)
            @application_name = name unless name.nil?
            @application_name || self.name.split('::').last
          end
        end

        option :query, 'Additional filter for for some commands (list/delete)', allowed: [Hash, Array, NilClass]
        option :bulk,  'Bulk operation (only some)',                            allowed: Allowed::TYPES_BOOLEAN, default: false
        option :bfail, 'Bulk operation error handling',                         allowed: Allowed::TYPES_BOOLEAN, default: true

        def initialize(context:)
          Aspera.assert_type(context, Context){'context'}
          Aspera.assert_type(context.man_header, TrueClass, FalseClass){'context.man_header'}
          @context = context
          # Auto-declare all options registered via the DSL `option` class method.
          # Walk the ancestor chain so that options declared on parent plugin classes
          # (e.g. Oauth, BasicAuth) are also registered for sub-classes (e.g. Aoc).
          # The options object is shared across all plugins in a run; skip options already
          # declared by an earlier plugin (Base.option prevents duplicates within one hierarchy).
          # Each OptionSpec is translated to an options.declare call, resolving the
          # handler: shorthand:
          #   Symbol handler → {o: self, m: <symbol>}  (Category B — plugin instance methods)
          #   Hash handler   → used as-is              (Category A — singletons / class constants)
          self.class.ancestors.each do |klass|
            next unless klass.is_a?(Class) && klass <= Base && klass.instance_variable_defined?(:@command_registry)
            klass.command_registry.option_specs.each_value do |spec|
              next if options.option_declared?(spec.name)
              resolved_handler =
                case spec.handler
                when Symbol then {o: self, m: spec.handler}
                when Hash   then spec.handler
                end
              options.declare(
                spec.name,
                spec.description,
                short:       spec.short,
                allowed:     spec.allowed,
                default:     spec.default,
                handler:     resolved_handler,
                deprecation: spec.deprecation,
                schema:      spec.schema
              )
            end
          end
          add_manual_header if @context.man_header
        end

        # Global objects
        attr_reader :context
        # Path reached in the command tree at the moment --help was intercepted.
        # Nil until set by dispatch_from_registry.
        attr_reader :help_path

        # @return [Aspera::Cli::Options]
        def options; @context.options; end
        # @return [Aspera::Cli::TransferAgent]
        def transfer; @context.transfer; end
        # @return [Aspera::Cli::Plugins::Config]
        def config; @context.config; end
        # @return [Aspera::Cli::Formatter]
        def formatter; @context.formatter; end
        # @return [Aspera::PersistencyFolder]
        def persistency; @context.persistency; end
        # @return [Aspera::Cli::PresetManager]
        def presets; @context.presets; end
        # @return [Aspera::Cli::Http]
        def http_config; @context.http_config; end
        # @return [Aspera::Cli::TransferProgress, nil]
        def progress_bar; @context.progress_bar; end

        def add_manual_header(_has_options = true)
          options.rename_current_group(self.class.name.split('::').last.downcase)
        end

        # Entry point for all DSL-based plugins.
        def execute_action
          @help_path = nil
          # Validate the registry once per class (memoised by the ivar check).
          # Passes the plugin class so implicit handler methods can be verified.
          unless self.class.instance_variable_defined?(:@registry_validated)
            self.class.command_registry.validate!(plugin_class: self.class)
            self.class.instance_variable_set(:@registry_validated, true)
          end
          # Run the root setup (if declared) before consuming any argument.
          # This ensures condition methods on root commands can read instance variables
          # populated by the setup (e.g. @connection_type in server.rb).
          init_ctx = {}
          if (rsm = self.class.root_setup_method)
            init_ctx = send(rsm) || {}
          end
          dispatch_from_registry([], init_ctx)
        end

        # Two-phase dispatcher: run setup on the current node (Phase A), then either
        # execute a leaf directly or consume the next argument and recurse (Phase B).
        # @param current_path [Array<Symbol>] path of the node currently being dispatched
        # @param ctx [Hash] accumulated context passed down from parent nodes
        # @return [Object] result suitable for CLI output
        def dispatch_from_registry(current_path, ctx = {})
          registry = self.class.command_registry
          spec     = registry[current_path]

          # Phase A — run setup on current node (skip when --help to avoid auth/network calls)
          ctx = ctx.merge(send(spec.setup)) if spec&.setup && !options.help_requested

          # Phase B — leaf fast-path or child dispatch
          if spec && registry.children_of(current_path).empty?
            dispatch_leaf(current_path, spec, ctx)
          else
            dispatch_child(current_path, registry, ctx)
          end
        end

        # Phase B, leaf branch: execute a spec that is already a leaf (no children).
        # Intercepts --help before calling execute_leaf.
        # @param current_path [Array<Symbol>]
        # @param spec [CommandSpec]
        # @param ctx [Hash]
        # @return [Object]
        def dispatch_leaf(current_path, spec, ctx)
          if options.help_requested
            @help_path = current_path
            raise Cli::HelpRequest, self
          end
          execute_leaf(spec, ctx)
        end

        # Phase B, child branch: consume the next command argument, resolve the matching
        # child spec, handle delegation / entity_execute shorthands, and recurse or execute.
        # @param current_path [Array<Symbol>]
        # @param registry [CommandRegistry]
        # @param ctx [Hash]
        # @return [Object]
        def dispatch_child(current_path, registry, ctx)
          children  = registry.children_of(current_path)
          available = children.reject{ |_, c| c.condition && !send(c.condition)}
          aliases   = children.values.each_with_object({}) do |c, h|
            Array(c.aliases).each{ |a| h[a] = c.id} if c.aliases
          end
          command = options.get_next_command(available.keys, aliases: aliases.empty? ? nil : aliases)
          child   = available[command]

          # Intercept --help when no more positional args remain after consuming this command.
          # (e.g. `aoc files -h` or `aoc files find -h`). When args remain, keep recursing.
          if options.help_requested && options.command_or_arg_empty?
            @help_path = current_path + [command]
            raise Cli::HelpRequest, self
          end

          # Instance delegation: hand off to a different plugin object
          if child.delegate_instance
            target = send(child.delegate_instance)
            return target.dispatch_from_registry(Array(child.delegates_to), {})
          end
          return dispatch_from_registry(Array(child.delegates_to), ctx) if child.delegates_to

          # entity_execute shorthand
          return run_entity_execute(child, ctx) if child.entity_execute

          if registry.children_of(current_path + [command]).any?
            # Intermediate node: recurse (child setup runs at the top of the next call)
            dispatch_from_registry(current_path + [command], ctx)
          else
            # Leaf: run child setup (if any), then execute handler
            ctx = ctx.merge(send(child.setup)) if child.setup
            execute_leaf(child, ctx)
          end
        end

        # Resolve the handler for a leaf CommandSpec.
        # Returns spec.handler (Symbol or Proc) if explicitly set; otherwise derives a Symbol
        # from the full path as :handle_<path_segment_1>_<path_segment_2>_...
        # (e.g. [:access_key, :list] → :handle_access_key_list).
        # @param spec [CommandSpec]
        # @return [Symbol, Proc]
        def handler_for(spec)
          spec.handler || :"handle_#{spec.full_path.join('_')}"
        end

        # Invoke a handler (Symbol method or Proc block) with the given positional
        # arguments and keyword context.
        # Procs are executed via instance_exec so they share the plugin's `self`.
        # @param handler [Symbol, Proc]
        # @param args    [Array]  positional arguments
        # @param ctx     [Hash]   keyword context
        # @return [Object]
        def invoke_handler(handler, args, ctx)
          if handler.is_a?(Proc)
            instance_exec(*args, **ctx, &handler)
          else
            send(handler, *args, **ctx)
          end
        end

        # Execute a leaf CommandSpec: resolve arguments (or skip for transfer_paths) and call handler.
        # @param spec [CommandSpec] a leaf node (no children)
        # @param ctx  [Hash]        accumulated context
        # @return [Object]
        def execute_leaf(spec, ctx)
          h = handler_for(spec)
          if spec.transfer_paths
            invoke_handler(h, [], ctx)
          else
            args = (spec.arguments || []).map{ |a| resolve_argument(a)}
            invoke_handler(h, args, ctx)
          end
        end

        # Expand an entity_execute shorthand from a CommandSpec.
        # Calls Base#entity_execute with the parameters from spec.entity_execute merged
        # with the context hash (context entries are low-priority: spec params win).
        # @param spec [CommandSpec] the command spec carrying entity_execute: Hash
        # @param ctx [Hash] accumulated context (e.g. api:, lookup block)
        # @return [Object]
        def run_entity_execute(spec, ctx)
          ee_params = spec.entity_execute.dup
          # Merge context into params (spec wins on key collision)
          merged = ctx.merge(ee_params)
          # Extract lookup_block before passing to entity_execute (it is not a kwarg of entity_execute)
          block = merged.delete(:lookup_block)
          if block
            entity_execute(**merged, &block)
          else
            entity_execute(**merged)
          end
        end

        # Resolve a single positional argument from the CLI argument stream.
        # @param arg_spec [ArgumentSpec]
        # @return [Object] the resolved value
        def resolve_argument(arg_spec)
          case arg_spec.type
          when :identifier
            options.instance_identifier
          else
            # Class or Array<Class> → pass as validation type
            options.get_next_argument(
              arg_spec.name.to_s,
              mandatory: arg_spec.mandatory,
              multiple:  arg_spec.multiple || false,
              validation: arg_spec.type,
              default:   arg_spec.default,
              schema:    arg_spec.schema
            )
          end
        end

        # Build a nested Hash tree of the registered command tree for help display.
        # Conditional commands are included with a '[condition_name]' annotation.
        # @param path [Array<Symbol>] starting path ([] for the full tree)
        # @return [Hash] { command_id => { description:, condition:, children: } }
        def generate_help(path = [])
          self.class.command_registry.children_of(path).transform_values do |child_spec|
            annotation = child_spec.condition ? " [#{child_spec.condition}]" : ''
            {
              description: "#{child_spec.description}#{annotation}",
              condition:   child_spec.condition,
              children:    generate_help(child_spec.full_path)
            }
          end
        end

        # For create and delete operations: execute one action or multiple if bulk is yes
        # @param command [Symbol] Operation: :create, :delete, ...
        # @param descr [String, nil] Description of the value
        # @param values [Class, Array, Symbol] Type, or list of values, or :identifier, result is given to the block in loop
        # @param id_result [String] Key in result Hash to use as identifier
        # @param fields [Symbol, Array] Fields to display
        # @param schema [Hash, nil] JSON schema for validation
        # @yieldparam param [Object] The parameter value to process
        # @yieldreturn [Hash, nil] Result hash for the operation (optional)
        # @return [Hash] Result suitable for CLI output
        def do_bulk_operation(command:, descr: nil, values: Hash, id_result: 'id', fields: :default, schema: nil, &block)
          Aspera.assert(block_given?, 'missing block')
          is_bulk = options.get_option(:bulk)
          case values
          when :identifier
            values = options.instance_identifier(description: descr)
          when Class
            values = value_create_modify(command: command, description: descr, type: values, bulk: is_bulk, schema: schema)
          end
          # If not bulk, there is a single value
          params = is_bulk ? values : [values]
          Log.log.warn('Empty list given for bulk operation') if params.empty?
          Log.dump(:bulk_operation, params)
          result_list = []
          params.each do |param|
            # Init for delete
            result = {id_result => param}
            begin
              # Execute custom code
              res = yield(param)
              # If block returns a hash, let's use this (create)
              result = res if res.is_a?(Hash)
              # TODO: remove when faspio gw api fixes this
              result = res.first if res.is_a?(Array) && res.first.is_a?(Hash)
              # Create -> created
              result['status'] = "#{command}#{'e' unless command.to_s.end_with?('e')}d".gsub(/yed$/, 'ied')
            rescue StandardError => e
              raise e if options.get_option(:bfail)
              result['status'] = e.to_s
            end
            result_list.push(result)
          end
          display_fields = [id_result, 'status']
          if is_bulk
            return Result::ObjectList.new(result_list, fields: display_fields)
          else
            display_fields = fields unless fields.eql?(:default)
            return Result::SingleObject.new(result_list.first, fields: display_fields)
          end
        end

        # Operations: Create, Delete, Show, List, Modify
        # @param api [Aspera::Rest] API to use
        # @param entity [String] Sub path in URL to resource relative to base url
        # @param command [Symbol, nil] Command to execute: :create, :show, :list, :modify, :delete
        # @param display_fields [Array, nil] Fields to display by default
        # @param items_key [String, nil] Result is in a sub key of the JSON
        # @param delete_style [String, nil] If set, the delete operation by array in payload
        # @param id_as_arg [Boolean, String] If set, the id is provided as url argument ?<id_as_arg>=<id>
        # @param is_singleton [Boolean] If `true`, entity is the full path to the resource
        # @param list_query [Hash, nil] Query parameters for list operation
        # @yieldparam value [String] Value to search for identifier
        # @yieldreturn [String] The identifier
        # @return [Hash] Result suitable for CLI result
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
          schema: nil,
          &block
        )
          command = options.get_next_command(Operations::ALL) if command.nil?
          if is_singleton
            one_res_path = entity
          elsif Operations::INSTANCE.include?(command)
            one_res_id = options.instance_identifier(&block)
            one_res_path = "#{entity}/#{one_res_id}"
            one_res_path = "#{entity}?#{id_as_arg}=#{one_res_id}" if id_as_arg
          end

          case command
          when :create
            raise BadArgument, 'cannot create singleton' if is_singleton
            return do_bulk_operation(command: command, descr: 'data', fields: display_fields, schema: schema) do |params|
              api.create(entity, params)
            end
          when :delete
            raise BadArgument, 'cannot delete singleton' if is_singleton
            if !delete_style.nil?
              one_res_id = [one_res_id] unless one_res_id.is_a?(Array)
              Aspera.assert_type(one_res_id, Array, type: Cli::BadArgument)
              api.delete(
                entity,
                nil,
                content_type: Mime::JSON,
                body:         {delete_style => one_res_id}
              )
              return Result::Status.new('deleted')
            end
            return do_bulk_operation(command: command, values: one_res_id) do |one_id|
              api.delete("#{entity}/#{one_id}", query_read_delete)
              {'id' => one_id}
            end
          when :show
            return Result::SingleObject.new(api.read(one_res_path), fields: display_fields)
          when :list
            data, http = api.read(entity, query_read_delete, ret: :both)
            return Result::Empty.new if http.code == '204'
            # TODO: not generic : which application is this for ?
            if http['Content-Type'].start_with?('application/vnd.api+json')
              Log.log.debug('is vnd.api')
              data = data[entity]
            end
            data = data[items_key] if items_key
            case data
            when Hash
              return Result::SingleObject.new(data, fields: display_fields)
            when Array
              return Result::ObjectList.new(data, fields: display_fields) if data.empty? || data.first.is_a?(Hash)
              return Result::ValueList.new(data)
            else
              Aspera.error_unexpected_value(data.class.name){'list type'}
            end
          when :modify
            parameters = value_create_modify(command: command, schema: schema)
            api.update(one_res_path, parameters)
            return Result::Status.new('modified')
          else
            Aspera.error_unexpected_value(command){'command'}
          end
        end

        # Query parameters in URL suitable for REST: list/`GET` and delete/`DELETE`
        # @param default [Hash, nil] Default query parameters
        # @return [Hash, nil] Query parameters
        def query_read_delete(default: nil)
          # Dup default, as it could be frozen
          query = options.get_option(:query) || default.dup
          Log.log.debug{"query_read_delete=#{query}".bg_red}
          begin
            # Check it is suitable
            URI.encode_www_form(query) unless query.nil?
          rescue StandardError => e
            raise Cli::BadArgument, "Query must be an extended value (Hash, Array) which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
          end
          return query
        end

        # Retrieves an extended value from command line.
        # Used for creation or modification of entities.
        # @param command [Symbol] Command name for error message
        # @param description [String, nil] Description of the value
        # @param type [Class, nil] Expected type of value
        # @param bulk [Boolean] If `true`, value must be an Array of `type`
        # @param default [Object, nil] Default value if not provided
        # @param schema [Hash, nil] JSON schema for validation
        # @return [Hash, Array<Hash>] The value(s) to create object(s)
        def value_create_modify(command:, description: nil, type: Hash, bulk: false, default: nil, schema: nil)
          value = options.get_next_argument(
            "parameters for #{command}#{" (#{description})" unless description.nil?}",
            mandatory: default.nil?,
            validation: bulk ? Array : type,
            schema: schema
          )
          value = default if value.nil?
          unless type.nil?
            Aspera.assert_type(type, Class){'type'}
            if bulk
              Aspera.assert_array_all(value, type, type: Cli::BadArgument){'type'}
            else
              Aspera.assert_type(value, type, type: Cli::BadArgument){'type'}
            end
          end
          return value
        end
      end
    end
  end
end
