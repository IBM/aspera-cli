# frozen_string_literal: true

require 'singleton'
module Aspera
  module Cli
    # Instantiate plugin from well-known locations
    class PluginFactory
      include Singleton

      RUBY_FILE_EXT = '.rb'
      PLUGINS_MODULE = 'Plugins'
      private_constant :RUBY_FILE_EXT, :PLUGINS_MODULE

      attr_reader :lookup_folders

      def initialize
        @lookup_folders = []
        # information on plugins
        @plugins = {}
      end

      # @return list of registered plugins
      def plugin_list
        @plugins.keys
      end

      # @return path to source file of plugin
      def plugin_source(plugin_name_sym)
        @plugins[plugin_name_sym][:source]
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
          Dir.entries(folder).select{ |file| file.end_with?(RUBY_FILE_EXT)}.each do |source|
            add_plugin_info(File.join(folder, source))
          end
        end
      end

      # @return Class object for plugin
      def plugin_class(plugin_name_sym)
        raise "ERROR: plugin not found: #{plugin_name_sym}" unless @plugins.key?(plugin_name_sym)
        require @plugins[plugin_name_sym][:require_stanza]
        # Module.nesting[1] is Aspera::Cli
        return Object.const_get("#{Module.nesting[1]}::#{PLUGINS_MODULE}::#{plugin_name_sym.to_s.capitalize}")
      end

      # Create specified plugin
      # @param plugin_name_sym [Symbol] name of plugin
      # @param args [Hash] arguments to pass to plugin constructor
      def create(plugin_name_sym, **args)
        # TODO: check that ancestor is Plugin?
        plugin_class(plugin_name_sym).new(**args)
      end

      private

      # add plugin information to list
      # @param path [String] path to plugin source file
      def add_plugin_info(path)
        raise "ERROR: plugin path must end with #{RUBY_FILE_EXT}" if !path.end_with?(RUBY_FILE_EXT)
        plugin_symbol = File.basename(path, RUBY_FILE_EXT).to_sym
        req = path.sub(/#{RUBY_FILE_EXT}$/o, '')
        if @plugins.key?(plugin_symbol)
          Log.log.warn{"skipping plugin already registered: #{plugin_symbol}"}
          return
        end
        @plugins[plugin_symbol] = {source: path, require_stanza: req}
      end
    end
  end
end
