# frozen_string_literal: true

require_relative '../web_server_simple'
require_relative '../servlet_helpers'
require_relative '../web_page'
require_relative 'blob'
require_relative '../assert'
require 'json'
require 'securerandom'

module Aspera
  module WebAuth
    # servlet called on callback: it records the callback request
    class Servlet < WEBrick::HTTPServlet::AbstractServlet
      include ServletHelpers

      # ERB template of page displayed in browser after authentication
      HTML_TEMPLATE_PATH = File.join(__dir__, 'index.html.erb')
      # ERB template of page displayed in browser after authentication, when the reply is given to the user to paste in a terminal
      REPLY_TEMPLATE_PATH = File.join(__dir__, 'reply.html.erb')
      # Policy of the reply page: it has a secret. Only its own script (with nonce) and style, nothing external
      REPLY_CSP = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'nonce-%<nonce>s'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      private_constant :HTML_TEMPLATE_PATH, :REPLY_TEMPLATE_PATH, :REPLY_CSP

      # @param server [WEBrick::HTTPServer] the HTTP server instance
      # @param web_auth [Server] the Server instance to record the callback
      def initialize(server, web_auth)
        Log.log.debug('Servlet initialize')
        super(server)
        @web_auth = web_auth
      end

      # called on request

      def service(request, response)
        Log.log.debug { "received request from browser #{request.request_method} #{request.path}" }
        # Refuse requests of other web pages
        check_request(request)
        Aspera.assert_values(request.request_method, ['GET'], type: WEBrick::HTTPStatus::MethodNotAllowed) { "Unsupported method: #{request.request_method}" }
        Aspera.assert_values(request.path, [@web_auth.expected_path], type: WEBrick::HTTPStatus::NotFound) { "Unsupported path: #{request.path}" }
        # response to browser
        response.status = 200
        if @web_auth.reply_keys.nil?
          WebPage.secure_headers(response)
          response.body = WebPage.render(HTML_TEMPLATE_PATH, title: 'Authentication Complete', additional_info: @web_auth.additional_info)
        else
          render_reply(request, response)
        end
        # continue internal processing
        @web_auth.signal_request(request)
        nil
      end

      private

      # Page that gives the reply to the user: the code to paste in the terminal of the remote ascli
      def render_reply(request, response)
        nonce = SecureRandom.base64(16)
        WebPage.secure_headers(response, content_security_policy: format(REPLY_CSP, nonce: nonce))
        code = Blob.encode(:reply, request.query.slice(*@web_auth.reply_keys).transform_values(&:to_s))
        response.body = WebPage.render(REPLY_TEMPLATE_PATH, title: 'Login Complete', additional_info: @web_auth.additional_info, code: code, nonce: nonce)
      end
    end

    # start a local web server
    # then start a browser that will callback the local server upon authentication
    # store the final query
    class Server < WebServerSimple
      # @return [Array<String>, nil] Keys of the query that the page gives to the user as a code to paste in a terminal, `nil` for the standard page
      attr_reader :additional_info, :expected_path, :reply_keys

      # @param endpoint_url    [String] e.g. 'https://127.0.0.1:12345'
      # @param additional_info [String] Information in web page
      # @param reply_keys      [Array<String>, nil] If set, the page shows to the user a code with these keys of the query, to paste in the terminal of `ascli` that waits for it
      def initialize(endpoint_url, additional_info = nil, reply_keys: nil)
        uri = URI.parse(endpoint_url)
        super(uri)
        @reply_keys = reply_keys
        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @expected_path = uri.path.empty? ? '/' : uri.path
        @query = nil
        @additional_info = additional_info
        # last argument (self) is provided to constructor of servlet
        mount(@expected_path, Servlet, self)
        # server runs in thread
        @thread = Thread.new { start }
      end

      # Wait until the server thread has ended: the response of the last request (page shown to the user) is sent.
      # To call after `received_request`, when the process does not continue with a long operation.
      # @param timeout [Integer] Maximum time to wait, in seconds
      # @return [nil]
      def wait_stopped(timeout = 10)
        @thread.join(timeout)
        nil
      end

      # Called by web server thread on received request
      # @return [nil]
      def signal_request(request)
        raise WEBrick::HTTPStatus::NotFound, "unexpected path: #{request.path}" unless request.path.eql?(@expected_path)
        # acquire lock and signal change
        @mutex.synchronize do
          @query = request.query
          @cond.signal
        end
        nil
      end

      # wait for request on web server (main thread)
      # @return [Hash] the query
      def received_request
        # wait for signal from thread, unless the request was already received (signal is not memorized)
        @mutex.synchronize { @cond.wait(@mutex) while @query.nil? }
        # tell server thread to stop
        shutdown
        return @query
      end
    end
  end
end
