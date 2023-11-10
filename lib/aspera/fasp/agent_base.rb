# frozen_string_literal: true

module Aspera
  module Fasp
    # Base class for FASP transfer agents
    # sub classes shall implement start_transfer and shutdown
    class AgentBase
      def wait_for_completion
        # list of: :success or "error message string"
        statuses = wait_for_transfers_completion
        @progress&.reset
        raise "internal error: bad statuses type: #{statuses.class}" unless statuses.is_a?(Array)
        raise "internal error: bad statuses content: #{statuses}" unless statuses.select{|i|!i.eql?(:success) && !i.is_a?(StandardError)}.empty?
        return statuses
      end

      private

      def initialize(options)
        raise 'internal error' unless respond_to?(:start_transfer)
        raise 'internal error' unless respond_to?(:wait_for_transfers_completion)
        Log.dump(:agent_options, options)
        raise "transfer agent options expecting Hash, but have #{options.class}" unless options.is_a?(Hash)
        @progress = options[:progress]
        options.delete(:progress)
      end

      def notify_progress(**parameters)
        @progress&.event(**parameters)
      end
    end
  end
end
