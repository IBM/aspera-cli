# frozen_string_literal: true

require 'aspera/log'
require 'aspera/assert'
module Aspera
  module Fasp
    # Base class for transfer agents
    class AgentBase
      class << self
        # compute options from user provided and default options
        def options(default:, options:)
          result = options.symbolize_keys
          available = default.map{|k, v|"#{k}(#{v})"}.join(', ')
          result.each_key do |k|
            assert_values(k, default.keys){"transfer agent parameter: #{k}"}
            # check it is the expected type: too limiting, as we can have an Integer or Float, or symbol and string
            # raise "Invalid value for transfer agent parameter: #{k}, expect #{default[k].class.name}" unless default[k].nil? || v.is_a?(default[k].class)
          end
          default.each do |k, v|
            raise "Missing required agent parameter: #{k}. Parameters: #{available}" if v.eql?(:required) && !result.key?(k)
            result[k] = v unless result.key?(k)
          end
          return result
        end

        def agent_list
          Dir.entries(File.dirname(File.expand_path(__FILE__))).select do |file|
            file.start_with?('agent_') && !file.eql?('agent_base.rb')
          end.map{|file|file.sub(/^agent_/, '').sub(/\.rb$/, '').to_sym}
        end
      end
      def wait_for_completion
        # list of: :success or "error message string"
        statuses = wait_for_transfers_completion
        @progress&.reset
        assert_type(statuses, Array)
        assert(statuses.none?{|i|!i.eql?(:success) && !i.is_a?(StandardError)}){"bad statuses content: #{statuses}"}
        return statuses
      end

      private

      def initialize(options)
        # method `shutdown` is optional
        assert(respond_to?(:start_transfer))
        assert(respond_to?(:wait_for_transfers_completion))
        assert_type(options, Hash){'transfer agent options'}
        Log.log.debug{Log.dump(:agent_options, options)}
        @progress = options[:progress]
        options.delete(:progress)
      end

      def notify_progress(**parameters)
        @progress&.event(**parameters)
      end
    end
  end
end
