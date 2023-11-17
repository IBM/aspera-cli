# frozen_string_literal: true

require 'aspera/log'

module Aspera
  # used for logging http
  class LineLogger
    def initialize(level)
      @level = level
      @buffer = []
    end

    def <<(string)
      return if string.nil? || string.empty?
      if !string.end_with?("\n")
        @buffer.push(string)
        return
      end
      Log.log.send(@level, @buffer.join('') + string.chomp)
      @buffer.clear
    end
  end
end
