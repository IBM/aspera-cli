# frozen_string_literal: true

# Unit tests for Aspera::Cli::TransferProgress: progress bar fed with transfer events.

require 'stringio'
require 'aspera/cli/transfer_progress'

module Aspera
  module Cli
    RSpec.describe(TransferProgress) do
      # Terminal output, to get the interactive progress bar (with fixed width)
      let(:output) do
        StringIO.new.tap do |io|
          io.define_singleton_method(:tty?) { true }
          io.define_singleton_method(:winsize) { [24, 100] }
        end
      end
      let(:progress) { described_class.new(output: output) }
      # Simulated monotonic time
      let(:clock) { [0.0] }

      before do
        allow(progress).to(receive(:now) { clock.first })
      end

      # @return [Integer] Size in bytes of `count` megabytes
      def mb(count)
        count * 1_000_000
      end

      # @param seconds [Float] advance simulated time
      def tick(seconds)
        clock[0] += seconds
      end

      # @return [Array<String>] Displayed lines, without duplicates
      def lines
        output.string.split(/[\r\n]/).map(&:strip).reject(&:empty?).chunk_while { |a, b| a == b }.map(&:first)
      end

      describe 'formatting' do
        it 'formats sizes with decimal units' do
          expect(described_class.format_bytes(999)).to(eq('999 B'))
          expect(described_class.format_bytes(12_345_678)).to(eq('12.3 MB'))
          expect(described_class.format_bytes(2 * (10**18))).to(eq('2000.0 PB'))
        end

        it 'formats rates in megabits per second' do
          expect(described_class.format_rate(nil)).to(eq('-- Mbps'))
          expect(described_class.format_rate(125_000)).to(eq('1.00 Mbps'))
          expect(described_class.format_rate(12_500_000)).to(eq('100 Mbps'))
        end

        it 'formats durations' do
          expect(described_class.format_duration(nil)).to(eq('--:--:--'))
          expect(described_class.format_duration(3725.4)).to(eq('01:02:05'))
        end
      end

      it 'shows initialization status, without leading space' do
        progress.event(:sessions_init, info: 'starting')
        expect(lines.last).to(start_with('starting Time: 00:00:00'))
      end

      it 'shows transferred bytes and rate when total size is unknown' do
        progress.event(:session_start, session_id: 's1')
        # data starts to flow
        tick(2)
        progress.event(:transfer, session_id: 's1', info: 0)
        tick(1)
        progress.event(:transfer, session_id: 's1', info: mb(10))
        expect(lines.last).to(match(/ 10\.0 MB +80 Mbps$/))
        tick(1)
        progress.event(:transfer, session_id: 's1', info: mb(30))
        expect(lines.last).to(match(/ 30\.0 MB +120 Mbps$/))
        progress.event(:session_size, session_id: 's1', info: mb(30))
        progress.event(:session_end, session_id: 's1')
        progress.event(:end)
        expect(lines.last).to(end_with('100% 30.0 MB 120 Mbps'))
      end

      it 'shows percentage, rate on sliding window and ETA when total size is known' do
        progress.event(:sessions_init, info: 'starting')
        # connection time is not included in rate
        tick(10)
        progress.event(:session_start, session_id: 's1')
        progress.event(:session_size, session_id: 's1', info: mb(100))
        # connection time is not included in rate
        tick(5)
        progress.event(:transfer, session_id: 's1', info: 0)
        tick(1)
        progress.event(:transfer, session_id: 's1', info: mb(10))
        expect(lines.last).to(match(/^Time: \S+ =+ +10% +80 Mbps ETA: 00:00:09$/))
        # older samples leave the window
        6.times do
          tick(1)
          progress.event(:transfer, session_id: 's1', info: mb(10))
        end
        expect(lines.last).to(match(/ 10% +0\.00 Mbps ETA: --:--:--$/))
      end

      it 'does not show rate on a too short period' do
        progress.event(:session_start, session_id: 's1')
        progress.event(:transfer, session_id: 's1', info: 0)
        tick(0.01)
        progress.event(:transfer, session_id: 's1', info: mb(1))
        expect(lines.last).to(match(/ 1\.0 MB +-- Mbps$/))
      end

      it 'keeps size and progress of a restarted session' do
        progress.event(:session_start, session_id: 's1')
        progress.event(:session_size, session_id: 's1', info: mb(100))
        progress.event(:transfer, session_id: 's1', info: mb(30))
        progress.event(:session_end, session_id: 's1')
        expect { progress.event(:session_start, session_id: 's1') }.not_to(raise_error)
        progress.event(:session_size, session_id: 's1', info: mb(100))
        # restarted session notifies again its progress from zero
        progress.event(:transfer, session_id: 's1', info: mb(10))
        expect(lines.last).to(match(/ 30% /))
        progress.event(:skip, session_id: 's1', info: mb(25))
        progress.event(:transfer, session_id: 's1', info: mb(15))
        expect(lines.last).to(match(/ 40% /))
        expect(lines.join).not_to(include('['))
      end

      it 'counts skipped bytes in progress, but not in rate' do
        progress.event(:session_start, session_id: 's1')
        progress.event(:session_size, session_id: 's1', info: mb(100))
        progress.event(:skip, session_id: 's1', info: mb(50))
        progress.event(:transfer, session_id: 's1', info: 0)
        tick(1)
        progress.event(:transfer, session_id: 's1', info: mb(10))
        expect(lines.last).to(match(/ 60% +80 Mbps ETA: 00:00:04$/))
      end

      it 'limits progress of a session to its size' do
        # In multi-session, each session notifies all skipped files
        %w[a b].each do |id|
          progress.event(:session_start, session_id: id)
          progress.event(:session_size, session_id: id, info: mb(6))
          progress.event(:skip, session_id: id, info: mb(12))
        end
        expect(lines.last).to(match(/ 100% /))
      end

      it 'does not complete progress when transfer failed' do
        progress.event(:session_start, session_id: 's1')
        progress.event(:session_size, session_id: 's1', info: mb(100))
        progress.event(:transfer, session_id: 's1', info: mb(30))
        progress.event(:session_end, session_id: 's1')
        progress.event(:end, info: false)
        expect(lines.last).to(match(/^failed Time: .* 30% 30.0 MB /))
        expect(output.string).to(end_with("\n"))
      end

      it 'shows failure before start of session' do
        progress.event(:sessions_init, info: 'starting')
        progress.event(:end, info: false)
        expect(lines.last).to(eq('failed Time: 00:00:00'))
      end

      it 'clears the progress bar to display a log line' do
        expect(progress.suspend { :no_bar }).to(eq(:no_bar))
        progress.event(:session_start, session_id: 's1')
        output.truncate(0)
        output.rewind
        progress.suspend { output.write("log line\n") }
        expect(output.string).to(match(/\A {100}\rlog line\nTime: .*\r\z/))
      end

      it 'starts from scratch after end' do
        2.times do |n|
          progress.event(:session_start, session_id: "r#{n}")
          progress.event(:session_size, session_id: "r#{n}", info: mb(10))
          progress.event(:transfer, session_id: "r#{n}", info: mb(5))
          expect(lines.last).to(match(/ 50% /))
          progress.event(:session_end, session_id: "r#{n}")
          progress.event(:end)
        end
        expect(lines.join).not_to(include('['))
      end

      it 'aggregates multiple sessions' do
        %w[a b].each do |id|
          progress.event(:session_start, session_id: id)
          progress.event(:session_size, session_id: id, info: mb(50))
        end
        progress.event(:transfer, session_id: 'a', info: mb(25))
        expect(lines.last).to(match(/^\[2\] .* 25% /))
        progress.event(:session_end, session_id: 'a')
        expect(lines.last).to(start_with('[1] '))
        progress.event(:session_end, session_id: 'b')
        # status of transfer is not displayed at end
        progress.event(:sessions_init, info: 'running')
        progress.event(:end)
        expect(lines.last).to(match(/^Time: .* 100% 100.0 MB /))
      end

      it 'accepts events from several threads' do
        expect(Log.log).not_to(receive(:warn))
        threads = Array.new(4) do |i|
          Thread.new do
            id = "s#{i}"
            progress.event(:session_start, session_id: id)
            progress.event(:session_size, session_id: id, info: mb(10))
            1.upto(100) { |n| progress.event(:transfer, session_id: id, info: mb(n) / 10) }
            progress.event(:session_end, session_id: id)
          end
        end
        threads.each(&:join)
        expect(lines.last).to(match(/ 100% /))
        progress.event(:end)
      end

      it 'logs errors once, without raising' do
        expect(Log.log).to(receive(:warn).once)
        expect { 2.times { progress.event(:bad_event) } }.not_to(raise_error)
      end
    end
  end
end
