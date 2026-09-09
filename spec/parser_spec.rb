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
          opts.set_option(:xenon, 'world', where: 'test')
          expect(opts.get_option(:xenon)).to(eq('world'))
        end

        it 'parses -X value when value is a space-separated token (-X value)' do
          opts = build_parser(['-X', 'hello'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          expect(opts.get_option(:xenon)).to(eq('hello'))
          expect(opts.final_errors).to(be_empty)
        end

        it 'treats -X alone (no glued value) as nil' do
          opts = build_parser(['-X'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          expect(opts.get_option(:xenon)).to(be_nil)
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

        context 'with a handler (like --preset / -P)' do
          it 'passes the glued value to the handler when using -Pvalue syntax' do
            received = nil
            target = Object.new
            target.define_singleton_method(:my_preset=){ |v| received = v}
            target.define_singleton_method(:my_preset){received}

            opts = build_parser(['-Pmypreset'])
            opts.declare(
              :my_preset, description: 'Load preset', short: 'P',
              handler: {o: target, m: :my_preset}
            )
            opts.parse_options!
            expect(received).to(eq('mypreset'))
          end

          it 'passes the space-separated value to the handler when using -P value syntax' do
            received = nil
            target = Object.new
            target.define_singleton_method(:my_preset=){ |v| received = v}
            target.define_singleton_method(:my_preset){received}

            opts = build_parser(['-P', 'mypreset'])
            opts.declare(
              :my_preset, description: 'Load preset', short: 'P',
              handler: {o: target, m: :my_preset}
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
        it 'raises BadArgument for a typed long option at end of line with no following value' do
          opts = build_parser(['--level'])
          opts.declare(:level, description: 'Level', allowed: %i[debug info warn])
          # nil is passed to assign_value when no argument follows; type validation raises BadArgument
          expect { opts.parse_options! }.to(raise_error(BadArgument))
        end

        it 'returns nil for an untyped (String) short option at end of line with no following value' do
          opts = build_parser(['-X'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          expect(opts.get_option(:xenon)).to(be_nil)
        end
      end

      describe '#get_option with schema: contextual override' do
        def build_query_option(opts)
          opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          opts
        end

        it 'set_option stores "help" without raising when option has no static schema' do
          opts = build_query_option(build_parser([]))
          expect{opts.set_option(:query, 'help', where: 'test')}.not_to(raise_error)
        end

        it 'raises SchemaRequest in get_option when value is "help" and schema: is provided' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, 'help', where: 'test')
          expect do
            opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')
          end.to(raise_error(SchemaRequest) do |e|
            expect(e.path).to(eq('faspex:paths./packages.get.parameters'))
            expect(e.message).to(include('query'))
          end)
        end

        it 'returns the value normally when schema: is provided but value is not "help"' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, {'status' => 'completed'}, where: 'test')
          expect(opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')).to(eq({'status' => 'completed'}))
        end

        it 'does not raise SchemaRequest in get_option when schema: is nil and value is "help"' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, 'help', where: 'test')
          expect{opts.get_option(:query)}.not_to(raise_error(SchemaRequest))
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
            opts.set_option(:data, 'help', where: 'test')
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
      end
    end
  end
end
