# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'
require 'aspera/cli/version'

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
  # rake target: `build`
  GEM_PACK_FILE = RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{Aspera::Cli::VERSION}.gem"
  # Definition of cmmand line tests
  TEST_DEFS = TST / 'tests.yml'
  CHANGELOG_FILE = TOP / 'CHANGELOG.md'
  VERSION_FILE = TOP / 'lib/aspera/cli/version.rb'
  DOCKERFILE_TEMPLATE = BUILD / 'container/Dockerfile.tmpl.erb'
  OVERRIDE_VERSION_FILE = TMP / 'container_beta_version.txt'
  WIN_ZIP_SRC = BUILD / 'windowszip'
end
