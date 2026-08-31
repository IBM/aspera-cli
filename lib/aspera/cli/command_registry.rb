# frozen_string_literal: true

require 'aspera/cli/command_spec'

module Aspera
  module Cli
    # Stores CommandSpec objects indexed by their full path (Array<Symbol>).
    # Each plugin class gets its own instance (not shared across the inheritance chain).
    #
    # Public API:
    #   register(spec)          - store a CommandSpec; raises on duplicate full_path
    #   register_option(spec)   - store an OptionSpec by name
    #   option_specs            - Hash{Symbol => OptionSpec} of all registered options
    #   [](path)                - retrieve a CommandSpec by full path
    #   children_of(path)       - Hash{Symbol => CommandSpec} of direct children (O(1))
    #   all_paths               - Array of all registered full paths
    #   any?                    - true if at least one spec has been registered
    #   validate!               - cross-spec consistency checks; raises on violation
    class CommandRegistry
      # @param path [Array<Symbol>] full path to look up
      # @return [CommandSpec, nil]
      def [](path)
        @specs[Array(path)]
      end

      # Register a CommandSpec. Raises if the full_path is already registered.
      # Also updates the children index so children_of remains O(1).
      # @param spec [CommandSpec]
      # @raise [ArgumentError] on duplicate full path
      # @return [CommandSpec] the registered spec
      def register(spec)
        path = spec.full_path
        raise ArgumentError, "Duplicate command path: #{path.inspect}" if @specs.key?(path)
        @specs[path] = spec
        # Index: parent_path -> { child_id -> spec }
        parent = path[0..-2] # [] for root-level commands
        (@children_index[parent] ||= {})[spec.id] = spec
        spec
      end

      # Returns a Hash mapping each child id to its CommandSpec for all direct
      # children of `path`. Empty hash if no children are registered.
      # O(1) lookup via the children index built in register().
      # @param path [Array<Symbol>] parent path ([] for root-level commands)
      # @return [Hash{Symbol => CommandSpec}]
      def children_of(path)
        @children_index[Array(path)] || {}
      end

      # @return [Array<Array<Symbol>>] all registered full paths
      def all_paths
        @specs.keys
      end

      # Register an OptionSpec. Raises if the option name is already registered.
      # @param spec [OptionSpec]
      # @raise [ArgumentError] on duplicate option name
      # @return [OptionSpec] the registered spec
      def register_option(spec)
        raise ArgumentError, "Duplicate option: #{spec.name.inspect}" if @option_specs.key?(spec.name)
        @option_specs[spec.name] = spec
      end

      # @return [Hash{Symbol => OptionSpec}] all registered option specs
      def option_specs
        @option_specs.dup
      end

      # @return [Boolean] true if at least one spec is registered
      def any?
        !@specs.empty?
      end

      # @return [Boolean] true if no specs have been registered
      def none?
        @specs.empty?
      end

      # Cross-spec consistency checks.
      # @param plugin_class [Class, nil] when given, also verify that implicit handler methods exist
      # @raise [ArgumentError] on any violation
      # @return [self]
      def validate!(plugin_class: nil)
        @specs.each_value do |spec|
          path = spec.full_path

          # Rule: delegates_to must point to a known path when present (non-empty array or symbol)
          if spec.delegates_to
            dt_path =
              case spec.delegates_to
              when Symbol then [spec.delegates_to]
              when Array  then spec.delegates_to
              end
            # An empty array [] means re-enter the root - always valid
            unless dt_path.empty? || @specs.key?(dt_path)
              raise ArgumentError,
                "#{path.inspect}: delegates_to #{dt_path.inspect} points to unknown path"
            end
          end

          # Rule: delegate_instance requires delegates_to
          if spec.delegate_instance && spec.delegates_to.nil?
            raise ArgumentError,
              "#{path.inspect}: delegate_instance requires delegates_to to be set"
          end

          # Rule: transfer_paths and arguments are mutually exclusive
          if spec.transfer_paths && spec.arguments && !spec.arguments.empty?
            raise ArgumentError,
              "#{path.inspect}: transfer_paths and arguments are mutually exclusive"
          end

          # Rule: leaf commands with no explicit handler must have a matching instance method
          next if spec.handler # explicit handler: skip
          next if @children_index[path]&.any? # intermediate node: skip
          next if spec.delegates_to || spec.entity_execute # delegated: skip
          next unless plugin_class
          implicit_method = :"handle_#{path.join('_')}"
          unless plugin_class.method_defined?(implicit_method)
            raise ArgumentError,
              "#{path.inspect}: no handler: and no method #{implicit_method} on #{plugin_class}"
          end
        end
        self
      end

      private

      def initialize
        # Keyed by Array<Symbol> full path
        @specs = {}
        # Keyed by Symbol option name
        @option_specs = {}
        # Children index: parent Array<Symbol> -> Hash{child_id Symbol => CommandSpec}
        # Built incrementally in register(); enables O(1) children_of lookups.
        @children_index = {}
      end
    end
  end
end
