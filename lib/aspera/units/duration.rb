# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require 'strscan'

module Aspera
  module Units
    # Duration in the format of Aspera Sync (`async` DURATION): parsed from user input and formatted for display.
    # Immutable, kept as an integer number of microseconds.
    class Duration
      include Comparable

      # Microseconds per unit
      UNIT_US = {'w' => 604_800_000_000, 'd' => 86_400_000_000, 'h' => 3_600_000_000, 'm' => 60_000_000, 's' => 1_000_000, 'ms' => 1_000, 'us' => 1}.freeze
      private_constant :UNIT_US

      # @param value [Numeric, String] Number of `unit`, or text parsed (a plain number in text is seconds, whatever `unit`)
      # @param unit  [String]          Time unit of a `Numeric` value, e.g. `ms`
      # @raise [ParameterError] if the text is invalid
      def initialize(value, unit = 's')
        @microseconds =
          if value.is_a?(Numeric)
            (value * unit_us(unit)).round
          else
            Aspera.assert_type(value, String) { 'duration' }
            parse_us(value)
          end
        freeze
      end

      # @return [Integer] Duration in microseconds
      attr_reader :microseconds

      # @param unit [String] Time unit of result, e.g. `ms`
      # @return [Integer] Duration in `unit`, rounded down
      def to_unit(unit)
        @microseconds / unit_us(unit)
      end

      # @return [String] Duration as `1h02m03s`, `2m03s` or `3s` (seconds rounded), accepted by {#initialize}
      def to_s
        seconds = rounded_seconds
        return "#{seconds}s" if seconds < 60
        hours, rest = seconds.divmod(3600)
        minutes, secs = rest.divmod(60)
        hours.positive? ? format('%dh%02dm%02ds', hours, minutes, secs) : format('%dm%02ds', minutes, secs)
      end

      # @return [String] Duration as `hh:mm:ss` (seconds rounded)
      def to_hms
        seconds = rounded_seconds
        format('%02d:%02d:%02d', seconds / 3600, (seconds / 60) % 60, seconds % 60)
      end

      def <=>(other)
        return unless other.is_a?(Duration)
        @microseconds <=> other.microseconds
      end

      def eql?(other)
        other.is_a?(Duration) && @microseconds.eql?(other.microseconds)
      end

      def hash
        @microseconds.hash
      end

      private

      # @param unit [String] Time unit
      # @return [Integer] Microseconds per unit
      def unit_us(unit)
        Aspera.assert_values(unit, UNIT_US.keys) { 'duration unit' }
        UNIT_US[unit]
      end

      # @param value [String] `DDd HH:MM:SS.mmm` or `NNw NNd NNh NNm NNs NNms NNus`, leading fields and spaces may be omitted, a plain number is seconds
      # @return [Integer] Duration in microseconds
      # @raise [ParameterError] if the duration is invalid
      def parse_us(value)
        value = value.delete(' ')
        if (m = value.match(/\A(?:(\d+)d)?(?:(?:(\d+):)?(\d+):)?(\d+)(?:\.(\d{1,3}))?\z/))
          days, hours, minutes, seconds, millis = m.captures
          hours = (days.to_i * 24) + hours.to_i
          minutes = (hours * 60) + minutes.to_i
          seconds = (minutes * 60) + seconds.to_i
          return (seconds * UNIT_US['s']) + (millis.to_s.ljust(3, '0').to_i * UNIT_US['ms'])
        end
        # anchored sequential matching (linear time, no backtracking over start positions)
        scanner = StringScanner.new(value)
        units = []
        until scanner.eos?
          Aspera.assert(scanner.scan(/(\d+)(ms|us|[wdhms])/), type: ParameterError) { "Invalid duration: #{value}" } # cspell:disable-line
          units.push([scanner[1], scanner[2]])
        end
        Aspera.assert(!units.empty?, type: ParameterError) { "Invalid duration: #{value}" }
        units.sum { |number, number_unit| number.to_i * UNIT_US[number_unit] }
      end

      # @return [Integer] Duration in seconds, rounded
      def rounded_seconds
        (@microseconds.to_r / UNIT_US['s']).round
      end
    end
  end
end
