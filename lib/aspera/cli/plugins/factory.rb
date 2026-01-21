# frozen_string_literal: true

require 'singleton'
require 'aspera/assert'
require 'aspera/cli/error'
require 'aspera/environment'

module Aspera
  module Cli
    # Instantiate plugin from well-known locations
    module Plugins
      class Factory
        include Singleton

        attr_reader :lookup_folders

        def initialize
          @lookup_folders = []
          # information on plugins
          @plugins = {}
        end

        # @return [Array<Symbol>] Sorted list of registered plugins
        def plugin_list
          @plugins.keys.sort
        end

        # add a folder to the list of folders to look for plugins
        def add_lookup_folder(folder)
          @lookup_folders.unshift(folder)
        end

        # find plugins in defined paths
        def add_plugins_from_lookup_folders
          @lookup_folders.each do |folder|
            next unless File.directory?(folder)
            # TODO: add gem root to load path ? and require short folder ?
            # $LOAD_PATH.push(folder) if i[:add_path]
            Dir.entries(folder).each do |source|
              next unless source.end_with?(Environment::RB_EXT)
              path = File.join(folder, source)
              plugin_symbol = File.basename(path, Environment::RB_EXT).to_sym
              next if IGNORE_PLUGINS.include?(plugin_symbol)
              req = path.sub(/#{Environment::RB_EXT}$/o, '')
              Aspera.assert(!@plugins.key?(plugin_symbol), type: :warn){"Plugin already registered: #{plugin_symbol}"}
              @plugins[plugin_symbol] = {source: path, require_stanza: req}
            end
          end
        end

        # @return path to source file of plugin
        def plugin_source(plugin_name_sym)
          Aspera.assert(@plugins.key?(plugin_name_sym), type: NoSuchElement){"plugin not found: #{plugin_name_sym}"}
          @plugins[plugin_name_sym][:source]
        end

        # @return Class object for plugin
        def plugin_class(plugin_name_sym)
          Aspera.assert(@plugins.key?(plugin_name_sym), type: NoSuchElement){"plugin not found: #{plugin_name_sym}"}
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
