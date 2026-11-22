# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../log'
require_relative '../assert'
require_relative '../environment'
require_relative '../bundle_registry'
require 'singleton'
module Aspera
  module Agent
    # Factory for Agents: the entries of the extension point `agent` of bundles, and the agents of this folder that no entry provides (legacy).
    #
    # `ALL` [Hash{Symbol => Hash}]: available agents, sorted by name: `long` capitalized name string, `short` single character symbol.
    # Computed on access (`instance.all`): bundles of folders added after this file is loaded are included.
    #
    # @!method self.instance
    #   Returns the singleton instance of Factory
    #   @return [Factory] the singleton instance
    class Factory
      include Singleton

      # Extension point of the agents of bundles
      POINT = :agent
      # Files of this folder that are not agents
      IGNORED_ITEMS = %i[factory base].freeze
      private_constant :IGNORED_ITEMS

      class << self
        # `ALL`: available agents, see `#all`
        def const_missing(name)
          return instance.all if name.eql?(:ALL)
          super
        end
      end

      # @param registry [BundleRegistry] Registry of the bundles that provide agents (loaded on use: the factory works without the CLI)
      def initialize(registry: BundleRegistry.instance)
        @registry = registry
        # Entries of the extension point used to build `@all`
        @entries = nil
        # Available agents, see `all`
        @all = nil
        # Entry of each agent provided by a bundle, by name
        @provided = {}
      end

      # Available agents: entries of the extension point `agent`, then the agents of this folder that no entry provides.
      # An entry whose name is provided by an earlier entry, or whose letter is taken, is left out with a warning.
      # Recomputed when the entries change.
      # @return [Hash{Symbol => Hash}] By name, sorted: `long` capitalized name string, `short` single character symbol
      def all
        entries = @registry.extensions(POINT)
        unless entries.eql?(@entries)
          @entries = entries
          legacy = legacy_agents
          @provided = provided_agents(entries, legacy)
          shorts = legacy.reject { |name, _| @provided.key?(name) }.merge(@provided.transform_values { |entry| entry.fields['short'].to_sym })
          @all = shorts.sort.to_h { |name, short| [name, {long: name.to_s.capitalize, short: short}.freeze] }.freeze
        end
        @all
      end

      # Load the class of an agent: the file of the entry of its bundle (with the checks of the registry: security level, availability, gems), or the legacy file
      # @param agent [Symbol, String] Name of an agent of `all`
      # @return [Class] The class of the agent
      # @raise [BundleRegistry::Unavailable] If the bundle of the agent is unavailable or a gem is missing
      def agent_class(agent)
        name = agent.to_sym
        Aspera.assert(all.key?(name)) { "unknown agent: #{name}" }
        return @registry.load_entry(@provided[name]) if @provided.key?(name)
        require "aspera/agent/#{name}"
        Aspera::Agent.const_get(name.to_s.capitalize)
      end

      # @param agent [Symbol, String] Name of an agent of `all`
      # @return [Boolean] `true` if the agent is provided by an entry of a bundle, `false` for the agents of this folder
      def provided?(agent)
        all
        @provided.key?(agent.to_sym)
      end

      # @param instance [Base] An agent
      # @return [Symbol, nil] Name of the agent of `all` this is an instance of, `nil` if none (a bundle that cannot be loaded is skipped)
      def agent_name(instance)
        all.each_key do |name|
          return name if agent_class(name).equal?(instance.class)
        rescue BundleRegistry::Unavailable
          next
        end
        nil
      end

      # Create new agent
      # @param agent   [Symbol, String] Name of an agent of `all`
      # @param options [Hash]           Keyword arguments of the constructor of the agent
      # @return [Base] The agent
      def create(agent, options)
        Log.dump(:options, options)
        agent_class(agent).new(**options)
      end

      private

      # Agents of this folder, letter by today's rule: first letter, except `direct`
      # @return [Hash{Symbol => Symbol}] Letter, by name
      def legacy_agents
        Dir.children(__dir__)
          .select { |file| file.end_with?(Environment::RB_EXT) }
          .map { |file| File.basename(file, Environment::RB_EXT).to_sym }
          .reject { |item| IGNORED_ITEMS.include?(item) }
          .to_h { |name| [name, name.eql?(:direct) ? :a : name.to_s[0].to_sym] }
      end

      # @param entries [Array<BundleRegistry::Extension>] Entries of the extension point, in the order of the registry
      # @param legacy  [Hash{Symbol => Symbol}]         Letter of the agents of this folder, by name
      # @return [Hash{Symbol => BundleRegistry::Extension}] Entries kept, by name of agent
      def provided_agents(entries, legacy)
        provided = {}
        entries.each do |entry|
          name, short = entry.fields.values_at('name', 'short')
          if !name.is_a?(String) || !short.is_a?(String) || !short.length.eql?(1)
            Log.log.warn { "Agent of bundle #{entry.bundle} is left out: invalid name #{name.inspect} or letter #{short.inspect}" }
            next
          end
          name = name.to_sym
          short = short.to_sym
          if provided.key?(name)
            Log.log.warn { "Agent #{name} of bundle #{entry.bundle} is left out: provided by bundle #{provided[name].bundle}" }
            next
          end
          owner = provided.find { |_, other| other.fields['short'].eql?(short.to_s) }&.first
          unless owner.nil?
            Log.log.warn { "Agent #{name} of bundle #{entry.bundle} is left out: letter #{short} is taken by agent #{owner}" }
            next
          end
          provided[name] = entry
        end
        # A legacy agent keeps its letter unless an entry provides it: checked once all entries are known, so that the order of entries does not matter.
        # An entry left out gives its legacy agent back, which can take the letter of another entry: repeat until stable.
        loop do
          clash = nil
          provided.each do |name, entry|
            owner = legacy.find { |other, letter| letter.to_s.eql?(entry.fields['short']) && !other.eql?(name) && !provided.key?(other) }&.first
            clash = [name, entry, owner] unless owner.nil?
            break unless clash.nil?
          end
          break if clash.nil?
          Log.log.warn { "Agent #{clash[0]} of bundle #{clash[1].bundle} is left out: letter #{clash[1].fields['short']} is taken by agent #{clash[2]}" }
          provided.delete(clash[0])
        end
        provided
      end
    end
  end
end
