# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../../assert'
require_relative '../../log'
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

        # @return [Array<Symbol>] Sorted list of plugins that provide commands and can be loaded: available, with their gems installed.
        #   Callers load the class of each one: `unavailable_plugins` gives the others, with the reason.
        def plugin_list
          @registry.names.select { |name| @registry[name].commands? && @registry.load_error(name).nil? }
        end

        # @return [Hash{Symbol => String}] Reason why a plugin that provides commands, or whose manifest is invalid, is not in `plugin_list`, by name
        def unavailable_plugins
          listed_plugins.to_h { |name| [name, @registry.load_error(name)] }.compact
        end

        # @return [Array<Symbol>] Sorted names of the plugins to list: those that provide commands, and those that cannot be loaded (their manifest may be invalid)
        def listed_plugins
          @registry.names.select { |name| @registry[name].commands? || !status_reason(name).nil? }
        end

        # @param name [Symbol] Name of a registered plugin
        # @return [String] `available`, or why the plugin cannot be loaded: unavailable, or a gem is missing
        def status(name)
          status_reason(name) || 'available'
        end

        # Description of a registered plugin, for introspection (data only: no code of the plugin is loaded).
        # @param name [Symbol] Name of a registered plugin
        # @return [Hash] `plugin`, `title`, `source` (`gem` or the folder), `form`, `path`, `security`, `status`, `commands`, then for a bundle:
        #   `agents`, `schemas`, `mounts`, `services`, `extension_points`, `depends`, `gems`, `missing_gems`
        # @raise [NoSuchElement] If no plugin has this name
        def describe(name)
          plugin = @registry[name]
          Aspera.assert(!plugin.nil?, type: NoSuchElement) { "plugin not found: #{name}" }
          result = {
            plugin:   name,
            title:    plugin.title,
            source:   source_of(plugin),
            form:     plugin.form,
            path:     plugin.path,
            security: plugin.security || 'any',
            status:   status(name),
            commands: plugin.commands?
          }
          return result unless plugin.bundle?
          result.merge(
            agents:           plugin.extensions.select { |extension| extension.point.eql?(:agent) }.map { |extension| extension.fields['name'] },
            schemas:          plugin.schemas.map(&:key),
            mounts:           plugin.mounts.map(&:target),
            services:         plugin.services.map(&:name),
            extension_points: plugin.extension_points.keys,
            depends:          plugin.depends,
            gems:             plugin.gems,
            missing_gems:     @registry.missing_gems(name)
          )
        end

        # add a folder to the list of folders to look for plugins
        # (absolute, as `require` resolves a relative path against $LOAD_PATH)
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
        rescue NameError, LoadError, SyntaxError => e
          # Broken code of a plugin of the gem is a bug of ascli: reported as such, with its location
          raise if !plugin.nil? && source_of(plugin).eql?('gem')
          # Else only the error of the plugin itself: not a bug of the gem code that it calls (DSL of `Base`, `use_options`, mounts), which is reported as such
          raise unless plugin_error?(plugin, e)
          # Broken code of an external plugin (no `commands.rb`, wrong constant, syntax error): same error as an unavailable plugin
          Log.log.debug { "plugin #{plugin_name_sym}: #{e.class}: #{e.message}" }
          raise Cli::Error, "plugin #{plugin_name_sym} cannot be loaded: #{e.class}: #{e.message}"
        end

        # Create specified plugin
        # @param plugin_name_sym [Symbol] name of plugin
        # @param args [Hash] arguments to pass to plugin constructor
        def create(plugin_name_sym, **args)
          # TODO: check that ancestor is Plugin?
          plugin_class(plugin_name_sym).new(**args)
        end

        private

        # @param plugin [BundleRegistry::Plugin, nil] External plugin that is loaded
        # @param error  [NameError, LoadError, SyntaxError] Error raised while it is loaded
        # @return [Boolean] `true` if the error comes from the plugin itself: a `LoadError` (no file) or `SyntaxError` of its files,
        #   or a `NameError` raised from a file of the plugin, or by the lookup of its class (wrong constant)
        def plugin_error?(plugin, error)
          return true if error.is_a?(LoadError) || error.is_a?(SyntaxError)
          # `const_get` may or may not be a location, according to the Ruby version and tools (coverage)
          location = error.backtrace_locations&.find { |loc| !loc.label.to_s.end_with?('const_get') }
          return false if plugin.nil? || location.nil?
          # The class is searched by name (a wrong constant): the first location is the lookup of the loader
          return true if error.instance_of?(NameError) && location.label.to_s.end_with?('#load_constant', '#plugin_class') && [__FILE__, BundleRegistry.instance_method(:load_constant).source_location.first].include?(location.path)
          path = File.realpath(plugin.path)
          file = File.expand_path(location.absolute_path || location.path)
          file.eql?(path) || file.start_with?(File.join(path, ''))
        end

        # @param name [Symbol] name of a registered plugin
        # @return [String, nil] Why the plugin cannot be loaded, short form: unavailable reason, or missing gems; `nil` if it can
        def status_reason(name)
          reason = @registry.unavailable_reason(name)
          return reason unless reason.nil?
          missing = @registry.missing_gems(name)
          missing.empty? ? nil : "missing gem #{missing.join(', ')}"
        end

        # @param plugin [BundleRegistry::Plugin] Registered plugin
        # @return [String] `gem` if in the gem, else the folder where it was found
        def source_of(plugin)
          folder = File.dirname(plugin.path)
          [BundleRegistry::GEM_FOLDER, GEM_SINGLE_FILES_FOLDER].any? { |gem_folder| File.identical?(folder, gem_folder) } ? 'gem' : folder
        end

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
