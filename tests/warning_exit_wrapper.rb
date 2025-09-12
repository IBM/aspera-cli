# frozen_string_literal: true

# First warning displayed will stop the execution
module Warning
  class << self
    def warn(message)
      # Stop on first warning if in this gem's code, not other gems
      raise message.to_s if message.to_s.include?('/aspera/')
      # ignore other gems code (do not call `super`)
    end
  end
end

$PROGRAM_NAME = ARGV.shift

load $PROGRAM_NAME
