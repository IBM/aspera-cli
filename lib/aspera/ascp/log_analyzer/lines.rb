# frozen_string_literal: true

# cspell:words getlocal MSGID PROCID rsyslog
module Aspera
  module Ascp
    class LogAnalyzer
      # Formats and timestamps of log lines: shared by LogFile and Records, which define `@path` and `@timezone` (nil: time zone of the analyst)
      module Lines
        MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze
        # Line of ascp: FASP message, or syslog line of process `ascp`
        ASCP_LINE = /\bFASP\b|\sascp\d*\[\d+\]:/
        # Gap in seconds between lines beyond which a syslog line may be in another year
        HALF_YEAR = 180 * 86_400

        # @return [Boolean] true if a line of the file is an ascp log line
        def ascp?
          @ascp || false
        end

        private

        # Remember that the file contains ascp log lines
        def track_ascp(line)
          @ascp ||= line.match?(ASCP_LINE)
        end

        # Fix variants of log formats
        def normalize(line)
          if line.match?(/\A\d+-\d+-\d+T/)
            line = line.sub(/(\d+-\d+-\d+)T(\d+:\d+:\d+)(?:\.\d+)?[+-]\d+:\d+(.*)$/, '\1 \2 \3') # ISO 8601 with time zone (rsyslog)
            line = line.sub(/^(\d+-\d+-\d+)T(\d+:\d+:\d+)Z(.*)$/, '\1 \2 \3') # ISO 8601 UTC
          end
          line = line.sub(/(^.*?\s+ascp)\s+(\d+)\s+-\s+-(.*)/, '\1[\2]\3') if line.include?(' - -') # RFC 5424: APP-NAME PROCID MSGID
          line = line.sub(/^<\d+>\d\s+(.*)/, '\1') if line.start_with?('<') # RFC 5424: PRI VERSION
          line
        end

        # @param time [Integer, nil] Epoch time
        # @return [String, nil] ISO 8601 time, in the time zone of the log lines
        def iso(time)
          Time.at(time, in: @timezone).iso8601 if time
        end

        # @return [Integer, nil] epoch time of `Mon DD HH:MM:SS` (year deduced) or `YYYY-MM-DD HH:MM:SS`, in the time zone of the log lines
        def parse_time(text)
          return if text.nil?
          @time_cache ||= {}
          @time_cache.clear if @time_cache.size > 10_000
          @time_cache[text] ||=
            if (m = text.match(/^(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)/)) && (month = MONTHS.index(m[1]))
              month += 1
              day = m[2].to_i
              Time.new(syslog_year(month, day), month, day, m[3].to_i, m[4].to_i, m[5].to_i, @timezone).to_i
            elsif (m = text.match(/^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)/))
              Time.new(*m.captures.map(&:to_i), @timezone).to_i
            end
        end

        # Syslog lines have no year. The log ends before the modification date of the file (the current date for the standard input):
        # the year of a line is the latest one that is not after this date. So the year decreases when going back past January
        # (a log from December to January analyzed in March: December is of the previous year).
        # @return [Integer] year of the line
        def syslog_year(month, day)
          @reference ||= (@path == STDIN_PATH ? Time.now : File.mtime(@path)).getlocal(@timezone)
          month > @reference.month || (month == @reference.month && day > @reference.day) ? @reference.year - 1 : @reference.year
        end
      end
    end
  end
end
