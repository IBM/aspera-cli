# frozen_string_literal: true

require 'aspera/web_server_simple'
require 'aspera/assert'

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
      Aspera.assert_values(request.request_method, ['GET'], exception_class: WEBrick::HTTPStatus::MethodNotAllowed){'HTTP verb'}
      additionnal_info = @web_auth.signal_request(request)
      response.status = 200
      response.content_type = 'text/html'
      response.body = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="icon" href="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIzMiIgaGVpZ2h0PSIzMiIgdmlld0JveD0iMCAwIDMyIDMyIiBmaWxsPSJub25lIiBzdHJva2U9IiMyMjIiIHN0cm9rZS13aWR0aD0iMyI+CiAgPGxpbmUgeDE9IjMiIHkxPSIzIiB4Mj0iMjkiIHkyPSIyOSIgIHN0cm9rZT0icmVkIi8+CiAgPGxpbmUgeDE9IjI5IiB5MT0iMyIgeDI9IjMiIHkyPSIyOSIgc3Ryb2tlPSJyZWQiIC8+Cjwvc3ZnPg==" type="image/svg+xml">
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

        /* Styling for animated IBM logos */
        .logo {
        position: absolute;
        bottom: -100px;
        width: 40px;
        height: 40px;
        background: none;
        display: flex;
        justify-content: center;
        align-items: center;
        animation: rise 10s infinite ease-in-out;
        }

        .logo svg {
        width: 100%;
        height: 100%;
        }

        .logo:nth-child(odd) {
        animation-duration: 8s;
        }

        .logo:nth-child(even) {
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
        <p>#{additionnal_info}</p>

        <!-- JavaScript to generate IBM logos -->
        <script>
        // Function to create logos dynamically
        function createLogos() {
        const body = document.body;
        const svgContent = `
        <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1000px" height="401.149px" viewBox="0 0 1000 401.149" xml:space="preserve">
        <g>
        <rect fill="#1F70C1" x="0" y="373.217" width="194.433" height="27.833"/>
        <rect fill="#1F70C1" x="0" y="319.83" width="194.433" height="27.931"/>
        <rect fill="#1F70C1" x="55.468" y="266.541" width="83.399" height="27.932"/>
        <rect fill="#1F70C1" x="55.468" y="213.253" width="83.399" height="27.932"/>
        <rect fill="#1F70C1" x="55.468" y="159.964" width="83.399" height="27.932"/>
        <rect fill="#1F70C1" x="55.468" y="106.577" width="83.399" height="27.932"/>
        <rect fill="#1F70C1" x="0" y="53.288" width="194.433" height="27.932"/>
        <rect fill="#1F70C1" x="0" y="0" width="194.433" height="27.932"/>
        <path fill="#1F70C1" d="M222.167,347.761h299.029c5.051-8.617,8.815-18.027,11.094-27.932H222.167V347.761z"/>
        <path fill="#1F70C1" d="M497.92,213.253H277.734v27.932h243.463C514.857,230.487,507.032,221.078,497.92,213.253z"/>
        <path fill="#1F70C1" d="M277.734,159.964v27.932H497.92c9.311-7.825,17.135-17.235,23.277-27.932H277.734z"/>
        <path fill="#1F70C1" d="M521.197,53.288H222.167V81.22H532.29C529.715,71.315,525.951,61.906,521.197,53.288z"/>
        <path fill="#1F70C1" d="M429.279,0H222.167v27.932h278.526C482.072,10.697,456.815,0,429.279,0z"/>
        <rect fill="#1F70C1" x="277.734" y="106.577" width="83.3" height="27.932"/>
        <path fill="#1F70C1" d="M444.433,134.509h87.163c2.476-8.914,3.764-18.324,3.764-27.932h-90.927z"/>
        <rect fill="#1F70C1" x="277.734" y="266.541" width="83.3" height="27.932"/>
        <path fill="#1F70C1" d="M444.433,266.541v27.932h90.927c0-9.608-1.288-19.017-3.764-27.932H444.433z"/>
        <path fill="#1F70C1" d="M222.167,400.852h207.112c27.734,0,52.793-10.697,71.513-27.932H222.167V400.852z"/>
        <rect fill="#1F70C1" x="555.567" y="373.217" width="138.866" height="27.833"/>
        <rect fill="#1F70C1" x="555.567" y="319.83" width="138.866" height="27.931"/>
        <rect fill="#1F70C1" x="611.034" y="266.541" width="83.399" height="27.932"/>
        <rect fill="#1F70C1" x="611.034" y="213.253" width="83.399" height="27.932"/>
        <polygon fill="#1F70C1" points="733.063,53.288 555.567,53.288 555.567,81.22 742.67,81.22"/>
        <polygon fill="#1F70C1" points="714.639,0 555.567,0 555.567,27.932 724.247,27.932"/>
        <rect fill="#1F70C1" x="861.034" y="373.217" width="138.866" height="27.833"/>
        <rect fill="#1F70C1" x="861.034" y="319.83" width="138.866" height="27.931"/>
        <rect fill="#1F70C1" x="861.034" y="266.541" width="83.399" height="27.932"/>
        <rect fill="#1F70C1" x="861.034" y="213.253" width="83.399" height="27.932"/>
        <polygon fill="#1F70C1" points="861.034,187.896 944.433,187.896 944.433,159.964 861.034,159.964 694.433,159.964 611.034,159.964 611.034,187.896 694.433,187.896 852.219,187.896"/>
        <polygon fill="#1F70C1" points="944.433,106.577 803.982,106.577 794.374,134.509 944.433,134.509"/>
        <polygon fill="#1F70C1" points="840.927,0 831.319,27.932 1000,27.932 1000,0"/>
        <polygon fill="#1F70C1" points="777.734,400.852 787.341,373.217 768.126,373.217"/>
        <polygon fill="#1F70C1" points="759.311,347.761 796.157,347.761 806.062,319.83 749.505,319.83"/>
        <polygon fill="#1F70C1" points="740.59,294.473 814.877,294.473 824.683,266.541 730.784,266.541"/>
        <polygon fill="#1F70C1" points="721.969,241.185 833.597,241.185 843.106,213.253 712.361,213.253"/>
        <polygon fill="#1F70C1" points="611.034,134.509 761.093,134.509 751.486,106.577 611.034,106.577"/>
        <polygon fill="#1F70C1" points="812.896,81.22 1000,81.22 1000,53.288 822.405,53.288"/>
        </g>
        </svg>
        `;
        for (let i = 0; i < 20; i++) {
        const logo = document.createElement('div');
        logo.className = 'logo';
        const size = Math.random() * 30 + 20; // Random size between 20px and 50px
        logo.style.width = `${size}px`;
        logo.style.height = `${size}px`;
        logo.style.left = `${Math.random() * 100}vw`;
        logo.style.animationDelay = `${Math.random() * 5}s`;
        logo.innerHTML = svgContent;
        body.appendChild(logo);
        }
        }

        // Call the function to create logos on load
        createLogos();
        </script>
        </body>
        </html>
      HTML

      return nil
    end
  end

  # start a local web server
  # then start a browser that will callback the local server upon authentication
  # store the final query
  class WebAuth < WebServerSimple
    # @param endpoint_url     [String] e.g. 'https://127.0.0.1:12345'
    # @param additionnal_info [String] Information in web page
    def initialize(endpoint_url, additionnal_info = nil)
      uri = URI.parse(endpoint_url)
      super(uri)
      @mutex = Mutex.new
      @cond = ConditionVariable.new
      @expected_path = uri.path.empty? ? '/' : uri.path
      @query = nil
      @additionnal_info = additionnal_info
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
      return @additionnal_info
    end

    # wait for request on web server (main thread)
    # @return [Hash] the query
    def received_request
      # wait for signal from thread
      @mutex.synchronize{@cond.wait(@mutex)}
      # tell server thread to stop
      shutdown
      return @query
    end
  end
end
