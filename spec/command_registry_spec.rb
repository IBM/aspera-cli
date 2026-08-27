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

  # -----------------------------------------------------------------------
  # validate! — delegates_to unknown path
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

    context 'delegates_to unknown path' do
      it 'raises when delegates_to points to an unregistered path (Symbol)' do
        registry.register(spec(id: :foo, delegates_to: :nonexistent))
        expect { registry.validate! }.to(raise_error(ArgumentError, /delegates_to.*unknown path/))
      end

      it 'raises when delegates_to points to an unregistered path (Array)' do
        registry.register(spec(id: :foo, delegates_to: %i[does not exist]))
        expect { registry.validate! }.to(raise_error(ArgumentError, /delegates_to.*unknown path/))
      end

      it 'does not raise when delegates_to is an empty array (re-enter root)' do
        registry.register(spec(id: :foo, delegates_to: []))
        expect { registry.validate! }.not_to(raise_error)
      end

      it 'does not raise when delegates_to points to a known path' do
        registry.register(spec(id: :target))
        registry.register(spec(id: :foo, delegates_to: :target))
        expect { registry.validate! }.not_to(raise_error)
      end
    end

    context 'delegate_instance without delegates_to' do
      it 'raises when delegate_instance is set but delegates_to is nil' do
        registry.register(spec(id: :foo, delegate_instance: :build_node))
        expect { registry.validate! }.to(raise_error(ArgumentError, /delegate_instance requires delegates_to/))
      end

      it 'does not raise when both delegate_instance and delegates_to are set' do
        registry.register(spec(id: :target))
        registry.register(spec(id: :foo, delegate_instance: :build_node, delegates_to: :target))
        expect { registry.validate! }.not_to(raise_error)
      end
    end

    context 'transfer_paths combined with arguments' do
      it 'raises when both transfer_paths and arguments are present' do
        args = [Aspera::Cli::ArgumentSpec.new(name: :path, type: String)]
        registry.register(spec(id: :upload, transfer_paths: :send, arguments: args))
        expect { registry.validate! }.to(raise_error(ArgumentError, /transfer_paths and arguments are mutually exclusive/))
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
