# frozen_string_literal: true

# coverage for tests
if ENV.key?('ENABLE_COVERAGE')
  require 'simplecov'
  require 'securerandom'
  require 'fileutils'
  # compute development top folder based on this source location
  development_root = File.dirname(File.realpath(__FILE__), 3)
  coverage_dir = 'tmp/coverage'
  coverage_root = File.join(development_root, coverage_dir)
  FileUtils.mkdir_p(coverage_root)
  SimpleCov.root(development_root)
  SimpleCov.coverage_dir(coverage_dir)
  SimpleCov.merge_subprocesses(true)
  # keep cache data for 1 day (must be longer than time to run the whole test suite)
  SimpleCov.merge_timeout(86400)
  SimpleCov.command_name(SecureRandom.uuid)
  # SimpleCov prints its summary on stderr (>= 1.3) or stdout (older): send both to a log file
  SimpleCov.at_exit do
    saved = [$stdout, $stderr].map(&:dup)
    File.open(File.join(coverage_root, 'simplecov.log'), 'a') do |log|
      $stdout.reopen(log)
      $stderr.reopen(log)
      # Tests may run in parallel: serialize merge + report so that the last report written includes all results
      log.flock(File::LOCK_EX)
      SimpleCov.result.format!
    ensure
      log.flock(File::LOCK_UN)
      $stdout.reopen(saved[0])
      $stderr.reopen(saved[1])
    end
  end
  # lines with those words are ignored from coverage
  no_cov_functions = %w[error_unreachable_line error_unexpected_value Log.log.trace].freeze
  SimpleCov.start do
    # assert usually do not trigger
    skip do |source_file|
      source_file.lines.each do |line|
        line.skipped! if no_cov_functions.any? { |i| line.src.include?(i) }
      end
      false
    end
    # no coverage in these files
    skip 'lib/aspera/secret/store/macos_security.rb'
    skip 'lib/aspera/assert.rb'
  end
end
