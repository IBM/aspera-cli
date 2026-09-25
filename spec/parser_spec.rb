# frozen_string_literal: true

# Unit tests for Aspera::Cli::Parser — no server, no config file needed.

require 'aspera/cli/parser'

module Aspera
  module Cli
    RSpec.describe(Parser) do
      # Build a fresh Parser instance with the given argv each time
      def build_parser(argv)
        Parser.new('test', argv)
      end

      describe 'short option parsing' do
        it 'parses -X value when value is glued to flag (-Xvalue)' do
          opts = build_parser(['-Xhello', 'arg1'])
          nil
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          received = opts.get_option(:xenon)
          expect(received).to(eq('hello'))
        end

        it 'parses -X value when value is a separate token (after parse via set_option)' do
          opts = build_parser([])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.set_option(:xenon, 'world')
          expect(opts.get_option(:xenon)).to(eq('world'))
        end

        it 'parses -X value when value is a space-separated token (-X value)' do
          opts = build_parser(['-X', 'hello'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          expect(opts.get_option(:xenon)).to(eq('hello'))
          expect(opts.final_errors).to(be_empty)
        end

        it 'raises BadArgument for -X alone (no value)' do
          opts = build_parser(['-X'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          expect { opts.parse_options! }.to(raise_error(BadArgument, /requires a value/))
        end

        it 'does not consume the next token for flag options (TYPES_NONE) with -N syntax' do
          opts = build_parser(['-N', 'myarg'])
          opts.declare(:no_default, description: 'No default flag', short: 'N', allowed: Type::NONE) do
            # flag callback — no-op
          end
          opts.parse_options!
          # The positional arg must still be available
          expect(opts.get_next_argument('arg')).to(eq('myarg'))
        end

        context 'with an on_set callback (like --preset / -P)' do
          it 'passes the glued value to the on_set callback when using -Pvalue syntax' do
            received = nil
            target = Object.new
            target.define_singleton_method(:my_preset=) { |v| received = v }

            opts = build_parser(['-Pmypreset'])
            opts.declare(
              :my_preset, description: 'Load preset', short: 'P',
              on_set: target.method(:my_preset=)
            )
            opts.parse_options!
            expect(received).to(eq('mypreset'))
          end

          it 'passes the space-separated value to the on_set callback when using -P value syntax' do
            received = nil
            target = Object.new
            target.define_singleton_method(:my_preset=) { |v| received = v }

            opts = build_parser(['-P', 'mypreset'])
            opts.declare(
              :my_preset, description: 'Load preset', short: 'P',
              on_set: target.method(:my_preset=)
            )
            opts.parse_options!
            expect(received).to(eq('mypreset'))
          end
        end
      end

      describe 'long option parsing' do
        it 'parses --option=value (inline = form)' do
          opts = build_parser(['--log-level=debug'])
          opts.declare(:log_level, description: 'Log level', allowed: %i[debug info warn error])
          opts.parse_options!
          expect(opts.get_option(:log_level)).to(eq(:debug))
        end

        it 'parses --option value (space-separated form)' do
          opts = build_parser(['--log-level', 'debug'])
          opts.declare(:log_level, description: 'Log level', allowed: %i[debug info warn error])
          opts.parse_options!
          expect(opts.get_option(:log_level)).to(eq(:debug))
          expect(opts.final_errors).to(be_empty)
        end

        it 'parses --query=@json:{"a":1} (inline = form, JSON value via extended value)' do
          opts = build_parser(['--query=@json:{"a":1}'])
          opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          opts.parse_options!
          expect(opts.get_option(:query)).to(eq({'a' => 1}))
        end

        it 'parses --query @json:{"a":1} (space-separated form, JSON value via extended value)' do
          opts = build_parser(['--query', '@json:{"a":1}'])
          opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          opts.parse_options!
          expect(opts.get_option(:query)).to(eq({'a' => 1}))
          expect(opts.final_errors).to(be_empty)
        end

        it 'does not consume next token for TYPES_NONE flags (--show-config style)' do
          opts = build_parser(['--no-flag', 'myarg'])
          opts.declare(:no_flag, description: 'No flag', allowed: Type::NONE) do
            # flag callback — no-op
          end
          opts.parse_options!
          expect(opts.get_next_argument('arg')).to(eq('myarg'))
        end

        it 'leaves positional args intact when option has inline value' do
          opts = build_parser(['--level=info', 'cmd'])
          opts.declare(:level, description: 'Level', allowed: %i[debug info warn])
          opts.parse_options!
          expect(opts.get_option(:level)).to(eq(:info))
          expect(opts.get_next_argument('cmd')).to(eq('cmd'))
        end

        it 'leaves remaining positional args intact when option uses space-separated value' do
          opts = build_parser(['--level', 'info', 'cmd'])
          opts.declare(:level, description: 'Level', allowed: %i[debug info warn])
          opts.parse_options!
          expect(opts.get_option(:level)).to(eq(:info))
          expect(opts.get_next_argument('cmd')).to(eq('cmd'))
        end

        it 'respects -- stop marker: token after -- is not consumed as option value' do
          opts = build_parser(['--', '--level', 'info'])
          opts.declare(:level, description: 'Level', allowed: %i[debug info warn])
          opts.parse_options!
          expect(opts.get_option(:level)).to(be_nil)
          # Both tokens after -- are positional args
          expect(opts.get_next_argument('a')).to(eq('--level'))
          expect(opts.get_next_argument('b')).to(eq('info'))
        end

        describe 'dotted notation' do
          it 'supports --a.b.c=val (inline)' do
            opts = build_parser(['--custom.field=42'])
            opts.declare(:custom, description: 'Custom object', allowed: [Hash, NilClass])
            opts.parse_options!
            expect(opts.get_option(:custom)).to(eq({'field' => 42}))
          end

          it 'supports --a.b.c val (space-separated)' do
            opts = build_parser(['--custom.field', '42'])
            opts.declare(:custom, description: 'Custom object', allowed: [Hash, NilClass])
            opts.parse_options!
            expect(opts.get_option(:custom)).to(eq({'field' => 42}))
            expect(opts.final_errors).to(be_empty)
          end

          it 'fills an array nested in a Hash with successive indexes' do
            opts = build_parser(['--custom.fld.0=name', '--custom.fld.1=id', '--custom.opt=true'])
            opts.declare(:custom, description: 'Custom object', allowed: [Hash, NilClass])
            opts.parse_options!
            expect(opts.get_option(:custom)).to(eq({'fld' => %w[name id], 'opt' => true}))
          end

          it 'fills an Array option with successive indexes' do
            opts = build_parser(['--list.0=a', '--list.1=b'])
            opts.declare(:list, description: 'List', allowed: Array)
            opts.parse_options!
            expect(opts.get_option(:list)).to(eq(%w[a b]))
          end

          it 'keeps a Proc in the current value' do
            format = ->(s) { s }
            opts = build_parser(['--custom.level=debug'])
            opts.declare(:custom, description: 'Custom object', allowed: Hash)
            opts.set_option(:custom, {'format' => format})
            opts.parse_options!
            expect(opts.get_option(:custom)).to(eq({'format' => format, 'level' => 'debug'}))
          end
        end
      end

      describe 'args_as_extended (@:)' do
        # The @: extended value handler is normally registered by Runner, so we register it here for unit tests.
        before do
          ExtendedValue.instance.on(:'') { |v| @opts.args_as_extended(v) }
        end

        it 'collects key=value args after the option using @: (no leading positional args)' do
          @opts = build_parser(['--query', '@:', 'status=active', 'END'])
          @opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          @opts.parse_options!
          expect(@opts.get_option(:query)).to(eq({'status' => 'active'}))
          expect(@opts.command_or_arg_empty?).to(be(true))
        end

        it 'skips leading positional args before the option when using @:' do
          # argv: cmd --query @: a=b END
          # "cmd" is a positional arg before --query; it must remain available after @: collection.
          @opts = build_parser(['cmd', '--query', '@:', 'a=b', 'END'])
          @opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          @opts.parse_options!
          expect(@opts.get_option(:query)).to(eq({'a' => 'b'}))
          # "cmd" must still be reachable as a positional argument
          expect(@opts.get_next_argument('cmd')).to(eq('cmd'))
        end
      end

      describe 'edge cases' do
        it 'raises BadArgument for a long option at end of line with no following value' do
          opts = build_parser(['--level'])
          opts.declare(:level, description: 'Level', allowed: %i[debug info warn])
          expect { opts.parse_options! }.to(raise_error(BadArgument, /requires a value/))
        end

        it 'does not take a following option as value' do
          opts = build_parser(['--name', '--level=info'])
          opts.declare(:name, description: 'Name')
          opts.declare(:level, description: 'Level', allowed: %i[debug info warn])
          expect { opts.parse_options! }.to(raise_error(BadArgument, /requires a value/))
        end

        it 'accepts a negative number and a single dash as values' do
          opts = build_parser(['--count', '-5', '--name', '-'])
          opts.declare(:count, description: 'Count', allowed: Type::INTEGER)
          opts.declare(:name, description: 'Name')
          opts.parse_options!
          expect(opts.get_option(:count)).to(eq(-5))
          expect(opts.get_option(:name)).to(eq('-'))
        end

        it 'raises BadArgument for a flag given a value' do
          opts = build_parser(['--flag=x'])
          opts.declare(:flag, description: 'Flag', allowed: Type::NONE) { nil }
          expect { opts.parse_options! }.to(raise_error(BadArgument, /does not take a value/))
        end
      end

      describe 'incremental declaration' do
        it 'keeps unknown option with its space-separated value for a later parse' do
          opts = build_parser(['--late', 'val', 'cmd'])
          opts.parse_options!
          # value is claimed by the unknown option, not a positional argument
          expect(opts.get_next_argument('cmd')).to(eq('cmd'))
          opts.declare(:late, description: 'Late option')
          opts.parse_options!
          expect(opts.get_option(:late)).to(eq('val'))
          expect(opts.final_errors).to(be_empty)
        end

        it 'keeps positional order for unknown dotted option' do
          opts = build_parser(['cmd1', '--custom.x', 'val', 'cmd2'])
          opts.parse_options!
          expect(opts.get_next_argument('a', multiple: true)).to(eq(%w[cmd1 cmd2]))
          opts.declare(:custom, description: 'Custom object', allowed: [Hash, NilClass])
          opts.parse_options!
          expect(opts.get_option(:custom)).to(eq({'x' => 'val'}))
        end

        it 'gives back the token following a flag declared later' do
          opts = build_parser(['-N', 'cmd', '--help', 'sub'])
          opts.parse_options!
          count = 0
          opts.declare(:no_default, description: 'No default', short: 'N', allowed: Type::NONE) { count += 1 }
          opts.declare(:help, description: 'Help', short: 'h', allowed: Type::NONE) { count += 1 }
          opts.parse_options!
          expect(count).to(eq(2))
          expect(opts.get_next_argument('a', multiple: true)).to(eq(%w[cmd sub]))
        end

        it 'supports combined short flags' do
          opts = build_parser(['-hN'])
          called = []
          opts.declare(:help, description: 'Help', short: 'h', allowed: Type::NONE) { called << :help }
          opts.declare(:no_default, description: 'No default', short: 'N', allowed: Type::NONE) { called << :no_default }
          opts.parse_options!
          expect(called).to(eq(%i[help no_default]))
        end

        it 'calls on_set method of a flag' do
          opts = build_parser(['-N'])
          target = Struct.new(:called) { def flag_found = self.called = true }.new(false)
          opts.declare(:no_default, description: 'No default', short: 'N', allowed: Type::NONE, on_set: target.method(:flag_found))
          opts.parse_options!
          expect(target.called).to(be(true))
        end

        it 'accepts unique abbreviation of long option' do
          opts = build_parser(['--form=json'])
          opts.declare(:format, description: 'Format')
          opts.parse_options!
          expect(opts.get_option(:format)).to(eq('json'))
        end

        it 'raises BadArgument for ambiguous abbreviation' do
          opts = build_parser(['--fo=json'])
          opts.declare(:format, description: 'Format')
          opts.declare(:folder, description: 'Folder')
          expect { opts.parse_options! }.to(raise_error(BadArgument, /Ambiguous option/))
        end

        it 'raises BadArgument when a later declaration makes a used abbreviation ambiguous' do
          opts = build_parser(['--fo=json'])
          opts.declare(:format, description: 'Format')
          opts.parse_options!
          expect { opts.declare(:folder, description: 'Folder') }.to(raise_error(BadArgument, /Ambiguous option/))
        end
      end

      describe 'value sources priority' do
        it 'does not override command line with a preset added later' do
          opts = build_parser(['--name=cli'])
          opts.declare(:name, description: 'Name')
          opts.parse_options!
          opts.add_option_preset({name: 'preset'}, 'test')
          opts.parse_options!
          expect(opts.get_option(:name)).to(eq('cli'))
        end

        it 'merges a preset added later under a Hash from command line' do
          opts = build_parser(['--vault.name=cli'])
          opts.declare(:vault, description: 'Vault', allowed: Hash)
          opts.parse_options!
          opts.add_option_preset({vault: {'type' => 'file', 'name' => 'preset'}}, 'test', override: false)
          opts.parse_options!
          expect(opts.get_option(:vault)).to(eq({'type' => 'file', 'name' => 'cli'}))
        end

        it 'does not fill a Hash emptied on command line with a preset added later' do
          opts = build_parser(['--vault=@none:'])
          opts.declare(:vault, description: 'Vault', allowed: Hash)
          opts.parse_options!
          opts.add_option_preset({vault: {'type' => 'file'}}, 'test')
          opts.parse_options!
          expect(opts.get_option(:vault)).to(eq({}))
        end

        it 'does not restore a value explicitly cleared on command line' do
          opts = build_parser(['--name=@none:'])
          opts.declare(:name, description: 'Name')
          opts.add_option_preset({name: 'preset'}, 'test')
          opts.parse_options!
          expect(opts.get_option(:name)).to(be_nil)
        end

        it 'does not override a preset with a plugin default preset added later' do
          opts = build_parser([])
          opts.declare(:name, description: 'Name')
          opts.add_option_preset({name: 'preset'}, 'test')
          opts.parse_options!
          opts.add_option_preset({name: 'default'}, 'test', override: false)
          opts.parse_options!
          expect(opts.get_option(:name)).to(eq('preset'))
        end
      end

      describe 'automatic parse' do
        it 'applies command line on read of option, without explicit parse' do
          opts = build_parser(['--name', 'val', 'cmd'])
          opts.declare(:name, description: 'Name')
          expect(opts.get_option(:name)).to(eq('val'))
          expect(opts.get_next_argument('cmd')).to(eq('cmd'))
        end

        it 'applies options declared after a first read' do
          opts = build_parser(['cmd', '--late=val'])
          expect(opts.get_next_argument('cmd')).to(eq('cmd'))
          opts.declare(:late, description: 'Late option')
          expect(opts.get_option(:late)).to(eq('val'))
          expect(opts.final_errors).to(be_empty)
        end
      end

      describe 'option kinds' do
        it 'recognizes boolean whatever the order of classes' do
          opts = build_parser(['--flag=no'])
          opts.declare(:flag, description: 'Flag', allowed: [TrueClass, FalseClass])
          expect(opts.get_option(:flag)).to(be(false))
        end

        it 'accepts @none: on an integer option allowing nil' do
          opts = build_parser(['--count=@none:'])
          opts.declare(:count, description: 'Count', allowed: [Integer, NilClass])
          expect(opts.get_option(:count)).to(be_nil)
        end

        it 'accepts a boolean for an enum including yes and no' do
          opts = build_parser([])
          opts.declare(:reset, description: 'Reset', allowed: %i[no header read])
          opts.set_option(:reset, false)
          expect(opts.get_option(:reset)).to(eq(:no))
        end

        it 'rejects a boolean for an enum without yes and no' do
          opts = build_parser([])
          opts.declare(:level, description: 'Level', allowed: %i[debug info])
          expect { opts.set_option(:level, true) }.to(raise_error(BadArgument, /unknown value/))
        end

        it 'shows allowed values, or types when not plain String' do
          opts = build_parser([])
          opts.declare(:text, description: 'Text')
          opts.declare(:level, description: 'Level', allowed: %i[debug info])
          opts.declare(:count, description: 'Count', allowed: [Integer, NilClass])
          opts.declare(:params, description: 'Params', allowed: [Hash, String])
          info = opts.declared_options.slice(:text, :level, :count, :params).transform_values(&:allowed_info)
          expect(info).to(eq(text: nil, level: 'debug|info', count: 'Integer', params: 'Hash|String'))
        end
      end

      describe '.smart_convert' do
        it 'converts true, yes, false and no to Boolean' do
          expect(%w[true yes false no].map { |v| Parser.smart_convert(v) }).to(eq([true, true, false, false]))
        end

        it 'converts numbers, and keeps other strings' do
          expect(%w[1 1.5 yess].map { |v| Parser.smart_convert(v) }).to(eq([1, 1.5, 'yess']))
        end

        it 'converts a dotted option value' do
          opts = build_parser(['--custom.a=yes', '--custom.b=no'])
          opts.declare(:custom, description: 'Custom object', allowed: Hash)
          expect(opts.get_option(:custom)).to(eq({'a' => true, 'b' => false}))
        end
      end

      describe 'misc' do
        it 'returns a boolean from get_from_list for exact and prefix match' do
          expect(Parser.get_from_list('yes', 'b', BoolValue::ALL)).to(be(true))
          expect(Parser.get_from_list('ye', 'b', BoolValue::ALL)).to(be(true))
          expect(Parser.get_from_list('no', 'b', BoolValue::ALL)).to(be(false))
        end

        it 'stores the value and calls the on_set callback with it' do
          target = Struct.new(:path).new
          opts = build_parser([])
          opts.declare(:path, description: 'Path', on_set: target.method(:path=))
          opts.add_option_preset({path: '/a'}, 'test')
          opts.parse_options!
          expect(target.path).to(eq('/a'))
          expect(opts.get_option(:path)).to(eq('/a'))
        end

        it 'calls the on_set callback with the merged value of a Hash option' do
          received = []
          opts = build_parser(['--opt.b=2'])
          opts.declare(:opt, description: 'Opt', allowed: Hash, on_set: ->(v) { received.push(v) })
          opts.add_option_preset({opt: {'a' => 1}}, 'test')
          opts.parse_options!
          expect(received.last).to(eq({'a' => 1, 'b' => 2}))
          # Previous value is not modified in place by dot notation
          expect(received[-2]).to(eq({'a' => 1}))
        end

        it 'calls an on_set callback bound after declaration with the current value' do
          target = Struct.new(:val).new
          opts = build_parser(['--val=x'])
          opts.declare(:val, description: 'Val')
          opts.parse_options!
          opts.on_set(:val, target.method(:val=))
          expect(target.val).to(eq('x'))
        end

        it 'stores a String as a Hash with shorthand' do
          opts = build_parser(['--transfer.url=u', '--transfer=node'])
          opts.declare(:transfer, description: 'Transfer', allowed: [Hash, String], shorthand: 'agent')
          opts.parse_options!
          expect(opts.get_option(:transfer)).to(eq({'url' => 'u', 'agent' => 'node'}))
        end

        it 'clears an option and calls its on_set callback' do
          target = Struct.new(:val).new('x')
          opts = build_parser([])
          opts.declare(:val, description: 'Val', on_set: target.method(:val=))
          opts.clear_option(:val)
          expect(opts.get_option(:val)).to(be_nil)
          expect(target.val).to(be_nil)
        end

        it 'unprocessed_options_with_value consumes space-separated values' do
          opts = build_parser(['--url', 'https://x', '--user.name=me', 'cmd'])
          opts.parse_options!
          expect(opts.unprocessed_options_with_value).to(eq({'url' => 'https://x', 'user' => {'name' => 'me'}}))
          expect(opts.get_next_argument('a', multiple: true)).to(eq(%w[cmd]))
          expect(opts.final_errors).to(be_empty)
        end
      end

      describe '#get_option with schema: contextual override' do
        def build_query_option(opts)
          opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          opts
        end

        it 'set_option stores "help" without raising when option has no static schema' do
          opts = build_query_option(build_parser([]))
          expect { opts.set_option(:query, 'help') }.not_to(raise_error)
        end

        it 'raises SchemaRequest in get_option when value is "help" and schema: is provided' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, 'help')
          expect do
            opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')
          end.to(raise_error(SchemaRequest) do |e|
            expect(e.path).to(eq('faspex:paths./packages.get.parameters'))
            expect(e.message).to(include('query'))
          end)
        end

        it 'returns the value normally when schema: is provided but value is not "help"' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, {'status' => 'completed'})
          expect(opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')).to(eq({'status' => 'completed'}))
        end

        it 'does not raise SchemaRequest in get_option when schema: is nil and value is "help"' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, 'help')
          expect { opts.get_option(:query) }.not_to(raise_error(SchemaRequest))
        end

        it 'returns nil normally when schema: is provided but no value is set' do
          opts = build_query_option(build_parser([]))
          expect(opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')).to(be_nil)
        end

        it 'set_option still raises SchemaRequest immediately for options with a static schema' do
          opts = build_parser([])
          opts.declare(
            :data, description: 'Data', allowed: [Hash],
            schema: 'faspex:paths./packages.post.requestBody.content.application/json.schema'
          )
          expect do
            opts.set_option(:data, 'help')
          end.to(raise_error(SchemaRequest) do |e|
            expect(e.path).to(include('requestBody'))
          end)
        end
      end

      describe '#help_text' do
        it 'displays semantic placeholders based on option type and schema' do
          opts = build_parser([])
          opts.declare(:bool_opt, description: 'Boolean option', allowed: Type::BOOLEAN)
          opts.declare(:enum_opt, description: 'Enum option', allowed: %i[alpha beta])
          opts.declare(:int_opt, description: 'Integer option', allowed: Type::INTEGER)
          opts.declare(:object_opt, description: 'Object option', allowed: Hash)
          opts.declare(:list_opt, description: 'List option', allowed: Type::STRING_ARRAY)
          opts.declare(:str_opt, description: 'String option')
          help = opts.help_text
          expect(help).to(include('--bool-opt=yes|no'))
          expect(help).to(include('--enum-opt=alpha|beta'))
          expect(help).to(include('--int-opt=INT'))
          expect(help).to(include('--object-opt=HASH'))
          expect(help).to(include('--list-opt=LIST'))
          expect(help).to(include('--str-opt=VALUE'))
        end

        it 'displays the deprecation with its version' do
          opts = build_parser([])
          opts.declare(:old_opt, description: 'Old option', deprecation: {last: '4.27.0', message: 'use --new-opt'})
          expect(opts.help_text).to(include('Old option (deprecated after 4.27.0: use --new-opt)'))
        end
      end
    end
  end
end
