# frozen_string_literal: true

require_relative '../../assert'
require_relative '../error'
require_relative '../security'
require_relative '../../environment'
require_relative '../../string_ext'
require 'singleton'

module Aspera
  module Cli
    # Instantiate plugin from well-known locations
    module Plugins
      # @!method self.instance
      #   Returns the singleton instance of Factory
      #   @return [Factory] the singleton instance
      class Factory
        include Singleton

        attr_reader :lookup_folders

        def initialize
          @lookup_folders = []
          # Security level (see `Security`) of each folder: a plugin is code
          @folder_security = {}
          # information on plugins
          @plugins = {}
        end

        # @return [Array<Symbol>] Sorted list of registered plugins
        def plugin_list
          @plugins.keys.sort
        end

        # add a folder to the list of folders to look for plugins
        # (absolute, as `require` resolves a relative path against $LOAD_PATH)
        # @param folder   [String]      Folder
        # @param security [Symbol, nil] Most restrictive security level at which plugins of this folder are used, `nil` for all levels (folder of the gem).
        #   A folder that a user or a client can write is `:low`: a file written there would be loaded as code.
        def add_lookup_folder(folder, security: nil)
          folder = File.expand_path(folder)
          @folder_security[folder] = security
          @lookup_folders.unshift(folder) unless @lookup_folders.include?(folder)
        end

        # find plugins in defined paths
        def add_plugins_from_lookup_folders
          @lookup_folders.each do |folder|
            next unless File.directory?(folder)
            # Plugins registered at start (level low) stay, but files that appear later are not
            next unless Security.instance.allowed?(@folder_security[folder])
            # TODO: add gem root to load path ? and require short folder ?
            # $LOAD_PATH.push(folder) if i[:add_path]
            Dir.children(folder).each do |source|
              next unless source.end_with?(Environment::RB_EXT)
              path = File.join(folder, source)
              plugin_symbol = File.basename(path, Environment::RB_EXT).to_sym
              next if IGNORE_PLUGINS.include?(plugin_symbol)
              req = path.sub(/#{Environment::RB_EXT}$/o, '')
              next if @plugins.key?(plugin_symbol)
              @plugins[plugin_symbol] = {source: path, require_stanza: req, security: @folder_security[folder]}
            end
          end
        end

        # @return [String] path to source file of plugin
        def plugin_source(plugin_name_sym)
          Aspera.assert(@plugins.key?(plugin_name_sym), type: NoSuchElement) { "plugin not found: #{plugin_name_sym}" }
          @plugins[plugin_name_sym][:source]
        end

        # @return [Class] class object for plugin
        def plugin_class(plugin_name_sym)
          Aspera.assert(@plugins.key?(plugin_name_sym), type: NoSuchElement) { "plugin not found: #{plugin_name_sym}" }
          # A plugin registered at start can be replaced by a file written since: it is code
          Security.instance.check_level(@plugins[plugin_name_sym][:security], "plugin #{plugin_name_sym}")
          require @plugins[plugin_name_sym][:require_stanza]
          # Module.nesting[1] is Aspera::Cli::Plugins
          return Object.const_get("#{Module.nesting[1]}::#{plugin_name_sym.to_s.snake_to_capital}")
        end

        # Create specified plugin
        # @param plugin_name_sym [Symbol] name of plugin
        # @param args [Hash] arguments to pass to plugin constructor
        def create(plugin_name_sym, **args)
          # TODO: check that ancestor is Plugin?
          plugin_class(plugin_name_sym).new(**args)
        end

        IGNORE_PLUGINS = %i[factory base basic_auth oauth]
        private_constant :IGNORE_PLUGINS
      end
    end
  end
end
