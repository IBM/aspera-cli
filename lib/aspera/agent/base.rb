# frozen_string_literal: true

require 'aspera/assert'
require 'aspera/transfer/result'
module Aspera
  module Agent
    # Base class for transfer agents
    # Transfer agents provide methods:
    # - `start_transfer`                 : take a transfer spec and start a transfer asynchronously
    # - `wait_for_transfers_completion`  : waits for all transfer sessions to finish
    # - `notify_progress`                : called back by transfer agent to notify transfer progress
    # - `self.transfer_status`           : (optional) re-query a previously started transfer by id
    class Base
      class << self
        # Re-query the status of a transfer that was started asynchronously.
        # Override in agents that support live status queries (desktop, node, connect, transferd).
        # @param transfer_id  [String] opaque id returned by start_transfer
        # @param agent_params [Hash]   connection parameters stored at submission time
        # @return [Hash, nil] status hash with at least 'status' key, or nil if not supported
        def transfer_status(_transfer_id, _agent_params)
          nil
        end
      end

      # Wait for all sessions to terminate and return a typed Transfer::Result.
      # @return [Transfer::Result::Success, Transfer::Result::Error]
      def wait_for_completion
        statuses = wait_for_transfers_completion
        @progress&.reset
        Aspera.assert_type(statuses, Array)
        Aspera.assert(statuses.none?{ |i| !i.eql?(:success) && !i.is_a?(StandardError)}){"bad statuses content: #{statuses}"}
        errors = statuses.reject{ |i| i.eql?(:success)}
        return errors.empty? ? Transfer::Result.success : Transfer::Result.error(errors.first)
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
