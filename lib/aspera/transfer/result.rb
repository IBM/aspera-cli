# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  module Transfer
    # Typed result of a transfer operation.
    # Replaces the ad-hoc Array polymorphism previously returned by agents.
    #
    # Agents return one of the three concrete sub-classes:
    #   Transfer::Result::Success  — all sessions completed successfully
    #   Transfer::Result::Error    — at least one session failed
    #   Transfer::Result::Async    — transfer submitted to a daemon; not yet complete
    #   Transfer::Result::DryRun   — transfer not started (option `dry_run`): final transfer spec
    class Result
      # All sessions completed successfully.
      class Success < Result
        def to_s
          'success'
        end
      end

      # At least one session failed.
      class Error < Result
        # @return [StandardError]
        attr_reader :exception

        def initialize(exception)
          super()
          @exception = exception
        end

        def to_s
          "error: #{@exception.message}"
        end
      end

      # Transfer submitted to an external daemon; status not yet known.
      class Async < Result
        # @return [String] UUID assigned to this background job
        attr_reader :job_id
        # @return [String] initial status string (e.g. 'running')
        attr_reader :status

        def initialize(job_id:, status: 'running')
          super()
          @job_id = job_id
          @status = status
        end

        # Convenience: export as a plain Hash for serialization / display
        def to_h
          {'job_id' => @job_id, 'status' => @status}
        end

        def to_s
          "async job_id=#{@job_id} status=#{@status}"
        end
      end

      # Transfer not started, because of option `dry_run`.
      class DryRun < Result
        # @return [Hash] final transfer spec, as it would be given to the agent
        attr_reader :transfer_spec

        def initialize(transfer_spec)
          super()
          @transfer_spec = transfer_spec
        end

        def to_s
          'dry run'
        end
      end

      # Factory helpers
      class << self
        def success
          Success.new
        end

        def error(exception)
          Error.new(exception)
        end

        def async(job_id:, status: 'running')
          Async.new(job_id: job_id, status: status)
        end

        def dry_run(transfer_spec)
          DryRun.new(transfer_spec)
        end
      end
    end
  end
end
