# frozen_string_literal: true

# Tests for Phase 0b: DSL class methods and dispatcher in Base.
# These tests are intentionally self-contained: they do NOT require spec_helper
# (which needs a live server config) because all dependencies of Base are doubled.

require 'aspera/cli/command_registry'
require 'aspera/cli/command_spec'
require 'aspera/cli/context'
require 'aspera/cli/plugins/base'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Base) do
        # ------------------------------------------------------------------
        # Minimal doubles for Base's context dependencies
        # ------------------------------------------------------------------

        # Minimal options double: get_next_command returns from a pre-set queue.
        let(:options) do
          double('Options').tap do |o|
            # Default stubs — tests override as needed
            allow(o).to(receive(:get_next_command)) { raise 'get_next_command not stubbed' }
            allow(o).to(receive(:get_next_argument)) { raise 'get_next_argument not stubbed' }
            allow(o).to(receive(:instance_identifier)) { raise 'instance_identifier not stubbed' }
          end
        end

        # Build a real Context object with the bare minimum attributes needed by
        # Base#initialize (man_header must be boolean; options is the only member
        # accessed at construction time when man_header is false).
        let(:context) do
          ctx = Context.new
          ctx.man_header = false
          ctx.options    = options
          ctx
        end

        # ------------------------------------------------------------------
        # Concrete DSL plugin subclass used by most tests
        # ------------------------------------------------------------------

        # Build a fresh anonymous DSL plugin class for each test
        # (to avoid registry pollution between tests).
        let(:plugin_class) do
          klass = Class.new(Base)
          # Register two top-level commands
          klass.command(:health, description: 'Check health', handler: :handle_health)
          klass.command(:info,   description: 'Show info',   handler: :handle_info)
          # Define handler stubs
          klass.define_method(:handle_health) { Result::Status.new('ok') }
          klass.define_method(:handle_info)   { Result::Status.new('info') }
          klass
        end

        let(:plugin) { plugin_class.new(context: context) }

        # ------------------------------------------------------------------
        # Class-level DSL accessors
        # ------------------------------------------------------------------

        describe '.command_registry' do
          it 'returns a CommandRegistry for every subclass' do
            expect(plugin_class.command_registry).to(be_a(CommandRegistry))
          end

          it 'is isolated per subclass (not shared with Base)' do
            klass_a = Class.new(Base)
            klass_b = Class.new(Base)
            klass_a.command(:foo, description: 'Foo')
            expect(klass_b.command_registry.any?).to(be(false))
          end

          it 'is not the same object as Base.command_registry' do
            klass = Class.new(Base)
            expect(klass.command_registry).not_to(equal(Base.command_registry))
          end
        end

        describe '.command' do
          it 'registers a CommandSpec in the registry' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping')
            expect(klass.command_registry[[:ping]]).to(be_a(CommandSpec))
          end

          it 'stores the correct id and description' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping', handler: :do_ping)
            spec = klass.command_registry[[:ping]]
            expect(spec.id).to(eq(:ping))
            expect(spec.description).to(eq('Ping'))
            expect(spec.handler).to(eq(:do_ping))
          end
        end

        describe '.option' do
          it 'registers an OptionSpec in the registry' do
            klass = Class.new(Base)
            klass.option(:verbose, description: 'Enable verbose output')
            expect(klass.command_registry.option_specs[:verbose]).to(be_a(OptionSpec))
          end
        end

        # ------------------------------------------------------------------
        # initialize — DSL path skips legacy assertions
        # ------------------------------------------------------------------

        describe '#initialize (DSL mode)' do
          it 'does not raise even without ACTIONS constant' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping', handler: :do_ping)
            expect { klass.new(context: context) }.not_to(raise_error)
          end

          it 'does not raise even without an execute_action override' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping', handler: :do_ping)
            expect { klass.new(context: context) }.not_to(raise_error)
          end
        end

        describe '#initialize (legacy mode)' do
          it 'raises InternalError when ACTIONS is missing and no DSL commands registered' do
            klass = Class.new(Base)
            # Define execute_action but no ACTIONS, no DSL
            klass.define_method(:execute_action) { nil }
            expect { klass.new(context: context) }.to(raise_error(InternalError, /ACTIONS/))
          end
        end

        # ------------------------------------------------------------------
        # execute_action (DSL default)
        # ------------------------------------------------------------------

        describe '#execute_action' do
          it 'calls dispatch_from_registry([]) when DSL commands are registered' do
            allow(options).to(receive(:get_next_command).with([:health, :info], aliases: nil).and_return(:health))
            expect(plugin.execute_action).to(be_a(Result::Status).and(have_attributes(data: 'ok')))
          end

          it 'raises InternalError when no DSL commands are registered (prevents bare Base use)' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping')
            # Remove all commands by creating a fresh-but-empty class
            empty_klass = Class.new(Base)
            # Bypass initialize check by calling send
            instance = empty_klass.allocate
            instance.instance_variable_set(:@context, context)
            expect { instance.execute_action }.to(raise_error(InternalError, /no registered DSL commands/))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — leaf dispatch
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry' do
          it 'dispatches to the correct handler for a root-level command' do
            allow(options).to(receive(:get_next_command).with([:health, :info], aliases: nil).and_return(:info))
            expect(plugin.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'info')))
          end

          it 'passes positional arguments resolved by resolve_argument to the handler' do
            klass = Class.new(Base)
            klass.command(
              :greet,
              description: 'Greet',
              handler:     :handle_greet,
              arguments:   [ArgumentSpec.new(name: :name, type: String)]
            )
            klass.define_method(:handle_greet) { |name| Result::Status.new("hello #{name}") }
            allow(options).to(receive(:get_next_command).with([:greet], aliases: nil).and_return(:greet))
            allow(options).to(receive(:get_next_argument).with('name', mandatory: true, multiple: false, validation: String, default: nil, schema: nil).and_return('world'))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'hello world')))
          end

          it 'passes ctx keyword arguments to the handler' do
            klass = Class.new(Base)
            klass.command(:show, description: 'Show', handler: :handle_show)
            klass.define_method(:handle_show) { |api:| Result::Status.new("api=#{api}") }
            allow(options).to(receive(:get_next_command).with([:show], aliases: nil).and_return(:show))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([], {api: 'my_api'})).to(be_a(Result::Status).and(have_attributes(data: 'api=my_api')))
          end

          it 'recurses into intermediate nodes' do
            klass = Class.new(Base)
            klass.command(:transfer,  description: 'Transfers')
            klass.command(:list, parent: :transfer, description: 'List', handler: :handle_list)
            klass.define_method(:handle_list) { Result::Status.new('listed') }
            allow(options).to(receive(:get_next_command).with([:transfer], aliases: nil).and_return(:transfer))
            allow(options).to(receive(:get_next_command).with([:list], aliases: nil).and_return(:list))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'listed')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — setup: phase
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with setup:' do
          it 'calls setup on the current node and merges result into ctx' do
            klass = Class.new(Base)
            klass.command(:parent_cmd, description: 'Parent', setup: :build_api)
            klass.command(:child_cmd, parent: :parent_cmd, description: 'Child', handler: :handle_child)
            klass.define_method(:build_api) { {api: 'built_api'} }
            klass.define_method(:handle_child) { |api:| Result::Status.new("api=#{api}") }
            allow(options).to(receive(:get_next_command).with([:parent_cmd], aliases: nil).and_return(:parent_cmd))
            allow(options).to(receive(:get_next_command).with([:child_cmd], aliases: nil).and_return(:child_cmd))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'api=built_api')))
          end

          it 'merges setup result with existing ctx (setup wins on key collision)' do
            klass = Class.new(Base)
            klass.command(:root_cmd, description: 'Root', setup: :override_api)
            klass.command(:leaf_cmd, parent: :root_cmd, description: 'Leaf', handler: :handle_leaf)
            klass.define_method(:override_api) { {api: 'new_api'} }
            klass.define_method(:handle_leaf) { |api:| Result::Status.new("api=#{api}") }
            allow(options).to(receive(:get_next_command).with([:root_cmd], aliases: nil).and_return(:root_cmd))
            allow(options).to(receive(:get_next_command).with([:leaf_cmd], aliases: nil).and_return(:leaf_cmd))
            inst = klass.new(context: context)
            # Pass an existing api in ctx; setup should replace it
            expect(inst.dispatch_from_registry([], {api: 'old_api'})).to(be_a(Result::Status).and(have_attributes(data: 'api=new_api')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — condition: filtering
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with condition:' do
          let(:conditional_class) do
            klass = Class.new(Base)
            klass.command(:always,   description: 'Always available', handler: :handle_always)
            klass.command(:ssh_only, description: 'SSH only',         handler: :handle_ssh, condition: :ssh_available?)
            klass.define_method(:handle_always) { Result::Status.new('always') }
            klass.define_method(:handle_ssh)    { Result::Status.new('ssh') }
            klass
          end

          it 'excludes conditional commands when condition returns false' do
            conditional_class.define_method(:ssh_available?) { false }
            allow(options).to(receive(:get_next_command).with([:always], aliases: nil).and_return(:always))
            inst = conditional_class.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'always')))
          end

          it 'includes conditional commands when condition returns true' do
            conditional_class.define_method(:ssh_available?) { true }
            allow(options).to(receive(:get_next_command).with([:always, :ssh_only], aliases: nil).and_return(:ssh_only))
            inst = conditional_class.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'ssh')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — aliases:
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with aliases:' do
          it 'forwards aliases to get_next_command' do
            klass = Class.new(Base)
            klass.command(:files, description: 'Files', handler: :handle_files, aliases: {repository: :files})
            klass.define_method(:handle_files) { Result::Status.new('files') }
            allow(options).to(receive(:get_next_command).with([:files], aliases: {repository: :files}).and_return(:files))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'files')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — delegates_to:
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with delegates_to:' do
          it 'jumps to the delegated path without consuming an extra argument' do
            klass = Class.new(Base)
            klass.command(:alias_cmd, description: 'Alias', delegates_to: :real_cmd)
            klass.command(:real_cmd,  description: 'Real',  handler: :handle_real)
            klass.define_method(:handle_real) { Result::Status.new('real') }
            # Only one get_next_command call for the alias, then none for real_cmd (leaf)
            allow(options).to(receive(:get_next_command).with([:alias_cmd, :real_cmd], aliases: nil).and_return(:alias_cmd))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'real')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — delegate_instance:
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with delegate_instance:' do
          it 'calls dispatch_from_registry on the returned object' do
            target = double('OtherPlugin')
            expect(target).to(receive(:dispatch_from_registry).with([:other_root], {}).and_return(Result::Status.new('delegated')))

            klass = Class.new(Base)
            klass.command(:other, description: 'Delegate', delegate_instance: :build_target, delegates_to: :other_root)
            # register :other_root so validate! would pass (not strictly needed here)
            klass.command(:other_root, description: 'Target root', handler: :noop)
            klass.define_method(:build_target) { target }
            klass.define_method(:noop) { nil }
            allow(options).to(receive(:get_next_command).with([:other, :other_root], aliases: nil).and_return(:other))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'delegated')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — transfer_paths:
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with transfer_paths:' do
          it 'calls the handler with only ctx (no positional args) when transfer_paths is set' do
            klass = Class.new(Base)
            klass.command(:upload, description: 'Upload', handler: :handle_upload, transfer_paths: :send)
            klass.define_method(:handle_upload) { |**ctx| Result::Status.new("upload ctx_keys=#{ctx.keys.sort.inspect}") }
            allow(options).to(receive(:get_next_command).with([:upload], aliases: nil).and_return(:upload))
            inst = klass.new(context: context)
            result = inst.dispatch_from_registry([], {api: 'a'})
            expect(result).to(be_a(Result::Status).and(have_attributes(data: 'upload ctx_keys=[:api]')))
          end
        end

        # ------------------------------------------------------------------
        # resolve_argument
        # ------------------------------------------------------------------

        describe '#resolve_argument' do
          it 'calls instance_identifier for :identifier type' do
            allow(options).to(receive(:instance_identifier).and_return('abc-123'))
            arg_spec = ArgumentSpec.new(name: :id, type: :identifier)
            expect(plugin.resolve_argument(arg_spec)).to(eq('abc-123'))
          end

          it 'calls get_next_argument with correct params for a Class type' do
            allow(options).to(receive(:get_next_argument).with('path', mandatory: true, multiple: false, validation: String, default: nil, schema: nil).and_return('/tmp/foo'))
            arg_spec = ArgumentSpec.new(name: :path, type: String)
            expect(plugin.resolve_argument(arg_spec)).to(eq('/tmp/foo'))
          end

          it 'passes mandatory: false and default: correctly' do
            allow(options).to(receive(:get_next_argument).with('sync_info', mandatory: false, multiple: false, validation: Hash, default: {}, schema: nil).and_return({}))
            arg_spec = ArgumentSpec.new(name: :sync_info, type: Hash, mandatory: false, default: {})
            expect(plugin.resolve_argument(arg_spec)).to(eq({}))
          end

          it 'passes multiple: true correctly' do
            allow(options).to(receive(:get_next_argument).with('files', mandatory: true, multiple: true, validation: String, default: nil, schema: nil).and_return(%w[a b]))
            arg_spec = ArgumentSpec.new(name: :files, type: String, multiple: true)
            expect(plugin.resolve_argument(arg_spec)).to(eq(%w[a b]))
          end
        end

        # ------------------------------------------------------------------
        # generate_help
        # ------------------------------------------------------------------

        describe '#generate_help' do
          it 'returns a hash keyed by command id' do
            result = plugin.generate_help
            expect(result.keys).to(contain_exactly(:health, :info))
          end

          it 'includes description in each entry' do
            result = plugin.generate_help
            expect(result[:health][:description]).to(eq('Check health'))
          end

          it 'returns empty children for leaf commands' do
            result = plugin.generate_help
            expect(result[:health][:children]).to(eq({}))
          end

          it 'recurses into children' do
            klass = Class.new(Base)
            klass.command(:transfer, description: 'Transfers')
            klass.command(:list, parent: :transfer, description: 'List transfers', handler: :handle_list)
            klass.define_method(:handle_list) { nil }
            inst = klass.new(context: context)
            result = inst.generate_help
            expect(result[:transfer][:children]).to(have_key(:list))
          end

          it 'annotates conditional commands with [condition_name]' do
            klass = Class.new(Base)
            klass.command(:ssh_only, description: 'SSH only', handler: :handle_ssh, condition: :ssh_available?)
            klass.define_method(:handle_ssh) { nil }
            inst = klass.new(context: context)
            result = inst.generate_help
            expect(result[:ssh_only][:description]).to(eq('SSH only [ssh_available?]'))
          end

          it 'sets condition key to the method name symbol for annotated commands' do
            klass = Class.new(Base)
            klass.command(:guarded, description: 'Guarded', handler: :handle_guarded, condition: :flag?)
            klass.define_method(:handle_guarded) { nil }
            inst = klass.new(context: context)
            expect(inst.generate_help[:guarded][:condition]).to(eq(:flag?))
          end
        end

        # ------------------------------------------------------------------
        # CommandRegistry#register_option
        # ------------------------------------------------------------------

        describe 'CommandRegistry#register_option' do
          let(:registry) { CommandRegistry.send(:new) }

          it 'stores and retrieves an OptionSpec by name' do
            spec = OptionSpec.new(name: :verbose, description: 'Verbose mode')
            registry.register_option(spec)
            expect(registry.option_specs[:verbose]).to(be(spec))
          end

          it 'raises on duplicate option name' do
            registry.register_option(OptionSpec.new(name: :verbose, description: 'v1'))
            expect {
              registry.register_option(OptionSpec.new(name: :verbose, description: 'v2'))
            }.to(raise_error(ArgumentError, /Duplicate option/))
          end

          it 'returns a dup so mutations do not affect the registry' do
            registry.register_option(OptionSpec.new(name: :foo, description: 'foo'))
            copy = registry.option_specs
            copy[:bar] = :something
            expect(registry.option_specs).not_to(have_key(:bar))
          end
        end
      end
    end
  end
end
