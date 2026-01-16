# frozen_string_literal: true

require 'singleton'
require 'aspera/log'
require 'aspera/environment'
module Aspera
  module Agent
    # Factory for Agents
    class Factory
      include Singleton

      # Create new agent
      def create(agent, options)
        Log.dump(:options, options)
        require "aspera/agent/#{agent}"
        Aspera::Agent.const_get(agent.to_s.capitalize).new(**options)
      end

      IGNORED_ITEMS = %i[factory base]
      # Available agents: :long : Capitalized name string, :short : single character symbol
      ALL =
        Dir.children(File.dirname(File.expand_path(__FILE__)))
          .select{ |file| file.end_with?(Environment::RB_EXT)}
          .map{ |file| File.basename(file, Environment::RB_EXT).to_sym}
          .reject{ |item| IGNORED_ITEMS.include?(item)}.each_with_object({}) do |agent_sym, hash|
          hash[agent_sym] = {
            long:  agent_sym.to_s.capitalize,
            short: agent_sym.eql?(:direct) ? :a : agent_sym.to_s[0].to_sym
          }.freeze
        end.freeze
      private_constant :IGNORED_ITEMS
    end
  end
end
