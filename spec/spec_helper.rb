# frozen_string_literal: true

require 'bundler/setup'
require 'yaml'
require_relative '../build/lib/paths'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'
  config.expect_with(:rspec) do |c|
    c.syntax = :expect
  end
  full_config = YAML.load_file(Paths.config_file_path)
  default_server = full_config.dig('default', 'server')
  raise 'Missing default config for server' if default_server.nil?
  params = full_config[default_server]
  %i[url username password].each do |p|
    param = params[p.to_s]
    raise "Missing parameter: #{p}" if param.nil?
    raise "Wrong value for parameter: #{p}" unless param.is_a?(String) && !param.empty?
    config.add_setting(p, default: param)
  end
end
