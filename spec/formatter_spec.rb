# frozen_string_literal: true

# Unit tests for Aspera::Cli::Formatter option handling — no server, no config file needed.

require 'stringio'
require 'aspera/cli/parser'
require 'aspera/cli/formatter'
require 'aspera/cli/result'

module Aspera
  module Cli
    RSpec.describe(Formatter) do
      # @return [Formatter] formatter bound to a parser with the given command line and preset
      def build_formatter(argv, preset: nil)
        parser = Parser.new('test', argv)
        formatter = described_class.new
        formatter.declare_options(parser)
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

        it 'sets the default output level from the format' do
          expect(build_formatter([]).instance_variable_get(:@options)[:display]).to(eq(:info))
          expect(build_formatter(['--format=json']).instance_variable_get(:@options)[:display]).to(eq(:data))
        end

        it 'keeps an explicit output level, whatever the order of options' do
          [
            ['--out.level=error', '--format=json'],
            ['--format=json', '--out.level=error'],
            ['--out=@json:{"level":"error","format":"json"}']
          ].each do |argv|
            expect(build_formatter(argv).instance_variable_get(:@options)[:display]).to(eq(:error), argv.join(' '))
          end
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

      describe 'option out colors and utf8' do
        # Rainbow and Environment settings are global: restore them after each test
        around do |example|
          colors = Rainbow.enabled
          example.run
        ensure
          Rainbow.enabled = colors
          Environment.unicode = nil
        end

        it 'overrides colors detection' do
          Rainbow.enabled = false
          build_formatter(['--out.colors=yes'])
          expect(Rainbow.enabled).to(be(true))
          build_formatter(['--out.colors=no'])
          expect(Rainbow.enabled).to(be(false))
        end

        it 'restores detected colors when reset' do
          Rainbow.enabled = false
          build_formatter(['--out.colors=yes', '--out.colors=@none:'])
          expect(Rainbow.enabled).to(be(false))
        end

        it 'disables detected colors when results go to a file, unless forced' do
          Dir.mktmpdir do |dir|
            file = File.join(dir, 'result.txt')
            {
              ["--out.file=#{file}"]                     => false,
              ['--out.colors=yes', "--out.file=#{file}"] => true,
              ['--out.file=-']                           => true
            }.each do |argv, colors|
              Rainbow.enabled = true
              build_formatter(argv)
              expect(Rainbow.enabled).to(be(colors), argv.join(' '))
            ensure
              $stdout.close unless $stdout.equal?(STDOUT) # rubocop:disable Style/GlobalStdStream
              $stdout = STDOUT
            end
          end
        end

        it 'overrides Unicode detection' do
          allow($stdout).to(receive(:tty?).and_return(false))
          expect(Environment.terminal_supports_unicode?).to(be(false))
          build_formatter(['--out.utf8=yes'])
          expect(Environment.terminal_supports_unicode?).to(be(true))
          expect(TerminalFormatter.tick(true)).to(include("\u2713"))
          build_formatter(['--out.utf8=no'])
          expect(Environment.terminal_supports_unicode?).to(be(false))
          build_formatter(['--out.utf8=@none:'])
          expect(Environment.terminal_supports_unicode?).to(be(false))
        end
      end

      describe 'structured formats' do
        # @return [String] standard output of the display of result
        def output_of(result, format)
          formatter = build_formatter(["--format=#{format}"])
          saved = $stdout
          $stdout = StringIO.new
          formatter.display_results(result)
          $stdout.string
        ensure
          $stdout = saved
        end

        {
          Result::Status.new('modified') => 'modified',
          Result::Empty.new              => [],
          Result::Nothing.new            => nil,
          Result::Null.new               => nil
        }.each do |result, expected|
          it "renders #{result.class.name.split('::').last} as valid JSON and YAML" do
            expect(JSON.parse(output_of(result, :json))).to(eq(expected))
            expect(YAML.safe_load(output_of(result, :yaml))).to(eq(expected))
          end

          it "renders #{result.class.name.split('::').last} as text" do
            expect(output_of(result, :text).chomp).to(eq(result.data.to_s))
          end
        end
      end

      describe 'table width' do
        let(:result) { Result::ObjectList.new([{'name' => 'identifier', 'description' => 'word ' * 30}]) }

        # @return [Array<String>] lines of the table display of result
        def table_lines(argv)
          formatter = build_formatter(argv)
          saved = $stdout
          $stdout = StringIO.new
          formatter.display_results(result)
          $stdout.string.lines.map(&:chomp)
        ensure
          $stdout = saved
        end

        it 'fits in the terminal' do
          allow(Environment).to(receive(:terminal_columns).and_return(50))
          expect(table_lines([]).map(&:length).max).to(be_between(40, 50))
        end

        it 'fits in the width of option out.table' do
          expect(table_lines(['--out.table.width=60']).map(&:length).max).to(be_between(50, 60))
        end

        it 'does not fail when width is too small' do
          expect(table_lines(['--out.table.width=10']).map(&:length).max).to(be > 10)
        end
      end
    end
  end
end
