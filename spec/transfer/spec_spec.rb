# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/transfer/spec'

module Aspera
  module Transfer
    RSpec.describe(Spec) do
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

      describe '.resolve_target_rate' do
        it 'converts target_rate (bps) into target_rate_kbps' do
          ts = {'target_rate' => '100m'}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 100_000}))
        end

        it 'rounds down to kbps' do
          ts = {'target_rate' => 1_999}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 1}))
        end

        it 'overrides target_rate_kbps' do
          ts = {'target_rate_kbps' => 5, 'target_rate' => '1g'}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 1_000_000}))
        end

        it 'removes a nil target_rate and keeps target_rate_kbps' do
          ts = {'target_rate_kbps' => 5, 'target_rate' => nil}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 5}))
        end

        it 'leaves a transfer spec without target_rate unchanged' do
          ts = {'target_rate_kbps' => 5}
          described_class.resolve_target_rate(ts)
          expect(ts).to(eq({'target_rate_kbps' => 5}))
        end
      end
    end
  end
end
