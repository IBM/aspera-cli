# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'
require 'aspera/cli/version'

# Gem version for build
GEM_VERSION = ENV['GEM_VERSION'] || Aspera::Cli::VERSION

# Fixed paths in project
module Paths
  # Main project folder
  TOP = Pathname.new(__dir__).parent.parent
  TMP = TOP / 'tmp'
  BIN = TOP / 'bin'
  CLI_CMD = BIN / Aspera::Cli::Info::CMD_NAME
  LIB = TOP / 'lib'
  DOC = TOP / 'docs'
  # Folder with tests
  TST = TOP / 'tests'
  BUILD = TOP / 'build'
  GEMSPEC = TOP / 'aspera-cli.gemspec'
  BUILD_LIB = BUILD / 'lib'
  RELEASE = TOP / 'pkg'
  GEMFILE = RELEASE / "#{Aspera::Cli::Info::GEM_NAME}-#{Aspera::Cli::VERSION}.gem"
  # Definition of cmmand line tests
  TEST_DEFS = TST / 'tests.yml'
  # @return [Pathname]
  def config_file_path
    raise 'missing env var ASPERA_CLI_TEST_CONF_FILE' unless ENV.key?('ASPERA_CLI_TEST_CONF_FILE')
    Pathname.new(ENV['ASPERA_CLI_TEST_CONF_FILE'])
  end
  module_function :config_file_path
end
