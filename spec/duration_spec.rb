# frozen_string_literal: true

require 'spec_helper'
require 'aspera/duration'

RSpec.describe(Aspera::Duration) do
  describe '.to_unit' do
    it 'converts unit format' do
      expect(described_class.to_unit('1h 30m', 'ms')).to(eq(5_400_000))
      expect(described_class.to_unit('1w2d', 'ms')).to(eq(777_600_000))
      expect(described_class.to_unit('2s500ms', 'ms')).to(eq(2_500))
      expect(described_class.to_unit('1500us', 'ms')).to(eq(1))
    end

    it 'converts clock format' do
      expect(described_class.to_unit('90', 'ms')).to(eq(90_000))
      expect(described_class.to_unit('1.5', 'ms')).to(eq(1_500))
      expect(described_class.to_unit('5:30', 'ms')).to(eq(330_000))
      expect(described_class.to_unit('1d 02:00:00.250', 'ms')).to(eq(93_600_250))
    end

    it 'converts to other units' do
      expect(described_class.to_unit('1h 30m', 's')).to(eq(5_400))
      expect(described_class.to_unit('5d', 's')).to(eq(432_000))
      expect(described_class.to_unit('0', 's')).to(eq(0))
      expect(described_class.to_unit('1.5', 'us')).to(eq(1_500_000))
      expect { described_class.to_unit('1h', 'x') }.to(raise_error(Aspera::AssertError, /duration unit/))
    end

    it 'fails on invalid duration' do
      expect { described_class.to_unit('30x', 'ms') }.to(raise_error(Aspera::ParameterError, /Invalid duration/))
      expect { described_class.to_unit('', 'ms') }.to(raise_error(Aspera::ParameterError, /Invalid duration/))
      expect { described_class.to_unit('-1', 's') }.to(raise_error(Aspera::ParameterError, /Invalid duration/))
    end
  end
end
