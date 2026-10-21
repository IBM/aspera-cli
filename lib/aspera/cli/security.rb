# frozen_string_literal: true

require 'singleton'
require 'aspera/assert'
require 'aspera/cli/error'

module Aspera
  module Cli
    # Security level: restricts the features that access local resources (files, environment, network) or execute code.
    # On the command line, the default level is `low`: the user can do anything that the account is allowed to do.
    # It can be raised, for example in MCP server mode, where commands come from a client.
    #
    # @!method self.instance
    #   Returns the singleton instance of Security
    #   @return [Security] the singleton instance
    class Security
      include Singleton

      # Security levels, from least to most restrictive
      LEVELS = %i[low medium high].freeze
      # Extended-value handlers restricted by security level, with the levels that allow them
      EXTENDED_VALUE_LEVELS = {
        ruby: %i[low],
        uri:  %i[low],
        env:  %i[low],
        file: %i[low medium]
      }.freeze
      private_constant :EXTENDED_VALUE_LEVELS

      def initialize
        reset
      end

      # Back to default: level `low`, no allowed path, not locked
      # @return [nil]
      def reset
        @level = nil
        @default_level = LEVELS.first
        @allowed_paths = []
        @locked = nil
      end

      # @return [Symbol] Level set by option `security`, else default level
      def level = @level || @default_level

      # Set by option `security`.
      # When locked, the value can only be set again to the current one.
      # @param value [Hash] `level` and `allowed_paths`, see schema `SecurityOptions`
      # @return [nil]
      def options=(value)
        Aspera.assert_type(value, Hash, type: BadArgument) { 'security' }
        # When locked, each command starts with the empty value of a Hash option: not a change
        return if @locked && value.empty?
        value = value.transform_keys(&:to_sym)
        new_level = value[:level]&.to_sym
        Aspera.assert_values(new_level, LEVELS, type: BadArgument) { 'security.level' } unless new_level.nil?
        new_paths = Array(value[:allowed_paths]).map do |path|
          path = File.expand_path(path)
          Aspera.assert(File.exist?(path), type: BadArgument) { "security.allowed_paths: no such file or folder: #{path}" }
          File.realpath(path)
        end
        if @locked
          Aspera.assert((new_level || @default_level).eql?(level) && new_paths.eql?(@allowed_paths), type: BadArgument) do
            "security cannot be changed #{@locked}"
          end
          return
        end
        @level = new_level
        @allowed_paths = new_paths
        nil
      end

      # Prevent further changes, e.g. by commands of an MCP client
      # @param reason [String] For error messages, e.g. `in MCP server mode`
      # @param default [Symbol, nil] Level if not set by option
      # @return [nil]
      def lock(reason, default: nil)
        Aspera.assert_values(default, LEVELS) unless default.nil?
        @default_level = default unless default.nil?
        @locked = reason
        nil
      end

      # @param handler [Symbol] Extended-value handler
      # @raise [BadArgument] If the handler is refused at current level, with the level that allows it and where to set it
      def check_extended_value(handler)
        allowed = EXTENDED_VALUE_LEVELS[handler]
        return if allowed.nil? || allowed.include?(level)
        # the least permissive level that allows it
        needed = handler.eql?(:file) ? "level #{allowed.last} with the file in security.allowed_paths" : "level #{allowed.last}"
        where = @locked.nil? ? 'option security' : "option security when starting, as it cannot be changed #{@locked}"
        raise BadArgument, "@#{handler}: extended value is disabled by security level #{level}: use #{needed} (#{where}), or give the value itself"
      end

      # At level `medium`, the real path is checked, so that neither `..` nor a symbolic link leads outside of allowed paths.
      # A missing file gets the same error as a file outside allowed paths: no information on other files.
      # @param path [String] Path of a file to read
      # @return [String] Path to read
      # @raise [BadArgument] If reading the file is refused at current level
      def readable_path(path)
        path = File.expand_path(path)
        case level
        when :low then path
        when :medium
          real_path = File.realpath(path) rescue nil
          Aspera.assert(!real_path.nil? && @allowed_paths.any? { |allowed| real_path.eql?(allowed) || real_path.start_with?(File.join(allowed, '')) }, type: BadArgument) do
            "no such file in security.allowed_paths: #{path}"
          end
          real_path
        else raise BadArgument, "reading files is disabled by security level #{level}"
        end
      end
    end
  end
end
