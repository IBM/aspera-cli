# frozen_string_literal: true

require 'singleton'
require 'aspera/log'
require 'aspera/assert'

module Aspera
  # implements a simple resume policy
  class Resumer
    # list of supported parameters and default values
    DEFAULTS = {
      iter_max:      7,
      sleep_initial: 2,
      sleep_factor:  2,
      sleep_max:     60
    }.freeze

    # @param params see DEFAULTS
    def initialize(params=nil)
      @parameters = DEFAULTS.dup
      if !params.nil?
        Aspera.assert_type(params, Hash)
        params.each do |k, v|
          Aspera.assert_values(k, DEFAULTS.keys){'resume parameter'}
          Aspera.assert_type(v, Integer){k}
          @parameters[k] = v
        end
      end
      Log.log.debug{"resume params=#{@parameters}"}
    end

    # calls block a number of times (resumes) until success or limit reached
    # this is re-entrant, one resumer can handle multiple transfers in //
    def execute_with_resume
      Aspera.assert(block_given?)
      # maximum of retry
      remaining_resumes = @parameters[:iter_max]
      sleep_seconds = @parameters[:sleep_initial]
      Log.log.debug{"retries=#{remaining_resumes}"}
      # try to send the file until ascp is successful
      loop do
        Log.log.debug('transfer starting')
        begin
          # call provided block
          yield
          # exit retry loop if success
          break
        rescue Transfer::Error => e
          Log.log.warn{"An error occurred during transfer: #{e.message}"}
          # failure in ascp
          if e.retryable?
            # exit if we exceed the max number of retry
            raise Transfer::Error, "Maximum number of retry reached (#{@parameters[:iter_max]})" if remaining_resumes <= 0
          else
            # give one chance only to non retryable errors
            unless remaining_resumes.eql?(@parameters[:iter_max])
              Log.log.error('non-retryable error'.red.blink)
              raise e
            end
          end
        end

        # take this retry in account
        remaining_resumes -= 1
        Log.log.warn{"Resuming in #{sleep_seconds} seconds (retry left:#{remaining_resumes})"}

        # wait a bit before retrying, maybe network condition will be better
        sleep(sleep_seconds)

        # increase retry period
        sleep_seconds *= @parameters[:sleep_factor]
        # cap value
        sleep_seconds = @parameters[:sleep_max] if sleep_seconds > @parameters[:sleep_max]
      end
    end
  end
end
