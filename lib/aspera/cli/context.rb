# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative '../bundle_registry'
require_relative 'error'
require_relative 'mailer'
require_relative 'secret_finder'

module Aspera
  module Cli
    # Global objects shared with plugins
    class Context
      # @type [Array<Symbol>]
      # Members that must be non-nil after bootstrap (validated in #validate)
      MEMBERS = %i[options config formatter persistency man_header presets vault http_config main_folder mailer secret_finder].freeze
      # @!attribute [rw] options
      #   @return [Parser] the command line options manager
      # @!attribute [rw] config
      #   @return [Plugins::Config] the configuration plugin, used by plugins to get configuration values and presets
      # @!attribute [rw] formatter
      #   @return [Formatter] the formatter, used by plugins to display results and messages
      # @!attribute [rw] persistency
      #   @return [Object] # whatever the type is
      # @!attribute [rw] man_header
      #   @return [Boolean] whether to display the manual header in plugin help
      # @!attribute [rw] presets
      #   @return [PresetManager] manages the YAML config file and preset resolution
      # @!attribute [rw] vault
      #   @return [VaultManager] secrets of the vault: `@vault:`, `config vault`, presets
      # @!attribute [rw] http_config
      #   @return [Http] manages HTTP/S and TLS runtime options
      # @!attribute [rw] mailer
      #   @return [Mailer] sends emails (SMTP) via ERB templates
      # @!attribute [rw] secret_finder
      #   @return [SecretFinder] resolves secrets for url+username pairs
      attr_accessor(*MEMBERS)
      # Optional: nil when progress bar is disabled
      attr_accessor :progress_bar
      # Optional: nil when no PAC script is configured
      attr_accessor :pac_executor
      # `true` when help is requested (`-h`)
      attr_accessor :help_requested

      # Initialize all members to nil, so that they are defined and can be validated later
      # @param registry [BundleRegistry] Registry of the bundles that provide services
      # @return [nil]
      def initialize(registry: BundleRegistry.instance)
        MEMBERS.each { |i| instance_variable_set(:"@#{i}", nil) }
        @progress_bar = nil
        @pac_executor = nil
        @help_requested = false
        @registry = registry
        # Services created, by name
        @services = {}
      end

      # Object shared by plugins, provided by a bundle (manifest `services`): created once, on first use, with the context (`new(context)`).
      # @param name [Symbol] Name of the service
      # @return [Object] The service
      # @raise [Cli::Error] If no available bundle provides the service, or its code cannot be loaded
      def service(name)
        @services[name] ||= @registry.load_entry(@registry.service(name)).new(self)
      rescue BundleRegistry::Unavailable => e
        raise Cli::Error, e.message
      end

      # Service `transfer`: transfer agent of bundle `transfer`, used by plugins that transfer files
      # @return [Object] The service, see `service`
      def transfer = service(:transfer)

      # @param value [Object] Object used as service `transfer` (e.g. a test double)
      def transfer=(value)
        @services[:transfer] = value
      end

      # Validate that all mandatory members are non-nil (detect bootstrap bugs)
      # @raise [Aspera::AssertionError] if any member is not set
      # @return [nil]
      def validate
        MEMBERS.each do |i|
          Aspera.assert(instance_variable_defined?(:"@#{i}")) { "context member @#{i} is not defined" }
          Aspera.assert(!instance_variable_get(:"@#{i}").nil?) { "context member @#{i} is nil" }
        end
      end

      # Check if the context is in manual-only mode
      # @return [Boolean] true if in manual-only mode
      def only_manual?
        @services[:transfer].eql?(:only_manual)
      end

      # Set the context to manual-only mode
      # @return [Symbol] :only_manual
      def only_manual!
        self.transfer = :only_manual
      end
    end
  end
end
