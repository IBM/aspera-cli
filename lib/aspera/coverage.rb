# frozen_string_literal: true

# coverage for tests
if ENV.key?('ENABLE_COVERAGE')
  require 'simplecov'
  require 'securerandom'
  # compute gem source root based on this script location, assuming it is in bin/
  # use dirname instead of gsub, in case folder separator is not /
  development_root = 3.times.inject(File.realpath(__FILE__)) { |p, _| File.dirname(p) }
  SimpleCov.root(development_root)
  SimpleCov.enable_for_subprocesses if SimpleCov.respond_to?(:enable_for_subprocesses)
  # keep cache data for 1 day (must be longer that time to run the whole test suite)
  SimpleCov.merge_timeout(86400)
  SimpleCov.command_name(SecureRandom.uuid)
  SimpleCov.at_exit do
    original_file_descriptor = $stdout
    $stdout.reopen(File.join(development_root, 'simplecov.log'))
    SimpleCov.result.format!
    $stdout.reopen(original_file_descriptor)
  end
  SimpleCov.start
end
