# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../schema/registry'
require_relative 'option_types'
require_relative 'security'

module Aspera
  module Cli
    # Declares a positional argument consumed by a command.
    # Declaration order in a command's `arguments:` array defines parsing order.
    # Mandatory arguments must come before optional ones.
    #
    # @!attribute name        [Symbol]                    Name used in help and error messages
    # @!attribute description [String]                    User-facing description
    # @!attribute type        [Class, Array<Class>, :identifier, nil] Validated type; :identifier triggers instance_identifier.
    #                                                     Default: String (unless allowed:); explicit nil accepts any value
    # @!attribute mandatory   [Boolean]                   Default true; optional args must come after all mandatory ones
    # @!attribute multiple    [Boolean, String]           true: consume all remaining; String: consume until named marker
    # @!attribute default     [Object, nil]               Default value when mandatory: false and no argument provided
    # @!attribute schema      [String, nil]               JSON schema name for validation and --help introspection
    # @!attribute bulk        [Boolean]                   When true, wraps read+loop for bulk mode (Array if --bulk yes)
    # @!attribute lookup      [Symbol, Proc, nil]         Percent-selector resolver (only used when type: :identifier).
    #                                                     Symbol → resolved via send(lookup, field, value, **ctx).
    #                                                     Proc/lambda → called via instance_exec(field, value, **ctx, &lookup).
    #                                                     Style: use Symbol for named methods; ->(){} for 1-liners; lambda do…end for 2–3 statements.
    # @!attribute allowed     [Array<Symbol>, #call, nil] Allowed Symbol values; when set, type is forced to Symbol and accept_list is applied.
    #   A callable returns the values when read: the list of values that bundles add after the command is declared (e.g. agents)
    # @!attribute interactive [Boolean]                   When true, prompts for this argument (only) when no CLI args are provided
    # @!attribute evaluate    [Symbol]                    How the value is read, one of `EVALUATIONS`. Default `:extended`.
    #                                                     `:extended`: extended value (`@json:`, `@file:`, `@val:`...); a value without prefix stays a string.
    #                                                     `:smart`: `true`/`yes`/`false`/`no` and numbers are converted, else extended value (as dotted options).
    #                                                     `:none`: the string as typed, not evaluated (e.g. `@env:`).
    # @!attribute complete    [Symbol, nil]               Values proposed by shell completion, one of `Complete::KINDS` (e.g. `:file`)
    # @!attribute omit_absent [Boolean]                   For an optional argument: when not given, it is not passed to the action,
    #                                                     so that the action (with its own default) can tell it from a value `nil` (`@none:`)
    # Ways to evaluate the value of an argument, see `ArgumentSpec#evaluate`
    EVALUATIONS = %i[extended smart none].freeze

    ArgumentSpec = Struct.new(
      :name,
      :description,
      :type,
      :mandatory,
      :multiple,
      :default,
      :schema,
      :bulk,
      :lookup,
      :allowed,
      :interactive,
      :evaluate,
      :complete,
      :omit_absent,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:mandatory]    = true  if kwargs[:mandatory].nil?
        kwargs[:multiple]     = false if kwargs[:multiple].nil?
        kwargs[:bulk]         = false if kwargs[:bulk].nil?
        kwargs[:interactive]  = false if kwargs[:interactive].nil?
        kwargs[:evaluate]     = :extended if kwargs[:evaluate].nil?
        kwargs[:omit_absent]  = false if kwargs[:omit_absent].nil?
        raise ArgumentError, "omit_absent: only for an optional argument: #{kwargs[:name]}" if kwargs[:omit_absent] && kwargs[:mandatory]
        kwargs[:type] = String unless kwargs.key?(:type) || kwargs[:allowed]
        raise ArgumentError, "evaluate: #{kwargs[:evaluate].inspect}, expecting one of: #{EVALUATIONS.join(', ')}" unless EVALUATIONS.include?(kwargs[:evaluate])
        super
      end

      # @return [Array<Symbol>, nil] Allowed values: the result of the callable given to `allowed:`, evaluated at each read
      def allowed
        values = self[:allowed]
        values.respond_to?(:call) ? values.call : values
      end

      # Syntax of argument for help, e.g. `<name>`, `[<name>]`, `<paths...>`, `<account:Hash>`.
      # Type is shown only when the argument is not free text.
      # @return [String]
      def syntax
        token = allowed ? allowed.join('|') : name.to_s
        token += '...' if multiple
        types = Array(type).grep(Class)
        token += ":#{types.map(&:name).join('|')}" unless allowed || types.empty? || types.include?(String)
        mandatory ? "<#{token}>" : "[<#{token}>]"
      end
    end

    # Declares an option referenced by name from command declarations.
    # Mirrors the existing `options.declare` call but associates the option with
    # the command(s) that use it.
    #
    # @!attribute name        [Symbol]               Option name (same symbol used in options.declare)
    # @!attribute description [String, nil]          User-facing description; nil derives it from schema:
    # @!attribute allowed     [Array, nil]           Allowed values (forwarded to options.declare)
    # @!attribute default     [Object, nil]          Default value
    # @!attribute short       [String, nil]          Single-character short form (e.g. 'x')
    # @!attribute on_set     [Symbol, Proc, #call, nil] Called with the new value each time the value is set
    #   (for a flag: called without argument when the flag is found)
    #   - Symbol: method of the plugin instance
    #   - Proc:   executed with instance_exec on the plugin instance
    #   - other:  object responding to `call`, e.g. `Log.instance.method(:level=)`
    #   - nil:    no callback, the value is read with `get_option`
    # @!attribute shorthand   [String, nil]          For a `Hash` option: a `String` value is stored as `{shorthand => value}`
    # @!attribute deprecation [Hash, nil]            Forwarded to options.declare as deprecation: `{last:, message:}`
    # @!attribute schema      [String, nil]          JSON schema name; also derives description when nil
    # @!attribute complete    [Symbol, nil]          Values proposed by shell completion, one of `Complete::KINDS` (e.g. `:file`)
    # @!attribute security    [Symbol, nil]          Most restrictive security level at which the option is available (`:low`: executes code), see `Security`
    OptionSpec = Struct.new(
      :name,
      :description,
      :allowed,
      :default,
      :short,
      :on_set,
      :shorthand,
      :deprecation,
      :schema,
      :complete,
      :security,
      keyword_init: true
    ) do
      # Declare this option on a parser, resolving the `on_set` callback.
      # @param parser [Parser] Parser to declare the option on
      # @param target [Object, nil] Object for Symbol and Proc `on_set` callbacks (plugin instance); nil: such callbacks are not bound
      # @return [void]
      def declare_on(parser, target: nil)
        parser.declare(
          name,
          description: description,
          short:       short,
          allowed:     allowed,
          default:     default,
          on_set:      resolved_on_set(target),
          shorthand:   shorthand,
          deprecation: deprecation,
          schema:      schema,
          complete:    complete,
          security:    security
        )
      end

      private

      # @param target [Object, nil] Object for Symbol and Proc `on_set` callbacks
      # @return [#call, nil] `on_set` callback for `Parser#declare`
      def resolved_on_set(target)
        case on_set
        when Symbol then target&.method(on_set)
        when Proc
          return if target.nil?
          proc_on_set = on_set
          ->(*value) { target.instance_exec(*value, &proc_on_set) }
        else on_set
        end
      end
    end

    # Declares that a command node exposes a sub-tree of another plugin class.
    # The mounted children appear in the host registry (dispatch, --help, completion)
    # as if they were declared by the host; host children with the same id take precedence.
    #
    # @!attribute plugin   [Class]                Target plugin class (subclass of Plugins::Base)
    # @!attribute at       [Array<Symbol>]        Path in the target registry whose children are mounted ([] = root)
    # @!attribute instance [Symbol]               Host instance method called with **ctx, returning the target plugin
    #                                             instance, or [instance, ctx] where ctx seeds the target dispatch
    #                                             (it replaces what the setups of `at` and its ancestors would provide)
    # @!attribute only     [Array<Symbol>, nil]   Restrict mounted children to these ids
    # @!attribute except   [Array<Symbol>, nil]   Exclude these ids from mounted children
    # @!attribute arguments [Array<ArgumentSpec>] Arguments read by the host after the mounted command, before its own
    #                                             arguments; resolved values are passed to `instance`
    #                                             (e.g. `packages ls <package_id> <path>`)
    MountSpec = Struct.new(
      :plugin,
      :at,
      :instance,
      :only,
      :except,
      :arguments,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:at] = Array(kwargs[:at]).freeze
        kwargs[:arguments] = Array(kwargs[:arguments]).map { |a| a.is_a?(Hash) ? ArgumentSpec.new(**a) : a }.freeze
        super
      end

      # @return [CommandRegistry] registry of the target plugin class
      def registry
        plugin.command_registry
      end

      # @param id [Symbol] id of a child of `at` in the target registry
      # @return [Boolean] true if this child is exposed by the mount
      def accepts?(id)
        (only.nil? || only.include?(id)) && !except&.include?(id)
      end
    end

    # Ids of the commands read-only by default (`read_only: :default`): they change nothing
    READ_ONLY_IDS = %i[list show status info health ls browse find].freeze

    # Declares a single command node in the flat registry.
    #
    # @!attribute id               [Symbol]                      Unique identifier within its parent's namespace
    # @!attribute parent           [Symbol, Array<Symbol>, nil]  Full path to parent; nil for root commands
    # @!attribute description      [String]                      User-facing help text
    # @!attribute arguments        [Array<ArgumentSpec>]         Positional arguments, in order.
    #                                                            The first ArgumentSpec with type: :identifier is treated as the instance
    #                                                            identifier for intermediate nodes (consumed in Phase A) and leaf nodes.
    # @!attribute action           [Symbol, Proc, nil]           Instance method (Symbol) or inline block (Proc) called when this is a leaf command
    # @!attribute setup            [Symbol, nil]                 Instance method called before dispatching to children; returns Hash merged into ctx
    # @!attribute aliases          [Array<Symbol>, nil] Alternative names accepted for this command (each resolves to this command's id)
    # @!attribute transfer_paths   [:send, :receive, nil]        File-list resolution delegated to TransferAgent; mutually exclusive with arguments
    # @!attribute condition        [Symbol, nil]                 Instance method returning Boolean; if false command is hidden from dispatch
    # @!attribute query_schema     [String, nil]                 Schema path for --query help; when set, the runner hints `--query=help`
    # @!attribute mount            [MountSpec, Hash, nil]        Expose children of another plugin's registry under this node
    # @!attribute security         [Symbol, nil]                 Most restrictive security level at which the command is available (`:low`: executes code), see `Security`
    # @!attribute read_only        [Boolean, :default]           Leaf only: the command changes nothing (on the server or locally), so it can be repeated (option `poll`).
    #                                                            `:default` (default): read-only if the id is one of READ_ONLY_IDS (`list`, `show`, ...)
    CommandSpec = Struct.new(
      :id,
      :parent,
      :description,
      :arguments,
      :action,
      :setup,
      :aliases,
      :transfer_paths,
      :condition,
      :query_schema,
      :mount,
      :security,
      :read_only,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        Aspera.assert_values(kwargs[:security], Security::LEVELS + [nil]) { "#{kwargs[:id]}: security" }
        kwargs[:read_only] = :default if kwargs[:read_only].nil?
        Aspera.assert_values(kwargs[:read_only], [true, false, :default]) { "#{kwargs[:id]}: read_only" }
        # Coerce each element of arguments: from Hash to ArgumentSpec if needed
        if kwargs[:arguments]
          kwargs[:arguments] = kwargs[:arguments].map do |a|
            a.is_a?(Hash) ? ArgumentSpec.new(**a) : a
          end
        end
        kwargs[:mount] = MountSpec.new(**kwargs[:mount]) if kwargs[:mount].is_a?(Hash)
        super
      end

      class << self
        # Derive the implicit action method name from a path array.
        # e.g. [:admin, :user, :list] -> :action_admin_user_list
        # @param path [Array<Symbol>]
        # @return [Symbol]
        def action_method(path)
          :"action_#{path.join('_')}"
        end
      end

      # @return [Boolean] `true` if the command changes nothing: explicit `read_only`, or from its id (READ_ONLY_IDS)
      def read_only?
        read_only.eql?(:default) ? READ_ONLY_IDS.include?(id) : read_only
      end

      # Compute the full path as Array<Symbol> from parent + id.
      # @return [Array<Symbol>]
      def full_path
        Array(parent) + [id]
      end

      # Derive the implicit action method name from the full path.
      # @return [Symbol]
      def action_method_name
        self.class.action_method(full_path)
      end
    end
  end
end
