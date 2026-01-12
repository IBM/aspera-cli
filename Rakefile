# frozen_string_literal: true

# Adds the following tasks:
# See: https://bundler.io/guides/creating_gem.html
# build            # Build aspera-cli-x.y.z.gem into the pkg directory
# build:checksum   # Generate SHA512 checksum of aspera-cli-x.y.z.gem into the checksums directory
# clean            # Remove any temporary products
# clobber          # Remove any generated files
# install          # Build and install aspera-cli-x.y.z.gem into system gems
# install:local    # Build and install aspera-cli-x.y.z.gem into system gems without network access
# release[remote]  # Create tag vx.y.z and build and push aspera-cli-x.y.z.gem to https://rubygems.org
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
