# frozen_string_literal: true

require 'singleton'

module Aspera
  module Rest
    # Global settings for Rest::Client
    # For example to remove certificate verification globally:
    # `Parameters.instance.session_cb = lambda{|http|http.verify_mode=OpenSSL::SSL::VERIFY_NONE}`
    #
    # @!method self.instance
    #   Returns the singleton instance of Parameters
    #   @return [Parameters] the singleton instance
    class Parameters
      include Singleton

      # @return [String] HTTP request header: `User-Agent`
      attr_accessor :user_agent
      # @return [String] Suffix of file being downloaded, removed when download is complete
      attr_accessor :download_partial_suffix
      # @return [Boolean] Retry on any error (network or HTTP)
      attr_accessor :retry_on_error
      # @return [Boolean] Retry on connection timeout
      attr_accessor :retry_on_timeout
      # @return [Boolean] Retry on HTTP code 503 (service unavailable)
      attr_accessor :retry_on_unavailable
      # @return [Integer] Maximum number of retries on error (first call not included)
      attr_accessor :retry_max
      # @return [Integer] Seconds to wait before retry
      attr_accessor :retry_sleep
      # @return [Proc, nil] Called on new HTTP session, with the `Net::HTTP` as argument, e.g. to set timeouts or certificate verification
      attr_accessor :session_cb
      # @return [Object, nil] Progress bar, receives `event` calls during download
      attr_accessor :progress_bar
      # @return [Proc, nil] Called with `(title = nil, action: :spin)` to display progress of long operations
      attr_accessor :spinner_cb

      private

      # Set default values
      def initialize
        @user_agent = 'RubyAsperaRest'
        @download_partial_suffix = '.http_partial'
        @retry_on_error = false
        @retry_on_timeout = true
        @retry_on_unavailable = true
        @retry_max = 1
        @retry_sleep = 4
        @session_cb = nil
        @progress_bar = nil
        @spinner_cb = nil
      end
    end
  end
end
