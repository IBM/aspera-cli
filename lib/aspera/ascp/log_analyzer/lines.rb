# frozen_string_literal: true

# cspell:words MSGID PROCID rsyslog
module Aspera
  module Ascp
    class LogAnalyzer
      # Formats and timestamps of log lines: shared by LogFile and Records
      module Lines
        MONTHS = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec].freeze

        private

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

        # @return [Integer, nil] epoch time of `Mon DD HH:MM:SS` (year guessed) or `YYYY-MM-DD HH:MM:SS`
        def parse_time(text)
          return if text.nil?
          @now ||= Time.now
          @time_cache ||= {}
          @time_cache.clear if @time_cache.size > 10_000
          @time_cache[text] ||=
            if (m = text.match(/^(\w+)\s+(\d+)\s+(\d+):(\d+):(\d+)/)) && (month = MONTHS.index(m[1]))
              month += 1
              day = m[2].to_i
              year = month > @now.month || (month == @now.month && day > @now.day) ? @now.year - 1 : @now.year
              Time.local(year, month, day, m[3].to_i, m[4].to_i, m[5].to_i).to_i
            elsif (m = text.match(/^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)/))
              Time.local(*m.captures.map(&:to_i)).to_i
            end
        end
      end
    end
  end
end
