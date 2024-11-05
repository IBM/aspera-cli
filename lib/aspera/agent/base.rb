# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
module Aspera
  module Agent
    # Base class for transfer agents
    class Base
      RUBY_EXT = '.rb'
      class << self
        def factory_create(agent, options)
          # Aspera.assert_values(agent, agent_list)
          require "aspera/agent/#{agent}"
          Aspera::Agent.const_get(agent.to_s.capitalize).new(**options)
        end

        # discover available agents
        def agent_list
          base_class = File.basename(__FILE__)
          Dir.entries(File.dirname(File.expand_path(__FILE__))).select do |file|
            file.end_with?(RUBY_EXT) && !file.eql?(base_class)
          end.map{|file|file[0..(-1 - RUBY_EXT.length)].to_sym}
        end
      end

      # Wait for all sessions to terminate and return the status of each session
      def wait_for_completion
        # list of: :success or "error message string"
        statuses = wait_for_transfers_completion
        @progress&.reset
        Aspera.assert_type(statuses, Array)
        Aspera.assert(statuses.none?{|i|!i.eql?(:success) && !i.is_a?(StandardError)}){"bad statuses content: #{statuses}"}
        return statuses
      end

      private

      def initialize(progress: nil)
        # method `shutdown` is optional
        Aspera.assert(respond_to?(:start_transfer))
        Aspera.assert(respond_to?(:wait_for_transfers_completion))
        @progress = progress
      end

      def notify_progress(**parameters)
        @progress&.event(**parameters)
      end
    end
  end
end
