# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../assert'
require_relative 'error'
require 'singleton'

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
      # `zlib`: a small value can decompress to gigabytes (decompression bomb), a limit on its size would not limit the number of values
      EXTENDED_VALUE_LEVELS = {
        ruby: %i[low],
        uri:  %i[low],
        env:  %i[low],
        zlib: %i[low],
        file: %i[low medium]
      }.freeze
      # Levels that allow processing a secret (e.g. by an extended value): the result could reveal it, as only declared values are hidden
      SECRET_PROCESSING_LEVELS = %i[low].freeze
      # Sources (`Option::Source`) of an option value set by the one who starts the process (environment, defaults, the program itself), not by a client.
      # A value from a preset is not one of them: a preset can also be given by the client (e.g. `--preset=@json:...`), see #add_configured.
      OPERATOR_SOURCES = %i[default code env].freeze
      # Keys of a `Hash` option (e.g. parameters of agent `node` in option `transfer`) that hold a secret sent to its key `url`
      CREDENTIAL_KEYS = %w[password client_secret private_key passphrase api_key].freeze
      # Keys of a transfer spec that hold a credential for its `remote_host`
      TRANSFER_CREDENTIAL_KEYS = %w[remote_password token ssh_private_key ssh_private_key_passphrase].freeze
      private_constant :EXTENDED_VALUE_LEVELS, :SECRET_PROCESSING_LEVELS, :OPERATOR_SOURCES, :CREDENTIAL_KEYS, :TRANSFER_CREDENTIAL_KEYS

      def initialize
        reset
      end

      # Back to default: level `low`, no allowed path, not locked, no value read from the configuration
      # @return [nil]
      def reset
        @level = nil
        @default_level = LEVELS.first
        @allowed_paths = []
        @writable_paths = []
        @locked = nil
        @configured_values = Set.new
        nil
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

      # Declare values of the configuration of the server: read from a preset (by its name) or the vault, or set in the environment of the process.
      # The provenance of a value is known by the value itself, whatever the way it is referenced (`--preset=<name>`, `@preset:`, `@vault:`, in a preset),
      # so that #check_credential_host knows that a secret is the one of the server, and that a URL is one of its configuration.
      # @param value [Object] Value read: a `String`, or a `Hash` or `Array` of values
      # @return [Object] The value
      def add_configured(value)
        case value
        when Hash then value.each_value { |v| add_configured(v) }
        when Array then value.each { |v| add_configured(v) }
        when String then @configured_values.add(value)
        end
        value
      end

      # @param value [Object] Value of an option
      # @return [Boolean] `true` if the value was read from the configuration, see #add_configured
      def configured?(value)
        value.is_a?(String) && @configured_values.include?(value)
      end

      # A secret of the server must not be sent to a host (option `url`) chosen by a client, so that a client cannot redirect the saved credentials of the server
      # to a host it controls: at levels `medium` and `high`, a secret of the server can be sent only to a URL of its configuration.
      # A secret is the one of the server when it is read from the configuration (preset, vault), whatever the way it is referenced (e.g. `@preset:<name>.password`),
      # or when it comes from an operator source (environment). Same for the URL.
      # The configuration cannot be changed by a client at these levels (commands that write presets and the vault are refused), so its URLs are the ones of the operator.
      # A secret of the server sent to the URL of another of its presets is not refused.
      # @param what          [String]      For the error message, e.g. `option password`
      # @param secret        [Object]      Value of the secret option
      # @param secret_source [Symbol, nil] Source of the secret option value (`Option::Source`)
      # @param url           [String, nil] Value of option `url`
      # @param url_source    [Symbol, nil] Source of option `url`
      # @raise [BadArgument] If, at level `medium` or `high`, the secret is the one of the server, and the URL is not one of its configuration
      def check_credential_host(what:, secret:, secret_source:, url:, url_source:)
        return if level.eql?(:low) || url.nil?
        # The secret is not the one of the server: the client's own
        return unless configured?(secret) || OPERATOR_SOURCES.include?(secret_source)
        return if configured?(url) || OPERATOR_SOURCES.include?(url_source)
        raise BadArgument, "#{what}: a secret of the configuration cannot be sent to a URL that is not in the configuration at security level #{level}: " \
          "use the preset that has both the URL and the secret, or give the secret itself (#{where_to_set})"
      end

      # Same as #check_credential_host for the keys of a `Hash`, e.g. the parameters of agent `node` in option `transfer`: key `url` and secret keys.
      # The provenance of a key is known only by its value, see #add_configured.
      # @param value [Object] Value of an option, checked if it is a `Hash` with key `url`
      # @param what  [String] For the error message, e.g. `option transfer`
      # @raise [BadArgument] If, at level `medium` or `high`, a secret of the configuration is sent to a URL that is not in the configuration
      def check_credentials_in(value, what:)
        return unless value.is_a?(Hash)
        url = value['url'] || value[:url]
        return unless url.is_a?(String)
        CREDENTIAL_KEYS.each do |key|
          secret = value[key] || value[key.to_sym]
          check_credential_host(what: "#{what}: #{key}", secret: secret, secret_source: nil, url: url, url_source: nil) unless secret.nil?
        end
      end

      # A transfer spec built by a command holds credentials for its `remote_host` (e.g. a token of the application, or the password of a preset):
      # at levels `medium` and `high`, option `ts` cannot send them to another host, unless that host is in the configuration (see #add_configured).
      # Credentials given in option `ts` with the host are the ones of the client.
      # @param transfer_spec      [Hash]        Final transfer spec, option `ts` merged
      # @param user_transfer_spec [Hash]        Option `ts`
      # @param application_host   [String, nil] `remote_host` of the transfer spec of the command, before option `ts`
      # @raise [BadArgument] If, at level `medium` or `high`, option `ts` changes the host of credentials that it does not give
      def check_transfer_host(transfer_spec, user_transfer_spec, application_host:)
        host = user_transfer_spec['remote_host']
        return if level.eql?(:low) || host.nil? || host.eql?(application_host) || configured?(host)
        credentials = TRANSFER_CREDENTIAL_KEYS.select do |key|
          transfer_spec.key?(key) && (!user_transfer_spec.key?(key) || configured?(user_transfer_spec[key]))
        end
        return if credentials.empty?
        raise BadArgument, "option ts: remote_host: the credentials of the transfer (#{credentials.join(', ')}) cannot be sent to a host that is not in the configuration " \
          "at security level #{level}: use the host of the command, or give the credentials with the host (#{where_to_set})"
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

      # Read a local file chosen by the caller, e.g. `@file:`, or a command that reads a file to display something about it.
      # Not for a file that a command sends (e.g. upload, import of a workflow): not restricted, as transfers.
      # @param path [String] Path of a file to read
      # Other arguments are those of `File.read`, e.g. `binmode: true` for bytes
      # @return [String] Content of the file
      # @raise [BadArgument] If reading the file is refused at current level
      def read_file(path, ...) = File.read(readable_path(path), ...)

      # A file or folder found by a command, e.g. in a folder given by the client, can be outside of allowed paths (symbolic link):
      # the command skips it, instead of failing. Same rules as `readable_path`.
      # @param path [String] Path of a file or folder to read
      # @return [Boolean] `true` if reading it is allowed at current level
      def readable_path?(path)
        readable_path(path)
        true
      rescue BadArgument
        false
      end

      # Writing a file where the client chooses (e.g. downloaded file) could replace a file that is used later (e.g. plugin, shell startup file).
      # At level `medium` and `high`, files can be written only in `writable_paths` (none by default): the real path of the folder is checked,
      # so that neither `..` nor a symbolic link leads outside of them.
      # @param path [String] Local path of a file or folder to write, that may not exist yet
      #   (not called for a transfer agent that writes on a remote system, see `Agent::Base#local_destination?`)
      # @return [String] Path to write: unchanged at level `low` (no restriction), else the real path
      # @raise [BadArgument] If writing is refused at current level
      def writable_path(path)
        return path if level.eql?(:low)
        path = File.expand_path(path)
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
