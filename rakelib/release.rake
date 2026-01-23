# frozen_string_literal: true

require 'date'
require_relative '../build/lib/paths'
require_relative '../build/lib/build_tools'
include BuildTools

# Release automation tasks
namespace :release do
  CHANGELOG_FILE = Paths::TOP / 'CHANGELOG.md'
  VERSION_FILE = Paths::TOP / 'lib/aspera/cli/version.rb'
  RELEASE_NOTES_FILE = Paths::TOP / 'release_notes.md'

  # Read current version from version.rb
  def current_version
    VERSION_FILE.read[/VERSION = '([^']+)'/, 1]
  end

  # Extract the latest changelog section (everything between first ## and second ##)
  # Strips the version heading and release date lines
  def extract_latest_changelog
    content = CHANGELOG_FILE.read
    # Match from first ## heading to the next ## heading (or end of file)
    match = content.match(/^(## .+?)(?=^## |\z)/m)
    return '' unless match

    section = match[1].strip
    # Remove the version heading (## X.Y.Z) and Released: line
    section.sub(/\A## .+\n+Released: .+\n*/, '').strip
  end

  # Update CHANGELOG.md for release:
  # - Replace version.pre with version
  # - Replace date placeholder with today's date
  def update_changelog_for_release(version)
    content = CHANGELOG_FILE.read
    today = Date.today.strftime('%Y-%m-%d')

    # Replace the .pre version heading with release version
    content.sub!(/^## #{Regexp.escape(version)}\.pre$/, "## #{version}")

    # Replace the date placeholder
    content.sub!(/^Released: \[Place date of release here\]$/, "Released: #{today}")

    CHANGELOG_FILE.write(content)
  end

  # Add a new development section to CHANGELOG.md for the next version
  def add_next_changelog_section(next_version)
    content = CHANGELOG_FILE.read

    new_section = <<~SECTION
      ## #{next_version}.pre

      Released: [Place date of release here]

      ### New Features

      ### Issues Fixed

      ### Breaking Changes

    SECTION

    # Insert after the header comment block (after the markdownlint line)
    content.sub!(
      /^(# Changes \(Release notes\)\n\n<!-- markdownlint-configure-file .+? -->\n)\n/,
      "\\1\n#{new_section}"
    )

    CHANGELOG_FILE.write(content)
  end

  # Update version.rb with a new version
  def update_version_file(version)
    content = VERSION_FILE.read
    content.sub!(/VERSION = '[^']+'/, "VERSION = '#{version}'")
    VERSION_FILE.write(content)
  end

  # Calculate next development version (increment minor version)
  def calculate_next_version(release_version)
    parts = release_version.split('.')
    major, minor, _patch = parts[0].to_i, parts[1].to_i, parts[2].to_i
    "#{major}.#{minor + 1}.0"
  end

  desc 'Extract latest changelog section to release_notes.md'
  task :extract_changelog do
    notes = extract_latest_changelog
    RELEASE_NOTES_FILE.write(notes)
    puts "Extracted changelog to #{RELEASE_NOTES_FILE}"
    puts notes
  end

  desc 'Update CHANGELOG.md for release (remove .pre, set date)'
  task :update_changelog, [:version] do |_t, args|
    version = args[:version] || raise('Missing version argument')
    update_changelog_for_release(version)
    puts "Updated CHANGELOG.md for release #{version}"
  end

  desc 'Add new .pre section to CHANGELOG.md'
  task :add_changelog_section, [:version] do |_t, args|
    version = args[:version] || raise('Missing version argument')
    add_next_changelog_section(version)
    puts "Added new section for #{version}.pre to CHANGELOG.md"
  end

  desc 'Update version.rb'
  task :update_version, [:version] do |_t, args|
    version = args[:version] || raise('Missing version argument')
    update_version_file(version)
    puts "Updated version.rb to #{version}"
  end

  desc 'Show current version'
  task :version do
    puts current_version
  end

  desc 'Full release: update files, build docs, commit, tag, and create GitHub release'
  task :create, [:version, :next_version] do |_t, args|
    # Determine release version
    release_version = args[:version] || current_version.sub(/\.pre$/, '')
    next_version = args[:next_version] || calculate_next_version(release_version)

    puts "Release version: #{release_version}"
    puts "Next development version: #{next_version}.pre"

    # Update version.rb for release
    Rake::Task['release:update_version'].invoke(release_version)

    # Update CHANGELOG.md for release
    Rake::Task['release:update_changelog'].invoke(release_version)

    # Extract release notes
    Rake::Task['release:extract_changelog'].invoke

    # Build documentation
    ENV['GEM_VERSION'] = release_version
    Rake::Task['doc:build'].invoke

    # Build gem
    Rake::Task['build'].invoke

    # Git operations
    run('git', 'add', '-A')
    run('git', 'commit', '-m', "Release v#{release_version}")
    run('git', 'tag', '-a', "v#{release_version}", '-m', "Version #{release_version}")
    run('git', 'push', 'origin', "v#{release_version}")

    # Create GitHub release with artifacts
    pdf_file = Paths::RELEASE / "Manual-#{Aspera::Cli::Info::CMD_NAME}-#{release_version}.pdf"
    gem_file = Paths::RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{release_version}.gem"

    run('gh', 'release', 'create', "v#{release_version}",
        '--title', "Aspera CLI v#{release_version}",
        '--notes-file', RELEASE_NOTES_FILE.to_s,
        pdf_file.to_s,
        gem_file.to_s)

    # Prepare for next development cycle
    Rake::Task['release:update_version'].reenable
    Rake::Task['release:update_version'].invoke("#{next_version}.pre")

    Rake::Task['release:add_changelog_section'].invoke(next_version)

    run('git', 'add', '-A')
    run('git', 'commit', '-m', "Prepare for next development cycle (#{next_version}.pre)")
    run('git', 'push', 'origin', 'main')

    puts "\nRelease v#{release_version} complete!"
  end
end
