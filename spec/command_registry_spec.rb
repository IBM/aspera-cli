# frozen_string_literal: true

require 'aspera/cli/command_registry'
require 'aspera/cli/command_spec'

RSpec.describe(Aspera::Cli::CommandRegistry) do
  subject(:registry) { described_class.send(:new) }

  # Helper: build a minimal CommandSpec
  def spec(id:, parent: nil, **kwargs)
    Aspera::Cli::CommandSpec.new(id: id, parent: parent, **kwargs)
  end

  # -----------------------------------------------------------------------
  # CommandSpec#full_path
  # -----------------------------------------------------------------------
  describe Aspera::Cli::CommandSpec do
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

    it 'maps each child id to its CommandSpec' do
      children = registry.children_of([:transfer])
      expect(children[:list]).to(be_a(Aspera::Cli::CommandSpec))
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

    context 'transfer_paths combined with arguments' do
      it 'does not raise when both transfer_paths and arguments are present' do
        args = [Aspera::Cli::ArgumentSpec.new(name: :path, type: String)]
        registry.register(spec(id: :upload, transfer_paths: :send, arguments: args))
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'does not raise when only transfer_paths is set' do
        registry.register(spec(id: :upload, transfer_paths: :send))
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'does not raise when only arguments are set' do
        args = [Aspera::Cli::ArgumentSpec.new(name: :path, type: String)]
        registry.register(spec(id: :cmd, arguments: args))
        expect { registry.validate! }.not_to(raise_error)
      end
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

    it 'coerces a Hash into a MountSpec with a frozen Array at:' do
      m = spec(id: :files, mount: {plugin: target_class, instance: :build, at: :keys}).mount
      expect(m).to(be_a(Aspera::Cli::MountSpec))
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
      expect(registry.mount_of([:files])).to(be_a(Aspera::Cli::MountSpec))
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

    it 'does not loop on a mount cycle' do
      target_registry.register(spec(id: :again, parent: %i[keys do], mount: {plugin: target_class, instance: :build, at: %i[keys do]}))
      mount_host(at: %i[keys do])
      expect(registry.leaf_paths).to(eq([%i[files ls], %i[files perm list]]))
    end

    describe '#validate!' do
      it 'accepts a valid mount without children or action' do
        mount_host(at: [:keys], only: [:do])
        expect { registry.validate! }.not_to(raise_error)
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
  # ArgumentSpec defaults
  # -----------------------------------------------------------------------
  describe Aspera::Cli::ArgumentSpec do
    it 'defaults mandatory to true' do
      expect(Aspera::Cli::ArgumentSpec.new(name: :x, type: String).mandatory).to(be(true))
    end

    it 'defaults multiple to false' do
      expect(Aspera::Cli::ArgumentSpec.new(name: :x, type: String).multiple).to(be(false))
    end

    it 'accepts mandatory: false' do
      a = Aspera::Cli::ArgumentSpec.new(name: :x, type: String, mandatory: false, default: 'foo')
      expect(a.mandatory).to(be(false))
      expect(a.default).to(eq('foo'))
    end
  end
end
