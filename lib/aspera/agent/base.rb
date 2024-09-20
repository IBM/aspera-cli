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

        # compute options from user provided and default options
        def to_move_options(default:, options:)
          result = options.symbolize_keys
          available = default.map{|k, v|"#{k}(#{v})"}.join(', ')
          result.each_key do |k|
            Aspera.assert_values(k, default.keys){"transfer agent parameter: #{k}"}
            # check it is the expected type: too limiting, as we can have an Integer or Float, or symbol and string
            # raise "Invalid value for transfer agent parameter: #{k}, expect #{default[k].class.name}" unless default[k].nil? || v.is_a?(default[k].class)
          end
          default.each do |k, v|
            raise "Missing required agent parameter: #{k}. Parameters: #{available}" if v.eql?(:required) && !result.key?(k)
            result[k] = v unless result.key?(k)
          end
          return result
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
