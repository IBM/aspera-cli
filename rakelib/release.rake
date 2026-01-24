# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require_relative '../build/lib/release_helper'
require_relative '../build/lib/paths'
include ReleaseHelper

namespace :release do
  desc 'Create a new release: args: release_version, next_version'
  task :run, %i[release_version next_version] do |_t, args|
    #--------------------------------------------------------------------------
    # Determine versions
    #--------------------------------------------------------------------------

    versions = release_versions(args[:release_version], args[:next_version])
    log.info("Current version in version.rb: #{versions[:current]}")
    log.info("Release version: #{versions[:release]}")
    log.info("Next development version: #{versions[:dev]}")

    #--------------------------------------------------------------------------
    # Release version + changelog
    #--------------------------------------------------------------------------

    update_version_file(versions[:release])
    log.info{"Version file:#{Paths::VERSION_FILE.read}"}
    update_changelog_for_release(versions[:current], versions[:release])

    #--------------------------------------------------------------------------
    # Extract release notes (temporary, not committed)
    #--------------------------------------------------------------------------

    release_notes_path = Pathname(Dir.tmpdir) / 'release_notes.md'
    release_notes_path.write(extract_latest_changelog)
    log.info(release_notes_path.read)

    #----------------------------------------------------------------------
    # Build documentation
    #----------------------------------------------------------------------

    Rake::Task['doc:build'].invoke(versions[:release])

    #----------------------------------------------------------------------
    # Commit release: CHANGELOG.md README.md version.rb
    #----------------------------------------------------------------------

    release_tag = "v#{versions[:release]}"
    run(*%w{git add -A})
    run('git', 'commit', '-m', "Release #{release_tag}")

    #----------------------------------------------------------------------
    # Tag + push
    #----------------------------------------------------------------------

    run('git', 'tag', '-a', release_tag, '-m', "Version #{versions[:release]}")
    run('git', 'push', 'origin', release_tag)

    #----------------------------------------------------------------------
    # GitHub release
    #----------------------------------------------------------------------

    run(
      'gh', 'release', 'create', release_tag, '--title', "Aspera CLI #{release_tag}", '--notes-file', release_notes_path,
      env: {'GH_TOKEN' => ENV.fetch('RELEASE_TOKEN')}
    )

    #--------------------------------------------------------------------------
    # Prepare next development cycle
    #--------------------------------------------------------------------------

    update_version_file(versions[:dev])
    log.info(Paths::VERSION_FILE.read)

    add_next_changelog_section(versions[:dev])

    run(*%w{git add -A})
    run('git', 'commit', '-m', "Prepare for next development cycle (#{versions[:dev]})")
    run(*%w{git push origin main})

    log.info("Release #{versions[:release]} completed")
  end
end
