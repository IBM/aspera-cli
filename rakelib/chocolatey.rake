# Rakefile
# frozen_string_literal: true

require_relative '../build/lib/build_tools'
include BuildTools

namespace :chocolatey do
  desc 'Package (TODO)'
  task :pack do
    run('choco', 'pack')
  end
  desc 'Push (TODO)'
  task :pack do
    run('choco', 'push', 'ascli.nupkg', '--source', 'https://push.chocolatey.org/')
  end
end
