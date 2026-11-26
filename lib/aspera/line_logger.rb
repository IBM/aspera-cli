# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'log'
require_relative 'secret/hider'

module Aspera
  # used for logging http: debug output of `Net::HTTP` (`set_debug_output`), one log line per line of output
  class LineLogger
    # Data sent (`<-`) or received (`->`): one or several dumped strings (`String#dump`)
    WIRE_DATA = /\A(?<direction><-|->) (?<data>".*")\z/
    # One dumped string
    DUMPED_STRING = /"(?:[^"\\]|\\.)*"/
    private_constant :WIRE_DATA, :DUMPED_STRING

    # @param level [Symbol] Log level
    def initialize(level)
      @level = level
      @buffer = []
    end

    # Called by `Net::HTTP`
    # @param string [String] Part of a line of debug output
    def <<(string)
      return if string.nil? || string.empty?
      @buffer.push(string)
      return unless string.end_with?("\n")
      line = @buffer.join.chomp
      @buffer.clear
      Log.log.send(@level) { hide_secrets(line) }
    end

    private

    # Hides secrets by key name in the HTTP data of a line, e.g. a token in a JSON body (see `Secret::Hider#hide_serialized_secrets`):
    # the data is dumped, its quotes escaped, so the patterns of the log formatter would not match
    # @param line [String] Line of debug output
    # @return [String] Line with secrets hidden
    def hide_secrets(line)
      match = WIRE_DATA.match(line)
      return line if match.nil? || Secret::Hider.instance.log_secrets
      data = match[:data].gsub(DUMPED_STRING) do |dumped|
        text = dumped.undump
        hidden = Secret::Hider.instance.hide_serialized_secrets(text)
        hidden.eql?(text) ? dumped : hidden.inspect
      rescue StandardError
        # Not text, e.g. binary data
        dumped
      end
      "#{match[:direction]} #{data}"
    end
  end
end
