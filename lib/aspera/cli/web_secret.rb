# frozen_string_literal: true

# cspell:ignore urlsafe

require 'aspera/log'
require 'aspera/assert'
require 'aspera/environment'
require 'aspera/web_page'
require 'aspera/servlet_helpers'
require 'aspera/cli/error'
require 'aspera/cli/info'
require 'openssl'
require 'securerandom'

module Aspera
  module Cli
    # Secrets entered by the user on a web page, instead of the terminal.
    # Used by extended value `@secret:` when option `ui` is `graphical`, and in MCP server mode (see Mcp::Secrets).
    #
    # Requests are kept in memory, identified by a random value in the URL of the page, and expire after TTL seconds.
    # Pages are served by a local web server, started on first request, or by the web server of the caller (see #handle).
    class WebSecret
      # Lifetime of a request in seconds: the user shall enter the secret within this time
      TTL = 600
      # Path of the page, followed by the request identifier
      PATH_PREFIX = '/secret/'
      # Interval in seconds between calls to the block while waiting for the user
      WAIT_SLICE = 10
      # Address of the local web server
      LOCAL_ADDRESS = '127.0.0.1'
      # Maximum time in seconds to wait for the local web server to send the last page on shutdown
      SHUTDOWN_TIMEOUT = 5
      # ERB template of the page
      HTML_TEMPLATE_PATH = File.join(__dir__, 'web_secret.html.erb')
      # A request for a secret, status is one of: :pending, :received, :cancelled
      Request = Struct.new(:prompt, :status, :value, :expires_at, keyword_init: true)
      private_constant :WAIT_SLICE, :LOCAL_ADDRESS, :SHUTDOWN_TIMEOUT, :HTML_TEMPLATE_PATH, :Request

      class << self
        # Ask for a secret on a web page, opened in the browser
        # @param prompt [String] Name of the secret
        # @return [String] The secret
        def ask(prompt)
          web_secret = new
          id = web_secret.create(prompt)
          Environment.instance.open_uri(web_secret.url(id))
          web_secret.wait_value(id)
        ensure
          web_secret&.shutdown
        end
      end

      # @param base_url    [String, nil] URL of the web server serving the pages (see #handle), `nil` to start a local web server on first request
      # @param access_code [String, nil] If set, the user must also enter it on the page
      # @param name        [String]      Name of the application needing the secret, shown on the page
      # @param requester   [String, nil] Who requested the command, shown on the page, e.g. `AI assistant`, `nil` for the user on terminal
      def initialize(base_url: nil, access_code: nil, name: Info::CMD_NAME, requester: nil)
        Aspera.assert(access_code.nil? || !access_code.to_s.empty?) { 'access_code must not be empty' }
        @base_url     = base_url
        @access_code  = access_code&.to_s
        @name         = name
        @requester    = requester
        @mutex        = Mutex.new
        @cond         = ConditionVariable.new
        # id => Request
        @requests     = {}
        @local_server = nil
        @local_thread = nil
      end

      # @param prompt [String] Name of the secret, shown to the user
      # @return [String] Identifier of the new request
      def create(prompt)
        id = SecureRandom.urlsafe_base64(24)
        @mutex.synchronize do
          purge_expired
          @requests[id] = Request.new(prompt: prompt, status: :pending, expires_at: Time.now + TTL)
        end
        id
      end

      # @param id [String] Identifier of the request
      # @return [String] URL of the page where the user enters the secret
      def url(id)
        "#{base_url}#{PATH_PREFIX}#{id}"
      end

      # @param id [String] Identifier of the request
      # @return [String, nil] Prompt of the request, `nil` if unknown or expired
      def prompt(id)
        @mutex.synchronize { live_request(id)&.prompt }
      end

      # Wait until the user enters the secret, or cancels, on the page
      # @param id [String] Identifier of the request
      # @yield [elapsed] Called periodically while waiting, with elapsed seconds
      # @return [String] The secret
      # @raise [Cli::Error] if the request is unknown, expired, or cancelled by the user
      def wait_value(id)
        start = Time.now
        loop do
          @mutex.synchronize do
            request = live_request(id)
            raise Error, 'Secret request expired: execute the command again' if request.nil?
            raise Error, 'Secret entry cancelled by user' if request.status.eql?(:cancelled)
            return request.value if request.status.eql?(:received)
            @cond.wait(@mutex, (request.expires_at - Time.now).clamp(0, WAIT_SLICE))
          end
          yield(Time.now - start) if block_given?
        end
      end

      # Forget requests, and their secrets
      # @param ids [Array<String>] Identifiers of requests
      def delete(ids)
        @mutex.synchronize { ids.each { |id| @requests.delete(id) } }
      end

      # Stop the local web server, if started, after it sends the last page to the browser
      def shutdown
        return if @local_server.nil?
        @local_server.shutdown
        @local_thread.join(SHUTDOWN_TIMEOUT)
      end

      # Serve the page: GET shows the form, POST receives the secret or the cancellation
      # @param req [WEBrick::HTTPRequest]
      # @param res [WEBrick::HTTPResponse]
      def handle(req, res)
        require 'webrick'
        id = req.path.delete_prefix(PATH_PREFIX)
        status, page = @mutex.synchronize do
          request = live_request(id)
          if request.nil? || !request.status.eql?(:pending)
            [404, {state: :unknown}]
          elsif req.request_method.eql?('GET')
            [200, {state: :form, prompt: request.prompt}]
          elsif req.request_method.eql?('POST')
            answer(request, WEBrick::HTTPUtils.parse_query(req.body.to_s))
          else
            [405, {state: :unknown}]
          end
        end
        res.status = status
        WebPage.secure_headers(res)
        # Variables of the template, state is one of: :form, :received, :cancelled, :unknown
        res.body = WebPage.render(
          HTML_TEMPLATE_PATH,
          title:                'Secret request',
          name:                 @name,
          requester:            @requester,
          action_url:           "#{PATH_PREFIX}#{id}",
          access_code_required: !@access_code.nil?,
          prompt:               nil,
          error:                nil,
          **page
        )
      end

      private

      # Record the answer of the user, called with the mutex locked
      # @param request [Request] The pending request
      # @param params  [Hash]    Fields of the form
      # @return [Array] HTTP status and attributes of the page
      def answer(request, params)
        if params['decision'].eql?('cancel')
          request.status = :cancelled
        elsif @access_code && !OpenSSL.secure_compare(params['access_code'].to_s, @access_code)
          Log.log.warn('Secret page: wrong access code')
          return [401, {state: :form, prompt: request.prompt, error: 'Invalid access code'}]
        else
          # Form data is binary, the page is UTF-8
          request.value = params['secret'].to_s.dup.force_encoding(Encoding::UTF_8)
          request.status = :received
        end
        @cond.broadcast
        [200, {state: request.status}]
      end

      # Called with the mutex locked
      # @return [Request, nil] The request, `nil` if unknown or expired
      def live_request(id)
        request = @requests[id]
        request unless request.nil? || request.expires_at < Time.now
      end

      def purge_expired
        now = Time.now
        @requests.delete_if { |_, request| request.expires_at < now }
      end

      # @return [String] URL of the server, for the browser
      def base_url
        @mutex.synchronize { @base_url ||= start_local_server }
      end

      # Start a local web server for the pages
      # @return [String] URL of the local server
      def start_local_server
        require 'webrick'
        servlet = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
          include ServletHelpers

          # Refuse requests of other web pages, the WebSecret instance is the option of the servlet
          def service(req, res)
            check_request(req)
            @options.first.handle(req, res)
          end
        end
        # Messages of WEBrick are not useful to the user: warnings and errors only.
        # Logs do not go to stdout: in MCP stdio mode, it is the JSON-RPC stream.
        logger = Log.log.dup.tap { |log| log.level = [Log.log.level, ::Logger::WARN].max }
        # Port 0: any free port
        @local_server = WEBrick::HTTPServer.new(BindAddress: LOCAL_ADDRESS, Port: 0, Logger: logger, AccessLog: [])
        @local_server.mount(PATH_PREFIX, servlet, self)
        @local_thread = Thread.new { @local_server.start }
        url = "http://#{LOCAL_ADDRESS}:#{@local_server.config[:Port]}"
        Log.log.debug { "Secret pages served on #{url}" }
        url
      end
    end
  end
end
