# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require 'bundler/setup'
# start coverage (if enabled) before any library is loaded
require_relative '../lib/aspera/coverage'
require 'stringio'

# Helpers for specs that read the terminal
module TerminalHelpers
  # Simulate a user typing `text` (then Enter) on a terminal in raw mode (hidden input)
  # @param text [String] Characters typed
  def type_on_terminal(text)
    allow($stdin).to(receive(:tty?).and_return(true))
    allow($stdin).to(receive(:raw)) { |&block| block.call(StringIO.new("#{text}\r")) }
  end
end

RSpec.configure do |config|
  config.include(TerminalHelpers)
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  # Specs create parsers with program name `test`: env vars `TEST_*` (e.g. `TEST_INTERACTIVE` of the integration tests) would be taken as options
  config.around do |example|
    saved = ENV.to_h.select { |name, _| name.start_with?('TEST_') }
    saved.each_key { |name| ENV.delete(name) }
    example.run
  ensure
    saved.each { |name, value| ENV[name] = value }
  end
end
