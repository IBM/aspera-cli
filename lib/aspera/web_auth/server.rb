# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'aspera/assert'
require 'erb'

module Aspera
  module WebAuth
    # servlet called on callback: it records the callback request
    class Servlet < WEBrick::HTTPServlet::AbstractServlet
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
        Aspera.assert_values(request.request_method, ['GET'], type: WEBrick::HTTPStatus::MethodNotAllowed) { "Unsupported method: #{req.request_method}" }
        Aspera.assert_values(request.path, ['/'], type: WEBrick::HTTPStatus::NotFound) { "Unsupported path: #{req.request_method}" }
        # response to browser
        response.status = 200
        response.content_type = 'text/html'
        response.body = File.read("#{__dir__}/index.html").gsub('__ADD_INFO__', @web_auth.info_html)
        # continue internal processing
        @web_auth.signal_request(request)
        nil
      end
    end

    # start a local web server
    # then start a browser that will callback the local server upon authentication
    # store the final query
    class Server < WebServerSimple
      attr_reader :info_html

      # @param endpoint_url    [String] e.g. 'https://127.0.0.1:12345'
      # @param additional_info [String] Information in web page
      def initialize(endpoint_url, additional_info = nil)
        uri = URI.parse(endpoint_url)
        super(uri)
        @mutex = Mutex.new
        @cond = ConditionVariable.new
        @expected_path = uri.path.empty? ? '/' : uri.path
        @query = nil
        @info_html = additional_info.to_s
        @info_html = "<p>#{ERB::Util.html_escape(@info_html)}</p>" unless @info_html.empty?
        # last argument (self) is provided to constructor of servlet
        mount(@expected_path, Servlet, self)
        # server runs in thread
        Thread.new { start }
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
        # wait for signal from thread
        @mutex.synchronize { @cond.wait(@mutex) }
        # tell server thread to stop
        shutdown
        return @query
      end
    end
  end
end
