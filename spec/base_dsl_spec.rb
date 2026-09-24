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
            # DSL auto-declare stubs: Base#initialize calls these for every OptionSpec
            # found in the ancestor chain (query, bulk, bfail on Base itself).
            allow(o).to(receive(:option_declared?)).and_return(false)
            allow(o).to(receive(:declare))
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
          klass.define_method(:handle_health) { Result::Status.new('ok') }
          klass.define_method(:handle_info) { Result::Status.new('info') }
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

        describe '.file_matcher' do
          it 'returns a matching lambda for a glob' do
            matcher = described_class.file_matcher('*.mp4')

            expect(matcher.call({'name' => 'movie.mp4'})).to(be(true))
            expect(matcher.call({'name' => 'movie.mov'})).to(be(false))
          end

          it 'returns a matching lambda for a regular expression' do
            matcher = described_class.file_matcher(/\.mp4\z/)

            expect(matcher.call({'name' => 'movie.mp4'})).to(be(true))
            expect(matcher.call({'name' => 'movie.mov'})).to(be(false))
          end

          it 'returns the supplied Proc unchanged' do
            matcher = ->(entry) { entry['size'] > 0 }

            expect(described_class.file_matcher(matcher)).to(be(matcher))
          end

          it 'matches every entry when no filter is supplied' do
            expect(described_class.file_matcher(nil).call({'name' => 'any'})).to(be(true))
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

        describe '.use_options' do
          it 'includes options from another Base plugin class' do
            source_klass = Class.new(Base) do
              option(:source_opt, description: 'From source plugin')
            end
            target_klass = Class.new(Base) do
              use_options source_klass
              option(:target_opt, description: 'From target plugin')
            end
            expect(target_klass.used_option_sources).to(include(source_klass))
            target_klass.new(context: context)
            # Both source_opt and target_opt should be declared on options
            expect(options).to(have_received(:declare).with(:source_opt, hash_including(description: 'From source plugin')))
            expect(options).to(have_received(:declare).with(:target_opt, hash_including(description: 'From target plugin')))
          end

          it 'includes options from an OptionDeclarator module' do
            source_mod = Module.new do
              extend OptionDeclarator

              option(:mod_opt, description: 'From module')
            end
            target_klass = Class.new(Base) do
              use_options source_mod
            end
            target_klass.new(context: context)
            expect(options).to(have_received(:declare).with(:mod_opt, hash_including(description: 'From module')))
          end
        end

        describe '.declare_options' do
          it 'declares all options on the given parser' do
            klass = Class.new(Base) do
              option(:custom_opt, description: 'Custom option')
            end
            parser = instance_double(Parser)
            allow(parser).to(receive(:option_declared?).and_return(false))
            allow(parser).to(receive(:declare))
            allow(parser).to(receive(:parse_options!))

            klass.declare_options(parser, parse: true)
            expect(parser).to(have_received(:declare).with(:custom_opt, hash_including(description: 'Custom option')))
            expect(parser).to(have_received(:parse_options!))
          end
        end

        # ------------------------------------------------------------------
        # initialize — DSL path skips legacy assertions
        # ------------------------------------------------------------------

        describe '#initialize (DSL mode)' do
          it 'does not raise even without ACTIONS constant' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping', action: :do_ping)
            expect { klass.new(context: context) }.not_to(raise_error)
          end

          it 'does not raise even without an execute_action override' do
            klass = Class.new(Base)
            klass.command(:ping, description: 'Ping', action: :do_ping)
            expect { klass.new(context: context) }.not_to(raise_error)
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
            klass.define_method(:handle_greet) { |name:, **| Result::Status.new("hello #{name}") }
            allow(options).to(receive(:get_next_command).with([:greet], aliases: nil).and_return(:greet))
            allow(options).to(receive(:get_next_argument).with('name', mandatory: true, multiple: false, validation: String, accept_list: nil, default: nil, schema: nil).and_return('world'))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'hello world')))
          end

          it 'passes ctx keyword arguments to the handler' do
            klass = Class.new(Base)
            klass.command(:show, description: 'Show', action: :handle_show)
            klass.define_method(:handle_show) { |api:| Result::Status.new("api=#{api}") }
            allow(options).to(receive(:get_next_command).with([:show], aliases: nil).and_return(:show))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([], {api: 'my_api'})).to(be_a(Result::Status).and(have_attributes(data: 'api=my_api')))
          end

          it 'recurses into intermediate nodes' do
            klass = Class.new(Base)
            klass.command(:transfer, description: 'Transfers')
            klass.command(:list, parent: :transfer, description: 'List', action: :handle_list)
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
            klass.command(:child_cmd, parent: :parent_cmd, description: 'Child', action: :handle_child)
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
            klass.command(:leaf_cmd, parent: :root_cmd, description: 'Leaf', action: :handle_leaf)
            klass.define_method(:override_api) { |**| {api: 'new_api'} }
            klass.define_method(:handle_leaf) { |api:| Result::Status.new("api=#{api}") }
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
            klass.define_method(:build_node) { {node_plugin: 'built_plugin'} }
            klass.define_method(:handle_node) { |node_plugin:| Result::Status.new("plugin=#{node_plugin}") }
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
            klass.define_method(:handle_always) { Result::Status.new('always') }
            klass.define_method(:handle_ssh) { Result::Status.new('ssh') }
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
            klass.define_method(:handle_files) { Result::Status.new('files') }
            allow(options).to(receive(:get_next_command).with([:files], aliases: {repository: :files}).and_return(:files))
            inst = klass.new(context: context)
            expect(inst.dispatch_from_registry([])).to(be_a(Result::Status).and(have_attributes(data: 'files')))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — mount:
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with mount:' do
          # Target: keys > do (setup must NOT run through the mount) > (ls, perm (setup) > list)
          let(:target_class) do
            Class.new(Base).tap do |k|
              k.command(:keys, description: 'Keys')
              k.command(:do, parent: :keys, description: 'Do', setup: :setup_do)
              k.command(:ls, parent: %i[keys do], description: 'List', action: ->(root:, **) { Result::Status.new("ls #{root}") })
              k.command(:perm, parent: %i[keys do], description: 'Perm', setup: :setup_perm, condition: :never?)
              k.command(:list, parent: %i[keys do perm], description: 'List perms', action: ->(root:, perm_setup:, **) { Result::Status.new("perm #{root} #{perm_setup}") })
              k.define_method(:setup_do) { |**| raise 'setup of mount point must not run' }
              k.define_method(:setup_perm) { |**| {perm_setup: 'done'} }
              k.define_method(:never?) { raise 'condition of mounted command must not be evaluated on host' }
            end
          end

          let(:host_class) do
            tc = target_class
            Class.new(Base).tap do |k|
              k.command(:files, description: 'Files', setup: :setup_files, mount: {plugin: tc, at: %i[keys do], instance: :build_target})
              k.command(:extra, parent: :files, description: 'Host command', action: ->(**) { Result::Status.new('extra') })
              k.define_method(:setup_files) { |**| {host_value: 'h'} }
              k.define_method(:build_target) { |host_value:, **| [tc.new(context: context), {root: "r-#{host_value}"}] }
            end
          end

          it 'dispatches a mounted leaf on the target instance with the seed ctx' do
            allow(options).to(receive(:get_next_command).with([:files], aliases: nil).and_return(:files))
            allow(options).to(receive(:get_next_command).with(%i[ls perm extra], aliases: nil).and_return(:ls))
            expect(host_class.new(context: context).dispatch_from_registry([])).to(have_attributes(data: 'ls r-h'))
          end

          it 'runs setups below the mount point in the target' do
            target_class.define_method(:never?) { true }
            allow(options).to(receive(:get_next_command).with([:files], aliases: nil).and_return(:files))
            allow(options).to(receive(:get_next_command).with(%i[ls perm extra], aliases: nil).and_return(:perm))
            allow(options).to(receive(:get_next_command).with([:list], aliases: nil).and_return(:list))
            expect(host_class.new(context: context).dispatch_from_registry([])).to(have_attributes(data: 'perm r-h done'))
          end

          it 'dispatches host children locally' do
            allow(options).to(receive(:get_next_command).with([:files], aliases: nil).and_return(:files))
            allow(options).to(receive(:get_next_command).with(%i[ls perm extra], aliases: nil).and_return(:extra))
            expect(host_class.new(context: context).dispatch_from_registry([])).to(have_attributes(data: 'extra'))
          end

          it 'accepts an instance method returning only the target' do
            tc = target_class
            host_class.define_method(:build_target) { |**| tc.new(context: context) }
            tc.command(:info, description: 'Info', action: -> { Result::Status.new('info') })
            host_class.command(:root, description: 'Root', mount: {plugin: tc, instance: :build_target})
            allow(options).to(receive(:get_next_command).with(%i[files root], aliases: nil).and_return(:root))
            allow(options).to(receive(:get_next_command).with(%i[keys info], aliases: nil).and_return(:info))
            expect(host_class.new(context: context).dispatch_from_registry([])).to(have_attributes(data: 'info'))
          end

          it 'reads the mount arguments after the mounted command and passes them to instance' do
            tc = target_class
            host_class.command(:pkg, description: 'Packages', mount: {plugin: tc, at: %i[keys do], instance: :build_pkg, arguments: [{name: :pkg_id, type: :identifier}]})
            host_class.define_method(:build_pkg) { |pkg_id:, **| [tc.new(context: context), {root: "p-#{pkg_id}"}] }
            allow(options).to(receive(:get_next_command).with(%i[files pkg], aliases: nil).and_return(:pkg))
            allow(options).to(receive(:get_next_command).with(%i[ls perm], aliases: nil).and_return(:ls))
            allow(options).to(receive(:instance_identifier).with(description: 'pkg_id').and_return('42'))
            expect(host_class.new(context: context).dispatch_from_registry([])).to(have_attributes(data: 'ls p-42'))
          end

          it 'walks mounted help without instantiating the target' do
            context.help_requested = true
            host_class.define_method(:build_target) { |**| raise 'must not instantiate target for help' }
            allow(options).to(receive(:command_or_arg_empty?).and_return(false, false, false, false, true))
            allow(options).to(receive(:get_next_command).with([:files], aliases: nil).and_return(:files))
            allow(options).to(receive(:get_next_command).with(%i[ls perm extra], aliases: nil).and_return(:perm))
            inst = host_class.new(context: context)
            expect { inst.dispatch_from_registry([]) }.to(raise_error(Cli::HelpRequest))
            expect(inst.help_path).to(eq(%i[files perm]))
          end

          it 'includes mounted children in generate_help' do
            help = host_class.new(context: context).generate_help
            expect(help[:files][:children].keys).to(eq(%i[ls perm extra]))
            expect(help[:files][:children][:perm][:children]).to(have_key(:list))
          end
        end

        # ------------------------------------------------------------------
        # dispatch_from_registry — transfer_paths:
        # ------------------------------------------------------------------

        describe '#dispatch_from_registry with transfer_paths:' do
          it 'calls the handler with only ctx (no positional args) when transfer_paths is set' do
            klass = Class.new(Base)
            klass.command(:upload, description: 'Upload', action: :handle_upload, transfer_paths: :send)
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
            klass.define_method(:handle_list) { nil }
            inst = klass.new(context: context)
            result = inst.generate_help
            expect(result[:transfer][:children]).to(have_key(:list))
          end

          it 'annotates conditional commands with [condition_name]' do
            klass = Class.new(Base)
            klass.command(:ssh_only, description: 'SSH only', action: :handle_ssh, condition: :ssh_available?)
            klass.define_method(:handle_ssh) { nil }
            inst = klass.new(context: context)
            result = inst.generate_help
            expect(result[:ssh_only][:description]).to(eq('SSH only [ssh_available?]'))
          end

          it 'sets condition key to the method name symbol for annotated commands' do
            klass = Class.new(Base)
            klass.command(:guarded, description: 'Guarded', action: :handle_guarded, condition: :flag?)
            klass.define_method(:handle_guarded) { nil }
            inst = klass.new(context: context)
            expect(inst.generate_help[:guarded][:condition]).to(eq(:flag?))
          end
        end

        # ------------------------------------------------------------------
        # commands_under auto-declaration
        # ------------------------------------------------------------------

        describe 'commands_under auto-declaration' do
          it 'auto-declares the terminal node when not yet registered' do
            klass = Class.new(Base)
            klass.commands_under(:things) do
              klass.command(:list, description: 'List things', action: :handle_list)
            end
            klass.define_method(:handle_list) { nil }
            reg = klass.command_registry
            expect(reg[[:things]]).not_to(be_nil)
            expect(reg[[:things]].description).to(eq('Manage Things'))
          end

          it 'uses description: when provided' do
            klass = Class.new(Base)
            klass.commands_under(:things, description: 'Browse things') do
              klass.command(:list, description: 'List things', action: :handle_list)
            end
            klass.define_method(:handle_list) { nil }
            expect(klass.command_registry[[:things]].description).to(eq('Browse things'))
          end

          it 'does not overwrite an existing command declaration' do
            klass = Class.new(Base)
            klass.command(:things, description: 'My things')
            klass.commands_under(:things) do
              klass.command(:list, description: 'List things', action: :handle_list)
            end
            klass.define_method(:handle_list) { nil }
            expect(klass.command_registry[[:things]].description).to(eq('My things'))
          end
        end

        # ------------------------------------------------------------------
        # ------------------------------------------------------------------
        # crud_commands DSL + per-verb methods
        # ------------------------------------------------------------------

        describe 'crud_commands' do
          let(:api_obj) { instance_double(Rest, 'api') }

          def build_klass(extra_kwargs = {})
            ao = api_obj
            k = Class.new(Base) do
              command :res, description: 'Resource', setup: :setup_res
              define_method(:setup_res) { {} }
              crud_commands(api: :resolve_api, entity: 'things', lookup: :lookup_thing_id, **extra_kwargs)
              define_method(:resolve_api) { ao }
              define_method(:lookup_thing_id) { |_f, _v, **| 'thing-42' }
            end
            k
          end

          it 'registers one command per operation with auto description' do
            klass = build_klass
            reg   = klass.command_registry
            Base::Operations::ALL.each do |verb|
              spec = reg[Array(verb)]
              expect(spec).not_to(be_nil)
              expect(spec.description).to(eq(verb.eql?(:list) ? 'List things' : "#{verb.capitalize} thing"))
            end
          end

          it 'adds ArgumentSpec for verbs appropriately' do
            klass = build_klass
            reg   = klass.command_registry
            # Instance operations have identifier named after entity as first argument
            Base::Operations::INSTANCE.each do |verb|
              spec = reg[Array(verb)]
              expect(spec.arguments).not_to(be_nil)
              expect(spec.arguments.first.name).to(eq(:thing_id))
              expect(spec.arguments.first.type).to(eq(:identifier))
              expect(spec.arguments.first.lookup).to(eq(:lookup_thing_id))
            end
            # :modify also has body argument named after entity as second argument
            expect(reg[[:modify]].arguments.map(&:name)).to(eq(%i[thing_id thing]))
            # :create has body argument named after entity
            expect(reg[[:create]].arguments.map(&:name)).to(eq(%i[thing]))
            # :list has no arguments
            expect(reg[[:list]].arguments).to(be_nil)
          end

          it 'omits id ArgumentSpec for instance verbs when is_singleton: true' do
            klass = build_klass(is_singleton: true)
            reg   = klass.command_registry
            # show has no id argument when singleton
            expect(reg[[:show]].arguments).to(be_nil)
            # modify only has body argument when singleton (plural name)
            expect(reg[[:modify]].arguments.map(&:name)).to(eq(%i[things]))
          end

          it 'restricts to a given operations: list' do
            ao = api_obj
            klass = Class.new(Base) do
              crud_commands(api: :resolve_api, entity: 'things', operations: %i[show list])
              define_method(:resolve_api) { ao }
            end
            reg = klass.command_registry
            expect(reg[[:show]]).not_to(be_nil)
            expect(reg[[:list]]).not_to(be_nil)
            expect(reg[[:create]]).to(be_nil)
          end

          it 'resolves entity: Symbol as a ctx key at runtime' do
            ao = api_obj
            resp = instance_double(Net::HTTPResponse, code: '200', '[]': 'application/json')
            allow(ao).to(receive(:read).with('nodes/7/things', nil, ret: :both)
              .and_return([[{'id' => '1'}], resp]))
            allow(options).to(receive(:get_option).with(:query, schema: nil).and_return(nil))
            allow(options).to(receive(:get_option).with(:bfail).and_return(false))
            allow(options).to(receive(:get_next_command).with([:list], aliases: nil).and_return(:list))
            klass = Class.new(Base) do
              crud_commands(api: :resolve_api, entity: :dynamic_entity, name: 'thing', operations: %i[list])
              define_method(:resolve_api) { ao }
            end
            inst = klass.new(context: context)
            # dynamic_entity: injected into ctx by a parent setup:, then forwarded to dispatch
            result = inst.dispatch_from_registry([], {dynamic_entity: 'nodes/7/things'})
            expect(result).to(be_a(Result::ObjectList))
          end
        end

        describe 'per-verb entity methods' do
          let(:api_obj) { instance_double(Rest, 'api') }

          before do
            allow(options).to(receive(:get_option).with(:query, schema: nil).and_return(nil))
            allow(options).to(receive(:get_option).with(:bfail).and_return(false))
          end

          it 'entity_list delegates to api.read and returns ObjectList' do
            inst = Base.new(context: context)
            resp = instance_double(Net::HTTPResponse, code: '200', '[]': 'application/json')
            allow(api_obj).to(receive(:read).with('things', nil, ret: :both).and_return([[{'id' => '1'}], resp]))
            result = inst.entity_list(api: api_obj, entity: 'things')
            expect(result).to(be_a(Result::ObjectList))
          end

          it 'entity_list returns Empty when HTTP 204' do
            inst = Base.new(context: context)
            resp = instance_double(Net::HTTPResponse, code: '204', '[]': 'application/json')
            allow(api_obj).to(receive(:read).with('things', nil, ret: :both).and_return([nil, resp]))
            expect(inst.entity_list(api: api_obj, entity: 'things')).to(be_a(Result::Empty))
          end

          it 'entity_show reads entity/id and returns SingleObject' do
            inst = Base.new(context: context)
            allow(api_obj).to(receive(:read).with('things/42').and_return({'id' => '42'}))
            result = inst.entity_show(api: api_obj, entity: 'things', id: '42')
            expect(result).to(be_a(Result::SingleObject))
          end

          it 'entity_show uses entity path directly when is_singleton: true' do
            inst = Base.new(context: context)
            allow(api_obj).to(receive(:read).with('things').and_return({'setting' => 'x'}))
            inst.entity_show(api: api_obj, entity: 'things', is_singleton: true)
          end

          it 'entity_create calls api.create with data' do
            inst = Base.new(context: context)
            allow(options).to(receive(:get_option).with(:bulk).and_return(false))
            allow(api_obj).to(receive(:create).with('things', {'name' => 'x'}).and_return({'id' => '1'}))
            result = inst.entity_create(api: api_obj, entity: 'things', data: {'name' => 'x'})
            expect(result).to(be_a(Result::SingleObject))
          end

          it 'entity_modify calls api.update and returns Status' do
            inst = Base.new(context: context)
            allow(api_obj).to(receive(:update).with('things/42', {'name' => 'y'}))
            result = inst.entity_modify(api: api_obj, entity: 'things', id: '42', data: {'name' => 'y'})
            expect(result).to(be_a(Result::Status))
          end

          it 'entity_delete calls api.delete and returns SingleObject' do
            inst = Base.new(context: context)
            allow(options).to(receive(:get_option).with(:bulk).and_return(false))
            allow(api_obj).to(receive(:delete).with('things/42', nil))
            result = inst.entity_delete(api: api_obj, entity: 'things', id: '42')
            expect(result).to(be_a(Result::SingleObject))
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
