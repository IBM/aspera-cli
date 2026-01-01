# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'bundler/setup'
require 'rspec/core/rake_task'
RSpec::Core::RakeTask.new do |t|
  # t.rspec_opts = ['-v', '-r ./spec/spec_helper.rb']
  t.pattern = 'spec/*_spec.rb'
end

task default: [:build]
