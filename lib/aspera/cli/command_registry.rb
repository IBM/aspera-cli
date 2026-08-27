# frozen_string_literal: true

require 'aspera/cli/command_spec'

module Aspera
  module Cli
    # Stores CommandSpec objects indexed by their full path (Array<Symbol>).
    # Each plugin class gets its own instance (not shared across the inheritance chain).
    #
    # Public API:
    #   register(spec)          — store a CommandSpec; raises on duplicate full_path
    #   register_option(spec)   — store an OptionSpec by name
    #   option_specs            — Hash{Symbol => OptionSpec} of all registered options
    #   [](path)                — retrieve a CommandSpec by full path
    #   children_of(path)       — Hash{Symbol => CommandSpec} of direct children
    #   all_paths               — Array of all registered full paths
    #   any?                    — true if at least one spec has been registered
    #   validate!               — cross-spec consistency checks; raises on violation
    class CommandRegistry
      # @param path [Array<Symbol>] full path to look up
      # @return [CommandSpec, nil]
      def [](path)
        @specs[Array(path)]
      end

      # Register a CommandSpec. Raises if the full_path is already registered.
      # @param spec [CommandSpec]
      # @raise [ArgumentError] on duplicate full path
      # @return [CommandSpec] the registered spec
      def register(spec)
        path = spec.full_path
        raise ArgumentError, "Duplicate command path: #{path.inspect}" if @specs.key?(path)
        @specs[path] = spec
      end

      # Returns a Hash mapping each child id to its CommandSpec for all direct
      # children of `path`. Empty hash if no children are registered.
      # @param path [Array<Symbol>] parent path ([] for root-level commands)
      # @return [Hash{Symbol => CommandSpec}]
      def children_of(path)
        parent_path = Array(path)
        result = {}
        @specs.each_value do |spec|
          fp = spec.full_path
          # A direct child has exactly one more element and the same prefix
          next unless fp.length == parent_path.length + 1
          next unless fp.first(parent_path.length) == parent_path
          result[spec.id] = spec
        end
        result
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

      # Cross-spec consistency checks.
      # @raise [ArgumentError] on any violation
      # @return [self]
      def validate!
        @specs.each_value do |spec|
          path = spec.full_path

          # Rule: delegates_to must point to a known path when present (non-empty array or symbol)
          if spec.delegates_to
            dt_path =
              case spec.delegates_to
              when Symbol then [spec.delegates_to]
              when Array  then spec.delegates_to
              end
            # An empty array [] means re-enter the root — always valid
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
        end
        self
      end

      private

      def initialize
        # Keyed by Array<Symbol> full path
        @specs = {}
        # Keyed by Symbol option name
        @option_specs = {}
      end
    end
  end
end
