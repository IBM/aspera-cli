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
            allow(o).to(receive(:get_next_command)){raise 'get_next_command not stubbed'}
            allow(o).to(receive(:get_next_argument)){raise 'get_next_argument not stubbed'}
            allow(o).to(receive(:instance_identifier)){raise 'instance_identifier not stubbed'}
            # DSL auto-declare stubs: Base#initialize calls these for every OptionSpec
            # found in the ancestor chain (query, bulk, bfail on Base itself).
            allow(o).to(receive(:option_declared?)).and_return(false)
            allow(o).to(receive(:declare))
            allow(o).to(receive(:help_requested)).and_return(false)
            allow(o).to(receive(:command_or_arg_empty?)).and_return(false)
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
          klass.command(:health, description: 'Check health', action: :handle_health)
          klass.command(:info,   description: 'Show info', action: :handle_info)
          # Define handler stubs
          klass.define_method(:handle_health){Result::Status.new('ok')}
          klass.define_method(:handle_info){Result::Status.new('info')}
          klass
        end

        let(:plugin){plugin_class.new(context: context)}

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
            klass.command(:ping, description: 'Ping', action: :do_ping)
            spec = klass.command_registry[[:ping]]
            expect(spec.id).to(eq(:ping))
            expect(spec.description).to(eq('Ping'))
            expect(spec.action).to(eq(:do_ping))
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
            klass.command(:ping, description: 'Ping', action: :do_ping)
            expect{klass.new(context: context)}.not_to(raise_error)
          end

          it 'does not raise even without an execute_action override' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping', action: :do_ping)
            expect{klass.new(context: context)}.not_to(raise_error)
          end
        end

        # ------------------------------------------------------------------
        # execute_action (DSL default)
        # ------------------------------------------------------------------

        describe '#execute_action' do
          it 'calls dispatch_from_registry([]) when DSL commands are registered' do
            allow(options).to(receive(:get_next_command).with(%i[health info], aliases: nil).and_return(:health))
            expect(plugin.execute_action).to(be_a(Result::Status).and(have_attributes(data: 'ok')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — leaf dispatch
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry' do
          it 'dispatches to the correct handler for a root-level command' do
            allow(options).to(receive(:get_next_command).with(%i[health info], aliases: nil).and_return(:info))
            expect(plugin.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'info')))
          end

          it 'passes named arguments resolved by resolve_argument as keyword args to the handler' do
            klass = Class.new(Base)
            klass.command(
              :greet,
              description: 'Greet',
              action:     :handle_greet,
              arguments:   [ArgumentSpec.new(name: :name, type: String)]
            )
            klass.define_method(:handle_greet){ |name:, **| Result::Status.new("hello #{name}")}
            allow(options).to(receive(:get_next_command).with([:greet], aliases: nil).and_return(:greet))
            allow(options).to(receive(:get_next_argument).with('name', mandatory: true, multiple: false, validation: String, accept_list: nil, default: nil, schema: nil).and_return('world'))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'hello world')))
          end

          it 'passes ctx keyword arguments to the handler' do
            klass = Class.new(Base)
            klass.command(:show, description: 'Show', action: :handle_show)
            klass.define_method(:handle_show){ |api:| Result::Status.new("api=#{api}")}
            allow(options).to(receive(:get_next_command).with([:show], aliases: nil).and_return(:show))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([], {api: 'my_api'})).to(be_a(Result::Status).and(have_attributes(data: 'api=my_api')))
          end

          it 'recurses into intermediate nodes' do
            klass = Class.new(Base)
            klass.command(:transfer, description: 'Transfers')
            klass.command(:list, parent: :transfer, description: 'List', action: :handle_list)
            klass.define_method(:handle_list){Result::Status.new('listed')}
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
            klass.command(:child_cmd, parent: :parent_cmd, description: 'Child', action: :handle_child)
            klass.define_method(:build_api){{api: 'built_api'}}
            klass.define_method(:handle_child){ |api:| Result::Status.new("api=#{api}")}
            allow(options).to(receive(:get_next_command).with([:parent_cmd], aliases: nil).and_return(:parent_cmd))
            allow(options).to(receive(:get_next_command).with([:child_cmd], aliases: nil).and_return(:child_cmd))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'api=built_api')))
          end

          it 'merges setup result with existing ctx (setup wins on key collision)' do
            klass = Class.new(Base)
            klass.command(:root_cmd, description: 'Root', setup: :override_api)
            klass.command(:leaf_cmd, parent: :root_cmd, description: 'Leaf', action: :handle_leaf)
            klass.define_method(:override_api){ |**| {api: 'new_api'}}
            klass.define_method(:handle_leaf){ |api:| Result::Status.new("api=#{api}")}
            allow(options).to(receive(:get_next_command).with([:root_cmd], aliases: nil).and_return(:root_cmd))
            allow(options).to(receive(:get_next_command).with([:leaf_cmd], aliases: nil).and_return(:leaf_cmd))
            inst = klass.new(context: context)
            # Pass an existing api in ctx; setup should replace it
            expect(inst.dispatch_from_registry([], {api: 'old_api'})).to(be_a(Result::Status).and(have_attributes(data: 'api=new_api')))
          end

          it 'runs setup: on a leaf command selected via Phase B dispatch' do
            # Mirrors the cos.rb pattern: a single root-level command with both setup: and handler:
            # (no children in DSL registry). The setup must run before the handler is called.
            klass = Class.new(Base)
            klass.command(:node, description: 'Node commands', setup: :build_node, action: :handle_node)
            klass.define_method(:build_node){{node_plugin: 'built_plugin'}}
            klass.define_method(:handle_node){ |node_plugin:| Result::Status.new("plugin=#{node_plugin}")}
            allow(options).to(receive(:get_next_command).with([:node], aliases: nil).and_return(:node))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'plugin=built_plugin')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — condition: filtering
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with condition:' do
          let(:conditional_class) do
            klass = Class.new(Base)
            klass.command(:always,   description: 'Always available', action: :handle_always)
            klass.command(:ssh_only, description: 'SSH only',         action: :handle_ssh, condition: :ssh_available?)
            klass.define_method(:handle_always){Result::Status.new('always')}
            klass.define_method(:handle_ssh){Result::Status.new('ssh')}
            klass
          end

          it 'excludes conditional commands when condition returns false' do
            conditional_class.define_method(:ssh_available?){false}
            allow(options).to(receive(:get_next_command).with([:always], aliases: nil).and_return(:always))
            inst = conditional_class.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'always')))
          end

          it 'includes conditional commands when condition returns true' do
            conditional_class.define_method(:ssh_available?){true}
            allow(options).to(receive(:get_next_command).with(%i[always ssh_only], aliases: nil).and_return(:ssh_only))
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
            klass.command(:files, description: 'Files', action: :handle_files, aliases: [:repository])
            klass.define_method(:handle_files){Result::Status.new('files')}
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
            klass.command(:real_cmd,  description: 'Real',  action: :handle_real)
            klass.define_method(:handle_real){Result::Status.new('real')}
            # Only one get_next_command call for the alias, then none for real_cmd (leaf)
            allow(options).to(receive(:get_next_command).with(%i[alias_cmd real_cmd], aliases: nil).and_return(:alias_cmd))
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
            klass.command(:other_root, description: 'Target root', action: :noop)
            klass.define_method(:build_target){target}
            klass.define_method(:noop){nil}
            allow(options).to(receive(:get_next_command).with(%i[other other_root], aliases: nil).and_return(:other))
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
            klass.command(:upload, description: 'Upload', action: :handle_upload, transfer_paths: :send)
            klass.define_method(:handle_upload){ |**ctx| Result::Status.new("upload ctx_keys=#{ctx.keys.sort.inspect}")}
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
            allow(options).to(receive(:get_next_argument).with('path', mandatory: true, multiple: false, validation: String, accept_list: nil, default: nil, schema: nil).and_return('/tmp/foo'))
            arg_spec = ArgumentSpec.new(name: :path, type: String)
            expect(plugin.resolve_argument(arg_spec)).to(eq('/tmp/foo'))
          end

          it 'passes mandatory: false and default: correctly' do
            allow(options).to(receive(:get_next_argument).with('sync_info', mandatory: false, multiple: false, validation: Hash, accept_list: nil, default: {}, schema: nil).and_return({}))
            arg_spec = ArgumentSpec.new(name: :sync_info, type: Hash, mandatory: false, default: {})
            expect(plugin.resolve_argument(arg_spec)).to(eq({}))
          end

          it 'passes multiple: true correctly' do
            allow(options).to(receive(:get_next_argument).with('files', mandatory: true, multiple: true, validation: String, accept_list: nil, default: nil, schema: nil).and_return(%w[a b]))
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
            klass.command(:list, parent: :transfer, description: 'List transfers', action: :handle_list)
            klass.define_method(:handle_list){nil}
            inst = klass.new(context: context)
            result = inst.generate_help
            expect(result[:transfer][:children]).to(have_key(:list))
          end

          it 'annotates conditional commands with [condition_name]' do
            klass = Class.new(Base)
            klass.command(:ssh_only, description: 'SSH only', action: :handle_ssh, condition: :ssh_available?)
            klass.define_method(:handle_ssh){nil}
            inst = klass.new(context: context)
            result = inst.generate_help
            expect(result[:ssh_only][:description]).to(eq('SSH only [ssh_available?]'))
          end

          it 'sets condition key to the method name symbol for annotated commands' do
            klass = Class.new(Base)
            klass.command(:guarded, description: 'Guarded', action: :handle_guarded, condition: :flag?)
            klass.define_method(:handle_guarded){nil}
            inst = klass.new(context: context)
            expect(inst.generate_help[:guarded][:condition]).to(eq(:flag?))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — entity_execute: shorthand
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with entity_execute:' do
          it 'calls entity_execute with the spec params when command has entity_execute:' do
            stub_api_obj = Object.new
            klass = Class.new(Base)
            klass.command(
              :bridges, description: 'Manage bridges',
              entity_execute: {api: :stub_api, entity: 'bridges'}
            )
            klass.define_method(:stub_api){stub_api_obj}
            allow(options).to(receive(:get_next_command).with([:bridges], aliases: nil).and_return(:bridges))
            allow(options).to(receive(:get_next_command).with(Base::Operations::ALL).and_return(:show))
            inst = klass.new(context: context)
            expect(inst).to(receive(:entity_execute).with(api: stub_api_obj, entity: 'bridges', command: :show).and_return(Result::Status.new('ok')))
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'ok')))
          end

          it 'merges ctx into entity_execute params (spec params win on collision)' do
            spec_api_obj = Object.new
            klass = Class.new(Base)
            klass.command(
              :items, description: 'Manage items',
              entity_execute: {api: :spec_api, entity: 'items'}
            )
            klass.define_method(:spec_api){spec_api_obj}
            allow(options).to(receive(:get_next_command).with([:items], aliases: nil).and_return(:items))
            allow(options).to(receive(:get_next_command).with(Base::Operations::ALL).and_return(:list))
            inst = klass.new(context: context)
            # ctx carries an api key; spec has its own api — spec should win
            expect(inst).to(receive(:entity_execute).with(api: spec_api_obj, entity: 'items', command: :list).and_return(Result::Status.new('ok')))
            inst.dispatch_from_registry([], {api: :ctx_api})
          end

          it 'passes lookup_block from ctx as a block to entity_execute (not as a kwarg)' do
            api_obj = Object.new
            klass = Class.new(Base)
            klass.command(:res, description: 'Resource', entity_execute: {api: :a, entity: 'res'})
            klass.define_method(:a){api_obj}
            allow(options).to(receive(:get_next_command).with([:res], aliases: nil).and_return(:res))
            allow(options).to(receive(:get_next_command).with(Base::Operations::ALL).and_return(:show))
            inst = klass.new(context: context)
            lookup = proc{'found'}
            # lookup_block must NOT be forwarded as a kwarg — only as a block (may be wrapped for instance_exec)
            expect(inst).to(
              receive(:entity_execute).with(api: api_obj, entity: 'res', command: :show) do |**kwargs, &blk|
                expect(kwargs).not_to(have_key(:lookup_block))
                expect(blk).not_to(be_nil)
                Result::Status.new('ok')
              end
            )
            inst.dispatch_from_registry([], {lookup_block: lookup})
          end

          it 'works together with setup: to provide api from ctx' do
            klass = Class.new(Base)
            klass.command(:root_cmd, description: 'Root', setup: :build_stub_api)
            klass.command(
              :bridges, parent: :root_cmd, description: 'Bridges',
              entity_execute: {entity: 'bridges'}
            )
            klass.define_method(:build_stub_api){{api: :ctx_api}}
            allow(options).to(receive(:get_next_command).with([:root_cmd], aliases: nil).and_return(:root_cmd))
            allow(options).to(receive(:get_next_command).with([:bridges], aliases: nil).and_return(:bridges))
            allow(options).to(receive(:get_next_command).with(Base::Operations::ALL).and_return(:list))
            inst = klass.new(context: context)
            # ctx api comes from setup; spec has no api — ctx api is used
            expect(inst).to(receive(:entity_execute).with(api: :ctx_api, entity: 'bridges', command: :list).and_return(Result::Status.new('ok')))
            inst.dispatch_from_registry([])
          end
        end

        # ------------------------------------------------------------------
        # CommandRegistry#register_option
        # ------------------------------------------------------------------

        describe 'CommandRegistry#register_option' do
          let(:registry){CommandRegistry.send(:new)}

          it 'stores and retrieves an OptionSpec by name' do
            spec = OptionSpec.new(name: :verbose, description: 'Verbose mode')
            registry.register_option(spec)
            expect(registry.option_specs[:verbose]).to(be(spec))
          end

          it 'raises on duplicate option name' do
            registry.register_option(OptionSpec.new(name: :verbose, description: 'v1'))
            expect do
              registry.register_option(OptionSpec.new(name: :verbose, description: 'v2'))
            end.to(raise_error(ArgumentError, /Duplicate option/))
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
