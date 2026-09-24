# frozen_string_literal: true

require 'aspera/schema/registry'

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
    # @!attribute allowed     [Array<Symbol>, nil]        Allowed Symbol values; when set, type is forced to Symbol and accept_list is applied
    # @!attribute interactive [Boolean]                   When true, sets ask_missing_mandatory before resolving so interactive prompting is triggered when no CLI args are provided
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
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:mandatory]    = true  if kwargs[:mandatory].nil?
        kwargs[:multiple]     = false if kwargs[:multiple].nil?
        kwargs[:bulk]         = false if kwargs[:bulk].nil?
        kwargs[:interactive]  = false if kwargs[:interactive].nil?
        kwargs[:type]         = String unless kwargs.key?(:type) || kwargs[:allowed]
        super
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
    # @!attribute handler     [Symbol, Hash, nil]
    #   - Symbol: resolved to {o: <plugin instance>, m: <symbol>} at runtime (Category B)
    #   - Hash:   {o: <object>, m: <method>} used as-is (Category A: singletons / class constants)
    #   - nil:    option stores its value locally (no delegation)
    # @!attribute deprecation [String, nil]          Forwarded to options.declare as deprecation:
    # @!attribute schema      [String, nil]          JSON schema name; also derives description when nil
    OptionSpec = Struct.new(
      :name,
      :description,
      :allowed,
      :default,
      :short,
      :handler, # kept as-is: this is the option accessor delegation, not a command action
      :deprecation,
      :schema,
      keyword_init: true
    )

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
      keyword_init: true
    ) do
      def initialize(**kwargs)
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
