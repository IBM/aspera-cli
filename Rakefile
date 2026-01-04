# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'bundler/setup'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new
task :signed do
  raise 'Please set env var: SIGNING_KEY to build a signed gem file' unless ENV.key?('SIGNING_KEY')
  Rake::Task['build'].invoke
end
task unsigned: [:build]
task default: [:signed]
