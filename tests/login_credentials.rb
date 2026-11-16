# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../lib/aspera/environment'
require_relative '../build/lib/paths'

# Login credentials for web pages, read from a preset of the test configuration file.
# Shared by `select_browser` (test_helpers.rb), that checks them before the test, and the auto browser (auto_browser.rb), that enters them.
module LoginCredentials
  KEYS = %w[username password].freeze
  ANSI_RE = /\e\[[\d;]*m/
  private_constant :KEYS, :ANSI_RE

  class << self
    # Read one value of a preset using ascli itself: all extended values are evaluated by ascli
    # (`@vault:`, `@file:`, `@extend:`, `@preset:`...), with the same home and config file as the tests.
    # @param preset [String] Name of the preset in the test configuration file
    # @param key    [String] Name of the value in the preset
    # @return [Array(String, String, Array<String>)] Evaluated value (nil if not found), the error message of `ascli` (nil if found), and the hint lines of `ascli`, as it displays them
    def fetch(preset, key)
      stdout, stderr, status = Aspera::Environment.secure_execute(
        # `--out.secrets=yes`: else a password is displayed as `***`
        # Colors as `ascli` would display them on this terminal (the output is captured, so it does not detect it)
        File.join(Paths::BIN, 'ascli'), "--home=#{Paths::TMP / 'ascli_home'}", '--interactive=no', '--out.secrets=yes', "--out.colors=#{$stderr.tty? ? 'yes' : 'no'}",
        'config', 'echo', "@preset:#{preset}.#{key}",
        mode:       :capture,
        exception:  false,
        stdin_data: ''
      )
      return [stdout.chomp, nil, []] if status.success? && !stdout.empty?
      lines = stderr.lines.map(&:chomp)
      # First line is the error; hints (if any) help to diagnose it
      [nil, lines.first.to_s.gsub(ANSI_RE, '').sub(/\AERRR\s+/, '').strip, lines.grep(/HINT:/)]
    end

    # Retrieve login credentials from a preset.
    # Values in the preset may be extended values, e.g. a reference to a vault.
    # @param preset [String, nil] Name of the preset, or nil if the test did not select one
    # @return [Hash] Keys `:username` and `:password` with String values, those not found are absent
    def read(preset)
      return {} if preset.nil?
      KEYS.to_h { |key| [key.to_sym, fetch(preset, key).first] }.compact
    end

    # Same as `read`, but fails if the preset does not give both user name and password.
    # @param preset [String] Name of the preset in the test configuration file
    # @return [Hash] Keys `:username` and `:password`
    # @raise [RuntimeError] if one is missing, with the reason given by `ascli`
    def read!(preset)
      results = KEYS.to_h { |key| [key, fetch(preset, key)] }
      missing = results.select { |_, (value)| value.nil? }
      return results.to_h { |key, (value, _)| [key.to_sym, value] } if missing.empty?
      # Same cause for several keys is shown once, with the hints of `ascli` as it displays them
      reasons = missing.map { |_, (_, error, hints)| [error, *hints].join("\n") }.uniq.map { |text| "\n  - #{text}" }.join
      raise "Login preset '#{preset}': cannot get #{missing.keys.join(' and ')} from the test configuration file (see docs/test_env.conf):#{reasons}"
    end
  end
end
