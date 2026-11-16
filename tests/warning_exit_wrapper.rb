# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# First warning displayed will stop the execution
module Warning
  # Ruby warnings start with the location: `<file>:<line>: warning: ...`
  GEM_LIB_DIR = "#{File.expand_path('../lib', __dir__)}/"
  class << self
    def warn(message)
      # Stop on first warning located in this gem's code, not other gems (e.g. simplecov messages mentioning the project path)
      raise message.to_s if message.to_s.start_with?(GEM_LIB_DIR)
      # ignore other gems code (do not call `super`)
    end
  end
end

$PROGRAM_NAME = ARGV.shift

load $PROGRAM_NAME
