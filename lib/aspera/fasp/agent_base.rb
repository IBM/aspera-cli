# frozen_string_literal: true

module Aspera
  module Fasp
    # Base class for transfer agents
    class AgentBase
      class << self
        # compute options from user provided and default options
        def options(default:, options:)
          result = options.symbolize_keys
          available = default.map{|k, v|"#{k}(#{v})"}.join(', ')
          result.each do |k, _v|
            raise "Unknown transfer agent parameter: #{k}, expect one of #{available}" unless default.key?(k)
          end
          default.each do |k, v|
            raise "Missing required agent parameter: #{k}. Parameters: #{available}" if v.eql?(:required) && !result.key?(k)
            result[k] = v unless result.key?(k)
          end
          return result
        end
      end
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
        # method `shutdown` is optional
        Log.log.debug{Log.dump(:agent_options, options)}
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
