# frozen_string_literal: true

# First warning displayed will stop the execution
module Warning
  class << self
    def warn(message)
      # display and raise only if in custom code, not gems
      if message.to_s.include?('/aspera/')
        super
        raise message.to_s
      end
    end
  end
end

$PROGRAM_NAME = ARGV.shift

load $PROGRAM_NAME
