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

require_relative 'build/lib/paths'

# default gem file build tasks
task default: [:signed]

desc 'Build signed gem (default)'
task :signed do
  raise 'Please set env var: SIGNING_KEY to build a signed gem file' unless ENV.key?('SIGNING_KEY')
  Rake::Task['build'].invoke
end

desc 'Build unsigned gem'
task unsigned: [:build]

desc 'Tag current version in git and push to remote'
task :release_tag do
  run('git', 'tag', '-a', "v#{GEM_VERSION}", '-m', "Version #{GEM_VERSION}")
  run('git', 'push', 'origin', "v#{GEM_VERSION}")
end

desc 'Build and push gem to rubygems.org'
task release_signed: :signed do
  run('gem', 'push', Paths::GEM_PACK_FILE)
end

desc 'Build and push gem to rubygems.org'
task release_unsigned: :unsigned do
  run('gem', 'push', Paths::GEM_PACK_FILE)
end
