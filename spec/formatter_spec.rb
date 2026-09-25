# frozen_string_literal: true

# Unit tests for Aspera::Cli::Formatter option handling — no server, no config file needed.

require 'aspera/cli/parser'
require 'aspera/cli/formatter'

module Aspera
  module Cli
    RSpec.describe(Formatter) do
      # @return [Formatter] formatter bound to a parser with the given command line and preset
      def build_formatter(argv, preset: nil)
        parser = Parser.new('test', argv)
        formatter = described_class.new
        described_class.declare_options(parser)
        formatter.bind_options(parser)
        parser.add_option_preset(preset, 'test') unless preset.nil?
        parser.parse_options!
        formatter
      end

      describe 'option out' do
        it 'dispatches sub-options to individual options' do
          formatter = build_formatter(['--out.format=json', '--out.level=error', '--out.flat=no'])
          expect(formatter.format_type).to(eq(:json))
          expect(formatter.flat_hash?).to(be(false))
          expect(formatter.instance_variable_get(:@options)[:display]).to(eq(:error))
        end

        it 'does not dispatch again unchanged sub-options' do
          # `--format` is not overridden by the previous `--out.format` when `--out.level` is added
          formatter = build_formatter(['--out.format=json', '--format=yaml', '--out.level=info'])
          expect(formatter.format_type).to(eq(:yaml))
        end

        it 'gives priority to command line over preset' do
          formatter = build_formatter(['--out.format=json'], preset: {out: {'format' => 'csv', 'flat' => false}})
          expect(formatter.format_type).to(eq(:json))
          expect(formatter.flat_hash?).to(be(false))
        end

        it 'does not override an individual option given on command line' do
          formatter = build_formatter(['--format=json'], preset: {out: {'format' => 'csv'}})
          expect(formatter.format_type).to(eq(:json))
        end

        it 'dispatches table pivot to multi_single' do
          expect(build_formatter(['--out.table.pivot=yes']).instance_variable_get(:@options)[:multi_single]).to(eq(:yes))
          expect(build_formatter(['--out.table.pivot=no']).instance_variable_get(:@options)[:multi_single]).to(eq(:no))
          expect(build_formatter(['--out.table.pivot=single']).instance_variable_get(:@options)[:multi_single]).to(eq(:single))
        end

        it 'rejects an unknown sub-option' do
          expect { build_formatter(['--out.foo=bar']) }.to(raise_error(/out sub-option/))
        end
      end
    end
  end
end
