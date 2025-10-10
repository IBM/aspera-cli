# frozen_string_literal: true

# parameters in `server_user` of `ASPERA_CLI_TEST_CONF_FILE`
# or direxctly in JSON: RSPEC_CONFIG

require 'bundler/setup'
require 'yaml'
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end
  params = if ENV.key?('RSPEC_CONFIG')
    JSON.parse(ENV['RSPEC_CONFIG'])
  else
    raise 'Missing env var: ASPERA_CLI_TEST_CONF_FILE' unless ENV.key?('ASPERA_CLI_TEST_CONF_FILE')
    YAML.load_file(ENV['ASPERA_CLI_TEST_CONF_FILE'])['server_user']
  end
  %i[url username password].each do |p|
    param = params[p.to_s]
    raise "Missing parameter: #{p}" if param.nil?
    raise "Wrong value for parameter: #{p}" unless param.is_a?(String) && !param.empty?
    config.add_setting(p, default: param)
  end
end
