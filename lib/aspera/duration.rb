# frozen_string_literal: true

require 'aspera/assert'
require 'strscan'

module Aspera
  # Duration in the format of Aspera Sync (`async` DURATION)
  module Duration
    # Microseconds per unit
    UNIT_US = {'w' => 604_800_000_000, 'd' => 86_400_000_000, 'h' => 3_600_000_000, 'm' => 60_000_000, 's' => 1_000_000, 'ms' => 1_000, 'us' => 1}.freeze
    private_constant :UNIT_US

    class << self
      # Convert a duration to an integer in the given time unit
      # @param value [String] `DDd HH:MM:SS.mmm` or `NNw NNd NNh NNm NNs NNms NNus`, leading fields and spaces may be omitted, a plain number is seconds
      # @param unit  [String] Time unit of result, e.g. `ms`
      # @return [Integer] Duration in `unit`, rounded down
      def to_unit(value, unit)
        Aspera.assert_values(unit, UNIT_US.keys) { 'duration unit' }
        value = value.to_s.delete(' ')
        if (m = value.match(/\A(?:(\d+)d)?(?:(?:(\d+):)?(\d+):)?(\d+)(?:\.(\d{1,3}))?\z/))
          days, hours, minutes, seconds, millis = m.captures
          hours = (days.to_i * 24) + hours.to_i
          minutes = (hours * 60) + minutes.to_i
          seconds = (minutes * 60) + seconds.to_i
          microseconds = (seconds * UNIT_US['s']) + (millis.to_s.ljust(3, '0').to_i * UNIT_US['ms'])
        else
          # anchored sequential matching (linear time, no backtracking over start positions)
          scanner = StringScanner.new(value)
          units = []
          until scanner.eos?
            Aspera.assert(scanner.scan(/(\d+)(ms|us|[wdhms])/), type: ParameterError) { "Invalid duration: #{value}" }
            units.push([scanner[1], scanner[2]])
          end
          Aspera.assert(!units.empty?, type: ParameterError) { "Invalid duration: #{value}" }
          microseconds = units.sum { |number, number_unit| number.to_i * UNIT_US[number_unit] }
        end
        microseconds / UNIT_US[unit]
      end
    end
  end
end
