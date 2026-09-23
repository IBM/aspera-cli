# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'aspera/assert'
require 'erb'

module Aspera
  # servlet called on callback: it records the callback request
  class WebAuthServlet < WEBrick::HTTPServlet::AbstractServlet
    # @param server   [WEBrick::HTTPServer] the HTTP server instance
    # @param web_auth [WebAuth]             the WebAuth instance to record the callback
    def initialize(server, web_auth)
      Log.log.debug('WebAuthServlet initialize')
      super(server)
      @web_auth = web_auth
    end

    def service(request, response)
      Log.log.debug { "received request from browser #{request.request_method} #{request.path}" }
      Aspera.assert_values(request.request_method, ['GET'], type: WEBrick::HTTPStatus::MethodNotAllowed) { 'HTTP verb' }
      additional_info = @web_auth.signal_request(request)
      response.status = 200
      response.content_type = 'text/html'
      response.body = File.read(__FILE__+".html")
      nil
    end
  end

  # start a local web server
  # then start a browser that will callback the local server upon authentication
  # store the final query
  class WebAuth < WebServerSimple
    # @param endpoint_url     [String] e.g. 'https://127.0.0.1:12345'
    # @param additional_info [String] Information in web page
    def initialize(endpoint_url, additional_info = nil)
      uri = URI.parse(endpoint_url)
      super(uri)
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @expected_path = uri.path.empty? ? '/' : uri.path
      @query = nil
      @additional_info = additional_info
      # last argument (self) is provided to constructor of servlet
      mount(@expected_path, WebAuthServlet, self)
      # server runs in thread
      Thread.new { start }
    end

    # Called by web server thread on received request
    # @return [String] additional information for web page
    def signal_request(request)
      raise WEBrick::HTTPStatus::NotFound, "unexpected path: #{request.path}" unless request.path.eql?(@expected_path)
      # acquire lock and signal change
      @mutex.synchronize do
        @query = request.query
        @cond.signal
      end
      return @additional_info
    end

    # wait for request on web server (main thread)
    # @return [Hash] the query
    def received_request
      # wait for signal from thread
      @mutex.synchronize { @cond.wait(@mutex) }
      # tell server thread to stop
      shutdown
      return @query
    end
  end
end
