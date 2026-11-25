# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../extended_value'
require_relative '../parser'
require_relative '../../assert'
require_relative '../result'
require_relative '../poll'
require_relative '../command/registry'
require_relative '../option/declarator'
require_relative '../security'
require_relative '../special_values'
require_relative '../../bundle_registry'
require_relative '../../log'
require_relative '../../rest/list'
require_relative '../../schema/registry'
require_relative '../../string_ext'

module Aspera
  module Cli
    module Plugins
      # Base class for command plugins
      class Base
        # Value of a path argument that means the standard input, not a local file, when the argument declares `stdin: true` (see `check_argument_access`)
        STDIN_ARGUMENT = '-'

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
          include Option::Declarator

          # Option sources added with `use_options`, with their `on_set` target.
          # @return [Hash{Class, Module => Proc, nil}]
          def used_option_sources
            @used_option_sources ||= {}
          end

          # Include options from another plugin or Option::Declarator module.
          # @param source [Class, Module]
          # @param target [Proc, nil] Executed on the plugin instance, returns the object for Symbol and Proc `on_set` callbacks
          #                           of `source` (e.g. `-> { http_config }`); nil: the plugin instance
          def use_options(source, target: nil)
            used_option_sources[source] = target unless used_option_sources.key?(source)
          end

          # Per-class DSL registry (not inherited: each subclass gets its own instance).
          # @return [Command::Registry]
          def command_registry
            @command_registry ||= Command::Registry.new
          end

          # DSL class method: register a command in this plugin's registry.
          # Inherits parent from the enclosing commands_under block when parent: is omitted.
          # @param id     [Symbol]
          # @param before [Symbol, nil] Command of the same parent before which this one is placed (e.g. by a mounted module), `nil`: after the others
          # @param kwargs [Hash] forwarded to [Command]
          def command(id, before: nil, **kwargs)
            kwargs[:parent] = @current_parent if kwargs[:parent].nil? && @current_parent
            kwargs[:security] = mounted_level(kwargs[:security])
            command_registry.register(Command.new(id: id, **kwargs), before: before)
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
              when /[^aeiou]y\z/ then noun.sub(/y\z/, 'ies') # cspell:disable-line
              when /(s|x|sh|ch)\z/ then "#{noun}es"
              else "#{noun}s"
              end
            "List #{plural}"
          end

          # DSL class method: declare CRUD commands for a REST entity.
          #
          # For each verb in operations:, registers one Command with:
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
          # @param lookup     [Symbol, Proc, Array<String>, nil] Percent-selector resolution: instance method, lambda,
          #                   or fields with unique values, looked up in the list of entities (plain Array of Hash)
          # @param id_name    [Symbol, nil]    Name of identifier argument; defaults to <name>_id, or id_as_arg field, or :id
          # @param schema_entity [String, nil] REST sub-path in the API schema (body_component), when entity is a ctx key Symbol
          # @param kwargs     [Hash]           Shared params forwarded to every per-verb method
          def crud_commands(api:, entity:, operations: nil, name: nil, lookup: nil, id_name: nil, schema_entity: nil, **kwargs)
            name       ||= entity_noun(entity, singular: !kwargs[:is_singleton]) unless entity.is_a?(Symbol)
            operations ||= Operations::ALL
            schema_entity ||= entity if entity.is_a?(String)
            if lookup.is_a?(Array)
              unique_fields = lookup
              # `%id:<id>` is the id itself (no lookup), other fields are looked up in the list of entities
              lookup = lambda do |field, value, **ctx|
                return value if field.eql?('id')
                resolved_entity = entity.is_a?(Symbol) ? ctx.fetch(entity) : entity
                label = name || resolved_entity
                Aspera.assert_values(field, unique_fields, type: Cli::BadArgument) { "#{label} search field" }
                Rest::List.lookup_entity_generic(field: field, value: value, entity: label) { crud_api(api).read(resolved_entity) }['id']
              end
            end
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
                if kwargs[:body_component] && schema_entity
                  case verb
                  when :create then Schema::Registry.req_body(kwargs[:body_component], "#{schema_entity}.post")
                  when :modify then Schema::Registry.req_body(kwargs[:body_component], "#{schema_entity}/{id}.put")
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
                resolved_entity = entity.is_a?(Symbol) ? ctx.fetch(entity) : entity
                ctx = ctx.merge(data: ctx[data_name]) if ctx.key?(data_name)
                ctx = ctx.merge(id: ctx[id_name]) if ctx.key?(id_name)
                send(:"entity_#{verb}", api: crud_api(api), entity: resolved_entity, **kwargs, **ctx)
              end
              cmd_attrs = {description: operation_description(verb, name || entity.inspect), action: action_proc}
              cmd_attrs[:arguments] = args if args
              cmd_attrs[:query_schema] = Schema::Registry.query_params(kwargs[:query_component], entity) if verb.eql?(:list) && kwargs[:query_component] && entity.is_a?(String)
              command(verb, **cmd_attrs)
            end
          end

          # DSL class method: define an instance method whose name is derived from a path array.
          # Equivalent to: define_method(Command.action_method(path), &block)
          # @param path [Array<Symbol>] command path segments, e.g. [:admin, :user, :list]
          # @yieldparam [Hash] keyword context forwarded from dispatch
          def define_action_method(path, &block)
            define_method(Command.action_method(path), &block)
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
              desc = description || "Manage #{entity_noun(id, singular: false)}"
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

          # Options of this plugin class (`option` DSL, see Option::Declarator).
          # Metadata is stored as an Option at class-load time; the actual
          # options.declare call happens in Base#initialize once the instance exists.
          # @return [Hash{Symbol => Option}]
          def option_specs
            command_registry.option_specs
          end

          # Store an Option in the command registry.
          # Raises ArgumentError at class-load time if the same option name is already
          # declared by any ancestor class, preventing silent shadowing.
          # @param spec   [Option]
          # @param before [Symbol, nil] Name of an option of this class to place it before (see `Command::Registry#register_option`)
          def register_option_spec(spec, before: nil)
            ancestor_owner = ancestors.drop(1).find do |klass|
              klass.is_a?(Class) && klass <= Base &&
                klass.instance_variable_defined?(:@command_registry) &&
                klass.command_registry.option_registered?(spec.name)
            end
            raise ArgumentError, "#{self}: option :#{spec.name} already declared in ancestor #{ancestor_owner}" if ancestor_owner
            spec.security = mounted_level(spec.security)
            command_registry.register_option(spec, before: before)
          end

          # Classes and modules whose options apply to this plugin:
          # this class, its plugin ancestors and sources added via `use_options`.
          # @return [Hash{Class, Module => Proc, nil}] key responds to `option_specs`, value: `on_set` target (see `use_options`)
          def option_sources
            sources = {}
            ancestors.each do |klass|
              next unless klass.is_a?(Class) && klass <= Base
              sources[klass] = nil if klass.instance_variable_defined?(:@command_registry) && !sources.key?(klass)
              klass.used_option_sources.each { |src, src_target| sources[src] = src_target unless sources.key?(src) }
            end
            sources
          end

          # Declare all options of `option_sources` onto a Parser instance.
          # Skips options already declared on the parser: it is shared across all plugins in a run.
          # @param options [Aspera::Cli::Parser]
          # @param target  [Base, nil] plugin instance for Symbol and Proc `on_set` callbacks; nil: such callbacks are not bound
          # @param parse   [Boolean] whether to call parse_options! after declaring
          def declare_options(options, target: nil, parse: false)
            option_sources.each do |src, src_target|
              src_target = src_target.nil? ? target : target&.instance_exec(&src_target)
              src.option_specs.each_value do |spec|
                spec.declare_on(options, target: src_target) unless options.option_declared?(spec.name)
              end
            end
            options.parse_options! if parse
          end

          # Name of the plugin: its top level command, set by `Factory` when it loads the class: name of the file (single file) or of the bundle.
          # Default (class not loaded by `Factory`, e.g. `Config`): from the class name `Aspera::Cli::Plugins::<Name>` or `Aspera::Plugins::<Name>::Commands`.
          # @return [String]
          def plugin_name
            @plugin_name || (name[/\AAspera::Plugins::(\w+)::Commands\z/, 1] || name.split('::').last).capital_to_snake
          end

          # @!attribute [w] plugin_name
          #   @param value [String] Name of the plugin, set by `Factory`
          attr_writer :plugin_name

          # Include the modules that bundles mount on this plugin (manifest `mounts`), each once, by name of bundle, then in the order of the manifest.
          # The `included` hook of a module declares its commands and options in this class, as an `include` of the module at this place of the class body would.
          # Called by `Factory` when it loads the class: mounted commands come after the ones of the class body; a class body may call it to place them.
          # The module of a bundle whose source is refused at the current security level is not loaded; the commands and options declared by a module
          # get the security level of its source, if more restrictive.
          # @param registry [BundleRegistry] Registry of the bundles
          # @return [nil]
          def include_mounts(registry = BundleRegistry.instance)
            @included_mounts ||= []
            registry.mounts(plugin_name.to_sym).each do |mount|
              next if @included_mounts.include?(mount) || !registry.allowed?(mount.bundle)
              @included_mounts.push(mount)
              mounted = registry.load_entry(mount)
              Aspera.assert(mounted.instance_of?(Module)) { "plugin #{mount.bundle}: #{mount.constant} is not a module" }
              @mount_security = registry[mount.bundle].security
              include(mounted)
            rescue BundleRegistry::Unavailable, AssertError, NameError, ScriptError, ArgumentError => e
              # A broken module (wrong constant, syntax error, failing hook) is skipped as an unavailable bundle: the target plugin still works
              Log.log.warn { "Commands of plugin #{mount.bundle} are not added to #{plugin_name}: #{e.message}" }
            ensure
              @mount_security = nil
            end
            nil
          end

          # DSL class method: declare the human-readable application name shown in wizards.
          # When called with an argument, sets the name. When called with no argument, returns it.
          # Falls back to the plugin name in CamelCase if never set.
          # @param name [String, nil]
          # @return [String]
          def application_name(name = nil)
            @application_name = name unless name.nil?
            @application_name || plugin_name.snake_to_capital
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

          private

          # @param level [Symbol, nil] Security level of a command or option declared in this class
          # @return [Symbol, nil] The most restrictive of this level and the one of the source of the module being mounted (see `include_mounts`)
          def mounted_level(level)
            return level if @mount_security.nil?
            return @mount_security if level.nil?
            [level, @mount_security].min_by { |item| Security::LEVELS.index(item) }
          end
        end

        # Shared positional argument for commands that accept an optional file name filter.
        # Accepted types: String (shell glob matched against entry name), Regexp, or Proc.
        # Used by node files find, and preview scan/events/trevents.
        FILTER_ARGS = [{name: :filter, type: [String, Regexp, Proc], description: 'File name filter: String (glob), Regexp, or Proc', mandatory: false, default: nil}].freeze

        option :query, description: 'Additional filter for for some commands (list/delete)', allowed: [Hash, Array, NilClass]
        option :bulk,  description: 'Bulk operation (only some)',                            allowed: Option::Type::BOOLEAN, default: false
        option :bfail, description: 'Bulk operation error handling',                         allowed: Option::Type::BOOLEAN, default: true
        option :poll,  description: 'Repeat a read-only command (dot-notation: interval, max, timeout, until, show, errors)', schema: Schema::Registry::POLL_OPTIONS

        def initialize(context:)
          Aspera.assert_type(context, Context) { 'context' }
          Aspera.assert_type(context.man_header, TrueClass, FalseClass) { 'context.man_header' }
          @context = context
          # Switch to the plugin-specific options group so that all options declared
          # below (DSL-registered and imperative) appear under the plugin section in
          # --help output, separate from the global options.
          options.group(self.class.plugin_name) if @context.man_header
          # Auto-declare all options registered via the DSL `option` class method,
          # including those of modules that give theirs when included (e.g. Oauth, BasicAuth) and `use_options` sources.
          self.class.declare_options(options, target: self)
        end

        # Global objects
        attr_reader :context
        # Path reached in the command tree at the moment --help was intercepted.
        # Nil until set by dispatch_from_registry.
        attr_reader :help_path

        # @return [Aspera::Cli::Parser]
        def options; @context.options; end
        # Plugins of bundles use `Aspera::Plugins::Xfer::Helper#transfer` (bundle `xfer`)
        # @return [Object] Service `transfer` of the context (`Aspera::Plugins::Xfer::TransferAgent`)
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

        # Entry point for all DSL-based plugins.
        def execute_action
          @help_path = nil
          validate_registry
          dispatch_from_registry([])
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
            if !is_leaf
              registry.arguments_at(current_path).each do |arg_spec|
                next if ctx.key?(arg_spec.name)
                options.get_next_argument(arg_spec.name.to_s, mandatory: false)
              end
            end
          else
            Security.instance.check_level(spec.security, "command #{current_path.join(' ')}") if spec
            # Before anything is executed (setup, arguments, action)
            poll = poll_result(current_path, spec) if is_leaf
            # Phase A - for intermediate nodes only: resolve all Argument declared on this node
            # before dispatching to children (leaf nodes resolve their arguments inside execute_leaf).
            ctx = resolve_arguments(spec.arguments, ctx) if !is_leaf && spec&.arguments
            ctx = ctx.merge(send(spec.setup, **ctx)) if spec&.setup
          end

          # Phase B - leaf fast-path or child dispatch
          if is_leaf
            dispatch_leaf(current_path, spec, ctx, poll: poll)
          else
            dispatch_child(current_path, registry, ctx)
          end
        end

        # Phase B, leaf branch: execute a spec that is already a leaf (no children).
        # Intercepts --help before calling execute_leaf.
        # @param current_path [Array<Symbol>]
        # @param spec [Command]
        # @param ctx [Hash]
        # @param poll [Result::Poll, nil] With option `poll`: result that executes the action when displayed
        # @return [Object]
        def dispatch_leaf(current_path, spec, ctx, poll: nil)
          if @context.help_requested
            @help_path = current_path
            raise Cli::HelpRequest, self
          end
          execute_leaf(spec, ctx, poll: poll)
        end

        # With option `poll`, check that the command is read-only, and the parameters of `poll`
        # @param current_path [Array<Symbol>] path of the leaf command
        # @param spec         [Command]   leaf command
        # @return [Result::Poll, nil] `nil` if option `poll` is not set
        # @raise [Cli::BadArgument] if the command is not read-only, or a parameter is invalid
        def poll_result(current_path, spec)
          parameters = options.get_option(:poll)
          return if parameters.nil? || parameters.empty?
          command = [self.class.plugin_name, *current_path].join(' ')
          Aspera.assert(spec.read_only?, type: Cli::BadArgument) do
            "Option poll: refused on `#{command}`: only a read-only command can be repeated (e.g. list, show, status)"
          end
          # Options that make a read-only command change state at each run
          Aspera.assert(!options.get_option(:once_only), type: Cli::BadArgument) { 'Option poll: refused with option once_only: it saves state at each run' }
          Aspera.assert(options.get_option(:notify_to).nil?, type: Cli::BadArgument) { 'Option poll: refused with option notify_to: it sends emails at each run' }
          Result::Poll.new(parameters, format: formatter&.format_type)
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
        # @param registry     [Command::Registry]
        # @param ctx          [Hash]
        # @return [Object]
        def dispatch_child(current_path, registry, ctx)
          children  = registry.children_of(current_path)
          # condition: methods belong to the class declaring the spec: only evaluate local ones
          # (mounted children are only walked here for --help, see below).
          # With --help, conditions are not evaluated: they may need the API, which is not built for help.
          available = children.reject { |id, c| c.condition && !@context.help_requested && registry.local?(current_path + [id]) && !send(c.condition) }
          # Aliases of available commands only: an alias must not bypass the condition of its command
          aliases   = available.values.each_with_object({}) do |c, h|
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

          # Both intermediate and leaf: arguments + setup are handled by Phase A of the next call
          dispatch_from_registry(child_path, ctx)
        end

        # Hand over dispatch of a mounted child to the target plugin instance.
        # Setups of the mount point `at` and of its ancestors in the target are not executed:
        # the seed ctx returned by the host's `instance` method replaces them.
        # The mount's own arguments (if any) are read first, and passed to `instance` in ctx.
        # @param mount   [Command::Mount]
        # @param command [Symbol] mounted child id, already consumed
        # @param ctx     [Hash]   host context, passed to the `instance` method
        # @return [Object]
        def dispatch_mount(mount, command, ctx)
          ctx = resolve_arguments(mount.arguments, ctx)
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

        # Resolve the action for a leaf Command.
        # Returns spec.action (Symbol or Proc) if explicitly set; otherwise derives a Symbol
        # from the full path as :action_<path_segment_1>_<path_segment_2>_...
        # (e.g. [:access_key, :list] -> :action_access_key_list).
        # @param spec [Command]
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

        # Execute a leaf Command: resolve arguments and call action.
        # Arguments already present in `ctx` (e.g. provided by a caller or a mount seed) are skipped:
        # they are not read again from the command line.
        # @param spec [Command] a leaf node (no children)
        # @param ctx  [Hash]        accumulated context (pre-resolved keys are not re-consumed)
        # @param poll [Result::Poll, nil] With option `poll`: the action is executed when this result is displayed
        # @return [Object]
        def execute_leaf(spec, ctx, poll: nil)
          a = action_for(spec)
          # Always resolve declared arguments (even when transfer_paths is set — those arguments
          # are consumed first; ts_source_paths then reads whatever remains in the queue).
          ctx = resolve_arguments(spec.arguments, ctx) if spec.arguments
          return invoke_action(a, [], ctx) if poll.nil?
          # Arguments are resolved once, the action is executed at each run
          poll.action = -> { invoke_action(a, [], ctx) }
          poll
        end

        # Resolve positional arguments from the CLI argument stream, in order.
        # Arguments already present in `ctx` (e.g. injected by a setup method) are not read from the command line.
        # If the next CLI argument is that same value, or `ALL`, it is skipped, so that it is not mistaken for a later argument
        # (e.g. `faspex5 packages receive ALL` with a public link to a package).
        # For type: :identifier, the percent-selector lookup receives the ctx accumulated so far.
        # @param arg_specs [Array<Argument>]
        # @param ctx       [Hash] accumulated context
        # @return [Hash] ctx merged with the resolved arguments
        def resolve_arguments(arg_specs, ctx)
          arg_specs.each do |arg_spec|
            if ctx.key?(arg_spec.name)
              options.get_next_argument(arg_spec.name.to_s, mandatory: false) if options.next_argument_in?([ctx[arg_spec.name].to_s, SpecialValues::ALL])
              next
            end
            # Not given: not passed to the action, which uses its own default
            next if arg_spec.omit_absent && options.command_or_arg_empty?
            lookup_cb = arg_spec.lookup if arg_spec.type.eql?(:identifier)
            current = ctx
            block =
              case lookup_cb
              when nil    then nil
              when Symbol then ->(f, v) { send(lookup_cb, f, v, **current) }
              else ->(f, v) { instance_exec(f, v, **current, &lookup_cb) }
              end
            ctx = ctx.merge(arg_spec.name => check_argument_access(arg_spec, resolve_argument(arg_spec, &block)))
          end
          ctx
        end

        # A local path given as an argument (`access: :read` or `:write`) is checked against the security level when it is read,
        # and replaced by its real path, so that the action receives a checked path (see `Cli::Security`).
        # For an argument with `stdin: true`, `-` (standard input) is not a local path: it is left unchanged, unless the standard input is disabled
        # (`@stdin:`, e.g. in MCP server mode). Elsewhere, `-` is a path, checked as any other.
        # @param arg_spec [Argument] declaration of the argument
        # @param value    [Object]   resolved value (a path, an Array of paths, or nil)
        # @return [Object] the value, with each path checked and resolved
        def check_argument_access(arg_spec, value)
          return value if value.nil?
          security = Security.instance
          resolver =
            case arg_spec.access
            when nil, :none then return value
            when :read      then security.method(:readable_path)
            when :write     then security.method(:writable_path)
            else Aspera.error_unexpected_value(arg_spec.access) { "access of argument #{arg_spec.name}" }
            end
          mapper = lambda do |one|
            next one unless one.is_a?(String)
            next resolver.call(one) unless arg_spec.stdin && one.eql?(STDIN_ARGUMENT)
            ExtendedValue.instance.check_enabled(:stdin, what: "argument #{arg_spec.name}: #{STDIN_ARGUMENT} (standard input)")
            one
          end
          value.is_a?(Array) ? value.map(&mapper) : mapper.call(value)
        end

        # Resolve a single positional argument from the CLI argument stream.
        # When arg_spec.bulk is true, always returns an Array (normalized to [value] when non-bulk).
        # Only such arguments are read as a list with `--bulk=yes`: others (e.g. the id of a parent node) are single values.
        # For type: :identifier, an optional block provides the percent-selector lookup.
        # @param arg_spec [Argument]
        # @yieldparam field [String]  field name from a percent-selector (%field:value)
        # @yieldparam value [String]  value from a percent-selector
        # @yieldreturn [String]       resolved identifier
        # @return [Object] the resolved value, or Array when arg_spec.bulk is true
        def resolve_argument(arg_spec, &block)
          if arg_spec.bulk
            is_bulk = options.get_option(:bulk)
            if arg_spec.type.eql?(:identifier)
              val = options.instance_identifier(description: arg_spec.name.to_s, multiple: is_bulk, &block)
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
              options.instance_identifier(description: arg_spec.name.to_s, mandatory: arg_spec.mandatory, default: arg_spec.default, &block)
            else
              # Class or Array<Class> -> pass as validation type
              # When interactive: true, prompt for this argument only when no CLI argument is provided
              # (mandatory is forced to true and default ignored: a non-nil default would short-circuit the prompt).
              options.with_interactive(enabled: arg_spec.interactive) do
                options.get_next_argument(
                  arg_spec.name.to_s,
                  mandatory:   arg_spec.interactive ? true : arg_spec.mandatory,
                  multiple:    arg_spec.multiple || false,
                  validation:  arg_spec.type,
                  accept_list: arg_spec.allowed,
                  default:     arg_spec.interactive ? nil : arg_spec.default,
                  schema:      arg_spec.schema,
                  evaluate:    arg_spec.evaluate
                )
              end
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

        # Resolve the `api:` reference given to `crud_commands`.
        # @param api [Symbol, Proc, Object] `:@ivar`, method name, Proc (instance_exec), or the API object itself
        # @return [Rest::Client]
        def crud_api(api)
          if api.is_a?(Symbol)
            api.to_s.start_with?('@') ? instance_variable_get(api) : send(api)
          elsif api.is_a?(Proc)
            instance_exec(&api)
          else
            api
          end
        end

        # --- Per-verb entity action methods ---
        # Each method handles exactly one CRUD verb.
        # The resource id (when needed) is received as `id:` from ctx — it must be
        # resolved upstream via an Argument(type: :identifier) on the command,
        # NOT read from the CLI queue inside the method.

        # List all instances of an entity.
        # @param api             [Aspera::Rest::Client]  REST API object
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
          elsif http['Content-Type'].start_with?(Mime::JSON_API)
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
        # @param api            [Aspera::Rest::Client]    REST API object
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
        # @param api            [Aspera::Rest::Client]      REST API object
        # @param entity         [String]            API sub-path
        # @param data           [Hash, Array<Hash>] Entity data (Array with bulk), from the command's declared `data` argument
        # @param display_fields [Array, nil]        Fields to display
        def entity_create(api:, entity:, data:, display_fields: nil, **)
          bulk_result(data, command: :create, fields: display_fields) do |params|
            api.create(entity, params)
          end
        end

        # Modify an existing instance of an entity.
        # @param api            [Aspera::Rest::Client]    REST API object
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
        # @param api             [Aspera::Rest::Client]    REST API object
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
