module Aspera
  # used to throttle logs
  class TimerLimiter
    # @param delay in seconds (float)
    def initialize(delay)
      @delay=delay
      @last_time=nil
      @count=0
    end

    def trigger?
      old_time=@last_time
      @last_time=Time.now.to_f
      @count+=1
      if old_time.nil? or (@last_time-old_time)>@delay
        @count=0
        return true
      end
      return false
    end
  end
end
