# frozen_string_literal: true

# coverage for tests
if ENV.key?('ENABLE_COVERAGE')
  require 'simplecov'
  require 'securerandom'
  # compute development top folder based on this source location
  development_root = File.dirname(File.realpath(__FILE__), 3)
  coverage_dir = 'tmp/coverage'
  coverage_root = File.join(development_root, coverage_dir)
  FileUtils.mkdir_p(coverage_root)
  SimpleCov.root(development_root)
  SimpleCov.coverage_dir(coverage_dir)
  SimpleCov.enable_for_subprocesses if SimpleCov.respond_to?(:enable_for_subprocesses)
  # keep cache data for 1 day (must be longer than time to run the whole test suite)
  SimpleCov.merge_timeout(86400)
  SimpleCov.command_name(SecureRandom.uuid)
  SimpleCov.at_exit do
    original_file_descriptor = $stdout
    $stdout.reopen(File.join(coverage_root, 'simplecov.log'))
    SimpleCov.result.format!
    $stdout.reopen(original_file_descriptor)
  end
  # lines with those words are ignored from coverage
  no_cov_functions = %w[error_unreachable_line error_unexpected_value Log.log.trace].freeze
  SimpleCov.start do
    # assert usually do not trigger
    add_filter do |source_file|
      source_file.lines.each do |line|
        line.skipped! if no_cov_functions.any?{ |i| line.src.include?(i)}
      end
      false
    end
    # no coverage in these files
    add_filter 'lib/aspera/cli/plugins/faspex.rb'
    add_filter 'lib/aspera/node_simulator.rb'
    add_filter 'lib/aspera/keychain/macos_security.rb'
    add_filter 'lib/aspera/assert.rb'
  end
end
