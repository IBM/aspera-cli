# frozen_string_literal: true

require 'date'
require 'pathname'
require_relative 'paths'
include Paths

# Helper for release automation
module ReleaseHelper
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
  module_function :release_versions, :extract_latest_changelog, :update_changelog_for_release, :add_next_changelog_section, :update_version_file
end
