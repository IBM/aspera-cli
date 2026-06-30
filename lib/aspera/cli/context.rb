# frozen_string_literal: true

require 'aspera/assert'

module Aspera
  module Cli
    # Global objects shared with plugins
    class Context
      # @type [Array<Symbol>]
      MEMBERS = %i[options transfer config formatter persistency man_header].freeze
      # @!attribute [rw] options
      #   @return [Manager] the command line options manager
      # @!attribute [rw] transfer
      #   @return [TransferAgent] the transfer agent, used by transfer plugins
      # @!attribute [rw] config
      #   @return [Plugins::Config] the configuration plugin, used by plugins to get configuration values and presets
      # @!attribute [rw] formatter
      #   @return [Formatter] the formatter, used by plugins to display results and messages
      # @!attribute [rw] persistency
      #   @return [Object] # whatever the type is
      # @!attribute [rw] man_header
      #   @return [Boolean] whether to display the manual header in plugin help
      attr_accessor(*MEMBERS)

      # Initialize all members to nil, so that they are defined and can be validated later
      # @return [nil]
      def initialize
        MEMBERS.each{ |i| instance_variable_set(:"@#{i}", nil)}
      end

      # Validate that all members are set, raise exception if not
      # @raise [Aspera::AssertionError] if any member is not set
      # @return [nil]
      def validate
        MEMBERS.each do |i|
          Aspera.assert(instance_variable_defined?(:"@#{i}")){"context member @#{i} is not defined"}
          Aspera.assert(!instance_variable_get(:"@#{i}").nil?){"context member @#{i} is nil"}
        end
      end

      # Check if the context is in manual-only mode
      # @return [Boolean] true if in manual-only mode
      def only_manual?
        transfer.eql?(:only_manual)
      end

      # Set the context to manual-only mode
      # @return [Symbol] :only_manual
      def only_manual!
        @transfer = :only_manual
      end
    end
  end
end
