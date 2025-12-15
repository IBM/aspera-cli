# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'

module Paths
  # Main project folder
  TOP = Pathname.new(__dir__).parent.parent
  TMP = TOP / 'tmp'
  BIN = TOP / 'bin'
  # Folder with tests
  TST = TOP / 'tests'
  # Definition of cmmand line tests
  PATH_TEST_DEFS = TST / 'tests.yml'
  def config_file_path
    raise 'missing env var ASPERA_CLI_TEST_CONF_FILE' unless ENV.key?('ASPERA_CLI_TEST_CONF_FILE')
    Pathname.new(ENV['ASPERA_CLI_TEST_CONF_FILE'])
  end
  module_function :config_file_path
end
