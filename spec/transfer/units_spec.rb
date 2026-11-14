# frozen_string_literal: true

require_relative '../../lib/aspera/transfer/units'
require 'bundler/setup'

module Aspera
  module Transfer
    RSpec.describe(Units) do
      describe '.rate_string_to_bps' do
        context 'with a plain integer (no suffix)' do
          it 'returns the value as-is in bps' do
            expect(described_class.rate_string_to_bps('500000')).to(eq(500_000))
          end

          it 'accepts zero' do
            expect(described_class.rate_string_to_bps('0')).to(eq(0))
          end

          it 'accepts an Integer' do
            expect(described_class.rate_string_to_bps(100_000_000)).to(eq(100_000_000))
          end

          it 'ignores surrounding spaces' do
            expect(described_class.rate_string_to_bps(' 100m ')).to(eq(100_000_000))
          end
        end

        context 'with suffix k/K (x1000)' do
          it 'multiplies by 1000 for lowercase k' do
            expect(described_class.rate_string_to_bps('100k')).to(eq(100_000))
          end

          it 'multiplies by 1000 for uppercase K' do
            expect(described_class.rate_string_to_bps('100K')).to(eq(100_000))
          end
        end

        context 'with suffix m/M (x1000000)' do
          it 'multiplies by 1_000_000 for lowercase m' do
            expect(described_class.rate_string_to_bps('100m')).to(eq(100_000_000))
          end

          it 'multiplies by 1_000_000 for uppercase M' do
            expect(described_class.rate_string_to_bps('100M')).to(eq(100_000_000))
          end
        end

        context 'with suffix g/G (x1000000000)' do
          it 'multiplies by 1_000_000_000 for lowercase g' do
            expect(described_class.rate_string_to_bps('1g')).to(eq(1_000_000_000))
          end

          it 'multiplies by 1_000_000_000 for uppercase G' do
            expect(described_class.rate_string_to_bps('2G')).to(eq(2_000_000_000))
          end
        end

        context 'with invalid input' do
          it 'raises on a non-numeric string' do
            expect { described_class.rate_string_to_bps('fast') }.to(raise_error(Aspera::AssertError))
          end

          it 'raises on an unknown suffix' do
            expect { described_class.rate_string_to_bps('100x') }.to(raise_error(Aspera::AssertError))
          end

          it 'raises on a float value' do
            expect { described_class.rate_string_to_bps('1.5m') }.to(raise_error(Aspera::AssertError))
          end

          it 'raises on a negative value' do
            expect { described_class.rate_string_to_bps(-1) }.to(raise_error(Aspera::AssertError))
          end

          it 'raises on an empty string' do
            expect { described_class.rate_string_to_bps('') }.to(raise_error(Aspera::AssertError))
          end
        end
      end

      describe '.rate_bps_to_string' do
        it 'gives the shortest exact text, read back by rate_string_to_bps' do
          {100_000_000 => '100M', 1_000_000_000 => '1G', 2 * (10**12) => '2T', 1_500_000 => '1500K', 999 => '999', 0 => '0'}.each do |bps, text|
            expect(described_class.rate_bps_to_string(bps)).to(eq(text))
            expect(described_class.rate_string_to_bps(text)).to(eq(bps))
          end
        end
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
    end
  end
end
