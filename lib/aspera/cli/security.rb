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
      # Levels that allow processing a secret (e.g. by an extended value): the result could reveal it, as only declared values are hidden
      SECRET_PROCESSING_LEVELS = %i[low].freeze
      private_constant :EXTENDED_VALUE_LEVELS, :SECRET_PROCESSING_LEVELS

      def initialize
        reset
      end

      # Back to default: level `low`, no allowed path, not locked
      # @return [nil]
      def reset
        @level = nil
        @default_level = LEVELS.first
        @allowed_paths = []
        @writable_paths = []
        @locked = nil
      end

      # @return [Symbol] Level set by option `security`, else default level
      def level = @level || @default_level

      # Set by option `security`.
      # When locked, the value can only be set again to the current one.
      # @param value [Hash] `level`, `allowed_paths` and `writable_paths`, see schema `SecurityOptions`
      # @return [nil]
      def options=(value)
        Aspera.assert_type(value, Hash, type: BadArgument) { 'security' }
        # When locked, each command starts with the empty value of a Hash option: not a change
        return if @locked && value.empty?
        value = value.transform_keys(&:to_sym)
        new_level = value[:level]&.to_sym
        Aspera.assert_values(new_level, LEVELS, type: BadArgument) { 'security.level' } unless new_level.nil?
        new_paths = existing_real_paths(value[:allowed_paths], 'allowed_paths')
        new_writable_paths = existing_real_paths(value[:writable_paths], 'writable_paths')
        if @locked
          Aspera.assert((new_level || @default_level).eql?(level) && new_paths.eql?(@allowed_paths) && new_writable_paths.eql?(@writable_paths), type: BadArgument) do
            "security cannot be changed #{@locked}"
          end
          return
        end
        @level = new_level
        @allowed_paths = new_paths
        @writable_paths = new_writable_paths
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

      # @param max_level [Symbol, nil] `security:` attribute of an option or command: most restrictive level that allows it, `nil` for any level
      # @return [Boolean] `true` if the feature is available at current level
      def allowed?(max_level)
        max_level.nil? || LEVELS.index(level) <= LEVELS.index(max_level)
      end

      # Features that execute code (own or downloaded), or load code, declare `security: :low`.
      # @param max_level [Symbol, nil] `security:` attribute of an option or command
      # @param what      [String] Feature, e.g. `option notify_template`
      # @raise [BadArgument] If the feature is refused at current level
      def check_level(max_level, what)
        return if allowed?(max_level)
        raise BadArgument, "#{what}: disabled by security level #{level}: use level #{max_level} (#{where_to_set})"
      end

      # A value stored to be used later (e.g. in a preset) is evaluated when used, maybe at another level (e.g. `low` on the command line).
      # So it must not use an extended value that is refused at current level, e.g. `@val:@ruby:...`.
      # @param value [Object] Value to store (`Hash`, `Array`, `String`)
      # @param what  [String] What stores the value, e.g. `preset option ts`
      # @raise [BadArgument] If the value contains an extended value refused at current level
      def check_stored_value(value, what)
        case value
        when Hash then value.each { |k, v| [k, v].each { |item| check_stored_value(item, what) } }
        when Array then value.each { |v| check_stored_value(v, what) }
        when String
          EXTENDED_VALUE_LEVELS.each do |handler, levels|
            next if levels.include?(level) || !value.include?("@#{handler}:")
            raise BadArgument, "#{what}: cannot store @#{handler}: extended value, disabled by security level #{level} (#{where_to_set})"
          end
        end
        nil
      end

      # @param handler [Symbol] Extended-value handler
      # @raise [BadArgument] If the handler is refused at current level, with the level that allows it and where to set it
      def check_extended_value(handler)
        allowed = EXTENDED_VALUE_LEVELS[handler]
        return if allowed.nil? || allowed.include?(level)
        # the least permissive level that allows it
        needed = handler.eql?(:file) ? "level #{allowed.last} with the file in security.allowed_paths" : "level #{allowed.last}"
        raise BadArgument, "@#{handler}: extended value is disabled by security level #{level}: use #{needed} (#{where_to_set}), or give the value itself"
      end

      # A secret (e.g. read by `@vault:`, `@secret:`, `@preset:`) is hidden in results only as declared: the result of processing it
      # could reveal it (e.g. split by `@list:`, in an error message of `@json:`, short value in a text by `@extend:`, converted as name of parameter).
      # @param what [String] What processes the value, e.g. `@list`
      # @param hint [String] What to do instead
      # @yieldreturn [Boolean] `true` if the value contains a secret, evaluated only if the level refuses it
      # @raise [BadArgument] If the value contains a secret and processing it is refused at current level
      def check_secret_processing(what, hint: 'give the secret as the whole value')
        return if SECRET_PROCESSING_LEVELS.include?(level) || !yield
        raise BadArgument, "#{what}: cannot process a secret at security level #{level}, as the result could reveal it: #{hint}, or use level low (#{where_to_set})"
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

      # Writing a file where the client chooses (e.g. downloaded file) could replace a file that is used later (e.g. plugin, shell startup file).
      # At level `medium` and `high`, files can be written only in `writable_paths` (none by default): the real path of the folder is checked,
      # so that neither `..` nor a symbolic link leads outside of them.
      # @param path [String] Path of a file or folder to write, that may not exist yet
      # @return [String] Path to write
      # @raise [BadArgument] If writing is refused at current level
      def writable_path(path)
        path = File.expand_path(path)
        return path if level.eql?(:low)
        # The first existing parent gives the real path, the missing part contains no link
        existing = path
        missing = []
        until File.exist?(existing) || File.dirname(existing).eql?(existing)
          missing.unshift(File.basename(existing))
          existing = File.dirname(existing)
        end
        real_path = File.join(File.realpath(existing), *missing)
        Aspera.assert(@writable_paths.any? { |allowed| real_path.eql?(allowed) || real_path.start_with?(File.join(allowed, '')) }, type: BadArgument) do
          "writing is refused by security level #{level}: not in security.writable_paths: #{path} (#{where_to_set})"
        end
        real_path
      end

      private

      # @param paths [Array<String>, nil] Paths given to option `security`
      # @param key   [String] Name of key, for error messages
      # @return [Array<String>] Real paths
      def existing_real_paths(paths, key)
        Array(paths).map do |path|
          path = File.expand_path(path)
          Aspera.assert(File.exist?(path), type: BadArgument) { "security.#{key}: no such file or folder: #{path}" }
          File.realpath(path)
        end
      end

      # @return [String] Where to set the level, for error messages
      def where_to_set
        @locked.nil? ? 'option security' : "option security when starting, as it cannot be changed #{@locked}"
      end
    end
  end
end
