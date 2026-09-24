# frozen_string_literal: true

require 'aspera/cli/extended_value'
require 'aspera/cli/parser'
require 'aspera/assert'
require 'aspera/cli/result'
require 'aspera/cli/command_registry'
require 'aspera/cli/option_declarator'
require 'aspera/schema/registry'

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
          def used_option_sources
            @used_option_sources ||= []
          end

          # Include options from another plugin or OptionDeclarator module.
          # @param source [Class, Module]
          def use_options(source)
            used_option_sources << source unless used_option_sources.include?(source)
          end

          def command_registry
            @command_registry ||= CommandRegistry.new
          end

          # DSL class method: register a command in this plugin's registry.
          # Inherits parent from the enclosing commands_under block when parent: is omitted.
          # @param id [Symbol]
          # @param kwargs [Hash] forwarded to [CommandSpec]
          def command(id, **kwargs)
            kwargs[:parent] = @current_parent if kwargs[:parent].nil? && @current_parent
            command_registry.register(CommandSpec.new(id: id, **kwargs))
          end

          # Derive a display name from an entity path:
          # last segment after '/', underscores replaced by spaces, first letter capitalized.
          # e.g. 'data/smtp_server' -> 'Smtp server', 'data/transfer_settings' -> 'Transfer settings'
          def entity_display_name(entity)
            entity.to_s.split('/').last.tr('_', ' ').capitalize
          end

          # Words displayed with specific case in descriptions
          NOUN_WORDS = {'smtp' => 'SMTP', 'ldap' => 'LDAP', 'saml' => 'SAML', 'oauth' => 'OAuth', 'kms' => 'KMS', 'api' => 'API'}.freeze
          private_constant :NOUN_WORDS

          # Derive a lowercase noun from an entity path, singular unless told otherwise.
          # e.g. 'access_keys' -> 'access key', 'data/smtp_server' -> 'SMTP server'
          # @param entity   [String, Symbol] REST path or entity name
          # @param singular [Boolean]        Singularize the last word
          # @return [String]
          def entity_noun(entity, singular: true)
            words = entity.to_s.split('/').last.split('_').map { |w| NOUN_WORDS.fetch(w, w) }
            words[-1] = words[-1].sub(/ies\z/, 'y').sub(/(ss|x|sh|ch)es\z/, '\1').sub(/(?<!s)s\z/, '') if singular
            words.join(' ')
          end

          # Standard description of a CRUD operation on an entity.
          # e.g. (:list, 'access key') -> 'List access keys', (:show, 'access key') -> 'Show access key'
          # @param verb [Symbol] Operation
          # @param noun [String] Singular noun of entity
          # @return [String]
          def operation_description(verb, noun)
            return "#{verb.capitalize} #{noun}" unless verb.eql?(:list)
            plural =
              case noun
              when /[^aeiou]y\z/ then noun.sub(/y\z/, 'ies')
              when /(s|x|sh|ch)\z/ then "#{noun}es"
              else "#{noun}s"
              end
            "List #{plural}"
          end

          # DSL class method: declare CRUD commands for a REST entity.
          #
          # For each verb in operations:, registers one CommandSpec with:
          #   - description: operation_description(verb, name)
          #   - arguments:   [{name: id_name, type: :identifier, lookup: lookup}] for instance verbs
          #                  (:show, :modify, :delete) when not a singleton; none for global verbs
          #                  body of :create and :modify is named after the entity (e.g. <access_key>), passed as data:
          #   - action:      calls entity_<verb>(api:, entity:, **shared_kwargs, **ctx)
          #
          # api: is resolved at runtime: :@ivar -> instance_variable_get, else -> send.
          # entity: may also be a Symbol — resolved at runtime as a ctx key (e.g. :sf_entity).
          #   This covers cases where the entity path is injected by a parent setup: method.
          #
          # @param api        [Symbol, String] Runtime API ref (:@ivar or method name) or literal string
          # @param entity     [String, Symbol] REST sub-path, or ctx key Symbol resolved at runtime
          # @param operations [Array<Symbol>]  Verbs to expose; defaults to Operations::ALL
          # @param name       [String, nil]    Singular display name; defaults to last segment of entity (static only)
          # @param lookup     [Symbol, nil]    Instance method for percent-selector resolution
          # @param id_name    [Symbol, nil]    Name of identifier argument; defaults to <name>_id, or id_as_arg field, or :id
          # @param kwargs     [Hash]           Shared params forwarded to every per-verb method
          def crud_commands(api:, entity:, operations: nil, name: nil, lookup: nil, id_name: nil, **kwargs)
            name       ||= entity_noun(entity, singular: !kwargs[:is_singleton]) unless entity.is_a?(Symbol)
            operations ||= Operations::ALL
            # Body argument is named after the entity, e.g. <access_key>, and passed as data: to entity_<verb>
            data_name = name ? name.downcase.tr(' ', '_').to_sym : :data
            # Identifier argument is named after the entity, e.g. <access_key_id>, and passed as id: to entity_<verb>
            id_name ||=
              if kwargs[:id_as_arg].is_a?(String) then kwargs[:id_as_arg].to_sym
              elsif name then :"#{data_name}_id"
              else :id
              end
            operations.each do |verb|
              id_arg = ({name: id_name, type: :identifier, lookup: lookup} if Operations::INSTANCE.include?(verb) && !kwargs[:is_singleton])
              schema_val =
                if kwargs[:body_component] && entity.is_a?(String)
                  case verb
                  when :create then Schema::Registry.req_body(kwargs[:body_component], "#{entity}.post")
                  when :modify then Schema::Registry.req_body(kwargs[:body_component], "#{entity}/{id}.put")
                  end
                end
              args =
                case verb
                when :create
                  [{name: data_name, type: Hash, bulk: true, schema: schema_val}]
                when :modify
                  [id_arg, {name: data_name, type: Hash, schema: schema_val}].compact
                when :delete
                  id_arg ? [id_arg.merge(bulk: true)] : nil
                else
                  id_arg ? [id_arg] : nil
                end
              action_proc = lambda do |**ctx|
                resolved_api =
                  if api.is_a?(Symbol)
                    api.to_s.start_with?('@') ? instance_variable_get(api) : send(api)
                  elsif api.is_a?(Proc)
                    instance_exec(&api)
                  else
                    api
                  end
                resolved_entity = entity.is_a?(Symbol) ? ctx.fetch(entity) : entity
                ctx = ctx.merge(data: ctx[data_name]) if ctx.key?(data_name)
                ctx = ctx.merge(id: ctx[id_name]) if ctx.key?(id_name)
                send(:"entity_#{verb}", api: resolved_api, entity: resolved_entity, **kwargs, **ctx)
              end
              cmd_attrs = {description: operation_description(verb, name || entity.inspect), action: action_proc}
              cmd_attrs[:arguments] = args if args
              cmd_attrs[:query_schema] = Schema::Registry.query_params(kwargs[:query_component], entity) if verb.eql?(:list) && kwargs[:query_component] && entity.is_a?(String)
              command(verb, **cmd_attrs)
            end
          end

          # DSL class method: define an instance method whose name is derived from a path array.
          # Equivalent to: define_method(CommandSpec.action_method(path), &block)
          # @param path [Array<Symbol>] command path segments, e.g. [:admin, :user, :list]
          # @yieldparam [Hash] keyword context forwarded from dispatch
          def define_action_method(path, &block)
            define_method(CommandSpec.action_method(path), &block)
          end

          # DSL class method: scope block that sets a default parent for nested command() calls.
          # Fully re-entrant: blocks may be nested for multi-level parent paths.
          # If the terminal node of `parent` has not been declared yet, it is auto-declared
          # as an intermediate command with description: "Manage <name>" (or the given description:).
          #
          # `parent` is always resolved relative to the current scope:
          #   Array(@current_parent) + Array(parent)
          #
          # @param parent      [Symbol, Array<Symbol>] one or more path segments, relative to current scope
          # @param description [String, nil]           Description of entity for the auto-declared node
          # @yieldreturn [void]
          def commands_under(parent, description: nil)
            # Always relative: append the given segments to the current scope.
            path = Array(@current_parent) + Array(parent)
            unless command_registry[path]
              id = path.last
              desc = description || "Manage #{entity_display_name(id)}"
              parent_path = path[0..-2]
              saved = @current_parent
              @current_parent = parent_path.empty? ? nil : parent_path
              command(id, description: desc)
              @current_parent = saved
            end
            previous = @current_parent
            @current_parent = path
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
          # @param name        [Symbol]          Option name
          # @param description [String, nil]     User-facing description; if nil, derived from schema: title/description
          # @param short       [String, nil]     Single-character short form (without leading '-')
          # @param allowed     [Object, nil]     Allowed values (see OptionValue)
          # @param default     [Object, nil]     Default value
          # @param handler     [Symbol, Hash, nil]
          #   - Symbol: resolved to {o: <plugin instance>, m: <symbol>} at runtime (Category B)
          #   - Hash:   {o: <object>, m: <method>} used as-is (Category A: singletons / constants)
          #   - nil:    option stores its value locally (no delegation)
          # @param deprecation [String, nil]     Deprecation message forwarded to options.declare
          # @param schema      [String, nil]     Schema reference (e.g. "opts:components.schemas.Foo");
          #                                      when description: is nil, the schema title or first description line is used
          def option(name, description: nil,
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

          # Declare all options registered on this plugin class onto a Parser instance.
          # Walks inherited options and any sources added via `use_options`.
          # @param options [Aspera::Cli::Parser]
          # @param parse [Boolean] whether to call parse_options! after declaring
          def declare_options(options, parse: false)
            sources = []
            ancestors.each do |klass|
              next unless klass.is_a?(Class) && klass <= Base
              sources << klass if klass.instance_variable_defined?(:@command_registry)
              sources.concat(klass.used_option_sources) if klass.respond_to?(:used_option_sources)
            end
            sources.uniq.each do |src|
              specs =
                if src.respond_to?(:command_registry)
                  src.command_registry.option_specs
                elsif src.respond_to?(:option_specs)
                  src.option_specs
                else
                  {}
                end
              specs.each_value do |spec|
                next if options.option_declared?(spec.name)
                resolved_handler =
                  case spec.handler
                  when Hash then spec.handler
                  end
                options.declare(
                  spec.name,
                  description: spec.description,
                  short:       spec.short,
                  allowed:     spec.allowed,
                  default:     spec.default,
                  handler:     resolved_handler,
                  deprecation: spec.deprecation,
                  schema:      spec.schema
                )
              end
            end
            options.parse_options! if parse
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

          # Build a filter lambda from a match expression (String glob, Regexp, Proc, or nil).
          # @param match_expression [String, Regexp, Proc, NilClass] as in FILTER_ARGS
          # @return [Proc] lambda(entry) -> Boolean
          def file_matcher(match_expression)
            case match_expression
            when Proc    then match_expression
            when Regexp  then ->(f) { f['name'].match?(match_expression) }
            when String  then ->(f) { File.fnmatch(match_expression, f['name'], File::FNM_DOTMATCH) }
            when NilClass then ->(_) { true }
            else Aspera.error_unexpected_value(match_expression.class.name, type: ParameterError)
            end
          end
        end

        # Shared positional argument for commands that accept an optional file name filter.
        # Accepted types: String (shell glob matched against entry name), Regexp, or Proc.
        # Used by node files find, and preview scan/events/trevents.
        FILTER_ARGS = [{name: :filter, type: [String, Regexp, Proc], description: 'File name filter: String (glob), Regexp, or Proc', mandatory: false, default: nil}].freeze

        option :query, description: 'Additional filter for for some commands (list/delete)', allowed: [Hash, Array, NilClass]
        option :bulk,  description: 'Bulk operation (only some)',                            allowed: Type::BOOLEAN, default: false
        option :bfail, description: 'Bulk operation error handling',                         allowed: Type::BOOLEAN, default: true

        def initialize(context:)
          Aspera.assert_type(context, Context) { 'context' }
          Aspera.assert_type(context.man_header, TrueClass, FalseClass) { 'context.man_header' }
          @context = context
          # Switch to the plugin-specific options group so that all options declared
          # below (DSL-registered and imperative) appear under the plugin section in
          # --help output, separate from the global options.
          options.group(self.class.name.split('::').last.downcase) if @context.man_header
          # Auto-declare all options registered via the DSL `option` class method.
          # Walk the ancestor chain so that options declared on parent plugin classes
          # (e.g. Oauth, BasicAuth) are also registered for sub-classes (e.g. Aoc).
          # The options object is shared across all plugins in a run; skip options already
          # declared by an earlier plugin (Base.option prevents duplicates within one hierarchy).
          # Each OptionSpec is translated to an options.declare call, resolving the
          # handler: shorthand:
          #   Symbol handler: {o: self, m: <symbol>}  (Category B - plugin instance methods)
          #   Hash handler:   used as-is              (Category A - singletons / class constants)
          sources = []
          self.class.ancestors.each do |klass|
            next unless klass.is_a?(Class) && klass <= Base
            sources << klass if klass.instance_variable_defined?(:@command_registry)
            sources.concat(klass.used_option_sources) if klass.respond_to?(:used_option_sources)
          end
          sources.uniq.each do |src|
            specs =
              if src.respond_to?(:command_registry)
                src.command_registry.option_specs
              elsif src.respond_to?(:option_specs)
                src.option_specs
              else
                {}
              end
            specs.each_value do |spec|
              next if options.option_declared?(spec.name)
              resolved_handler =
                case spec.handler
                when Symbol then {o: self, m: spec.handler}
                when Hash   then spec.handler
                end
              options.declare(
                spec.name,
                description: spec.description,
                short:       spec.short,
                allowed:     spec.allowed,
                default:     spec.default,
                handler:     resolved_handler,
                deprecation: spec.deprecation,
                schema:      spec.schema
              )
            end
          end
        end

        # Global objects
        attr_reader :context
        # Path reached in the command tree at the moment --help was intercepted.
        # Nil until set by dispatch_from_registry.
        attr_reader :help_path

        # @return [Aspera::Cli::Parser]
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
          # No-op: the group is set at the start of initialize.
          # Kept for compatibility with Config, which calls add_manual_header(false) from Runner.
        end

        # Entry point for all DSL-based plugins.
        def execute_action
          @help_path = nil
          validate_registry
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
          is_leaf  = spec && registry.children_of(current_path).empty?

          if @context.help_requested
            # help_requested on an intermediate node: drain positional args without validation
            # so that dispatch_child can still consume the correct sub-command token
            if !is_leaf && spec&.arguments
              spec.arguments.each do |arg_spec|
                next if ctx.key?(arg_spec.name)
                options.get_next_argument(arg_spec.name.to_s, mandatory: false)
              end
            end
          else
            # Phase A - for intermediate nodes only: resolve all ArgumentSpec declared on this node
            # before dispatching to children (leaf nodes resolve their arguments inside execute_leaf).
            if !is_leaf
              (spec&.arguments || []).each do |arg_spec|
                next if ctx.key?(arg_spec.name)
                if arg_spec.type.eql?(:identifier)
                  lookup_cb = arg_spec.lookup
                  res_id = if lookup_cb.nil?
                    options.instance_identifier(description: arg_spec.name.to_s)
                  elsif lookup_cb.is_a?(Symbol)
                    options.instance_identifier(description: arg_spec.name.to_s) { |f, v| send(lookup_cb, f, v, **ctx) }
                  else
                    options.instance_identifier(description: arg_spec.name.to_s) { |f, v| instance_exec(f, v, **ctx, &lookup_cb) }
                  end
                  ctx = ctx.merge(arg_spec.name => res_id)
                else
                  ctx = ctx.merge(arg_spec.name => resolve_argument(arg_spec))
                end
              end
            end
            ctx = ctx.merge(send(spec.setup, **ctx)) if spec&.setup
          end

          # Phase B - leaf fast-path or child dispatch
          if is_leaf
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
          if @context.help_requested
            @help_path = current_path
            raise Cli::HelpRequest, self
          end
          execute_leaf(spec, ctx)
        end

        # Phase B, child branch: consume the next command argument, then either continue
        # on a mounted plugin instance, or recurse into the child.
        # --help is intercepted at two points:
        #   1. Before get_next_command when no positional arg is pending: raises HelpRequest
        #      immediately so the subcommand list with descriptions is shown rather than a
        #      MissingArgument error.
        #   2. After get_next_command when no further args remain: raises HelpRequest scoped
        #      to the consumed command (e.g. `aoc files find -h`).
        # @param current_path [Array<Symbol>]
        # @param registry     [CommandRegistry]
        # @param ctx          [Hash]
        # @return [Object]
        def dispatch_child(current_path, registry, ctx)
          children  = registry.children_of(current_path)
          # condition: methods belong to the class declaring the spec: only evaluate local ones
          # (mounted children are only walked here for --help, see below)
          available = children.reject { |id, c| c.condition && registry.local?(current_path + [id]) && !send(c.condition) }
          aliases   = children.values.each_with_object({}) do |c, h|
            Array(c.aliases).each { |a| h[a] = c.id } if c.aliases
          end

          # Intercept --help before consuming the command token when no arg is pending.
          # This avoids MissingArgument being raised by get_next_command before HelpRequest.
          if @context.help_requested && options.command_or_arg_empty?
            @help_path = current_path
            raise Cli::HelpRequest, self
          end

          command = options.get_next_command(available.keys, aliases: aliases.empty? ? nil : aliases)

          # Intercept --help after a command was consumed but no further args remain.
          # (e.g. `aoc files find -h`). When further args remain, keep recursing.
          if @context.help_requested && options.command_or_arg_empty?
            @help_path = current_path + [command]
            raise Cli::HelpRequest, self
          end

          # Mounted child: continue on the target plugin instance, in its own namespace.
          # For --help, keep walking the (mount-aware) registry of this class instead, so that
          # no target instance (and thus no API connection) is needed.
          child_path = current_path + [command]
          return dispatch_mount(registry.mount_of(current_path), command, ctx) unless @context.help_requested || registry.local?(child_path)

          # Both intermediate and leaf: instance_arg + setup are handled by Phase A of the next call
          dispatch_from_registry(child_path, ctx)
        end

        # Hand over dispatch of a mounted child to the target plugin instance.
        # Setups of the mount point `at` and of its ancestors in the target are not executed:
        # the seed ctx returned by the host's `instance` method replaces them.
        # @param mount   [MountSpec]
        # @param command [Symbol] mounted child id, already consumed
        # @param ctx     [Hash]   host context, passed to the `instance` method
        # @return [Object]
        def dispatch_mount(mount, command, ctx)
          target = send(mount.instance, **ctx)
          target, seed = target if target.is_a?(Array)
          Aspera.assert_type(target, mount.plugin)
          target.validate_registry
          target.dispatch_from_registry(mount.at + [command], seed || {})
        end

        # Validate the registry once per class (memoised by the ivar check).
        # Passes the plugin class so implicit action methods can be verified.
        def validate_registry
          return if self.class.instance_variable_defined?(:@registry_validated)
          self.class.command_registry.validate!(plugin_class: self.class)
          self.class.instance_variable_set(:@registry_validated, true)
        end

        # Resolve the action for a leaf CommandSpec.
        # Returns spec.action (Symbol or Proc) if explicitly set; otherwise derives a Symbol
        # from the full path as :action_<path_segment_1>_<path_segment_2>_...
        # (e.g. [:access_key, :list] -> :action_access_key_list).
        # @param spec [CommandSpec]
        # @return [Symbol, Proc]
        def action_for(spec)
          spec.action || spec.action_method_name
        end

        # Invoke an action (Symbol method or Proc block) with the given positional
        # arguments and keyword context.
        # Procs are executed via instance_exec so they share the plugin's `self`.
        # @param action [Symbol, Proc]
        # @param args   [Array]  positional arguments
        # @param ctx    [Hash]   keyword context
        # @return [Object]
        def invoke_action(action, args, ctx)
          if action.is_a?(Proc)
            instance_exec(*args, **ctx, &action)
          else
            send(action, *args, **ctx)
          end
        end

        # Execute a leaf CommandSpec: resolve arguments and call action.
        # Arguments already present in `ctx` (e.g. provided by a caller or a mount seed) are skipped:
        # they are not read again from the command line.
        # instance_arg (if any) is resolved here as an ArgumentSpec(type: :identifier) and merged
        # into ctx, exactly like any other keyword argument received by the action.
        # @param spec [CommandSpec] a leaf node (no children)
        # @param ctx  [Hash]        accumulated context (pre-resolved keys are not re-consumed)
        # @return [Object]
        def execute_leaf(spec, ctx)
          a = action_for(spec)
          # Always resolve declared arguments (even when transfer_paths is set — those arguments
          # are consumed first; ts_source_paths then reads whatever remains in the queue).
          (spec.arguments || []).each do |arg_spec|
            next if ctx.key?(arg_spec.name)
            if arg_spec.type.eql?(:identifier)
              lookup_cb = arg_spec.lookup
              block =
                if lookup_cb.nil? then nil
                elsif lookup_cb.is_a?(Symbol) then ->(f, v) { send(lookup_cb, f, v, **ctx) }
                else ->(f, v) { instance_exec(f, v, **ctx, &lookup_cb) }
                end
              ctx = ctx.merge(arg_spec.name => resolve_argument(arg_spec, &block))
            else
              ctx = ctx.merge(arg_spec.name => resolve_argument(arg_spec))
            end
          end
          invoke_action(a, [], ctx)
        end

        # Resolve a single positional argument from the CLI argument stream.
        # When arg_spec.bulk is true, always returns an Array (normalized to [value] when non-bulk).
        # For type: :identifier, an optional block provides the percent-selector lookup.
        # @param arg_spec [ArgumentSpec]
        # @yieldparam field [String]  field name from a percent-selector (%field:value)
        # @yieldparam value [String]  value from a percent-selector
        # @yieldreturn [String]       resolved identifier
        # @return [Object] the resolved value, or Array when arg_spec.bulk is true
        def resolve_argument(arg_spec, &block)
          if arg_spec.bulk
            is_bulk = options.get_option(:bulk)
            if arg_spec.type.eql?(:identifier)
              val = options.instance_identifier(description: arg_spec.name.to_s, &block)
            else
              val = options.get_next_argument(
                arg_spec.name.to_s,
                mandatory: arg_spec.mandatory,
                validation: is_bulk ? Array : arg_spec.type,
                default:   arg_spec.default,
                schema:    arg_spec.schema
              )
              if is_bulk
                Aspera.assert_array_all(val, arg_spec.type, type: Cli::BadArgument) { 'type' } unless arg_spec.type.nil?
              end
            end
            # Always return an Array when bulk: true
            is_bulk ? val : [val]
          else
            case arg_spec.type
            when :identifier
              options.instance_identifier(description: arg_spec.name.to_s, &block)
            else
              # Class or Array<Class> -> pass as validation type
              # When interactive: true, set ask_missing_mandatory so that get_interactive is triggered
              # when no CLI arguments are provided (mandatory is forced to true for the same reason:
              # a non-nil default would short-circuit get_interactive before it is ever called).
              options.ask_missing_mandatory = true if arg_spec.interactive
              options.get_next_argument(
                arg_spec.name.to_s,
                mandatory:   arg_spec.interactive ? true : arg_spec.mandatory,
                multiple:    arg_spec.multiple || false,
                validation:  arg_spec.type,
                accept_list: arg_spec.allowed,
                default:     arg_spec.interactive ? nil : arg_spec.default,
                schema:      arg_spec.schema
              )
            end
          end
        end

        # Build a nested Hash tree of the registered command tree for help display.
        # Conditional commands are included with a '[condition_name]' annotation.
        # @param path [Array<Symbol>] starting path ([] for the full tree)
        # @return [Hash] { command_id => { description:, condition:, children: } }
        def generate_help(path = [])
          self.class.command_registry.children_of(path).to_h do |id, child_spec|
            annotation = child_spec.condition ? " [#{child_spec.condition}]" : ''
            # path + [id], not child_spec.full_path: a mounted spec's full_path is in the target namespace
            [id, {
              description: "#{child_spec.description}#{annotation}",
              condition:   child_spec.condition,
              children:    generate_help(path + [id])
            }]
          end
        end

        # Convenience wrapper: reads :bulk and :bfail from options, normalizes `items`
        # to an Array, then delegates to Result.bulk.
        # Use this in action methods instead of the three-line boilerplate:
        #   is_bulk = options.get_option(:bulk)
        #   items   = x.is_a?(Array) ? x : [x]
        #   Result.bulk(items, is_bulk: is_bulk, ...)
        # @param items     [Object, Array]  Single item or Array; wrapped in Array when needed
        # @param command   [Symbol]         Operation name (:create, :delete, ...)
        # @param id_result [String]         Key used as item identifier in the result row
        # @param fields    [Object]         Fields hint passed to Result constructor (non-bulk only)
        # @yieldparam item [Object]         Each item in `items`
        # @return [Result::ObjectList, Result::SingleObject]
        def bulk_result(items, command:, id_result: 'id', fields: :default, &block)
          items = items.is_a?(Array) ? items : [items]
          Result.bulk(
            items,
            is_bulk:   options.get_option(:bulk),
            command:   command,
            id_result: id_result,
            fields:    fields,
            bfail:     options.get_option(:bfail),
            &block
          )
        end

        # --- Per-verb entity action methods ---
        # Each method handles exactly one CRUD verb.
        # The resource id (when needed) is received as `id:` from ctx — it must be
        # resolved upstream via an ArgumentSpec(type: :identifier) on the command,
        # NOT read from the CLI queue inside the method.

        # List all instances of an entity.
        # @param api             [Aspera::Rest]  REST API object
        # @param entity          [String]        API sub-path
        # @param display_fields  [Array, nil]    Fields to display
        # @param items_key       [String, nil]   Sub-key in response containing the array
        # @param list_query      [Hash, nil]     Default query parameters
        # @param query_component [String, nil]   Registry key for --query=help schema
        def entity_list(api:, entity:, display_fields: nil, items_key: nil, list_query: nil, query_component: nil, **)
          qs_path = query_component ? Schema::Registry.query_params(query_component, entity) : nil
          data, http = api.read(entity, query_read_delete(default: list_query, schema: qs_path), ret: :both)
          return Result::Empty.new if http.code == '204'
          if !data.is_a?(Hash)
            # already the list
          elsif items_key
            data = data[items_key]
          elsif http['Content-Type'].start_with?('application/vnd.api+json')
            # JSON:API: list is under the entity name
            data = data[entity]
          end
          case data
          when Hash then Result::SingleObject.new(data, fields: display_fields)
          when Array
            return Result::ObjectList.new(data, fields: display_fields) if data.empty? || data.first.is_a?(Hash)
            Result::ValueList.new(data)
          else Aspera.error_unexpected_value(data.class.name) { 'list type' }
          end
        end

        # Show one instance of an entity.
        # @param api            [Aspera::Rest]    REST API object
        # @param entity         [String]          API sub-path
        # @param id             [String, nil]     Resource identifier; nil when is_singleton: true
        # @param display_fields [Array, nil]      Fields to display
        # @param is_singleton   [Boolean]         When true, entity is the full path (no id appended)
        # @param id_as_arg      [Boolean, String] When set, id is appended as ?<id_as_arg>=<id>
        def entity_show(api:, entity:, id: nil, display_fields: nil, is_singleton: false, id_as_arg: false, **)
          path = entity_res_path(entity, id, is_singleton: is_singleton, id_as_arg: id_as_arg)
          Result::SingleObject.new(api.read(path), fields: display_fields)
        end

        # Create one or more instances of an entity (supports bulk).
        # @param api            [Aspera::Rest]      REST API object
        # @param entity         [String]            API sub-path
        # @param data           [Hash, Array<Hash>] Entity data (Array with bulk), from the command's declared `data` argument
        # @param display_fields [Array, nil]        Fields to display
        def entity_create(api:, entity:, data:, display_fields: nil, **)
          data = [data] unless data.is_a?(Array)
          bulk_result(data, command: :create, fields: display_fields) do |params|
            api.create(entity, params)
          end
        end

        # Modify an existing instance of an entity.
        # @param api            [Aspera::Rest]    REST API object
        # @param entity         [String]          API sub-path
        # @param id             [String, nil]     Resource identifier; nil when is_singleton: true
        # @param is_singleton   [Boolean]         When true, entity is the full path (no id appended)
        # @param id_as_arg      [Boolean, String] When set, id is appended as ?<id_as_arg>=<id>
        # @param data           [Hash]            Modified fields, from the command's declared `data` argument
        def entity_modify(api:, entity:, data:, id: nil, is_singleton: false, id_as_arg: false, **)
          path = entity_res_path(entity, id, is_singleton: is_singleton, id_as_arg: id_as_arg)
          api.update(path, data)
          Result::Status.new('modified')
        end

        # Delete one or more instances of an entity (supports bulk).
        # @param api             [Aspera::Rest]    REST API object
        # @param entity          [String]          API sub-path
        # @param id              [String, Array, nil] Resource identifier(s)
        # @param id_as_arg       [Boolean, String] When set, id is appended as ?<id_as_arg>=<id>
        # @param delete_style    [String, nil]     When set, deletes by sending id array in payload
        # @param query_component [String, nil]     Registry key for --query=help schema
        def entity_delete(api:, entity:, id: nil, id_as_arg: false, delete_style: nil, query_component: nil, **)
          qs_path = query_component ? Schema::Registry.query_params(query_component, entity) : nil
          if !delete_style.nil?
            ids = id.is_a?(Array) ? id : [id]
            Aspera.assert_type(ids, Array, type: Cli::BadArgument)
            api.delete(entity, nil, content_type: Mime::JSON, body: {delete_style => ids})
            return Result::Status.new('deleted')
          end
          bulk_result(id, command: :delete) do |one_id|
            api.delete(
              id_as_arg ? "#{entity}?#{id_as_arg}=#{one_id}" : "#{entity}/#{one_id}",
              query_read_delete(schema: qs_path)
            )
            {'id' => one_id}
          end
        end

        # Build the resource path for an instance operation.
        # @param entity       [String]          API sub-path
        # @param id           [String, nil]     Resource identifier
        # @param is_singleton [Boolean]         When true, entity IS the full path
        # @param id_as_arg    [Boolean, String] When set, id appended as ?<id_as_arg>=<id>
        # @return [String]
        def entity_res_path(entity, id, is_singleton: false, id_as_arg: false)
          return entity if is_singleton
          return "#{entity}?#{id_as_arg}=#{id}" if id_as_arg
          "#{entity}/#{id}"
        end

        # Query parameters in URL suitable for REST: list/`GET` and delete/`DELETE`
        # @param default [Hash, nil] Default query parameters
        # @param schema [String, nil] Contextual schema path for --query help display
        # @return [Hash, nil] Query parameters
        def query_read_delete(default: nil, schema: nil)
          # Dup default, as it could be frozen
          query = options.get_option(:query, schema: schema) || default&.dup
          Log.dump(:query_read_delete, query)
          begin
            # Check it is suitable
            URI.encode_www_form(query) unless query.nil?
          rescue StandardError => e
            raise Cli::BadArgument, "Query must be an extended value (Hash, Array) which can be encoded with URI.encode_www_form. Refer to manual. (#{e.message})"
          end
          return query
        end
      end
    end
  end
end
