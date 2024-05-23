# frozen_string_literal: true

# First warning displayed will stop the execution
module Warning
  class << self
    def warn(message)
      super
      raise message.to_s
    end
  end
end

$PROGRAM_NAME = ARGV.shift

load $PROGRAM_NAME
