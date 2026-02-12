# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'
require 'aspera/cli/version'

# Path constants for the project layout (build scripts, docs, tests).
# All paths are relative to the repository root.
module Paths
  # Project (repository) root directory.
  TOP = Pathname.new(__dir__).parent.parent
  # Subdirectories under project root.
  TMP = TOP / 'tmp'
  BIN = TOP / 'bin'
  LIB = TOP / 'lib'
  DOC = TOP / 'docs'
  TST = TOP / 'tests'
  BUILD = TOP / 'build'
  BUILD_LIB = BUILD / 'lib'
  RELEASE = TOP / 'pkg'
  PANDOC = BUILD / 'doc' / 'pandoc'
  MKDOCS = BUILD / 'doc' / 'mkdocs'
  # Paths to key configuration and source files.
  GEMSPEC = TOP / 'aspera-cli.gemspec'
  GEMFILE = TOP / 'Gemfile'
  GEMFILE_LOCK = TOP / 'Gemfile.lock'
  CONF_SIGNATURE = DOC / 'conf_signature.txt'
  PDF_MANUAL = RELEASE / "Manual-#{Aspera::Cli::Info::CMD_NAME}.pdf"
  # Command-line test suite configuration.
  TEST_DEFS = TST / 'tests.yml'
  CHANGELOG_FILE = TOP / 'CHANGELOG.md'
  VERSION_FILE = TOP / 'lib/aspera/cli/version.rb'
  DOCKERFILE_TEMPLATE = BUILD / 'container/Dockerfile.tmpl.erb'
  OVERRIDE_VERSION_FILE = TMP / 'container_beta_version.txt'
  WIN_ZIP_SRC = BUILD / 'windowszip'
  TMPL_CONF_FILE = DOC / 'test_env.conf'
  TSPEC_JSON_SCHEMA = DOC / 'spec.schema.json'
  UML_PNG = Paths::DOC / 'uml.png'
  MD_MANUAL = DOC / 'README.md'
  MD_ERB = DOC / 'README.erb.md'
  TSPEC_YAML_SCHEMA = LIB / 'aspera/transfer/spec.schema.yaml'
  ASYNC_YAML_SCHEMA = LIB / 'aspera/sync/conf.schema.yaml'
  BUILD_TOOLS = BUILD_LIB / 'build_tools.rb'
  DOC_HELPER = BUILD_LIB / 'doc_helper.rb'
  COMMAND = BIN / Aspera::Cli::Info::CMD_NAME
  ASESSION = BIN / 'asession'
end
