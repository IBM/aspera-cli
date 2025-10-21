# frozen_string_literal: true

require 'aspera/assert'
module Aspera
  module Agent
    # Base class for transfer agents
    # Transfer agents provide methods:
    # - `start_transfer` : take a transfer spec and start a transfer asynchronously
    # - `wait_for_transfers_completion` : waits for all transfer sessions to finish
    # - `notify_progress` : called back by transfer agent to notify transfer progress
    class Base
      # Wait for all sessions to terminate and return the status of each session
      def wait_for_completion
        # list of: :success or "error message string"
        statuses = wait_for_transfers_completion
        @progress&.reset
        Aspera.assert_type(statuses, Array)
        Aspera.assert(statuses.none?{ |i| !i.eql?(:success) && !i.is_a?(StandardError)}){"bad statuses content: #{statuses}"}
        return statuses
      end

      private

      Aspera.require_method!(:start_transfer)
      Aspera.require_method!(:wait_for_transfers_completion)
      # method `shutdown` is optional
      def shutdown
        nil
      end

      attr_reader :config_dir

      # Base transfer agent object
      # @param progress   [Object] Progress bar
      # @param config_dir [String] Config folder
      def initialize(
        progress: nil,
        config_dir: nil
      )
        @progress = progress
        @config_dir = config_dir
      end

      def notify_progress(*pos_args, **kw_args)
        @progress&.event(*pos_args, **kw_args)
      end
    end
  end
end
