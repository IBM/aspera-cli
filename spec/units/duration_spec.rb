# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../../lib/aspera/units/duration'

RSpec.describe(Aspera::Units::Duration) do
  # @return [Integer] Duration of `text` in `unit`
  def to_unit(text, unit)
    described_class.new(text).to_unit(unit)
  end

  describe '#to_unit' do
    it 'converts unit format' do
      expect(to_unit('1h 30m', 'ms')).to(eq(5_400_000))
      expect(to_unit('1w2d', 'ms')).to(eq(777_600_000))
      expect(to_unit('2s500ms', 'ms')).to(eq(2_500))
      expect(to_unit('1500us', 'ms')).to(eq(1))
    end

    it 'converts clock format' do
      expect(to_unit('90', 'ms')).to(eq(90_000))
      expect(to_unit('1.5', 'ms')).to(eq(1_500))
      expect(to_unit('5:30', 'ms')).to(eq(330_000))
      expect(to_unit('1d 02:00:00.250', 'ms')).to(eq(93_600_250))
    end

    it 'converts to other units' do
      expect(to_unit('1h 30m', 's')).to(eq(5_400))
      expect(to_unit('5d', 's')).to(eq(432_000))
      expect(to_unit('0', 's')).to(eq(0))
      expect(to_unit('1.5', 'us')).to(eq(1_500_000))
      expect { to_unit('1h', 'x') }.to(raise_error(Aspera::AssertError, /duration unit/))
    end

    it 'fails on invalid duration' do
      expect { described_class.new('30x') }.to(raise_error(Aspera::ParameterError, /Invalid duration/))
      expect { described_class.new('') }.to(raise_error(Aspera::ParameterError, /Invalid duration/))
      expect { described_class.new('-1') }.to(raise_error(Aspera::ParameterError, /Invalid duration/))
    end
  end

  describe '#initialize' do
    it 'takes a number in the given unit, seconds by default' do
      expect(described_class.new(90).to_unit('ms')).to(eq(90_000))
      expect(described_class.new(0.5).to_unit('ms')).to(eq(500))
      expect(described_class.new(1500, 'ms').to_unit('s')).to(eq(1))
      expect(described_class.new(2, 'h').to_unit('m')).to(eq(120))
    end

    it 'rejects an unknown unit or type' do
      expect { described_class.new(1, 'x') }.to(raise_error(Aspera::AssertError, /duration unit/))
      expect { described_class.new(nil) }.to(raise_error(Aspera::AssertError))
    end

    it 'is immutable' do
      expect(described_class.new(1)).to(be_frozen)
    end
  end

  describe '#to_s' do
    it 'formats in units' do
      expect(described_class.new(3).to_s).to(eq('3s'))
      expect(described_class.new(123).to_s).to(eq('2m03s'))
      expect(described_class.new(3723.4).to_s).to(eq('1h02m03s'))
    end

    it 'gives a text accepted by the constructor' do
      [0, 59, 60, 3599, 3600, 90_061].each do |seconds|
        expect(described_class.new(described_class.new(seconds).to_s).to_unit('s')).to(eq(seconds))
      end
    end
  end

  describe '#to_hms' do
    it 'formats as clock' do
      expect(described_class.new(3725.4).to_hms).to(eq('01:02:05'))
    end
  end

  describe 'comparison' do
    it 'compares durations of any unit' do
      expect(described_class.new('1m')).to(eq(described_class.new(60)))
      expect(described_class.new('1h')).to(be > described_class.new(59, 'm'))
      expect(described_class.new('1m')).to(eql(described_class.new(60_000, 'ms')))
      expect(described_class.new('1m').hash).to(eq(described_class.new(60).hash))
    end
  end
end
