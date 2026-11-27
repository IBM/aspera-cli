# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'spec_helper'
require_relative '../../lib/aspera/units/timestamp'

RSpec.describe(Aspera::Units::Timestamp) do
  # Local time zone with daylight saving time, to check that a summer date is not read with the winter offset
  around do |example|
    saved = ENV.fetch('TZ', nil)
    ENV['TZ'] = 'Europe/Paris'
    example.run
  ensure
    ENV['TZ'] = saved
  end

  let(:now) { Time.local(2026, 11, 27, 10, 0, 0) }

  # @return [Time]
  def parse(text, utc: false)
    described_class.parse(text, now: now, utc: utc)
  end

  describe '.parse' do
    it 'gives the reference time or a midnight for a keyword' do
      expect(parse('now')).to(eq(now))
      expect(parse('today')).to(eq(Time.local(2026, 11, 27)))
      expect(parse('yesterday')).to(eq(Time.local(2026, 11, 26)))
      expect(parse(' tomorrow ')).to(eq(Time.local(2026, 11, 28)))
    end

    it 'adds or subtracts a duration from a keyword' do
      expect(parse('now-24h')).to(eq(Time.local(2026, 11, 26, 10, 0, 0)))
      expect(parse('now+1h30m')).to(eq(Time.local(2026, 11, 27, 11, 30, 0)))
      expect(parse('now - 2w')).to(eq(Time.local(2026, 11, 13, 10, 0, 0)))
      expect(parse('now-500ms')).to(eq(now - 0.5))
      expect(parse('today+9h')).to(eq(Time.local(2026, 11, 27, 9, 0, 0)))
      expect(parse('yesterday+1d 02:00:00')).to(eq(Time.local(2026, 11, 27, 2, 0, 0)))
    end

    it 'parses an absolute date in local time, unless a time zone is given' do
      expect(parse('2026-11-01 08:30:00')).to(eq(Time.local(2026, 11, 1, 8, 30, 0)))
      expect(parse('2026-07-01 12:00').utc_offset).to(eq(7200))
      expect(parse('2026-07-01T12:00:00Z')).to(eq(Time.utc(2026, 7, 1, 12, 0, 0)))
      expect(parse('2026-07-01T12:00:00+05:00')).to(eq(Time.utc(2026, 7, 1, 7, 0, 0)))
      expect(parse('12:30')).to(eq(Time.local(2026, 11, 27, 12, 30, 0)))
    end

    it 'with utc, reads a date without time zone, and midnight, in UTC' do
      expect(parse('2013-02-28 12:00:00', utc: true)).to(eq(Time.utc(2013, 2, 28, 12, 0, 0)))
      expect(parse('2013-02-28T12:00:00+01:00', utc: true)).to(eq(Time.utc(2013, 2, 28, 11, 0, 0)))
      expect(parse('today', utc: true)).to(eq(Time.utc(2026, 11, 27)))
      expect(parse('now-24h', utc: true)).to(eq(Time.utc(2026, 11, 26, 9, 0, 0)))
    end

    it 'refuses a duration not after a keyword' do
      expect { parse('30s') }.to(raise_error(Aspera::ParameterError, /use now-30s or now\+30s/))
      expect { parse('1h30m') }.to(raise_error(Aspera::ParameterError, /use now-1h30m or now\+1h30m/))
      expect { parse('1d 02:00:00') }.to(raise_error(Aspera::ParameterError, /use now-1d 02:00:00/))
      expect { parse('-1h') }.to(raise_error(Aspera::ParameterError, /use now-1h/))
      expect { parse('+12:30') }.to(raise_error(Aspera::ParameterError, /use now\+12:30/))
    end

    it 'refuses a number of seconds, read by Time.parse as a day of month or a time, but parses a compact date' do
      expect { parse('30') }.to(raise_error(Aspera::ParameterError, /use now-30 or now\+30/))
      expect { parse('3600') }.to(raise_error(Aspera::ParameterError, /use now-3600 or now\+3600/))
      expect { parse('30.5') }.to(raise_error(Aspera::ParameterError, /use now-30.5 or now\+30.5/))
      expect(parse('now-30')).to(eq(Time.local(2026, 11, 27, 9, 59, 30)))
      expect(parse('20261101')).to(eq(Time.local(2026, 11, 1)))
      expect(parse('20261101T083000Z')).to(eq(Time.utc(2026, 11, 1, 8, 30, 0)))
    end

    it 'fails on an invalid date or duration' do
      expect { parse('foo') }.to(raise_error(Aspera::ParameterError, /Invalid date: foo .*expected a date/))
      expect { parse('2026-13-01') }.to(raise_error(Aspera::ParameterError, /Invalid date: 2026-13-01/))
      expect { parse('') }.to(raise_error(Aspera::ParameterError, /Invalid date/))
      expect { parse('now-x') }.to(raise_error(Aspera::ParameterError, /Invalid duration: x/))
      expect { parse('now-') }.to(raise_error(Aspera::ParameterError, /Invalid date: now-/))
      expect { described_class.parse(nil) }.to(raise_error(Aspera::AssertError))
    end
  end
end
