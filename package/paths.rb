# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'

module Paths
  TOP = Pathname.new(__dir__).parent
  TMP = TOP / 'tmp'
  BIN = TOP / 'bin'
  TST = TOP / 'tests'
  PATH_TEST_DEFS = TST / 'tests.yml'
end
