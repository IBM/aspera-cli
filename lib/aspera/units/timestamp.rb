# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative 'duration'
require 'date'
require 'time'

module Aspera
  module Units
    # Point in time given by the user: an absolute date, or a keyword (`now`, `today`...) optionally followed by `-` or `+` and a {Duration},
    # as the date math of Elasticsearch and Grafana, e.g. `now-24h`, `today+9h`.
    module Timestamp
      # Days from today of the keywords at midnight
      MIDNIGHT_DAYS = {'today' => 0, 'yesterday' => -1, 'tomorrow' => 1}.freeze
      # Keywords, with their description: the reference time, or a midnight
      KEYWORDS = {
        'now'       => 'Current time, e.g. now-24h',
        'today'     => 'Today at midnight, e.g. today+9h',
        'yesterday' => 'Yesterday at midnight',
        'tomorrow'  => 'Tomorrow at midnight'
      }.freeze
      # Keyword, optionally followed by sign and duration
      REGEX_KEYWORD = /\A(#{Regexp.union(KEYWORDS.keys).source})\s*(?:([-+])(.+))?\z/m
      # Number of seconds, a {Duration} without units: 8 digits or more is a date (ISO 8601 basic format, e.g. `20261127`)
      REGEX_SECONDS = /\A\d{1,7}(?:\.\d+)?\z/
      # Accepted syntax, for messages
      SYNTAX = "a date (e.g. 2026-11-27 10:00:00, ISO 8601), or #{KEYWORDS.keys.join(', ')} optionally followed by -<duration> or +<duration> (e.g. now-24h)".freeze
      private_constant :MIDNIGHT_DAYS, :REGEX_KEYWORD, :REGEX_SECONDS

      class << self
        # @param value [String]  Absolute date (a format of `Time.parse`, e.g. ISO 8601), or `now`, `today`, `yesterday`, `tomorrow`
        #                        optionally followed by `-` (in the past) or `+` (in the future) and a {Duration}
        # @param now   [Time]    Reference time of keywords
        # @param utc   [Boolean] `true`: an absolute date without time zone, and midnight of keywords, are in UTC; else in local time
        # @return [Time]
        # @raise [ParameterError] if the date is invalid
        def parse(value, now: Time.now, utc: false)
          Aspera.assert_type(value, String) { 'date' }
          text = value.strip
          now = now.getutc if utc
          if (m = text.match(REGEX_KEYWORD))
            base = keyword_time(m[1], now, utc)
            return base if m[2].nil?
            offset = Duration.new(m[3]).microseconds.quo(1_000_000)
            return m[2].eql?('-') ? base - offset : base + offset
          end
          # `Time.parse` reads a duration such as `30s` or `30` as a day of month, `30.5` or `1h30m` or `-1h` as a time of day
          raise ParameterError, "Invalid date: #{value}: for a duration from now, use now#{text}" if text.match?(/\A[-+]/)
          raise ParameterError, "Invalid date: #{value}: for a duration from now, use now-#{text} or now+#{text}" if duration?(text)
          text = "#{text} UTC" if utc && Date._parse(text)[:offset].nil?
          Time.parse(text, now)
        rescue ArgumentError => e
          raise ParameterError, "Invalid date: #{value} (#{e.message}): expected #{SYNTAX}"
        end

        private

        # @param keyword [String]  One of `KEYWORDS`
        # @param now     [Time]    Reference time
        # @param utc     [Boolean] Midnight in UTC, else in local time
        # @return [Time] Time of keyword
        def keyword_time(keyword, now, utc)
          return now if keyword.eql?('now')
          day = now.to_date + MIDNIGHT_DAYS.fetch(keyword)
          utc ? Time.utc(day.year, day.month, day.day) : Time.local(day.year, day.month, day.day)
        end

        # @param text [String] Value given
        # @return [Boolean] `true` if `text` is a duration: a number of seconds (e.g. `30`), or with units (e.g. `30s`, `1d 02:00:00`)
        def duration?(text)
          return true if text.match?(REGEX_SECONDS)
          return false unless text.match?(/[a-z]/)
          Duration.new(text)
          true
        rescue ParameterError
          false
        end
      end
    end
  end
end
