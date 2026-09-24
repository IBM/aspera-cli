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
    #   [](path)                - retrieve a CommandSpec by full path (follows mounts)
    #   children_of(path)       - Hash{Symbol => CommandSpec} of direct children (follows mounts)
    #   resolve(path)           - [registry, path] owning the spec at path (follows mounts)
    #   local?(path)            - true if path is owned by this registry (not reached through a mount)
    #   mount_of(path)          - MountSpec of the local node at path, if any
    #   mount_at(path)          - MountSpec of the node at path, if any (follows mounts)
    #   own_children_of(path)   - Hash{Symbol => CommandSpec} of direct children declared on the node, without mounted ones
    #   leaf_paths              - Array of all leaf paths (follows mounts, or stops at mount nodes)
    #   all_paths               - Array of all locally registered full paths
    #   any?                    - true if at least one spec has been registered
    #   validate!               - cross-spec consistency checks; raises on violation
    #
    # Paths are always expressed in this registry's namespace: a path going through a
    # mounted node (see MountSpec) is translated to the target registry transparently.
    # Specs returned for mounted paths are the target's specs (their full_path is in the
    # target namespace).
    class CommandRegistry
      # @param path [Array<Symbol>] full path to look up
      # @return [CommandSpec, nil]
      def [](path)
        registry, local_path = resolve(path)
        registry.equal?(self) ? @specs[local_path] : registry[local_path]
      end

      # Find the registry owning `path`, following mounts.
      # A host child always takes precedence over a mounted child with the same id.
      # @param path [Array<Symbol>] path in this registry's namespace
      # @return [Array(CommandRegistry, Array<Symbol>)] owning registry and path in its namespace
      def resolve(path)
        path = Array(path)
        path.each_index do |i|
          prefix = path[0, i]
          mount = @specs[prefix]&.mount
          next if mount.nil? || @children_index[prefix]&.key?(path[i]) || !mount.accepts?(path[i])
          return mount.registry.resolve(mount.at + path[i..])
        end
        [self, path]
      end

      # @param path [Array<Symbol>] path in this registry's namespace
      # @return [Boolean] true if the node at path is declared in this registry (not mounted)
      def local?(path)
        resolve(path).first.equal?(self)
      end

      # @param path [Array<Symbol>] local path of a node
      # @return [MountSpec, nil] the mount declared on that node
      def mount_of(path)
        @specs[Array(path)]&.mount
      end

      # @param path [Array<Symbol>] path in this registry's namespace
      # @return [MountSpec, nil] the mount declared on the node at path, following mounts
      def mount_at(path)
        registry, local_path = resolve(path)
        registry.mount_of(local_path)
      end

      # Children declared on the node itself, without the ones exposed by its mount.
      # @param path [Array<Symbol>] path in this registry's namespace
      # @return [Hash{Symbol => CommandSpec}]
      def own_children_of(path)
        registry, local_path = resolve(path)
        return registry.own_children_of(local_path) unless registry.equal?(self)
        @children_index[local_path] || {}
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
      # For a mount node: mounted children (filtered) followed by local children,
      # local ones overriding mounted ones with the same id.
      # @param path [Array<Symbol>] parent path ([] for root-level commands)
      # @return [Hash{Symbol => CommandSpec}]
      def children_of(path)
        registry, local_path = resolve(path)
        return registry.children_of(local_path) unless registry.equal?(self)
        own = @children_index[local_path] || {}
        mount = @specs[local_path]&.mount
        return own if mount.nil?
        mount.registry.children_of(mount.at).select { |id, _| mount.accepts?(id) }.merge(own)
      end

      # All leaf paths under path, in tree order, following mounts.
      # A mount cycle (a sub-tree mounting one of its ancestors) is not expanded twice.
      # @param path          [Array<Symbol>] root of the listing ([] for all)
      # @param expand_mounts [Boolean]       `false`: a mount node is listed as a leaf, followed by its own children only
      # @return [Array<Array<Symbol>>]
      def leaf_paths(path = [], chain = [], expand_mounts: true)
        children_of(path).keys.flat_map do |id|
          child = path + [id]
          key = subtree_key(child)
          next [] if chain.include?(key)
          if !expand_mounts && mount_at(child)
            next [child] + own_children_of(child).keys.flat_map do |own_id|
              own_child = child + [own_id]
              children_of(own_child).empty? ? [own_child] : leaf_paths(own_child, chain + [key], expand_mounts: false)
            end
          end
          children_of(child).empty? ? [child] : leaf_paths(child, chain + [key], expand_mounts: expand_mounts)
        end
      end

      # @return [Array<Array<Symbol>>] all locally registered full paths
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
      # @param plugin_class [Class, nil] when given, also verify that implicit action methods exist
      # @raise [ArgumentError] on any violation
      # @return [self]
      def validate!(plugin_class: nil)
        # Rule: every non-root parent path that appears in the children index must have
        # a registered CommandSpec. A missing parent means commands_under(:x) was used
        # without a matching command :x declaration.
        @children_index.each_key do |parent_path|
          next if parent_path.empty? # root is never a CommandSpec
          unless @specs.key?(parent_path)
            raise ArgumentError,
              "commands_under(#{parent_path.map(&:inspect).join(', ')}) used but #{parent_path.last.inspect} has no command declaration"
          end
        end

        @specs.each_value do |spec|
          path = spec.full_path

          if (mount = spec.mount)
            # Rule: a mount needs an instance method, no action, and must point to existing target nodes
            raise ArgumentError, "#{path.inspect}: mount requires instance:" if mount.instance.nil?
            raise ArgumentError, "#{path.inspect}: mount and action: are exclusive" if spec.action
            raise ArgumentError, "#{path.inspect}: mount at #{mount.at.inspect} not found in #{mount.plugin}" unless mount.at.empty? || mount.registry[mount.at]
            target_ids = mount.registry.children_of(mount.at).keys
            unknown = Array(mount.only) + Array(mount.except) - target_ids
            raise ArgumentError, "#{path.inspect}: mount only/except unknown in #{mount.plugin}: #{unknown.inspect}" unless unknown.empty?
            instance_defined = plugin_class.nil? || plugin_class.method_defined?(mount.instance) || plugin_class.private_method_defined?(mount.instance)
            raise ArgumentError, "#{path.inspect}: no method #{mount.instance} on #{plugin_class}" unless instance_defined
            next
          end

          # Rule: leaf commands with no explicit action must have a matching instance method
          next if spec.action # explicit action: skip
          next if @children_index[path]&.any? # intermediate node: skip
          next unless plugin_class
          implicit_method = CommandSpec.action_method(path)
          unless plugin_class.method_defined?(implicit_method) || plugin_class.private_method_defined?(implicit_method)
            raise ArgumentError,
              "#{path.inspect}: no action: and no method #{implicit_method} on #{plugin_class}"
          end
        end
        self
      end

      private

      # Identity of the sub-tree exposed at path: the mount point for a mount node, else the owning node.
      # @return [Array(Integer, Array<Symbol>)]
      def subtree_key(path)
        registry, local_path = resolve(path)
        mount = registry.mount_of(local_path)
        mount ? [mount.registry.object_id, mount.at] : [registry.object_id, local_path]
      end

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
