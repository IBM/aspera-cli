# frozen_string_literal: true

require 'pathname'
require 'aspera/cli/info'

module Folders
  TOP = Pathname.new(__dir__).parent
  TMP = TOP / 'tmp'
  BIN = TOP / 'bin'
  TST = TOP / 'tests'
end
