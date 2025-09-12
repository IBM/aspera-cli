# frozen_string_literal: true

# First warning displayed will stop the execution
module Warning
  class << self
    def warn(message)
      # display and raise only if in this gem's code, not other gems
      raise message.to_s if message.to_s.include?('/aspera/')
      # call original warn method
      super
    end
  end
end

$PROGRAM_NAME = ARGV.shift

load $PROGRAM_NAME
