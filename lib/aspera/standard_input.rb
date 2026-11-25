# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  # The standard input given where a command reads a file (e.g. a log file to analyze): the command reads it, as it would read the file.
  # On command line: the argument `-`, or the extended value `@stdin:stream`.
  # Unlike `@stdin:`, which reads the standard input when the value is evaluated, it is not read until the command reads it.
  class StandardInput
    # Name of the standard input where a file name is expected, also in results and messages
    NAME = '-'

    # @return [String] `-`, e.g. as the file name in results
    def to_s = NAME

    # @return [String] the content of the standard input, in binary mode
    def read = $stdin.binmode.read
  end
end
