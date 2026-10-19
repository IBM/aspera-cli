# frozen_string_literal: true

require 'bundler/setup'
# start coverage (if enabled) before any library is loaded
require 'aspera/coverage'

RSpec.configure do |config|
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
