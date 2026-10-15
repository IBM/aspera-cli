# frozen_string_literal: true

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

      class << self
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
