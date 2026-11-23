# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Option `poll`: repetition of a read-only command, no server needed. Time and sleep are simulated.

require_relative '../lib/aspera/cli/runner'
require_relative '../lib/aspera/cli/poll'
require_relative '../lib/aspera/cli/plugins/orchestrator'
require_relative '../lib/aspera/cli/plugins/faspex5'
require_relative '../lib/aspera/cli/plugins/node'
require_relative '../lib/aspera/cli/plugins/aoc'
require_relative '../lib/aspera/cli/plugins/server'
require_relative '../lib/aspera/cli/plugins/shares'
require_relative '../lib/aspera/cli/plugins/ats'
require_relative '../lib/aspera/plugins/httpgw/commands'
require 'json'
require 'tmpdir'

module Aspera
  module Cli
    RSpec.describe(Result::Poll) do
      # Formatter with the given command line options, e.g. `--format=json`
      def build_formatter(*argv)
        parser = Parser.new('test', argv)
        formatter = Formatter.new
        formatter.declare_options(parser)
        parser.parse_options!
        formatter
      end

      # Poll whose action returns the given data, one per run (the last one repeated), with simulated time
      # An exception is raised, an Array is a list of objects
      # @return [Result::Poll]
      def build_poll(parameters, data_list)
        poll = described_class.new(parameters)
        runs = data_list.dup
        poll.action = lambda do
          data = runs.length > 1 ? runs.shift : runs.first
          raise data if data.is_a?(Exception)
          data.is_a?(Array) ? Result::ObjectList.new(data) : Result::SingleObject.new(data)
        end
        now = 0.0
        allow(poll).to(receive(:clock)) { now }
        allow(poll).to(receive(:pause)) { |seconds| now += seconds }
        poll
      end

      let(:formatter) { build_formatter('--format=json') }

      # Displayed lines of stdout and stderr
      def run_poll(poll)
        stdout = nil
        stderr = StringIO.new
        saved = $stderr
        $stderr = stderr
        begin
          error = nil
          stdout = capture_stdout do
            poll.format(formatter)
          rescue StandardError => e
            error = e
          end
        ensure
          $stderr = saved
        end
        [stdout.lines.map { |line| JSON.parse(line) }, stderr.string.lines.map(&:chomp), error]
      end

      def capture_stdout
        saved = $stdout
        $stdout = StringIO.new
        yield
        $stdout.string
      ensure
        $stdout = saved
      end

      describe 'until' do
        it 'stops as soon as the condition is true' do
          poll = build_poll({'interval' => 10, 'max' => 5, 'until' => 'status == `Complete`'}, [{'status' => 'Running'}, {'status' => 'Running'}, {'status' => 'Complete'}])
          displayed, status, error = run_poll(poll)
          expect(error).to(be_nil)
          expect(displayed).to(eq([{'status' => 'Running'}, {'status' => 'Complete'}]))
          expect(status.first).to(match(%r{\Apoll: run 1/5 \d{4}-\d\d-\d\d \d\d:\d\d:\d\d\z}))
          expect(status.last).to(eq('poll: condition met at run 3'))
          expect(poll).to(have_received(:pause).with(10).twice)
        end

        it 'fails when the condition is never met' do
          poll = build_poll({'interval' => 1, 'max' => 3, 'until' => 'status == `Complete`'}, [{'status' => 'Running'}])
          displayed, _status, error = run_poll(poll)
          expect(error).to(be_a(PollConditionNotMet))
          expect(error.message).to(eq('condition not met after 3 runs: status == `Complete`'))
          expect(displayed).to(eq([{'status' => 'Running'}]))
          expect(poll).to(have_received(:pause).twice)
        end

        it 'stops at timeout, with a last run at the time limit' do
          poll = build_poll({'interval' => '4s', 'timeout' => '10s', 'until' => 'status == `Complete`'}, [{'status' => 'Running'}])
          _displayed, _status, error = run_poll(poll)
          expect(error.message).to(start_with('condition not met after 4 runs'))
          expect(poll).to(have_received(:pause).with(4).twice)
          expect(poll).to(have_received(:pause).with(2.0).once)
        end

        it 'takes durations with a unit' do
          poll = build_poll({'interval' => '1m', 'max' => 2}, [{'n' => 1}])
          run_poll(poll)
          expect(poll).to(have_received(:pause).with(60).once)
        end

        it 'waits for a non-empty list with @' do
          poll = build_poll({'max' => 5, 'until' => '@'}, [[], [], [{'id' => 'a'}]])
          displayed, status, error = run_poll(poll)
          expect(error).to(be_nil)
          expect(displayed).to(eq([[], [{'id' => 'a'}]]))
          expect(status.last).to(eq('poll: condition met at run 3'))
        end

        it 'evaluates the expression after --select' do
          formatter = build_formatter('--format=json', '--select=@json:{"status":"Running"}')
          poll = build_poll({'max' => 2, 'until' => '@'}, [[{'id' => 'a', 'status' => 'Complete'}]])
          allow(formatter).to(receive(:display_message).and_call_original)
          allow(formatter).to(receive(:display_message).with(:error, anything))
          error = nil
          capture_stdout do
            poll.format(formatter)
          rescue PollConditionNotMet => e
            error = e
          end
          expect(error).not_to(be_nil)
        end

        it 'uses the truth of JMESPath' do
          [false, nil, '', [], {}].each { |value| expect(described_class.truthy?(value)).to(be(false), value.inspect) }
          [true, 0, 'x', [1], {'a' => 1}].each { |value| expect(described_class.truthy?(value)).to(be(true), value.inspect) }
        end

        it 'evaluates the expression on the data before --out.query' do
          formatter = build_formatter('--format=json', '--out.query=name')
          poll = build_poll({'max' => 2, 'until' => 'status == `Complete`'}, [{'name' => 'a', 'status' => 'Complete'}])
          allow(formatter).to(receive(:display_message).and_call_original)
          allow(formatter).to(receive(:display_message).with(:error, anything))
          stdout = capture_stdout { poll.format(formatter) }
          expect(stdout).to(eq(%("a"\n)))
        end

        it 'checks the syntax before the first run' do
          expect { described_class.new({'until' => 'status =='}) }.to(raise_error(BadArgument, /poll.until: JMESPath/))
        end
      end

      describe 'show' do
        let(:data_list) { [{'n' => 1}, {'n' => 1}, {'n' => 2}, {'n' => 2}] }

        it 'change: displays a result when it differs from the previous one' do
          displayed, status, = run_poll(build_poll({'max' => 4}, data_list))
          expect(displayed).to(eq([{'n' => 1}, {'n' => 2}]))
          expect(status.map { |line| line[%r{run \d+/\d+}] }).to(eq(['run 1/4', 'run 3/4']))
        end

        it 'each: displays every result' do
          displayed, = run_poll(build_poll({'max' => 4, 'show' => 'each'}, data_list))
          expect(displayed.length).to(eq(4))
        end

        it 'last: displays only the last result' do
          displayed, status, = run_poll(build_poll({'max' => 4, 'show' => 'last'}, data_list))
          expect(displayed).to(eq([{'n' => 2}]))
          expect(status.length).to(eq(1))
        end

        it 'last: displays the last result, also when interrupted' do
          poll = build_poll({'show' => 'last'}, [{'n' => 1}])
          calls = 0
          allow(poll).to(receive(:pause)) { (calls += 1) > 1 ? raise(Interrupt) : nil }
          allow(formatter).to(receive(:display_message).and_call_original)
          allow(formatter).to(receive(:display_message).with(:error, anything))
          interrupted = false
          stdout = capture_stdout do
            poll.format(formatter)
          rescue Interrupt
            interrupted = true
          end
          expect(interrupted).to(be(true))
          expect(stdout).to(eq(%({"n":1}\n)))
        end
      end

      describe 'errors' do
        it 'fail: ends with the error of a run' do
          poll = build_poll({'max' => 3}, [RuntimeError.new('not ready'), {'n' => 1}])
          _displayed, _status, error = run_poll(poll)
          expect(error.message).to(eq('not ready'))
          expect(poll).not_to(have_received(:pause))
        end

        it 'retry: runs again after an error' do
          poll = build_poll({'max' => 3, 'until' => '@', 'errors' => 'retry'}, [RuntimeError.new('not ready'), {'n' => 1}])
          displayed, status, error = run_poll(poll)
          expect(error).to(be_nil)
          expect(displayed).to(eq([{'n' => 1}]))
          expect(status.first).to(match(%r{\Apoll: run 1/3 .* error: not ready\z}))
        end

        it 'retry: ends with the error of the last run' do
          poll = build_poll({'max' => 2, 'errors' => 'retry'}, [RuntimeError.new('not ready')])
          _displayed, _status, error = run_poll(poll)
          expect(error.message).to(eq('not ready'))
        end
      end

      describe 'parameters' do
        it 'refuses an unknown parameter, a bad value or format nagios' do
          expect { described_class.new({'every' => 1}) }.to(raise_error(BadArgument, /unknown parameter: every/))
          expect { described_class.new({'max' => 0}) }.to(raise_error(BadArgument, /poll.max/))
          expect { described_class.new({'show' => 'all'}) }.to(raise_error(BadArgument))
          expect { described_class.new({'interval' => 'soon'}) }.to(raise_error(BadArgument, /poll.interval/))
          expect { described_class.new({'errors' => 'ignore'}) }.to(raise_error(BadArgument))
          expect { described_class.new({}, format: :nagios) }.to(raise_error(BadArgument, /nagios/))
        end
      end

      describe 'read-only commands' do
        # Result of the command line, not displayed
        def run_with_result(*argv)
          Dir.mktmpdir do |home|
            stub_const('ENV', ENV.to_h.merge('ASCLI_HOME' => home))
            Runner.new([*argv, '--version-check-days=0']).run_with_result
          end
        end

        it 'refuses a command that changes state, before anything is executed' do
          allow(Rest::Client).to(receive(:new))
          expect do
            run_with_result('faspex5', 'packages', 'send', '@json:{"title":"test"}', 'test-file', '--url=https://localhost', '--poll.max=2')
          end.to(raise_error(BadArgument, /refused on `faspex5 packages send`: only a read-only command/))
          expect(Rest::Client).not_to(have_received(:new))
        end

        it 'refuses options that change state at each run' do
          expect { run_with_result('config', 'echo', 'test-value', '--poll.max=2', '--once-only=yes') }.to(raise_error(BadArgument, /once_only/))
        end

        it 'accepts a read-only command, executed when displayed' do
          expect(run_with_result('config', 'echo', 'test-value', '--poll.max=2')).to(be_a(described_class))
        end

        it 'marks the generic list and show operations, and the commands of the demo' do
          {
            Plugins::Orchestrator => [%i[workflows workorders], %i[workorders status], %i[tasks list], %i[pools status], %i[queues list], %i[queues items]],
            Plugins::Faspex5      => [%i[packages list], %i[packages show], %i[admin workgroups list]],
            Plugins::Node         => [%i[ls], %i[transfer list], %i[access_keys list], %i[access_keys show], %i[access_keys do thumbnail]],
            Plugins::Aoc          => [%i[packages list], %i[admin analytics transfers]]
          }.each do |plugin, paths|
            paths.each { |path| expect(plugin.command_registry[path].read_only?).to(be(true), "#{plugin} #{path}") }
          end
          expect(Plugins::Faspex5.command_registry[%i[packages send]].read_only?).to(be(false))
          expect(Plugins::Node.command_registry[%i[access_keys delete]].read_only?).to(be(false))
        end

        it 'marks the read-only commands of server, and other commands that only read' do
          {
            Plugins::Server  => [%i[ls], %i[df], %i[du], %i[md5sum], %i[info]],
            Plugins::Node    => [%i[async list], %i[ssync state], %i[stream list], %i[service list], %i[watch_folder show]],
            Plugins::Faspex5 => [%i[user profile show], %i[admin configuration show], %i[admin smtp show]],
            Plugins::Shares  => [%i[info], %i[share list]],
            Plugins::Ats     => [%i[cluster list], %i[access_key show]],
            Aspera::Plugins::Httpgw::Commands => [%i[info]]
          }.each do |plugin, paths|
            paths.each { |path| expect(plugin.command_registry[path].read_only?).to(be(true), "#{plugin} #{path}") }
          end
          %i[rm mv cp mkdir upload download].each { |cmd| expect(Plugins::Server.command_registry[[cmd]].read_only?).to(be(false), "server #{cmd}") }
        end

        it 'makes read-only by default the commands with a generic id, unless explicit' do
          expect(CommandSpec.new(id: :list).read_only).to(eq(:default))
          READ_ONLY_IDS.each { |id| expect(CommandSpec.new(id: id).read_only?).to(be(true), id.to_s) }
          expect(CommandSpec.new(id: :delete).read_only?).to(be(false))
          expect(CommandSpec.new(id: :show, read_only: false).read_only?).to(be(false))
          expect(CommandSpec.new(id: :stats, read_only: true).read_only?).to(be(true))
          expect { CommandSpec.new(id: :list, read_only: :yes) }.to(raise_error(StandardError, /read_only/))
          require_relative '../lib/aspera/cli/plugins/preview'
          expect(Plugins::Preview.command_registry[%i[show]].read_only?).to(be(false))
        end
      end
    end
  end
end
