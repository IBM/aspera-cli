# frozen_string_literal: true

require 'uri'
require 'aspera/assert'
require 'aspera/log'
require 'aspera/cli/prompt'
require 'aspera/cli/info'
require 'aspera/web_auth/blob'

module Aspera
  module WebAuth
    # Receives the result of a web login from the user, who gives it in the terminal.
    # No server is started: used when the browser cannot reach the loopback address of this host (e.g. SSH session, without tunnel).
    # The user gives either:
    # - a code (`Blob`) shown by the browser of the workstation, after `ascli config web_login <code>` (`ascli` is installed there)
    # - the URL the browser was redirected to (it shows a connection error), or its query
    # Same interface as `Server` for the part used by OAuth clients: `received_request`.
    class Paste
      class << self
        # Extract the query parameters from what the user pasted
        # @param input [String] Code, or full redirect URL, or the query only (with or without leading `?`)
        # @return [Hash{String=>String}] Query parameters, includes a non-empty `state`
        # @raise [ParameterError] if the input has no query, or no `state`
        def parse(input)
          text = input.to_s.strip
          raise ParameterError, 'Nothing was pasted' if text.empty?
          params =
            if Blob.code?(text)
              type, data = Blob.decode(text)
              raise ParameterError, 'This code is for ascli on the workstation: paste the code shown by the browser after login' unless type.eql?(:reply)
              data
            else
              parse_query(text)
            end
          raise ParameterError, 'No "state" found in what was pasted' if params['state'].to_s.empty?
          params
        end

        private

        # @param text [String] Full redirect URL, or query
        # @return [Hash{String=>String}]
        def parse_query(text)
          # fragment is not sent to a server, ignore it
          text = text.sub(/#.*\z/m, '')
          query =
            if text.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
              URI.parse(text).query.to_s
            else
              text.delete_prefix('?')
            end
          raise ParameterError, 'No query found in pasted URL: copy the full URL from the address bar of the browser' if query.empty?
          URI.decode_www_form(query).to_h
        rescue URI::InvalidURIError, ArgumentError => e
          raise ParameterError, "Pasted text is not a valid code, URL or query: #{e.message}"
        end
      end

      # @param redirect_uri [String]        Loopback URL registered for the login (the browser fails to connect to it)
      # @param login_url    [String, nil]   URL of the login page: if set, a code is given to the user for `ascli` on the workstation
      # @param reply_keys   [Array, nil]    Keys of the query needed to continue (with `login_url`)
      def initialize(redirect_uri, login_url: nil, reply_keys: nil)
        @redirect_uri = redirect_uri
        @login_url = login_url
        @reply_keys = reply_keys
      end

      # Ask the user for the code, or the URL the browser was redirected to
      # Input is not echoed on a terminal: it contains an authorization code or tokens.
      # @return [Hash{String=>String}] The query
      def received_request
        Log.log.warn do
          url_step = "copy the full URL from the address bar of the browser (it shows a connection error on #{@redirect_uri}: this is expected)"
          if @login_url.nil?
            "USER ACTION: log in with the web browser, then #{url_step}, and paste it here."
          else
            code = Blob.encode(:login, {'login_url' => @login_url.to_s, 'redirect_uri' => @redirect_uri, 'reply_keys' => @reply_keys})
            [
              'USER ACTION: log in with the web browser, then paste the result here. Two ways:',
              "  1. Log in with the URL above, then #{url_step}.",
              "  2. If #{Cli::Info::CMD_NAME} is installed on the workstation that has the browser, instead run there:",
              "       #{Cli::Info::CMD_NAME} config web_login #{code}",
              '     log in in the page it opens, then copy the code shown by the browser.'
            ].join("\n")
          end
        end
        self.class.parse(Cli::Prompt.prompt_user_input('Code or URL', sensitive: true))
      end
    end
  end
end
