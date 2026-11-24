# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../lib/aspera/cli/command/registry'
require_relative '../../lib/aspera/cli/command'

RSpec.describe(Aspera::Cli::Command::Registry) do
  subject(:registry) { described_class.send(:new) }

  # Helper: build a minimal Command
  def spec(id:, parent: nil, **kwargs)
    Aspera::Cli::Command.new(id: id, parent: parent, **kwargs)
  end

  # -----------------------------------------------------------------------
  # Command#full_path
  # -----------------------------------------------------------------------
  describe Aspera::Cli::Command do
    describe '#full_path' do
      it 'returns [id] for a root command (parent: nil)' do
        expect(spec(id: :foo).full_path).to(eq([:foo]))
      end

      it 'returns [parent, id] for a Symbol parent' do
        expect(spec(id: :bar, parent: :foo).full_path).to(eq(%i[foo bar]))
      end

      it 'returns parent + [id] for an Array parent' do
        expect(spec(id: :baz, parent: %i[foo bar]).full_path).to(eq(%i[foo bar baz]))
      end
    end
  end

  # -----------------------------------------------------------------------
  # register / []
  # -----------------------------------------------------------------------
  describe '#register and #[]' do
    it 'stores and retrieves a spec by full path' do
      s = spec(id: :foo)
      registry.register(s)
      expect(registry[[:foo]]).to(be(s))
    end

    it 'raises on duplicate full path' do
      registry.register(spec(id: :foo))
      expect { registry.register(spec(id: :foo)) }.to(raise_error(ArgumentError, /Duplicate command path/))
    end

    it 'returns nil for an unknown path' do
      expect(registry[[:unknown]]).to(be_nil)
    end

    it 'places a command before a child of the same parent' do
      %i[first last].each { |id| registry.register(spec(id: id)) }
      registry.register(spec(id: :one, parent: :first))
      registry.register(spec(id: :middle), before: :last)
      registry.register(spec(id: :zero, parent: :first), before: :one)
      expect(registry.children_of([]).keys).to(eq(%i[first middle last]))
      expect(registry.children_of([:first]).keys).to(eq(%i[zero one]))
      expect(registry[[:middle]]).not_to(be_nil)
    end

    it 'refuses to place a command before a command that is not a child of the same parent' do
      registry.register(spec(id: :first))
      registry.register(spec(id: :one, parent: :first))
      expect { registry.register(spec(id: :two), before: :one) }.to(raise_error(ArgumentError, '[:two]: no command :one to place it before'))
      expect(registry[[:two]]).to(be_nil)
    end
  end

  # -----------------------------------------------------------------------
  # children_of
  # -----------------------------------------------------------------------
  describe '#children_of' do
    before do
      registry.register(spec(id: :transfer))
      registry.register(spec(id: :list,   parent: :transfer))
      registry.register(spec(id: :cancel, parent: :transfer))
      registry.register(spec(id: :info))
    end

    it 'returns direct children of a path' do
      children = registry.children_of([:transfer])
      expect(children.keys).to(contain_exactly(:list, :cancel))
    end

    it 'maps each child id to its Command' do
      children = registry.children_of([:transfer])
      expect(children[:list]).to(be_a(Aspera::Cli::Command))
      expect(children[:list].id).to(eq(:list))
    end

    it 'returns root-level commands for an empty path' do
      children = registry.children_of([])
      expect(children.keys).to(contain_exactly(:transfer, :info))
    end

    it 'returns empty hash when no children exist' do
      expect(registry.children_of([:info])).to(eq({}))
    end

    it 'does not include grandchildren' do
      registry.register(spec(id: :deep, parent: %i[transfer list]))
      children = registry.children_of([:transfer])
      expect(children.keys).not_to(include(:deep))
    end
  end

  # -----------------------------------------------------------------------
  # all_paths / any?
  # -----------------------------------------------------------------------
  describe '#all_paths' do
    it 'returns an empty array when nothing is registered' do
      expect(registry.all_paths).to(eq([]))
    end

    it 'returns all registered full paths' do
      registry.register(spec(id: :foo))
      registry.register(spec(id: :bar, parent: :foo))
      expect(registry.all_paths).to(contain_exactly([:foo], %i[foo bar]))
    end
  end

  describe '#any?' do
    it 'is false when empty' do
      expect(registry.any?).to(be(false))
    end

    it 'is true after registration' do
      registry.register(spec(id: :foo))
      expect(registry.any?).to(be(true))
    end
  end

  describe '#none?' do
    it 'is true when empty' do
      expect(registry.none?).to(be(true))
    end

    it 'is false after registration' do
      registry.register(spec(id: :foo))
      expect(registry.none?).to(be(false))
    end

    it 'is the inverse of any?' do
      expect(registry.none?).to(eq(!registry.any?))
      registry.register(spec(id: :foo))
      expect(registry.none?).to(eq(!registry.any?))
    end
  end

  # -----------------------------------------------------------------------
  # validate!
  # -----------------------------------------------------------------------
  describe '#validate!' do
    it 'passes when the registry is empty' do
      expect { registry.validate! }.not_to(raise_error)
    end

    it 'passes for a well-formed registry' do
      registry.register(spec(id: :parent_cmd))
      registry.register(spec(id: :child_cmd, parent: :parent_cmd))
      expect { registry.validate! }.not_to(raise_error)
    end

    context 'action arity' do
      let(:plugin_class) { Class.new { def action_leaf(**) = nil; def action_fixed = nil } } # rubocop:disable Style/Semicolon

      it 'passes for lambda and method actions accepting **' do
        registry.register(spec(id: :lambda, action: ->(**) {}))
        registry.register(spec(id: :leaf))
        registry.register(spec(id: :proc, action: proc {}))
        expect { registry.validate!(plugin_class: plugin_class) }.not_to(raise_error)
      end

      it 'raises for a lambda without **' do
        registry.register(spec(id: :lambda, action: -> {}))
        expect { registry.validate! }.to(raise_error(ArgumentError, /must accept any keyword/))
      end

      it 'raises for a lambda with only named keywords' do
        registry.register(spec(id: :lambda, action: ->(api:) { api }))
        expect { registry.validate! }.to(raise_error(ArgumentError, /must accept any keyword/))
      end

      it 'raises for an implicit method without **' do
        registry.register(spec(id: :fixed))
        expect { registry.validate!(plugin_class: plugin_class) }.to(raise_error(ArgumentError, /must accept any keyword/))
      end

      it 'raises for an explicit Symbol action without **' do
        registry.register(spec(id: :other, action: :action_fixed))
        expect { registry.validate!(plugin_class: plugin_class) }.to(raise_error(ArgumentError, /must accept any keyword/))
      end
    end

    context 'methods referenced by Symbol' do
      let(:plugin_class) { Class.new { def setup_ok(**) = {}; def lookup_ok(*, **) = nil } } # rubocop:disable Style/Semicolon
      let(:leaf_action) { ->(**) {} }

      it 'passes when setup:, condition: and lookup: methods exist' do
        args = [{name: :id, type: :identifier, lookup: :lookup_ok}]
        registry.register(spec(id: :leaf, action: leaf_action, setup: :setup_ok, condition: :setup_ok, arguments: args))
        expect { registry.validate!(plugin_class: plugin_class) }.not_to(raise_error)
      end

      it 'raises for a missing setup: method' do
        registry.register(spec(id: :leaf, action: leaf_action, setup: :nope))
        expect { registry.validate!(plugin_class: plugin_class) }.to(raise_error(ArgumentError, /no method nope .* for setup:/))
      end

      it 'raises for a missing condition: method' do
        registry.register(spec(id: :leaf, action: leaf_action, condition: :nope))
        expect { registry.validate!(plugin_class: plugin_class) }.to(raise_error(ArgumentError, /no method nope .* for condition:/))
      end

      it 'raises for a missing lookup: method' do
        registry.register(spec(id: :leaf, action: leaf_action, arguments: [{name: :id, type: :identifier, lookup: :nope}]))
        expect { registry.validate!(plugin_class: plugin_class) }.to(raise_error(ArgumentError, /no method nope .* for lookup:/))
      end

      it 'does not check methods without plugin_class' do
        registry.register(spec(id: :leaf, action: leaf_action, setup: :nope))
        expect { registry.validate! }.not_to(raise_error)
      end
    end

    context 'arguments' do
      let(:leaf_action) { ->(**) {} }

      it 'raises for lookup: on an argument that is not an identifier' do
        registry.register(spec(id: :leaf, action: leaf_action, arguments: [{name: :id, lookup: :lookup_ok}]))
        expect { registry.validate! }.to(raise_error(ArgumentError, /requires type: :identifier/))
      end

      it 'raises for a mandatory argument after an optional one' do
        registry.register(spec(id: :leaf, action: leaf_action, arguments: [{name: :a, mandatory: false}, {name: :b}]))
        expect { registry.validate! }.to(raise_error(ArgumentError, /argument b: mandatory after optional a/))
      end

      it 'raises for an argument after one taking all remaining arguments' do
        registry.register(spec(id: :leaf, action: leaf_action, arguments: [{name: :a, multiple: true}, {name: :b, mandatory: false}]))
        expect { registry.validate! }.to(raise_error(ArgumentError, /argument b: after a/))
      end

      it 'accepts an argument after one read until a marker' do
        registry.register(spec(id: :leaf, action: leaf_action, arguments: [{name: :a, multiple: '--'}, {name: :b}]))
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'raises for an unknown kind of completion' do
        registry.register(spec(id: :leaf, action: leaf_action, arguments: [{name: :a, complete: :file}, {name: :b, complete: :nope}]))
        expect { registry.validate! }.to(raise_error(ArgumentError, /argument b: complete: :nope is not one of/))
      end
    end

    context 'aliases' do
      let(:leaf_action) { ->(**) {} }

      it 'raises for an alias equal to a sibling command' do
        registry.register(spec(id: :ls, action: leaf_action, aliases: [:list]))
        registry.register(spec(id: :list, action: leaf_action))
        expect { registry.validate! }.to(raise_error(ArgumentError, /alias conflicts .*:list/))
      end

      it 'raises for an alias of two sibling commands' do
        registry.register(spec(id: :ls, action: leaf_action, aliases: [:browse]))
        registry.register(spec(id: :find, action: leaf_action, aliases: [:browse]))
        expect { registry.validate! }.to(raise_error(ArgumentError, /alias conflicts .*:browse/))
      end

      it 'accepts the same alias under different parents' do
        registry.register(spec(id: :a))
        registry.register(spec(id: :b))
        registry.register(spec(id: :ls, parent: :a, action: leaf_action, aliases: [:browse]))
        registry.register(spec(id: :ls, parent: :b, action: leaf_action, aliases: [:browse]))
        expect { registry.validate! }.not_to(raise_error)
      end
    end

    context 'transfer_paths combined with arguments' do
      it 'does not raise when both transfer_paths and arguments are present' do
        args = [Aspera::Cli::Argument.new(name: :path, type: String)]
        registry.register(spec(id: :upload, transfer_paths: :send, arguments: args))
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'does not raise when only transfer_paths is set' do
        registry.register(spec(id: :upload, transfer_paths: :send))
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'does not raise when only arguments are set' do
        args = [Aspera::Cli::Argument.new(name: :path, type: String)]
        registry.register(spec(id: :cmd, arguments: args))
        expect { registry.validate! }.not_to(raise_error)
      end
    end
  end

  # -----------------------------------------------------------------------
  # command_path
  # -----------------------------------------------------------------------
  describe '#command_path' do
    before do
      registry.register(spec(id: :packages))
      registry.register(spec(id: :receive, parent: :packages, action: :x, aliases: [:recv], arguments: [{name: :package_id}]))
      registry.register(spec(id: :do, parent: :packages, arguments: [{name: :id}]))
      registry.register(spec(id: :ls, parent: %i[packages do], action: :x))
    end

    it 'follows sub-commands and aliases, and stops at a leaf' do
      expect(registry.command_path(%i[packages recv ALL extra])).to(eq([%i[packages receive], nil]))
    end

    it 'skips the arguments of intermediate nodes' do
      expect(registry.command_path(%i[packages do 42 ls])).to(eq([%i[packages do ls], nil]))
    end

    it 'returns the first word that is neither a command nor an expected argument' do
      expect(registry.command_path(%i[packages nope])).to(eq([%i[packages], :nope]))
      expect(registry.command_path(%i[packages do 42 43])).to(eq([%i[packages do], :'43']))
    end
  end

  # -----------------------------------------------------------------------
  # command_position
  # -----------------------------------------------------------------------
  describe '#command_position' do
    before do
      registry.register(spec(id: :packages))
      registry.register(spec(id: :receive, parent: :packages, action: :x, aliases: [:recv], arguments: [{name: :package_id}]))
      registry.register(spec(id: :send, parent: :packages, action: :x, arguments: [{name: :paths, multiple: true}]))
      registry.register(spec(id: :do, parent: :packages, arguments: [{name: :id}]))
      registry.register(spec(id: :ls, parent: %i[packages do], action: :x))
    end

    it 'counts the arguments given to the command' do
      expect(registry.command_position([])).to(eq([[], 0]))
      expect(registry.command_position(%i[packages recv])).to(eq([%i[packages receive], 0]))
      expect(registry.command_position(%i[packages receive 42])).to(eq([%i[packages receive], 1]))
      expect(registry.command_position(%i[packages send a b c])).to(eq([%i[packages send], 3]))
    end

    it 'reads the arguments of an intermediate command before its sub-command' do
      expect(registry.command_position(%i[packages do])).to(eq([%i[packages do], 0]))
      expect(registry.command_position(%i[packages do ls])).to(eq([%i[packages do], 1]))
      expect(registry.command_position(%i[packages do 42 ls])).to(eq([%i[packages do ls], 0]))
    end

    it 'accepts a unique prefix of a command or alias, as the parser' do
      expect(registry.command_position(%i[pack rece 42])).to(eq([%i[packages receive], 1]))
      expect(registry.command_position(%i[packages recv])).to(eq([%i[packages receive], 0]))
      expect(registry.command_position(%i[packages rec])).to(be_nil)
    end

    it 'returns nil for a word that is neither a command nor an expected argument' do
      expect(registry.command_position(%i[nope])).to(be_nil)
      expect(registry.command_position(%i[packages receive 42 43])).to(be_nil)
      expect(registry.command_position(%i[packages do 42 43])).to(be_nil)
    end
  end

  # -----------------------------------------------------------------------
  # mount:
  # -----------------------------------------------------------------------
  describe 'mount:' do
    # target tree: info, keys > (list, do > (ls, perm > list))
    let(:target_registry) do
      described_class.send(:new).tap do |r|
        r.register(spec(id: :info, action: :x))
        r.register(spec(id: :keys))
        r.register(spec(id: :list, parent: :keys, action: :x))
        r.register(spec(id: :do, parent: :keys))
        r.register(spec(id: :ls, parent: %i[keys do], action: :x))
        r.register(spec(id: :perm, parent: %i[keys do]))
        r.register(spec(id: :list, parent: %i[keys do perm], action: :x))
      end
    end
    let(:target_class) { double('TargetPlugin', command_registry: target_registry) }

    def mount_host(**mount)
      registry.register(spec(id: :files, mount: {plugin: target_class, instance: :build, **mount}))
      registry
    end

    it 'coerces a Hash into a Command::Mount with a frozen Array at:' do
      m = spec(id: :files, mount: {plugin: target_class, instance: :build, at: :keys}).mount
      expect(m).to(be_a(Aspera::Cli::Command::Mount))
      expect(m.at).to(eq([:keys]))
    end

    it 'exposes the children of the mount point' do
      mount_host(at: %i[keys do])
      expect(registry.children_of([:files]).keys).to(eq(%i[ls perm]))
    end

    it 'resolves deep paths into the target namespace' do
      mount_host(at: %i[keys do])
      expect(registry.resolve(%i[files perm list])).to(eq([target_registry, %i[keys do perm list]]))
      expect(registry[%i[files perm list]]).to(be(target_registry[%i[keys do perm list]]))
      expect(registry.children_of(%i[files perm]).keys).to(eq([:list]))
    end

    it 'reports local and mounted paths' do
      mount_host(at: %i[keys do])
      expect(registry.local?([:files])).to(be(true))
      expect(registry.local?(%i[files ls])).to(be(false))
      expect(registry.mount_of([:files])).to(be_a(Aspera::Cli::Command::Mount))
    end

    it 'filters with only: and except:' do
      mount_host(only: %i[info keys], except: %i[info])
      expect(registry.children_of([:files]).keys).to(eq([:keys]))
      expect(registry[%i[files info]]).to(be_nil)
    end

    it 'lets a host child override a mounted child with the same id' do
      mount_host
      registry.register(spec(id: :info, parent: :files, action: :mine))
      expect(registry.children_of([:files]).keys).to(eq(%i[info keys]))
      expect(registry[%i[files info]].action).to(eq(:mine))
      expect(registry.local?(%i[files info])).to(be(true))
    end

    it 'lists leaf paths through the mount' do
      registry.register(spec(id: :other, action: :x))
      mount_host(at: [:keys])
      expect(registry.leaf_paths).to(eq([[:other], %i[files list], %i[files do ls], %i[files do perm list]]))
    end

    it 'stops at the mount node, keeping its own children, when not expanding mounts' do
      registry.register(spec(id: :other, action: :x))
      mount_host(at: [:keys])
      registry.register(spec(id: :mine, parent: :files, action: :y))
      expect(registry.own_children_of([:files]).keys).to(eq([:mine]))
      expect(registry.leaf_paths(expand_mounts: false)).to(eq([[:other], [:files], %i[files mine]]))
    end

    it 'finds the mount of a node reached through a mount' do
      target_registry.register(spec(id: :nested, parent: %i[keys do], mount: {plugin: target_class, instance: :build, at: [:keys]}))
      mount_host(at: %i[keys do])
      expect(registry.mount_at([:files])).to(be_a(Aspera::Cli::Command::Mount))
      expect(registry.mount_at(%i[files nested]).at).to(eq([:keys]))
      expect(registry.mount_at(%i[files ls])).to(be_nil)
    end

    it 'lists leaf paths under a path inside the mount' do
      mount_host(at: [:keys])
      expect(registry.leaf_paths([:files], expand_mounts: false)).to(eq([%i[files list], %i[files do ls], %i[files do perm list]]))
    end

    it 'does not loop on a mount cycle' do
      target_registry.register(spec(id: :again, parent: %i[keys do], mount: {plugin: target_class, instance: :build, at: %i[keys do]}))
      mount_host(at: %i[keys do])
      expect(registry.leaf_paths).to(eq([%i[files ls], %i[files perm list]]))
    end

    describe '#arguments_at' do
      let(:target_ls_args) { [{name: :path, type: String}] }

      before do
        target_registry.register(spec(id: :find, parent: %i[keys do], action: :x, arguments: target_ls_args))
        registry.register(spec(id: :local, parent: :files, action: :x, arguments: [{name: :name}]))
      end

      it 'prepends the mount arguments to the arguments of a mounted command' do
        mount_host(at: %i[keys do], arguments: [{name: :package_id, type: :identifier}])
        expect(registry.arguments_at(%i[files find]).map(&:name)).to(eq(%i[package_id path]))
      end

      it 'does not apply the mount arguments to host children, nor below the mounted command' do
        mount_host(at: %i[keys do], arguments: [{name: :package_id, type: :identifier}])
        expect(registry.arguments_at(%i[files local]).map(&:name)).to(eq([:name]))
        expect(registry.arguments_at(%i[files perm list])).to(eq([]))
      end

      it 'returns only the node arguments without mount arguments' do
        mount_host(at: %i[keys do])
        expect(registry.arguments_at(%i[files find]).map(&:name)).to(eq([:path]))
        expect(registry.arguments_at([])).to(eq([]))
      end
    end

    describe '#validate!' do
      it 'accepts a valid mount without children or action' do
        mount_host(at: [:keys], only: [:do])
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'raises when a mount argument is optional' do
        mount_host(arguments: [{name: :package_id, mandatory: false}])
        expect { registry.validate! }.to(raise_error(ArgumentError, /must be mandatory/))
      end

      it 'raises when instance: is missing' do
        registry.register(spec(id: :files, mount: {plugin: target_class}))
        expect { registry.validate! }.to(raise_error(ArgumentError, /mount requires instance/))
      end

      it 'raises when combined with action:' do
        registry.register(spec(id: :files, action: :x, mount: {plugin: target_class, instance: :build}))
        expect { registry.validate! }.to(raise_error(ArgumentError, /exclusive/))
      end

      it 'raises when at: does not exist in the target' do
        mount_host(at: [:nope])
        expect { registry.validate! }.to(raise_error(ArgumentError, /not found/))
      end

      it 'raises on unknown only:/except: ids' do
        mount_host(only: %i[info nope])
        expect { registry.validate! }.to(raise_error(ArgumentError, /unknown.*nope/))
      end

      it 'raises when the instance method is missing on the plugin class' do
        mount_host
        expect { registry.validate!(plugin_class: Class.new) }.to(raise_error(ArgumentError, /no method build/))
      end
    end
  end

  # -----------------------------------------------------------------------
  # Argument defaults
  # -----------------------------------------------------------------------
  describe Aspera::Cli::Argument do
    it 'evaluates allowed values given as a callable each time they are read, and gives a list as it is' do
      values = %i[a]
      spec = Aspera::Cli::Argument.new(name: :x, allowed: -> { values })
      expect(spec.allowed).to(eq(%i[a]))
      values = %i[a b]
      expect(spec.allowed).to(eq(%i[a b]))
      expect(spec.syntax).to(eq('<a|b>'))
      expect(Aspera::Cli::Argument.new(name: :x, allowed: %i[c]).allowed).to(eq(%i[c]))
      expect(Aspera::Cli::Argument.new(name: :x).allowed).to(be_nil)
    end

    it 'defaults mandatory to true' do
      expect(Aspera::Cli::Argument.new(name: :x, type: String).mandatory).to(be(true))
    end

    it 'defaults multiple to false' do
      expect(Aspera::Cli::Argument.new(name: :x, type: String).multiple).to(be(false))
    end

    it 'accepts mandatory: false' do
      a = Aspera::Cli::Argument.new(name: :x, type: String, mandatory: false, default: 'foo')
      expect(a.mandatory).to(be(false))
      expect(a.default).to(eq('foo'))
    end

    it 'defaults omit_absent to false, and accepts it for an optional argument' do
      expect(Aspera::Cli::Argument.new(name: :x).omit_absent).to(be(false))
      expect(Aspera::Cli::Argument.new(name: :x, mandatory: false, omit_absent: true).omit_absent).to(be(true))
    end

    it 'refuses omit_absent for a mandatory argument' do
      expect { Aspera::Cli::Argument.new(name: :x, omit_absent: true) }.to(raise_error(ArgumentError, /omit_absent/))
    end
  end

  # -----------------------------------------------------------------------
  # Options: order, placement before another option
  # -----------------------------------------------------------------------
  describe '#register_option' do
    # @param names [Array<Symbol>] Options to register, a Hash `name => anchor` places it before the anchor
    def register(*names)
      names.each do |name|
        name, before = name.is_a?(Hash) ? name.first : [name, nil]
        registry.register_option(Aspera::Cli::Option.new(name: name), before: before)
      end
      registry.option_specs.keys
    end

    it 'keeps the order of registration' do
      expect(register(:a, :b, :c)).to(eq(%i[a b c]))
    end

    it 'places an option before another one, also registered later, in their order of registration' do
      expect(register(:a, {x: :c}, {y: :c}, :b, :c, :d)).to(eq(%i[a b x y c d]))
      expect(register({z: :a})).to(eq(%i[z a b x y c d]))
    end

    it 'places a chain of options before an anchor, whatever the declaration order' do
      expect(register({x: :y}, {y: :smtp}, :a, :smtp)).to(eq(%i[a x y smtp]))
    end

    it 'places a chain of options when the anchors are declared first' do
      expect(register({y: :smtp}, {x: :y}, :a, :smtp)).to(eq(%i[a x y smtp]))
    end

    context 'when an option cannot be placed' do
      before { allow(Aspera::Log.log).to(receive(:warn)) }

      it 'puts an option whose anchor is never registered at the end, with one warning' do
        expect(register(:a, {x: :none}, :b)).to(eq(%i[a b x]))
        3.times { registry.option_specs }
        expect(Aspera::Log.log).to(have_received(:warn).once)
        expect(Aspera::Log.log).to(have_received(:warn) { |&block| expect(block.call).to(include('x before none')) })
      end

      it 'puts the options of a cycle at the end, in order of registration, with one warning' do
        expect(register({x: :y}, :a, {y: :x}, :b)).to(eq(%i[a b x y]))
        registry.option_specs
        expect(Aspera::Log.log).to(have_received(:warn).once)
        expect(Aspera::Log.log).to(have_received(:warn) { |&block| expect(block.call).to(include('x before y, y before x')) })
      end

      it 'keeps the chains that can be placed' do
        expect(register({x: :y}, {y: :smtp}, {z: :none}, :a, :smtp)).to(eq(%i[a x y smtp z]))
      end

      it 'does not warn when every option can be placed' do
        register({x: :y}, :y)
        expect(Aspera::Log.log).not_to(have_received(:warn))
      end
    end

    it 'refuses a duplicate option' do
      register(:a)
      expect { register({a: :b}) }.to(raise_error(ArgumentError, /Duplicate option: :a/))
    end
  end
end
