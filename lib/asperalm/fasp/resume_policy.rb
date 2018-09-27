require 'singleton'
require 'asperalm/log'

module Asperalm
  module Fasp
    # implements a simple resume policy
    class ResumePolicy
      include Singleton

      private
      def initialize
        # resume algorithm
        # TODO: command line parameters ?
        @iter_max      = 7
        @sleep_initial = 2
        @sleep_factor  = 2
        @sleep_max     = 60
      end

      public

      # calls block a number of times (resumes) until success or limit reached
      def process(&block)
        # maximum of retry
        remaining_resumes = @iter_max
        sleep_seconds = @sleep_initial
        Log.log.debug("retries=#{remaining_resumes}")
        # try to send the file until ascp is succesful
        loop do
          Log.log.debug('transfer starting');
          begin
            block.call
            break
          rescue Fasp::Error => e
            Log.log.warn("An error occured: #{e.message}" );
            # failure in ascp
            if Error.fasp_error_retryable?(e.err_code) then
              # exit if we exceed the max number of retry
              unless remaining_resumes > 0
                Log.log.error "Maximum number of retry reached"
                raise Fasp::Error,"max retry after: [#{status[:message]}]"
              end
            else
              # give one chance only to non retryable errors
              unless remaining_resumes.eql?(@iter_max)
                Log.log.error('non-retryable error')
                raise e
              end
            end
          end

          # take this retry in account
          remaining_resumes-=1
          Log.log.warn( "resuming in  #{sleep_seconds} seconds (retry left:#{remaining_resumes})" );

          # wait a bit before retrying, maybe network condition will be better
          sleep(sleep_seconds)

          # increase retry period
          sleep_seconds *= @sleep_factor
          # cap value
          if sleep_seconds > @sleep_max then
            sleep_seconds = @sleep_max
          end
        end # loop
      end
    end
  end
end
