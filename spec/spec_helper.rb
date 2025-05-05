# frozen_string_literal: true

# Parameters are provided with env var RSPEC_CONFIG set to a json with url, username, password

require 'bundler/setup'
require 'json'
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end
  raise 'Missing env var: RSPEC_CONFIG' unless ENV.key?('RSPEC_CONFIG')
  params = JSON.parse(ENV['RSPEC_CONFIG'])
  %i[url username password].each do |p|
    param = params[p.to_s]
    raise "Missing parameter: #{p}" if param.nil?
    raise "Wrong value for parameter: #{p}" unless param.is_a?(String) && !param.empty?
    config.add_setting(p, default: param)
  end
end
