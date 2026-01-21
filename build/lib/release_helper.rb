# frozen_string_literal: true

require 'date'
require 'pathname'

# Helper for release automation
module ReleaseHelper
  TOP = Pathname.new(__dir__).parent.parent
  CHANGELOG_FILE = TOP / 'CHANGELOG.md'
  VERSION_FILE = TOP / 'lib/aspera/cli/version.rb'

  class << self
    # Extract the latest changelog section (everything between first ## and second ##)
    # @return [String] The changelog content for the latest version
    def extract_latest_changelog
      content = CHANGELOG_FILE.read
      # Match from first ## heading to the next ## heading (or end of file)
      match = content.match(/^(## .+?)(?=^## |\z)/m)
      return '' unless match

      match[1].strip
    end

    # Update CHANGELOG.md for release:
    # - Replace version.pre with version
    # - Replace date placeholder with today's date
    # @param version [String] The release version (without .pre)
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
    # @param next_version [String] The next version (without .pre suffix)
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
    # @param version [String] The new version string
    def update_version_file(version)
      content = VERSION_FILE.read
      content.sub!(/VERSION = '[^']+'/, "VERSION = '#{version}'")
      VERSION_FILE.write(content)
    end
  end
end

# CLI interface when run directly
if __FILE__ == $PROGRAM_NAME
  command = ARGV.shift
  case command
  when 'extract-changelog'
    puts ReleaseHelper.extract_latest_changelog
  when 'update-changelog'
    version = ARGV.shift || raise('Missing version argument')
    ReleaseHelper.update_changelog_for_release(version)
    puts "Updated CHANGELOG.md for release #{version}"
  when 'add-changelog-section'
    version = ARGV.shift || raise('Missing version argument')
    ReleaseHelper.add_next_changelog_section(version)
    puts "Added new section for #{version}.pre to CHANGELOG.md"
  when 'update-version'
    version = ARGV.shift || raise('Missing version argument')
    ReleaseHelper.update_version_file(version)
    puts "Updated version.rb to #{version}"
  else
    warn "Usage: #{$PROGRAM_NAME} <command> [args]"
    warn 'Commands:'
    warn '  extract-changelog              - Print latest changelog section'
    warn '  update-changelog <version>     - Update changelog for release'
    warn '  add-changelog-section <version> - Add new .pre section'
    warn '  update-version <version>       - Update version.rb'
    exit 1
  end
end
