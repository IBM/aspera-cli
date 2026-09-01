# frozen_string_literal: true

module Aspera
  module Cli
    # Declares a positional argument consumed by a command.
    # Declaration order in a command's `arguments:` array defines parsing order.
    # Mandatory arguments must come before optional ones.
    #
    # @!attribute name        [Symbol]                    Name used in help and error messages
    # @!attribute description [String]                    User-facing description
    # @!attribute type        [Class, Array<Class>, :identifier] Validated type; :identifier triggers instance_identifier
    # @!attribute mandatory   [Boolean]                   Default true; optional args must come after all mandatory ones
    # @!attribute multiple    [Boolean, String]           true: consume all remaining; String: consume until named marker
    # @!attribute default     [Object, nil]               Default value when mandatory: false and no argument provided
    # @!attribute schema      [String, nil]               JSON schema name for validation and --help introspection
    # @!attribute bulk        [Boolean]                   When true, wraps read+loop for bulk mode (Array if --bulk yes)
    # @!attribute lookup      [Symbol, nil]               Instance method name for percent-selector resolution (only used when type: :identifier)
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
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:mandatory] = true  if kwargs[:mandatory].nil?
        kwargs[:multiple]  = false if kwargs[:multiple].nil?
        kwargs[:bulk]      = false if kwargs[:bulk].nil?
        super
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
      :handler,   # kept as-is: this is the option accessor delegation, not a command action
      :deprecation,
      :schema,
      keyword_init: true
    )

    # Declares a single command node in the flat registry.
    #
    # @!attribute id               [Symbol]                      Unique identifier within its parent's namespace
    # @!attribute parent           [Symbol, Array<Symbol>, nil]  Full path to parent; nil for root commands
    # @!attribute description      [String]                      User-facing help text
    # @!attribute options          [Array<Symbol>]               Option names consumed by this command
    # @!attribute arguments        [Array<ArgumentSpec>]         Positional arguments, in order.
    #                                                            The first ArgumentSpec with type: :identifier is treated as the instance
    #                                                            identifier for intermediate nodes (consumed in Phase A) and leaf nodes.
    # @!attribute action           [Symbol, Proc, nil]           Instance method (Symbol) or inline block (Proc) called when this is a leaf command
    # @!attribute setup            [Symbol, nil]                 Instance method called before dispatching to children; returns Hash merged into ctx
    # @!attribute delegates_to     [Symbol, Array<Symbol>, nil]  Re-enter the command tree at this path
    # @!attribute delegate_instance [Symbol, nil]                Instance method returning a different plugin object
    # @!attribute aliases          [Array<Symbol>, nil] Alternative names accepted for this command (each resolves to this command's id)
    # @!attribute entity_execute   [Hash, nil]                   Shorthand: expand to Base#entity_execute with these parameters
    # @!attribute transfer_paths   [:send, :receive, nil]        File-list resolution delegated to TransferAgent; mutually exclusive with arguments
    # @!attribute condition        [Symbol, nil]                 Instance method returning Boolean; if false command is hidden from dispatch
    CommandSpec = Struct.new(
      :id,
      :parent,
      :description,
      :options,
      :arguments,
      :action,
      :setup,
      :delegates_to,
      :delegate_instance,
      :aliases,
      :entity_execute,
      :transfer_paths,
      :condition,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        # Coerce each element of arguments: from Hash to ArgumentSpec if needed
        if kwargs[:arguments]
          kwargs[:arguments] = kwargs[:arguments].map do |a|
            a.is_a?(Hash) ? ArgumentSpec.new(**a) : a
          end
        end
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
