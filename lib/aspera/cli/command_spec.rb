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
    ArgumentSpec = Struct.new(
      :name,
      :description,
      :type,
      :mandatory,
      :multiple,
      :default,
      :schema,
      keyword_init: true
    ) do
      def initialize(**kwargs)
        kwargs[:mandatory] = true  if kwargs[:mandatory].nil?
        kwargs[:multiple]  = false if kwargs[:multiple].nil?
        super
      end
    end

    # Declares an option referenced by name from command declarations.
    # Mirrors the existing `options.declare` call but associates the option with
    # the command(s) that use it.
    #
    # @!attribute name        [Symbol]        Option name (same symbol used in options.declare)
    # @!attribute description [String]        User-facing description
    # @!attribute allowed     [Array, nil]    Allowed values (forwarded to options.declare)
    # @!attribute default     [Object, nil]   Default value
    # @!attribute short       [String, nil]   Single-character short form (e.g. '-q')
    OptionSpec = Struct.new(
      :name,
      :description,
      :allowed,
      :default,
      :short,
      keyword_init: true
    )

    # Declares a single command node in the flat registry.
    #
    # @!attribute id               [Symbol]                      Unique identifier within its parent's namespace
    # @!attribute parent           [Symbol, Array<Symbol>, nil]  Full path to parent; nil for root commands
    # @!attribute description      [String]                      User-facing help text
    # @!attribute options          [Array<Symbol>]               Option names consumed by this command
    # @!attribute arguments        [Array<ArgumentSpec>]         Positional arguments, in order
    # @!attribute handler          [Symbol, Proc, nil]           Instance method (Symbol) or inline block (Proc) called when this is a leaf command
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
      :handler,
      :setup,
      :delegates_to,
      :delegate_instance,
      :aliases,
      :entity_execute,
      :transfer_paths,
      :condition,
      keyword_init: true
    ) do
      # Compute the full path as Array<Symbol> from parent + id.
      # @return [Array<Symbol>]
      def full_path
        case parent
        when nil
          [id]
        when Symbol
          [parent, id]
        when Array
          parent + [id]
        end
      end
    end
  end
end
