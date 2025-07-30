# frozen_string_literal: true

module Aspera
  # trigger returns true only if the delay has passed since the last trigger
  class TimerLimiter
    # @param delay in seconds (float)
    def initialize(delay)
      @delay = delay
      @last_trigger_time = nil
      @count = 0
    end

    # Check if the trigger condition is met
    # @return [Boolean] true if the trigger condition is met, false otherwise
    def trigger?
      current_time = Time.now.to_f
      @count += 1
      if @last_trigger_time.nil? || ((current_time - @last_trigger_time) > @delay)
        @last_trigger_time = current_time
        @count = 0
        return true
      end
      return false
    end
  end
end
