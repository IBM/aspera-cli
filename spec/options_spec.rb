# frozen_string_literal: true

# Unit tests for Aspera::Cli::Options — no server, no config file needed.

require 'aspera/cli/options'

module Aspera
  module Cli
    RSpec.describe(Options) do
      # Build a fresh Options instance with the given argv each time
      def build_options(argv)
        Options.new('test', argv)
      end

      describe 'short option parsing' do
        it 'parses -X value when value is glued to flag (-Xvalue)' do
          opts = build_options(['-Xhello', 'arg1'])
          received = nil
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          received = opts.get_option(:xenon)
          expect(received).to(eq('hello'))
        end

        it 'parses -X value when value is a separate token (after parse via set_option)' do
          opts = build_options([])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.set_option(:xenon, 'world', where: 'test')
          expect(opts.get_option(:xenon)).to(eq('world'))
        end

        it 'treats -X alone (no glued value) as nil' do
          opts = build_options(['-X'])
          opts.declare(:xenon, description: 'Xenon option', short: 'X')
          opts.parse_options!
          expect(opts.get_option(:xenon)).to(be_nil)
        end

        context 'with a handler (like --preset / -P)' do
          it 'passes the glued value to the handler when using -Pvalue syntax' do
            received = nil
            target = Object.new
            target.define_singleton_method(:my_preset=) { |v| received = v }
            target.define_singleton_method(:my_preset)  { received }

            opts = build_options(['-Pmypreset'])
            opts.declare(:my_preset, description: 'Load preset', short: 'P',
              handler: {o: target, m: :my_preset})
            opts.parse_options!
            expect(received).to(eq('mypreset'))
          end
        end
      end
    end
  end
end
