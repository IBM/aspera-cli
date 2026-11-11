# frozen_string_literal: true

require 'aspera/assert'

module Aspera
  module Transfer
    # Rates, sizes and durations of transfers: parsed from user input and formatted for display.
    # Decimal units, like `ascp`. Depends only on `aspera/assert`: usable without the CLI.
    module Units
      # Decimal prefixes: each one is `KILO` times the previous one
      PREFIX = ['', 'K', 'M', 'G', 'T', 'P'].freeze
      KILO = 1000
      # Multiplier of each prefix, e.g. `'M' => 1_000_000`
      MULTIPLIER = PREFIX.each_with_index.to_h { |prefix, power| [prefix, KILO**power] }.freeze
      # Units of sizes: `B`, `KB`, `MB`...
      BYTE_UNITS = PREFIX.map { |prefix| "#{prefix}B" }.freeze
      # Rate typed by a user: integer with an optional prefix, case ignored
      RATE_INPUT = /\A(\d+)([#{PREFIX.join}])?\z/i
      BITS_PER_BYTE = 8
      private_constant :MULTIPLIER, :BYTE_UNITS, :RATE_INPUT, :BITS_PER_BYTE

      class << self
        # Parse a human-readable rate (as accepted by async -l) into an integer bps value.
        # Accepted: plain integer (bps), or integer + prefix of `PREFIX`, case ignored, e.g. `k` (x1000), `M` (x1000000), `g` (x1000000000).
        # @param value [String, Integer] e.g. "100m", "500000", "1g", 500000
        # @return [Integer] value in bps
        def rate_string_to_bps(value)
          m = RATE_INPUT.match(value.to_s.strip)
          Aspera.assert(m) { "Invalid rate value: #{value.inspect}. Expected integer with optional suffix #{PREFIX.drop(1).join(', ')} (case ignored)." }
          return m[1].to_i * MULTIPLIER.fetch(m[2].to_s.upcase)
        end

        # Inverse of `rate_string_to_bps`: the shortest exact text, e.g. `100M`, `1G`, `1500K`, `999`
        # @param bps [Integer] Rate in bits per second
        # @return [String] Rate accepted by `rate_string_to_bps`
        def rate_bps_to_string(bps)
          prefix = PREFIX.reverse.find { |candidate| bps.positive? && (bps % MULTIPLIER[candidate]).zero? } || ''
          "#{bps / MULTIPLIER[prefix]}#{prefix}"
        end

        # @param bytes [Integer] Size in bytes
        # @return [String] Size with decimal unit, e.g. `12.3 MB`
        def format_bytes(bytes)
          value = bytes.to_f
          index = 0
          while value >= KILO && index < BYTE_UNITS.length - 1
            value /= KILO
            index += 1
          end
          return "#{bytes} B" if index.zero?
          format('%.1f %s', value, BYTE_UNITS[index])
        end

        # @param bytes_per_second [Float, nil] Rate, `nil` if unknown
        # @return [String] Rate in megabits per second (decimal, like `ascp`)
        def format_rate(bytes_per_second)
          return '-- Mbps' if bytes_per_second.nil?
          mbps = bytes_per_second * BITS_PER_BYTE / MULTIPLIER.fetch('M')
          mbps < 10 ? format('%.2f Mbps', mbps) : format('%.0f Mbps', mbps)
        end

        # @param seconds [Numeric, nil] Duration, `nil` if unknown
        # @return [String] Duration as `hh:mm:ss`
        def format_duration(seconds)
          return '--:--:--' if seconds.nil?
          seconds = seconds.round
          format('%02d:%02d:%02d', seconds / 3600, (seconds / 60) % 60, seconds % 60)
        end
      end
    end
  end
end
