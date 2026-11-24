# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

module Aspera
  module Cli
    # Exit status of the process, by category of error
    module ExitCode
      SUCCESS     = 0
      ERROR       = 1
      USAGE       = 2
      AUTH        = 3
      NOT_FOUND   = 4
      TRANSFER    = 5
      NETWORK     = 6
      API         = 7
      # 128 + SIGINT, as shells do
      INTERRUPTED = 130
      # For help and documentation
      DESCRIPTIONS = {
        SUCCESS     => 'Success',
        ERROR       => 'Other error',
        USAGE       => 'Command line error: unknown command or option, invalid or missing argument',
        AUTH        => 'Authentication or authorization failure: SSH, HTTP 401 or 403, OAuth grant',
        NOT_FOUND   => 'Resource not found, or several resources match the identifier, HTTP 404',
        TRANSFER    => 'Transfer failure',
        NETWORK     => 'Network or TLS failure: name resolution, connection, timeout, certificate',
        API         => 'Other error returned by a remote API',
        INTERRUPTED => 'Interrupted by user (Ctrl-C)'
      }.freeze
      # OAuth 2.0 error codes of a refused authentication (RFC 6749, RFC 6750)
      OAUTH_AUTH_ERRORS = %w[invalid_client invalid_grant unauthorized_client access_denied invalid_token insufficient_scope].freeze
      private_constant :OAUTH_AUTH_ERRORS
      # Category of errors of the code used by bundles (e.g. domain library), by class, see `add_error`
      @errors = {}

      class << self
        # Add the category of an error class (and its subclasses) raised by code that is not of the CLI, e.g. the domain library used by a bundle.
        # The runner gives such an error its label and exit code, instead of `Other`.
        # @param error_class [Class]   Class of the error
        # @param label       [String]  Label of the error message, e.g. `Transfer`
        # @param code        [Integer] Exit code, one of the constants of this module
        # @return [nil]
        def add_error(error_class, label:, code:)
          raise ArgumentError, "not an error class: #{error_class}" unless error_class.is_a?(Class) && error_class <= StandardError
          raise ArgumentError, "unknown exit code: #{code}" unless DESCRIPTIONS.key?(code)
          @errors[error_class] = {label: label, code: code}.freeze
          nil
        end

        # @param error [Exception] An error
        # @return [Hash, nil] `label` and `code` of the most specific added class of the error (whatever the order of `add_error`), `nil` if none
        def error_category(error)
          error.class.ancestors.each { |klass| return @errors[klass] if @errors.key?(klass) }
          nil
        end

        # @param error [Rest::CallError] Failed API call
        # @return [Integer] Exit code for the HTTP status, or OAuth error
        def for_call_error(error)
          return AUTH if error.data.is_a?(Hash) && OAUTH_AUTH_ERRORS.include?(error.data['error'])
          case error.response&.code
          when '401', '403' then AUTH
          when '404' then NOT_FOUND
          else API
          end
        end
      end
    end

    # CLI base exception
    class Error < StandardError; end

    # Raised by dispatch_from_registry when --help is encountered mid-dispatch.
    # Carries the plugin instance (with #help_path set) so the runner can display
    # context-sensitive help without unwinding through a full rescue chain.
    class HelpRequest < StandardError
      # @return [Plugins::Base]
      attr_reader :plugin

      def initialize(plugin)
        super('help requested')
        @plugin = plugin
      end
    end

    # Raised when an unexpected argument is provided.
    class BadArgument < Error; end

    class MissingArgument < Error; end

    class NoSuchElement < Error; end

    # Raised when the condition of option `poll` (`until`) is not met after the last run.
    class PollConditionNotMet < Error; end

    # Raised when a lookup for a specific entity fails to return exactly one result.
    #
    # Provides a formatted message indicating whether the entity was missing
    # or if multiple matches were found (ambiguity).
    class BadIdentifier < Error
      # @param res_type [String] The type of entity being looked up (e.g., 'user').
      # @param res_id   [String] The value of the identifier that failed.
      # @param field    [String] The name of the field used for lookup (defaults to 'identifier').
      # @param count    [Integer] The number of matches found (0 for not found, >1 for ambiguous).
      def initialize(res_type, res_id, field: 'identifier', count: 0)
        msg = count.eql?(0) ? 'not found' : "found #{count}"
        super("#{res_type} with #{field}=#{res_id}: #{msg}")
      end
    end
  end
end
