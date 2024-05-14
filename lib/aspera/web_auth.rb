# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'stringio'

module Aspera
  # servlet called on callback: it records the callback request
  class WebAuthServlet < WEBrick::HTTPServlet::AbstractServlet
    # @param server [WEBrick::HTTPServer]
    # @param web_auth [WebAuth]
    def initialize(server, web_auth)
      Log.log.debug('WebAuthServlet initialize')
      super(server)
      @web_auth = web_auth
    end

    def service(request, response)
      Log.log.debug{"received request from browser #{request.request_method} #{request.path}"}
      raise WEBrick::HTTPStatus::MethodNotAllowed, "unexpected method: #{request.request_method}" unless request.request_method.eql?('GET')
      raise WEBrick::HTTPStatus::NotFound, "unexpected path: #{request.path}" unless request.path.eql?(@web_auth.expected_path)
      # acquire lock and signal change
      @web_auth.mutex.synchronize do
        @web_auth.query = request.query
        @web_auth.cond.signal
      end
      response.status = 200
      response.content_type = 'text/html'
      response.body = '<html><head><title>Ok</title></head><body><h1>Thank you !</h1><p>You can close this window.</p></body></html>'
      return nil
    end
  end

  # start a local web server, then start a browser that will callback the local server upon authentication
  class WebAuth < WebServerSimple
    attr_reader :expected_path, :mutex, :cond
    attr_writer :query

    # @param endpoint_url [String] e.g. 'https://127.0.0.1:12345'
    def initialize(endpoint_url)
      uri = URI.parse(endpoint_url)
      super(uri)
      # parameters for servlet
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @expected_path = uri.path.empty? ? '/' : uri.path
      @query = nil
      # last argument (self) is provided to constructor of servlet
      mount(@expected_path, WebAuthServlet, self)
      Thread.new { start }
    end

    # wait for request on web server
    # @return Hash the query
    def received_request
      # wait for signal from thread
      @mutex.synchronize{@cond.wait(@mutex)}
      # tell server thread to stop
      shutdown
      return @query
    end
  end
end
