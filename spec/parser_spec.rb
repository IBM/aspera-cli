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

        it 'treats -X alone (no glued value) as nil' do
          opts = build_parser(['-X'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          expect(opts.get_option(:xenon)).to(be_nil)
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
        end
      end

      describe '#get_option with schema: contextual override' do
        def build_query_option(opts)
          opts.declare(:query, description: 'Query filter', allowed: [Hash, NilClass])
          opts
        end

        it 'set_option stores "help" without raising when option has no static schema' do
          opts = build_query_option(build_parser([]))
          expect { opts.set_option(:query, 'help', where: 'test') }.not_to raise_error
        end

        it 'raises SchemaRequest in get_option when value is "help" and schema: is provided' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, 'help', where: 'test')
          expect {
            opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')
          }.to raise_error(SchemaRequest) { |e|
            expect(e.path).to eq('faspex:paths./packages.get.parameters')
            expect(e.message).to include('query')
          }
        end

        it 'returns the value normally when schema: is provided but value is not "help"' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, {'status' => 'completed'}, where: 'test')
          expect(opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')).to eq({'status' => 'completed'})
        end

        it 'does not raise SchemaRequest in get_option when schema: is nil and value is "help"' do
          opts = build_query_option(build_parser([]))
          opts.set_option(:query, 'help', where: 'test')
          expect { opts.get_option(:query) }.not_to raise_error(SchemaRequest)
        end

        it 'returns nil normally when schema: is provided but no value is set' do
          opts = build_query_option(build_parser([]))
          expect(opts.get_option(:query, schema: 'faspex:paths./packages.get.parameters')).to be_nil
        end

        it 'set_option still raises SchemaRequest immediately for options with a static schema' do
          opts = build_parser([])
          opts.declare(:data, description: 'Data', allowed: [Hash],
            schema: 'faspex:paths./packages.post.requestBody.content.application/json.schema')
          expect {
            opts.set_option(:data, 'help', where: 'test')
          }.to raise_error(SchemaRequest) { |e|
            expect(e.path).to include('requestBody')
          }
        end
      end
    end
  end
end
