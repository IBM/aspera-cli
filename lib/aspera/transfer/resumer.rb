# frozen_string_literal: true

require 'singleton'
require 'aspera/log'
require 'aspera/assert'
require 'aspera/transfer/error'

module Aspera
  module Transfer
    # Implements a simple resume policy
    class Resumer
      # @param iter_max      [Integer] Maximum number of executions
      # @param sleep_initial [Integer] Initial wait to re-execute
      # @param sleep_factor  [Integer] Multiplier
      # @param sleep_max.    [Integer] Max iterations
      def initialize(
        iter_max: 7,
        sleep_initial: 2,
        sleep_factor:  2,
        sleep_max:     60
      )
        Aspera.assert_type(iter_max, Integer){k}
        @iter_max = iter_max
        Aspera.assert_type(sleep_initial, Integer){k}
        @sleep_initial = sleep_initial
        Aspera.assert_type(sleep_factor, Integer){k}
        @sleep_factor = sleep_factor
        Aspera.assert_type(sleep_max, Integer){k}
        @sleep_max = sleep_max
      end

      # Calls block a number of times (resumes) until success or limit reached
      # This is re-entrant, one resumer can handle multiple transfers in //
      #
      # @param block [Proc]
      def execute_with_resume
        Aspera.assert(block_given?)
        # maximum of retry
        remaining_resumes = @iter_max
        sleep_seconds = @sleep_initial
        Log.log.debug{"retries=#{remaining_resumes}"}
        # try to send the file until ascp is successful
        loop do
          Log.log.debug('Transfer session starting')
          begin
            # Call provided block: execute transfer
            yield
            # Exit retry loop if success
            break
          rescue Error => e
            Log.log.warn{"A transfer error occurred during transfer: #{e.message}"}
            Log.log.debug{"Retryable ? #{e.retryable?}"}
            # do not retry non-retryable
            raise unless e.retryable?
            # exit if we exceed the max number of retry
            raise Error, "Maximum number of retry reached: #{@iter_max}" if remaining_resumes <= 0
          end

          # take this retry in account
          remaining_resumes -= 1
          Log.log.warn{"Resuming in #{sleep_seconds} seconds (retry left:#{remaining_resumes})"}

          # wait a bit before retrying, maybe network condition will be better
          sleep(sleep_seconds)

          # increase retry period
          sleep_seconds *= @sleep_factor
          # cap value
          sleep_seconds = @sleep_max if sleep_seconds > @sleep_max
        end
      end
    end
  end
end
