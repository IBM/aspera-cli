# frozen_string_literal: true

require 'aspera/web_server_simple'

module Aspera
  # servlet called on callback: it records the callback request
  class WebAuthServlet < WEBrick::HTTPServlet::AbstractServlet
    # @param server [WEBrick::HTTPServer]
    # @param web_auth [WebAuth]
    def initialize(server, web_auth, additionnal_info)
      Log.log.debug('WebAuthServlet initialize')
      super(server)
      @web_auth = web_auth
      @additionnal_info = additionnal_info
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
      response.body = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Close Now</title>
          <style>
            body {
              font-family: Arial, sans-serif;
              text-align: center;
              padding: 2rem;
              margin: 0;
              background: linear-gradient(135deg, #f0f4f8, #d9e2ec);
              color: #333;
              overflow: hidden; /* Ensure no scrollbars for the background animation */
              position: relative;
            }
            h1 {
              font-size: 2.5rem;
              color: #0078d4;
            }
            p {
              font-size: 1.2rem;
              margin-top: 1rem;
            }

            /* Styling for animated bubbles */
            .bubble {
              position: absolute;
              bottom: -100px;
              width: 20px;
              height: 20px;
              background: rgba(0, 120, 212, 0.4);
              border-radius: 50%;
              animation: rise 10s infinite ease-in-out;
            }

            .bubble:nth-child(odd) {
              background: rgba(0, 120, 212, 0.6);
              animation-duration: 8s;
            }

            .bubble:nth-child(even) {
              background: rgba(0, 120, 212, 0.8);
              animation-duration: 12s;
            }

            @keyframes rise {
              0% {
                transform: translateY(0) scale(1);
                opacity: 1;
              }
              50% {
                opacity: 0.7;
              }
              100% {
                transform: translateY(-120vh) scale(0.7);
                opacity: 0;
              }
            }
          </style>
        </head>
        <body>
          <h1>Thank You!</h1>
          <p>You can close this window.</p>
          <p>#{@additionnal_info}</p>

          <!-- JavaScript to generate bubbles -->
          <script>
            // Function to create bubbles dynamically
            function createBubbles() {
              const body = document.body;
              for (let i = 0; i < 20; i++) {
                const bubble = document.createElement('div');
                bubble.className = 'bubble';
                const size = Math.random() * 40 + 10; // Random size between 10px and 50px
                bubble.style.width = `${size}px`;
                bubble.style.height = `${size}px`;
                bubble.style.left = `${Math.random() * 100}vw`;
                bubble.style.animationDelay = `${Math.random() * 5}s`;
                body.appendChild(bubble);
              }
            }

            // Call the function to create bubbles on load
            createBubbles();
          </script>
        </body>
        </html>
      HTML

      return nil
    end
  end

  # start a local web server, then start a browser that will callback the local server upon authentication
  class WebAuth < WebServerSimple
    attr_reader :expected_path, :mutex, :cond
    attr_writer :query

    # @param endpoint_url [String] e.g. 'https://127.0.0.1:12345'
    def initialize(endpoint_url, additionnal_info = nil)
      uri = URI.parse(endpoint_url)
      super(uri)
      # parameters for servlet
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @expected_path = uri.path.empty? ? '/' : uri.path
      @query = nil
      # last argument (self) is provided to constructor of servlet
      mount(@expected_path, WebAuthServlet, self, additionnal_info)
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
