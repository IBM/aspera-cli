# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../command'
require_relative '../complete'

module Aspera
  module Cli
    class Command
      # Stores Command objects indexed by their full path (Array<Symbol>).
      # Each plugin class gets its own instance (not shared across the inheritance chain).
      #
      # Public API:
      #   register(spec)          - store a Command; raises on duplicate full_path
      #   register_option(spec)   - store an Option by name
      #   option_specs            - Hash{Symbol => Option} of all registered options
      #   [](path)                - retrieve a Command by full path (follows mounts)
      #   children_of(path)       - Hash{Symbol => Command} of direct children (follows mounts)
      #   resolve(path)           - [registry, path] owning the spec at path (follows mounts)
      #   local?(path)            - true if path is owned by this registry (not reached through a mount)
      #   mount_of(path)          - Command::Mount of the local node at path, if any
      #   mount_at(path)          - Command::Mount of the node at path, if any (follows mounts)
      #   own_children_of(path)   - Hash{Symbol => Command} of direct children declared on the node, without mounted ones
      #   arguments_at(path)      - Array of Argument read by the node at path (mount arguments first)
      #   leaf_paths              - Array of all leaf paths (follows mounts, or stops at mount nodes)
      #   command_path(words)     - command path designated by command line words (aliases, prefixes, arguments)
      #   command_position(words) - command path and number of its arguments, as read by the dispatcher
      #   all_paths               - Array of all locally registered full paths
      #   any?                    - true if at least one spec has been registered
      #   validate!               - cross-spec consistency checks; raises on violation
      #
      # Paths are always expressed in this registry's namespace: a path going through a
      # mounted node (see Command::Mount) is translated to the target registry transparently.
      # Specs returned for mounted paths are the target's specs (their full_path is in the
      # target namespace).
      class Registry
        # @param path [Array<Symbol>] full path to look up
        # @return [Command, nil]
        def [](path)
          registry, local_path = resolve(path)
          registry.equal?(self) ? @specs[local_path] : registry[local_path]
        end

        # Find the registry owning `path`, following mounts.
        # A host child always takes precedence over a mounted child with the same id.
        # @param path [Array<Symbol>] path in this registry's namespace
        # @return [Array(Command::Registry, Array<Symbol>)] owning registry and path in its namespace
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
        # @return [Command::Mount, nil] the mount declared on that node
        def mount_of(path)
          @specs[Array(path)]&.mount
        end

        # @param path [Array<Symbol>] path in this registry's namespace
        # @return [Command::Mount, nil] the mount declared on the node at path, following mounts
        def mount_at(path)
          registry, local_path = resolve(path)
          registry.mount_of(local_path)
        end

        # Children declared on the node itself, without the ones exposed by its mount.
        # @param path [Array<Symbol>] path in this registry's namespace
        # @return [Hash{Symbol => Command}]
        def own_children_of(path)
          registry, local_path = resolve(path)
          return registry.own_children_of(local_path) unless registry.equal?(self)
          @children_index[local_path] || {}
        end

        # Arguments read by the node at path, in order.
        # For a child exposed by a mount, the mount's arguments come first (read by the host).
        # @param path [Array<Symbol>] path in this registry's namespace
        # @return [Array<Argument>]
        def arguments_at(path)
          path = Array(path)
          (path.empty? ? [] : mount_arguments(path)) + (self[path]&.arguments || [])
        end

        # Register a Command. Raises if the full_path is already registered.
        # Also updates the children index so children_of remains O(1).
        # @param spec   [Command]
        # @param before [Symbol, nil] Id of a registered child of the same parent: the command is placed before it; `nil`: after the other children
        # @raise [ArgumentError] on duplicate full path, or unknown `before`
        # @return [Command] the registered spec
        def register(spec, before: nil)
          path = spec.full_path
          raise ArgumentError, "Duplicate command path: #{path.inspect}" if @specs.key?(path)
          # Index: parent_path -> { child_id -> spec }
          parent = path[0..-2] # [] for root-level commands
          siblings = (@children_index[parent] ||= {})
          raise ArgumentError, "#{path.inspect}: no command #{before.inspect} to place it before" unless before.nil? || siblings.key?(before)
          @specs[path] = spec
          if before.nil?
            siblings[spec.id] = spec
          else
            @children_index[parent] = siblings.each_with_object({}) do |(id, sibling), placed|
              placed[spec.id] = spec if id.eql?(before)
              placed[id] = sibling
            end
          end
          spec
        end

        # Returns a Hash mapping each child id to its Command for all direct
        # children of `path`. Empty hash if no children are registered.
        # For a mount node: mounted children (filtered) followed by local children,
        # local ones overriding mounted ones with the same id.
        # @param path [Array<Symbol>] parent path ([] for root-level commands)
        # @return [Hash{Symbol => Command}]
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

        # Command path designated by words of a command line: sub-commands (or their aliases, or a unique prefix),
        # each possibly followed by its positional arguments, e.g. `packages receive ALL` designates `packages receive`.
        # Words after a leaf command are its arguments.
        # @param words [Array<Symbol>] words following the plugin name
        # @return [Array(Array<Symbol>, Symbol)] command path, and the first word that is neither a sub-command
        #   nor an expected argument (`nil` if none)
        def command_path(words)
          path = []
          # Number of positional arguments still accepted by the node at path
          args_left = 0
          words.each do |word|
            children = children_of(path)
            break if children.empty?
            id = child_id(children, word)
            if id
              path += [id]
              arguments = arguments_at(path)
              args_left = arguments.any?(&:multiple) ? Float::INFINITY : arguments.length
            elsif args_left.positive?
              args_left -= 1
            else
              return [path, word]
            end
          end
          [path, nil]
        end

        # Position reached by words of a command line, as read by the dispatcher: an intermediate command reads
        # its positional arguments before its sub-command, a leaf command reads the following words as arguments.
        # Unlike `command_path`, a word expected as argument is never taken as a sub-command.
        # @param words [Array<Symbol>] words following the plugin name
        # @return [Array(Array<Symbol>, Integer), nil] command path, and number of its positional arguments given;
        #   `nil` if a word is neither a sub-command nor an expected argument
        def command_position(words)
          path = []
          given = 0
          words.each do |word|
            children = children_of(path)
            arguments = arguments_at(path)
            if given < arguments.length || (children.empty? && arguments.last&.multiple)
              given += 1
            else
              id = child_id(children, word)
              return nil if id.nil?
              path += [id]
              given = 0
            end
          end
          [path, given]
        end

        # @return [Array<Array<Symbol>>] all locally registered full paths
        def all_paths
          @specs.keys
        end

        # Register an Option. Raises if the option name is already registered.
        # @param spec   [Option]
        # @param before [Symbol, nil] Name of an option to place this one before, also when that option is registered later
        #                             (e.g. by the body of a plugin class, after the modules mounted on it); the anchor can itself be placed before another option.
        #                             An option whose anchor is not registered, or that is in a cycle of anchors, is not an error: see `option_specs`
        # @raise [ArgumentError] on duplicate option name
        # @return [Option] the registered spec
        def register_option(spec, before: nil)
          raise ArgumentError, "Duplicate option: #{spec.name.inspect}" if @option_specs.key?(spec.name)
          @option_before[spec.name] = before unless before.nil?
          @option_specs[spec.name] = spec
        end

        # @param name [Symbol] option name
        # @return [Boolean] true if an option of this name is registered (no ordering)
        def option_registered?(name)
          @option_specs.key?(name)
        end

        # Options that cannot be placed (the anchor of their `before:` is not registered, or the anchors form a cycle) do not raise,
        # so that a wrong anchor in one module does not break every command: they go at the end, in order of registration,
        # and a warning names each of them and its anchor (logged once per registry, as the list is built several times).
        # @return [Hash{Symbol => Option}] all registered option specs, in order of registration, except those placed before another one (see `register_option`)
        def option_specs
          return @option_specs.dup if @option_before.empty?
          ordered = @option_specs.except(*@option_before.keys)
          pending = @option_before.dup
          until pending.empty?
            # an option whose anchor is itself a pending option waits for the anchor to be placed (chains, whatever the declaration order)
            ready = pending.select { |_name, anchor| ordered.key?(anchor) }
            unless ready.empty?
              ready.each do |name, anchor|
                spec = @option_specs[name]
                ordered = ordered.each_with_object({}) do |(id, other), placed|
                  placed[name] = spec if id.eql?(anchor)
                  placed[id] = other
                end
                pending.delete(name)
              end
              next
            end
            # the remaining ones cannot be placed: unknown anchor, or cycle
            warn_unplaced(pending)
            @option_specs.each { |name, spec| ordered[name] = spec if pending.key?(name) }
            break
          end
          ordered
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
        # @param plugin_class [Class, nil] when given, also verify that methods referenced by Symbol
        #   (implicit and explicit actions, `setup:`, `condition:`, `lookup:`, mount `instance:`) exist
        # @raise [ArgumentError] on any violation
        # @return [self]
        def validate!(plugin_class: nil)
          @children_index.each do |parent_path, children|
            # Rule: every non-root parent path that appears in the children index must have
            # a registered Command. A missing parent means commands_under(:x) was used
            # without a matching command :x declaration.
            unless parent_path.empty? || @specs.key?(parent_path)
              raise ArgumentError,
                "commands_under(#{parent_path.map(&:inspect).join(', ')}) used but #{parent_path.last.inspect} has no command declaration"
            end
            # Rule: an alias designates a single command, and does not hide a sibling command
            aliases = children.values.flat_map { |c| Array(c.aliases) }
            conflicts = aliases.select { |a| children.key?(a) || aliases.count(a) > 1 }.uniq
            raise ArgumentError, "#{parent_path.inspect}: alias conflicts with a sibling command or alias: #{conflicts.inspect}" unless conflicts.empty?
          end

          @specs.each_value do |spec|
            path = spec.full_path

            validate_arguments(path, spec.arguments, plugin_class)
            # Rule: methods called on the plugin instance exist
            if plugin_class
              {setup: spec.setup, condition: spec.condition}.each do |attribute, method_name|
                raise ArgumentError, "#{path.inspect}: no method #{method_name} on #{plugin_class} for #{attribute}:" unless method_name.nil? || instance_method?(plugin_class, method_name)
              end
            end

            if (mount = spec.mount)
              # Rule: a mount needs an instance method, no action, and must point to existing target nodes
              raise ArgumentError, "#{path.inspect}: mount requires instance:" if mount.instance.nil?
              # Mount arguments precede the arguments of the mounted command: they cannot be optional
              raise ArgumentError, "#{path.inspect}: mount arguments must be mandatory" unless mount.arguments.all?(&:mandatory)
              validate_arguments(path, mount.arguments, plugin_class)
              raise ArgumentError, "#{path.inspect}: mount and action: are exclusive" if spec.action
              raise ArgumentError, "#{path.inspect}: mount and read_only: are exclusive" if spec.read_only.eql?(true)
              raise ArgumentError, "#{path.inspect}: mount at #{mount.at.inspect} not found in #{mount.plugin}" unless mount.at.empty? || mount.registry[mount.at]
              target_ids = mount.registry.children_of(mount.at).keys
              unknown = Array(mount.only) + Array(mount.except) - target_ids
              raise ArgumentError, "#{path.inspect}: mount only/except unknown in #{mount.plugin}: #{unknown.inspect}" unless unknown.empty?
              instance_defined = plugin_class.nil? || instance_method?(plugin_class, mount.instance)
              raise ArgumentError, "#{path.inspect}: no method #{mount.instance} on #{plugin_class}" unless instance_defined
              next
            end

            # Rule: only a leaf is executed, so only a leaf is read-only
            raise ArgumentError, "#{path.inspect}: read_only: only on a leaf" if spec.read_only.eql?(true) && @children_index[path]&.any?
            next if @children_index[path]&.any? # intermediate node: skip
            action = spec.action
            if action.nil?
              next unless plugin_class
              # Rule: leaf commands with no explicit action must have a matching instance method
              action = Command.action_method(path)
              unless instance_method?(plugin_class, action)
                raise ArgumentError,
                  "#{path.inspect}: no action: and no method #{action} on #{plugin_class}"
              end
            end
            action = plugin_class.instance_method(action) if action.is_a?(Symbol) && plugin_class && instance_method?(plugin_class, action)
            # Rule: the action receives the whole dispatch context as keywords (setup results, arguments),
            # so it must accept any keyword (`**`): a lambda or method with fixed arity would raise ArgumentError.
            # A non-lambda Proc ignores extra keywords.
            next if action.is_a?(Symbol) || (action.is_a?(Proc) && !action.lambda?)
            raise ArgumentError, "#{path.inspect}: action must accept any keyword (**), parameters: #{action.parameters.inspect}" unless action.parameters.any? { |kind, _| kind.eql?(:keyrest) }
          end
          self
        end

        private

        # As the parser: an exact name, else the unique name starting with word (e.g. `brow` for alias `browse` of `ls`).
        # @param children [Hash{Symbol => Command}] children of a node
        # @param word     [Symbol]                      command line word
        # @return [Symbol, nil] id of the child designated by word: id or alias, or unique prefix of one
        def child_id(children, word)
          # Name (id or alias) => id
          names = children.each_with_object({}) do |(id, spec), h|
            h[id] = id
            Array(spec.aliases).each { |a| h[a] = id }
          end
          return names[word] if names.key?(word)
          matching = names.keys.select { |name| name.to_s.start_with?(word.to_s) }
          names[matching.first] if matching.length.eql?(1)
        end

        # @return [Boolean] true if plugin_class defines instance method name (public or private)
        def instance_method?(plugin_class, name)
          plugin_class.method_defined?(name) || plugin_class.private_method_defined?(name)
        end

        # Consistency of the positional arguments of a node, in reading order.
        # @param path         [Array<Symbol>]       node path, for error messages
        # @param arg_specs    [Array<Argument>] arguments of the node (or of its mount)
        # @param plugin_class [Class, nil]          when given, verify that `lookup:` methods exist
        # @raise [ArgumentError] on any violation
        def validate_arguments(path, arg_specs, plugin_class)
          previous = nil
          Array(arg_specs).each do |arg|
            where = "#{path.inspect}: argument #{arg.name}"
            # Rule: an argument following an optional one, or one that takes all remaining arguments, is never read reliably
            raise ArgumentError, "#{where}: mandatory after optional #{previous.name}" if previous && arg.mandatory && !previous.mandatory
            raise ArgumentError, "#{where}: after #{previous.name}, which takes all remaining arguments" if previous&.multiple.eql?(true)
            raise ArgumentError, "#{where}: complete: #{arg.complete.inspect} is not one of #{Complete::KINDS.inspect}" unless arg.complete.nil? || Complete::KINDS.include?(arg.complete)
            unless arg.lookup.nil?
              # Rule: the percent-selector lookup is only used for identifiers
              raise ArgumentError, "#{where}: lookup: requires type: :identifier" unless arg.type.eql?(:identifier)
              raise ArgumentError, "#{where}: no method #{arg.lookup} on #{plugin_class} for lookup:" if arg.lookup.is_a?(Symbol) && plugin_class && !instance_method?(plugin_class, arg.lookup)
            end
            previous = arg
          end
        end

        # @param path [Array<Symbol>] non-empty path in this registry's namespace
        # @return [Array<Argument>] arguments of the mount exposing the last segment of path, if any
        def mount_arguments(path)
          registry, parent = resolve(path[0..-2])
          return registry.send(:mount_arguments, parent + [path.last]) unless registry.equal?(self)
          mount = @specs[parent]&.mount
          return [] if mount.nil? || @children_index[parent]&.key?(path.last) || !mount.accepts?(path.last)
          mount.arguments
        end

        # Identity of the sub-tree exposed at path: the mount point for a mount node, else the owning node.
        # @return [Array(Integer, Array<Symbol>)]
        def subtree_key(path)
          registry, local_path = resolve(path)
          mount = registry.mount_of(local_path)
          mount ? [mount.registry.object_id, mount.at] : [registry.object_id, local_path]
        end

        # Log a warning for the options that cannot be placed, once per option
        # @param unplaced [Hash{Symbol => Symbol}] option name => anchor
        def warn_unplaced(unplaced)
          fresh = unplaced.reject { |name, _anchor| @option_warned.key?(name) }
          return if fresh.empty?
          fresh.each_key { |name| @option_warned[name] = true }
          Log.log.warn { "Options not placed before their anchor (unknown option or cycle), put at the end: #{fresh.map { |name, anchor| "#{name} before #{anchor}" }.join(', ')}" }
        end

        def initialize
          # Keyed by Array<Symbol> full path
          @specs = {}
          # Keyed by Symbol option name
          @option_specs = {}
          # Option name => name of the option it is placed before
          @option_before = {}
          # Names of the options already reported by warn_unplaced
          @option_warned = {}
          # Children index: parent Array<Symbol> -> Hash{child_id Symbol => Command}
          # Built incrementally in register(); enables O(1) children_of lookups.
          @children_index = {}
        end
      end
    end
  end
end
