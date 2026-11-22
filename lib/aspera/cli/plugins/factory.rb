# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../assert'
require_relative '../../bundle_registry'
require_relative '../error'
require_relative '../security'
require_relative '../../string_ext'
require 'singleton'

module Aspera
  module Cli
    # Instantiate plugin from well-known locations
    module Plugins
      # Plugins that provide commands, from the plugin registry: single files (class `Aspera::Cli::Plugins::<Name>`)
      # and bundles with `commands: true` (class `Aspera::Plugins::<Name>::Commands` in `commands.rb`).
      # @!method self.instance
      #   Returns the singleton instance of Factory
      #   @return [Factory] the singleton instance
      class Factory
        include Singleton

        # @return [BundleRegistry] Registry of plugins, shared with the domain library
        attr_reader :registry

        # @param registry [BundleRegistry] Registry of plugins, its security level checks are those of `Security`
        def initialize(registry: BundleRegistry.instance)
          @registry = registry
          @registry.security_checks(allowed: Security.instance.method(:allowed?), check: Security.instance.method(:check_level))
        end

        # @return [Array<String>] Folders where plugins are looked up, the first one with priority
        def lookup_folders = @registry.folders

        # @return [Array<Symbol>] Sorted list of available plugins that provide commands
        def plugin_list
          @registry.names.select { |name| @registry[name].commands? && @registry.unavailable_reason(name).nil? }
        end

        # add a folder to the list of folders to look for plugins
        # (absolute, as `require` resolves a relative path against $LOAD_PATH)
        # The folder of the single files of the gem comes after the folder of the bundles of the gem: a bundle hides the shim left at the path of its former single file.
        # @param folder   [String]      Folder
        # @param security [Symbol, nil] Most restrictive security level at which plugins of this folder are used, `nil` for all levels (folder of the gem).
        #   A folder that a user or a client can write is `:low`: a file written there would be loaded as code.
        def add_lookup_folder(folder, security: nil)
          @registry.add_source(folder, security: security, ignore: IGNORE_PLUGINS, last: File.identical?(folder, GEM_SINGLE_FILES_FOLDER))
        end

        # find plugins in defined paths
        def add_plugins_from_lookup_folders
          @registry.scan
        end

        # @return [String] path to source file of a single file plugin, or folder of a bundle
        def plugin_source(plugin_name_sym)
          command_plugin(plugin_name_sym).path
        end

        # @return [Class] class object for plugin, with its plugin name set and the modules mounted on it by bundles included
        def plugin_class(plugin_name_sym)
          plugin = command_plugin(plugin_name_sym)
          klass =
            case plugin.form
            when :single
              @registry.require_code(plugin_name_sym)
              # Module.nesting[1] is Aspera::Cli::Plugins
              Object.const_get("#{Module.nesting[1]}::#{plugin_name_sym.to_s.snake_to_capital}")
            when :bundle
              @registry.load_constant(plugin_name_sym, COMMANDS_FILE, COMMANDS_CLASS)
            else Aspera.error_unexpected_value(plugin.form)
            end
          klass.plugin_name = plugin_name_sym.to_s
          klass.include_mounts(@registry)
          klass
        rescue BundleRegistry::Unavailable => e
          raise Cli::Error, e.message
        end

        # Create specified plugin
        # @param plugin_name_sym [Symbol] name of plugin
        # @param args [Hash] arguments to pass to plugin constructor
        def create(plugin_name_sym, **args)
          # TODO: check that ancestor is Plugin?
          plugin_class(plugin_name_sym).new(**args)
        end

        private

        # @param plugin_name_sym [Symbol] name of plugin
        # @return [BundleRegistry::Plugin] Registered plugin that provides commands
        def command_plugin(plugin_name_sym)
          plugin = @registry[plugin_name_sym]
          Aspera.assert(plugin&.commands?, type: NoSuchElement) { "plugin not found: #{plugin_name_sym}" }
          plugin
        end

        IGNORE_PLUGINS = %i[factory base basic_auth oauth].freeze
        # Folder of the single files of the gem: `config`, `mcp`
        GEM_SINGLE_FILES_FOLDER = File.dirname(File.expand_path(__FILE__))
        # Commands of a bundle
        COMMANDS_FILE = 'commands.rb'
        COMMANDS_CLASS = 'Commands'
        private_constant :IGNORE_PLUGINS, :GEM_SINGLE_FILES_FOLDER, :COMMANDS_FILE, :COMMANDS_CLASS
      end
    end
  end
end
