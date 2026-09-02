# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/transfer/spec'

module Aspera
  module Transfer
    RSpec.describe(Spec) do
      describe '.rate_string_to_kbps' do
        context 'with a plain integer (no suffix)' do
          it 'returns the value as-is in kbps' do
            expect(described_class.rate_string_to_kbps('500000')).to(eq(500_000))
          end

          it 'accepts zero' do
            expect(described_class.rate_string_to_kbps('0')).to(eq(0))
          end

          it 'returns 900 as-is (not Mbps, not bps — plain kbps)' do
            expect(described_class.rate_string_to_kbps('900')).to(eq(900))
          end
        end

        context 'with suffix k/K (kbps)' do
          it 'returns unchanged value for lowercase k' do
            expect(described_class.rate_string_to_kbps('100k')).to(eq(100))
          end

          it 'returns unchanged value for uppercase K' do
            expect(described_class.rate_string_to_kbps('100K')).to(eq(100))
          end
        end

        context 'with suffix m/M (x1000 kbps)' do
          it 'multiplies by 1000 for lowercase m' do
            expect(described_class.rate_string_to_kbps('100m')).to(eq(100_000))
          end

          it 'multiplies by 1000 for uppercase M' do
            expect(described_class.rate_string_to_kbps('100M')).to(eq(100_000))
          end

          it 'handles 1m' do
            expect(described_class.rate_string_to_kbps('1m')).to(eq(1_000))
          end
        end

        context 'with suffix g/G (x1000000 kbps)' do
          it 'multiplies by 1_000_000 for lowercase g' do
            expect(described_class.rate_string_to_kbps('1g')).to(eq(1_000_000))
          end

          it 'multiplies by 1_000_000 for uppercase G' do
            expect(described_class.rate_string_to_kbps('2G')).to(eq(2_000_000))
          end
        end

        context 'with invalid input' do
          it 'raises on a non-numeric string' do
            expect{described_class.rate_string_to_kbps('fast')}.to(raise_error(Aspera::AssertError))
          end

          it 'raises on an unknown suffix' do
            expect{described_class.rate_string_to_kbps('100x')}.to(raise_error(Aspera::AssertError))
          end

          it 'raises on a float value' do
            expect{described_class.rate_string_to_kbps('1.5m')}.to(raise_error(Aspera::AssertError))
          end

          it 'raises on an empty string' do
            expect{described_class.rate_string_to_kbps('')}.to(raise_error(Aspera::AssertError))
          end
        end
      end
    end
  end
end
