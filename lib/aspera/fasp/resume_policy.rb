# frozen_string_literal: true

require 'singleton'
require 'aspera/log'

module Aspera
  module Fasp
    # implements a simple resume policy
    class ResumePolicy
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
          raise "expecting Hash (or nil), but have #{params.class}" unless params.is_a?(Hash)
          params.each do |k, v|
            raise "unknown resume parameter: #{k}, expect one of #{DEFAULTS.keys.map(&:to_s).join(',')}" unless DEFAULTS.has_key?(k)
            raise "#{k} must be Integer" unless v.is_a?(Integer)
            @parameters[k] = v
          end
        end
        Log.log.debug("resume params=#{@parameters}")
      end

      # calls block a number of times (resumes) until success or limit reached
      # this is re-entrant, one resumer can handle multiple transfers in //
      def execute_with_resume
        raise 'block manndatory' unless block_given?
        # maximum of retry
        remaining_resumes = @parameters[:iter_max]
        sleep_seconds = @parameters[:sleep_initial]
        Log.log.debug("retries=#{remaining_resumes}")
        # try to send the file until ascp is succesful
        loop do
          Log.log.debug('transfer starting');
          begin
            # call provided block
            yield
            break
          rescue Fasp::Error => e
            Log.log.warn("An error occurred: #{e.message}");
            # failure in ascp
            if e.retryable?
              # exit if we exceed the max number of retry
              raise Fasp::Error, 'Maximum number of retry reached' if remaining_resumes <= 0
            else
              # give one chance only to non retryable errors
              unless remaining_resumes.eql?(@parameters[:iter_max])
                Log.log.error('non-retryable error')
                raise e
              end
            end
          end

          # take this retry in account
          remaining_resumes -= 1
          Log.log.warn("resuming in  #{sleep_seconds} seconds (retry left:#{remaining_resumes})");

          # wait a bit before retrying, maybe network condition will be better
          sleep(sleep_seconds)

          # increase retry period
          sleep_seconds *= @parameters[:sleep_factor]
          # cap value
          sleep_seconds = @parameters[:sleep_max] if sleep_seconds > @parameters[:sleep_max]
        end # loop
      end
    end
  end
end
