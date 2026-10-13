# frozen_string_literal: true

# cspell:ignore webrick

require 'aspera/log'
require 'aspera/servlet_helpers'
require 'aspera/cli/web_secret'
require 'json'
require 'openssl'
require 'stringio'
require 'webrick'

module Aspera
  module Cli
    module Mcp
      # Servlet of the HTTP transport of the MCP server, on WEBrick (already a project dependency).
      # Rack 3 removed Rack::Handler: the servlet calls the Rack app of the MCP transport directly.
      #
      # Routes:
      #   /                     Discovery: server metadata, no authentication
      #   /.well-known/oauth-authorization-server, /oauth/*: OAuth 2.0 PKCE server, if enabled
      #   /secret/<id>          Secret pages (see WebSecret), protected by their access code
      #   other paths           MCP endpoints: static Bearer token or OAuth access token, if configured
      # Requests that a web page could send are refused on all paths (see ServletHelpers#check_request),
      # as the MCP transport does for its own endpoints, with the same `allowed_hosts` and `allowed_origins`.
      class HttpServlet < WEBrick::HTTPServlet::AbstractServlet
        include ServletHelpers

        # Paths with a JSON body, not handled by the MCP transport
        JSON_PATHS = %w[/oauth/register].freeze
        private_constant :JSON_PATHS

        class << self
          # Start the HTTP server, until signal INT or TERM
          # @param bind    [String]  Bind address
          # @param port    [Integer] TCP port
          # @param options [Hash]    Options of the servlet, see #initialize
          def start(bind:, port:, **options)
            # WEBrick logs Errno::ECONNRESET as ERROR when a client disconnects mid-stream
            # (normal for SSE/streaming connections). Suppress those noisy non-fatal errors.
            quiet_logger = WEBrick::Log.new($stderr).tap do |log|
              log.define_singleton_method(:error) do |msg|
                return if msg.to_s.include?('ECONNRESET') || msg.to_s.include?('Broken pipe')
                super(msg)
              end
            end
            webrick = WEBrick::HTTPServer.new(BindAddress: bind, Port: port, Logger: quiet_logger, AccessLog: [])
            webrick.mount('/', self, options)
            Log.log.info { "MCP HTTP server listening on http://#{bind}:#{port}/" }
            trap('INT') { webrick.shutdown }
            trap('TERM') { webrick.shutdown }
            webrick.start
          end
        end

        # @param server  [WEBrick::HTTPServer]
        # @param options [Hash] With keys:
        #   app:          [#call]                    Rack app of the MCP transport
        #   server_info:  [Hash]                     Name, version and description of the server, for discovery
        #   web_secret:   [WebSecret]                Secret pages
        #   auth_token:   [String, nil]              Static Bearer token, if any
        #   oauth_server: [OAuth::Server::Pkce, nil] OAuth server, if enabled
        #   allowed_hosts:   [Array<String>, nil]    Other values accepted in header `Host`
        #   allowed_origins: [Array<String>, nil]    Other values accepted in header `Origin`
        def initialize(server, options)
          super(server)
          @app          = options.fetch(:app)
          @server_info  = options.fetch(:server_info)
          @web_secret   = options.fetch(:web_secret)
          @auth_token   = options[:auth_token]
          @oauth_server = options[:oauth_server]
          @allowed      = {allowed_hosts: Array(options[:allowed_hosts]), allowed_origins: Array(options[:allowed_origins])}
        end

        def do_GET(req, res) = dispatch(req, res)
        def do_POST(req, res) = dispatch(req, res)
        def do_DELETE(req, res) = dispatch(req, res)

        private

        def dispatch(req, res)
          check_request(req, json: JSON_PATHS.include?(req.path), **@allowed)
          case req.path
          when '/'
            # Discovery endpoint (server metadata, no auth required)
            json_response(res, 200, @server_info)
          when '/.well-known/oauth-authorization-server' then oauth(req, res, :handle_discovery)
          when '/oauth/register'                          then oauth(req, res, :handle_register, post_only: true)
          when '/oauth/authorize'                         then oauth(req, res, :handle_authorize)
          when '/oauth/token'                             then oauth(req, res, :handle_token, post_only: true)
          when ->(path) { path.start_with?(WebSecret::PATH_PREFIX) }
            # Page opened by the user in a browser (no bearer token), protected by the access code
            @web_secret.handle(req, res)
          else
            # All other paths are MCP endpoints: require authorization
            return unauthorized(res) unless authorized?(req)
            call_app(req, res)
          end
        rescue WEBrick::HTTPStatus::Error => e
          Log.log.warn { "Rejected request: #{e.message}" }
          json_error(res, e.code, 'invalid_request', e.message)
        end

        # Route to the OAuth server, if enabled
        # @param handler   [Symbol]  Method of the OAuth server
        # @param post_only [Boolean] Accept only method POST
        def oauth(req, res, handler, post_only: false)
          return json_error(res, 405, 'method_not_allowed') if post_only && !req.request_method.eql?('POST')
          return json_error(res, 404, 'not_found') if @oauth_server.nil?
          @oauth_server.public_send(handler, req, res)
        end

        # @return [Boolean] true if no auth is configured, or the request carries a valid token
        def authorized?(req)
          return true if @auth_token.nil? && @oauth_server.nil?
          # Static token check
          scheme, value = req['Authorization'].to_s.split(' ', 2)
          return false unless scheme.to_s.casecmp?('Bearer')
          return true if @auth_token && OpenSSL.secure_compare(value.to_s, @auth_token.to_s)
          # OAuth access token check
          !@oauth_server.nil? && @oauth_server.authorized?(req['Authorization'])
        end

        def unauthorized(res)
          json_error(res, 401, 'Unauthorized', headers: {'WWW-Authenticate' => @oauth_server.nil? ? 'Bearer' : @oauth_server.www_authenticate_header})
        end

        # Call the Rack app, with streaming of the response body if it is a callable (SSE)
        def call_app(req, res)
          status, headers, rack_body = @app.call(rack_env(req))
          res.status = status
          headers.each { |k, v| res[k] = v }
          if rack_body.respond_to?(:call)
            res.chunked = true
            res.body = proc do |socket|
              stream = Object.new
              stream.define_singleton_method(:write) { |data| socket.write(data) }
              stream.define_singleton_method(:flush) { socket.flush rescue nil }
              stream.define_singleton_method(:close) { socket.close rescue nil }
              rack_body.call(stream)
            end
          else
            buf = +''
            rack_body.each { |chunk| buf << chunk }
            rack_body.close if rack_body.respond_to?(:close)
            res.body = buf
          end
        end

        # @return [Hash] Rack environment of the WEBrick request
        def rack_env(req)
          {
            'REQUEST_METHOD'    => req.request_method,
            'SCRIPT_NAME'       => '',
            'PATH_INFO'         => req.path,
            'QUERY_STRING'      => req.query_string || '',
            'SERVER_NAME'       => req.host,
            'SERVER_PORT'       => req.port.to_s,
            'HTTP_VERSION'      => req.http_version,
            'rack.input'        => StringIO.new(req.body.to_s),
            'rack.errors'       => $stderr,
            'rack.url_scheme'   => 'http',
            'rack.multithread'  => true,
            'rack.multiprocess' => false,
            'rack.run_once'     => false
          }.tap do |env|
            req.header.each do |key, values|
              http_key = "HTTP_#{key.upcase.tr('-', '_')}"
              case key.downcase
              when 'content-type'   then env['CONTENT_TYPE']   = values.first
              when 'content-length' then env['CONTENT_LENGTH'] = values.first
              else                       env[http_key] = values.join(', ')
              end
            end
          end
        end
      end
    end
  end
end
