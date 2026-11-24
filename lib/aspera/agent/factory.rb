# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../log'
require_relative '../assert'
require_relative '../bundle_registry'
require 'singleton'
module Aspera
  module Agent
    # Factory for Agents: the entries of the extension point `agent` of bundles.
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

      # Available agents: entries of the extension point `agent`.
      # An entry whose name is provided by an earlier entry, or whose letter is taken, is left out with a warning.
      # Recomputed when the entries change.
      # @return [Hash{Symbol => Hash}] By name, sorted: `long` capitalized name string, `short` single character symbol
      def all
        entries = @registry.extensions(POINT)
        unless entries.eql?(@entries)
          @entries = entries
          @provided = provided_agents(entries)
          @all = @provided.sort.to_h { |name, entry| [name, {long: name.to_s.capitalize, short: entry.fields['short'].to_sym}.freeze] }.freeze
        end
        @all
      end

      # Load the class of an agent: the file of the entry of its bundle, with the checks of the registry: security level, availability, gems
      # @param agent [Symbol, String] Name of an agent of `all`
      # @return [Class] The class of the agent
      # @raise [BundleRegistry::Unavailable] If the bundle of the agent is unavailable or a gem is missing
      def agent_class(agent)
        name = agent.to_sym
        reason = unavailable_reason(name)
        raise BundleRegistry::Unavailable, reason unless reason.nil?
        Aspera.assert(@provided.key?(name)) { "unknown agent: #{name}" }
        @registry.load_entry(@provided[name])
      end

      # @param agent [Symbol, String] Name of an agent
      # @return [Boolean] `true` if the agent is provided by an entry of a bundle
      def provided?(agent)
        all
        @provided.key?(agent.to_sym)
      end

      # @param agent [Symbol, String] Name of an agent
      # @return [String, nil] Why the agent is not in `all`: its bundle is unavailable (a bundle that declares it, or, if its manifest is invalid, a bundle of this name); `nil` if it is in `all` or unknown
      def unavailable_reason(agent)
        name = agent.to_sym
        all
        return if @provided.key?(name)
        @registry.names.each do |bundle_name|
          bundle = @registry[bundle_name]
          next unless bundle.bundle?
          reason = @registry.unavailable_reason(bundle_name)
          next if reason.nil?
          return "plugin #{bundle_name} is unavailable: #{reason}" if declares_agent?(bundle, name) || (bundle_name.eql?(name) && !bundle.error.nil?)
        end
        nil
      end

      # Found by the name of the class: no code is loaded (a bundle that cannot be loaded does not hide the others).
      # @param instance [Base] An agent
      # @return [Symbol, nil] Name of the agent of `all` this is an instance of, `nil` if none
      def agent_name(instance)
        class_name = instance.class.name
        all
        @provided.each { |name, entry| return name if @registry.constant_name(entry.bundle, entry.constant).eql?(class_name) }
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

      # @param bundle [BundleRegistry::Plugin] A bundle with a valid manifest
      # @param name   [Symbol]                 Name of an agent
      # @return [Boolean] `true` if the manifest of the bundle declares an agent of this name
      def declares_agent?(bundle, name)
        bundle.extensions.any? { |entry| entry.point.eql?(POINT) && entry.fields['name'].to_s.eql?(name.to_s) }
      end

      # @param entries [Array<BundleRegistry::Extension>] Entries of the extension point, in the order of the registry
      # @return [Hash{Symbol => BundleRegistry::Extension}] Entries kept, by name of agent
      def provided_agents(entries)
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
        provided
      end
    end
  end
end
