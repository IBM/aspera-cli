# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
module Aspera
  module Agent
    # Base class for transfer agents
    class Base
      RUBY_EXT = '.rb'
      private_constant :RUBY_EXT
      class << self
        def factory_create(agent, options)
          # Aspera.assert_values(agent, agent_list)
          require "aspera/agent/#{agent}"
          Aspera::Agent.const_get(agent.to_s.capitalize).new(**options)
        end

        # discover available agents
        # @return [Array] list of symbols of agents
        def agent_list
          base_class = File.basename(__FILE__)
          Dir.entries(File.dirname(File.expand_path(__FILE__))).select do |file|
            file.end_with?(RUBY_EXT) && !file.eql?(base_class)
          end.map{ |file| file[0..(-1 - RUBY_EXT.length)].to_sym}
        end
      end

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

      def initialize(progress: nil)
        @progress = progress
      end

      def notify_progress(*pos_args, **kw_args)
        @progress&.event(*pos_args, **kw_args)
      end
    end
  end
end
