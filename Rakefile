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
require_relative 'build/lib/build_tools'

# clean   : Remove any temporary products.
CLEAN.push(Paths::TMP)
# clobber : Remove any generated file.
CLOBBER.push(Paths::GEMFILE_LOCK)
CLOBBER.push(Paths::RELEASE)

# default gem file build tasks
task default: [:signed]

desc 'Build signed gem (default)'
task :signed do
  BuildTools.check_gem_signing_key unless BuildTools.dry_run?
  Rake::Task['build'].invoke
end

desc 'Build unsigned gem'
task unsigned: [:build]

desc 'Build and push gem to rubygems.org'
task release_signed: :signed do
  run('gem', 'push', Paths::GEM_PACK_FILE)
end

desc 'Build and push gem to rubygems.org'
task release_unsigned: :unsigned do
  run('gem', 'push', Paths::GEM_PACK_FILE)
end
