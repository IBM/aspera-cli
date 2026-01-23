# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'
require 'aspera/cli/version'

# Gem version for build and release
GEM_VERSION = ENV['GEM_VERSION'] || ENV['GITHUB_REF_NAME']&.gsub(/^v/, '') || Aspera::Cli::VERSION
# `true` if built from local gem file
GEM_BETA = !GEM_VERSION.eql?(Aspera::Cli::VERSION)

# Fixed paths in project
module Paths
  # Main project folder
  TOP = Pathname.new(__dir__).parent.parent
  TMP = TOP / 'tmp'
  BIN = TOP / 'bin'
  LIB = TOP / 'lib'
  DOC = TOP / 'docs'
  TST = TOP / 'tests'
  BUILD = TOP / 'build'
  GEMSPEC = TOP / 'aspera-cli.gemspec'
  GEMFILE = TOP / 'Gemfile'
  GEMFILE_LOCK = TOP / 'Gemfile.lock'
  BUILD_LIB = BUILD / 'lib'
  RELEASE = TOP / 'pkg'
  CONF_SIGNATURE = DOC / 'conf_signature.txt'
  GEM_PACK_FILE = RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{GEM_VERSION}.gem"
  # Definition of cmmand line tests
  TEST_DEFS = TST / 'tests.yml'
  CHANGELOG_FILE = TOP / 'CHANGELOG.md'
  VERSION_FILE = TOP / 'lib/aspera/cli/version.rb'
end
