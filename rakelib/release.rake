# frozen_string_literal: true

require 'pathname'
require 'tmpdir'
require_relative '../build/lib/paths'

# Pre-release
PRE_SUFFIX = '.pre'
DATE_PLACE_HOLDER = 'Released: [Place date of release here]'

# Determine release versions
# @param release_version [String] Release version (empty to use current version without .pre)
# @param next_version [String] Next development version (empty to auto-increment minor)
# @return [Hash<Symbol,String>] Versions: :current, :release, :next, :dev
def release_versions(release_version, next_version)
  versions = {}
  versions[:current] = Aspera::Cli::VERSION
  versions[:release] =
    if release_version.to_s.empty?
      Aspera::Cli::VERSION.delete_suffix(PRE_SUFFIX)
    else
      release_version
    end
  versions[:next] =
    if next_version.to_s.empty?
      major, minor, _patch = versions[:release].split('.').map(&:to_i)
      [major, minor + 1, 0].map(&:to_s).join('.')
    else
      next_version
    end
  versions[:dev] = "#{versions[:next]}#{PRE_SUFFIX}"
  return versions
end

# Extract the latest changelog section (everything between first ## and second ##)
# Strips the version heading and release date lines
# @return [String] The changelog content for the latest version
def extract_latest_changelog
  content = CHANGELOG_FILE.read
  # Match from first ## heading to the next ## heading (or end of file)
  match = content.match(/^(## .+?)(?=^## |\z)/m)
  raise 'Missing changelog' unless match

  section = match[1].strip
  # Remove the version heading (## X.Y.Z) and Released: line
  section.sub(/\A## .+\n+Released: .+\n*/, '').strip
end

# Update `CHANGELOG.md` for release:
# - Replace current version with release version
# - Replace date placeholder with today's date
# @param current_version [String] The current version (with `.pre`)
# @param release_version [String] The release version (without `.pre`)
def update_changelog_for_release(current_version, release_version)
  content = CHANGELOG_FILE.read
  today = Date.today.strftime('%Y-%m-%d')

  # Replace the .pre version heading with release version
  content.sub!("\n## #{current_version}\n", "\n## #{release_version}\n")

  # Replace the date placeholder
  content.sub!(DATE_PLACE_HOLDER, "Released: #{today}")

  CHANGELOG_FILE.write(content)
end

# Add a new development section to `CHANGELOG.md` for the next version
# @param next_version_dev [String] The next version (with .pre suffix)
def add_next_changelog_section(next_version_dev)
  content = CHANGELOG_FILE.read

  new_section = <<~SECTION
    ## #{next_version_dev}

    #{DATE_PLACE_HOLDER}

    ### New Features

    ### Issues Fixed

    ### Breaking Changes

  SECTION

  # Insert before the first section
  content.sub!("\n## ", "\n#{new_section}## ")

  CHANGELOG_FILE.write(content)
end

# Update version.rb with a new version
# @param version [String] The new version string
def update_version_file(version)
  content = VERSION_FILE.read
  content.sub!(/VERSION = '[^']+'/, "VERSION = '#{version}'")
  VERSION_FILE.write(content)
end

def gem_file(version)
  Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{version}.gem"
end

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
    # Build documentation and signed gem
    #----------------------------------------------------------------------

    Rake::Task['doc:build'].invoke(versions[:release])
    Rake::Task['signed'].invoke

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
      'gh', 'release', 'create', release_tag,
      '--title', "Aspera CLI #{release_tag}",
      '--notes-file', release_notes_path,
      Paths::PDF_MANUAL,
      gem_file(versions[:release]),
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
