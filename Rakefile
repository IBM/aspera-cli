# frozen_string_literal: true

# build tasks for gem file
require 'bundler/gem_tasks'
require 'bundler/setup'
# spec tests
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new
# default gem file build tasks
task default: [:signed]
desc 'Build signed gem (default)'
task :signed do
  raise 'Please set env var: SIGNING_KEY to build a signed gem file' unless ENV.key?('SIGNING_KEY')
  Rake::Task['build'].invoke
end
desc 'Build unsigned gem'
task unsigned: [:build]
