# frozen_string_literal: true

# cspell:ignore ascli jsonrpc pkce enotty

require 'aspera/cli/plugins/base'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'aspera/oauth/server/pkce'
require 'json'
require 'securerandom'

module Aspera
  module Cli
    module Plugins
      # Plugin to start the MCP (Model Context Protocol) server.
      # The `server` action accepts an optional Hash argument (extended value)
      # to configure the MCP server and transport.
      #
      # Supported keys in the options Hash:
      #   transport:              "stdio" (default) or "http"
      #   extra_args:             Array<String> - flags prepended to every ascli call
      #                           (default: ["--interactive=no", "--transfer.asynchronous=true"])
      #   max_text_bytes:         Integer - max bytes of JSON text content for list results (default 100_000)
      #   # stdio transport:
      #   max_line_bytes:         Integer - max JSON frame size (default 4 MiB)
      #   # http transport:
      #   auth_token:             String  - if set, require "Authorization: Bearer <token>" on MCP requests,
      #                                     and asked on the OAuth consent page (mandatory on a non-local bind)
      #   oauth:                  Boolean - enable OAuth 2.0 PKCE flow with dynamic client registration (RFC 7591)
      #   oauth_access_token_ttl: Integer - access token lifetime in seconds (default 3600)
      #   oauth_refresh_token_ttl: Integer - refresh token lifetime in seconds (default 2592000 = 30 days)
      #   base_url:               String  - URL of the server for clients, used in OAuth metadata and secret pages
      #                                     (default: from bind and port, mandatory with oauth on a wildcard bind)
      #   port:                   Integer - TCP port (default 3000)
      #   bind:                   String  - bind address (default "127.0.0.1")
      #   stateless:              Boolean - stateless mode (default false)
      #   allowed_origins:        Array<String>
      #   allowed_hosts:          Array<String>
      #   session_idle_timeout:   Integer (seconds)
      #   max_sessions:           Integer
      #   # MCP::Server options:
      #   instructions:           String  - hint shown to the AI client
      #   protocol_version:       String  - e.g. "2024-11-05"
      #   validate_tool_call_arguments: Boolean (default true)
      #
      # Examples:
      #   ascli mcp server
      #   ascli mcp server @json:{"instructions":"Aspera transfers"}
      #   ascli mcp server @json:{"transport":"http","port":3000}
      #   ascli mcp server @json:{"protocol_version":"2024-11-05","max_line_bytes":1048576}
      class Mcp < Base
        application_name 'Model Context Protocol Server'
        # Default instructions shown to the AI client when none are provided by the user.
        DEFAULT_INSTRUCTIONS = <<~INST.strip
          This is the Aspera CLI (ascli) MCP server (IBM Aspera file transfer and management).
          It exposes a single tool, execute_ascli_command, which runs any ascli command in-process.
          Its description gives the syntax and the discovery sequence: follow it before any
          command whose syntax you have not verified in this session.

          Plugins: aoc (Aspera on Cloud), faspex5 (Faspex 5), node (Node API), server (FASP/SSH
          server), config (local configuration), console, orchestrator, ats, preview, shares,
          cos, httpgw, faspio, alee.

          CREDENTIALS
          Use saved presets by default: call ["config", "preset", "overview"] first, then pass
          --preset=<name>, or nothing if a default preset exists for the plugin.
          If the user provides credentials inline (--url, --username, --password, --private-key),
          use those exact values verbatim — never substitute a preset or another server.
          Some plugins support browser login (--auth=web).
          For a secret the user did not give (password, passphrase), pass "@secret:<name>" as value:
          the user enters it on a web page, you never see it. Prefer it to asking in the conversation.
          On error, report it as-is and stop.

          TRANSFERS
          Pass verbatim any flag the user requests (--transfer.agent=<agent>, --to-folder, …).
          Agents: direct (default, in-process ascp), desktop (IBM Aspera Desktop Client,
          graphical), node, transferd, httpgw, connect.
          Transfers are asynchronous: the command returns a job_id immediately — never retry it.
            monitor → ["config", "transfer", "status", "<job_id>"]
            list    → ["config", "transfer", "list"]
            cleanup → ["config", "transfer", "cleanup"]
        INST

        # Keys forwarded to MCP::Server constructor (symbolized)
        SERVER_KEYS = %i[instructions description].freeze
        # Keys forwarded to MCP::Configuration
        CONFIG_KEYS = %i[protocol_version validate_tool_call_arguments].freeze
        # Keys forwarded to StdioTransport
        STDIO_KEYS  = %i[max_line_bytes].freeze
        # Keys forwarded to StreamableHTTPTransport
        HTTP_KEYS   = %i[stateless allowed_origins allowed_hosts session_idle_timeout max_sessions].freeze
        # Keys consumed locally (not forwarded to MCP gem)
        TOOL_KEYS   = %i[max_text_bytes extra_args].freeze
        # Extended-value handlers disabled for the whole process in MCP server mode, including in presets:
        # @ruby: code execution (a client can write a preset), @stdin: is the JSON-RPC stream (stdio).
        # Other unsafe handlers are refused in client arguments only, see Mcp::Tool, so that presets
        # can still use @file: and @env:.
        # @secret: is entered on a web page instead of the terminal, see Mcp::Secrets.
        DISABLED_EXTENDED_VALUE_HANDLERS = %i[ruby stdin].freeze
        private_constant :SERVER_KEYS, :CONFIG_KEYS, :STDIO_KEYS, :HTTP_KEYS, :TOOL_KEYS, :DISABLED_EXTENDED_VALUE_HANDLERS

        command :server, description: 'Start the MCP (Model Context Protocol) server',
          arguments:   [{name: :mcp_options, type: [Hash], mandatory: false, schema: 'opts:components.schemas.McpServerOptions'}]

        def action_server(mcp_options: nil, **)
          require 'aspera/cli/mcp/tool'
          require 'aspera/cli/extended_value'
          mcp_options = (mcp_options || {}).transform_keys(&:to_sym)
          unknown = mcp_options.keys - SERVER_KEYS - CONFIG_KEYS - STDIO_KEYS - HTTP_KEYS - TOOL_KEYS -
            %i[transport port bind base_url auth_token oauth oauth_access_token_ttl oauth_refresh_token_ttl]
          Aspera.assert(unknown.empty?, type: Cli::BadArgument) { "Unknown MCP option(s): #{unknown.join(', ')}" }
          Cli::Mcp::Tool.max_text_bytes = mcp_options.delete(:max_text_bytes)
          Cli::Mcp::Tool.extra_args     = mcp_options.delete(:extra_args)
          transport = mcp_options.delete(:transport) || 'stdio'
          raise Cli::BadArgument, "Unknown transport: #{transport}. Use 'stdio' or 'http'" \
            unless %w[stdio http].include?(transport.to_s)
          DISABLED_EXTENDED_VALUE_HANDLERS.each do |handler|
            ExtendedValue.instance.on(handler) { |_| raise Cli::BadArgument, "@#{handler}: extended value is disabled in MCP server mode" }
          end
          ExtendedValue.instance.on(:secret) { |prompt| Cli::Mcp::Secrets.value(prompt) }
          Log.log.info { "Starting MCP server (transport=#{transport})..." }
          start_mcp_server(transport: transport.to_sym, mcp_options: mcp_options)
          Result::Nothing.new
        end

        private

        # Build the MCP::Server from the options hash.
        # @param mcp_options [Hash] symbolized options
        # @return [MCP::Server]
        def build_mcp_server(mcp_options)
          tool = Cli::Mcp::Tool
          config_opts = mcp_options.slice(*CONFIG_KEYS)
          server_opts = mcp_options.slice(*SERVER_KEYS)
          server_opts[:instructions] ||= DEFAULT_INSTRUCTIONS
          server_opts[:description]  ||= "#{Info::GEM_NAME} MCP server (IBM Aspera file transfer and management)"
          configuration = config_opts.empty? ? nil : MCP::Configuration.new(**config_opts)
          MCP::Server.new(
            name:                   Info::GEM_NAME,
            version:                VERSION,
            tools:                  [tool],
            configuration:          configuration,
            # The request state of secret requests (@secret:) goes through the client: encrypted and bound to the tool call
            request_state_security: MCP::Server::RequestStateSecurity.new(key: SecureRandom.random_bytes(32), ttl: Cli::WebSecret::TTL),
            **server_opts
          )
        end

        # Build and start the MCP server.
        # @param transport [Symbol] :stdio or :http
        # @param mcp_options [Hash] symbolized options
        def start_mcp_server(transport:, mcp_options:)
          server = build_mcp_server(mcp_options)
          case transport
          when :stdio
            # Secret pages are served by a local web server, started on first use of @secret:
            Cli::Mcp::Tool.web_secret = Cli::Mcp::Secrets.web_secret
            stdio_opts = mcp_options.slice(*STDIO_KEYS)
            MCP::Server::Transports::StdioTransport.new(server, **stdio_opts).open
          when :http
            start_http_transport(server, mcp_options)
          end
        end

        LOCAL_BIND_ADDRESSES = %w[127.0.0.1 ::1 localhost].freeze
        # Bind addresses listening on all interfaces: not a host name usable by clients
        WILDCARD_BIND_ADDRESSES = %w[0.0.0.0 ::].freeze
        private_constant :LOCAL_BIND_ADDRESSES, :WILDCARD_BIND_ADDRESSES

        # Validate auth configuration.
        # - On a non-local bind address, auth_token is mandatory for security, also with OAuth:
        #   it is the secret asked on the consent page, else anyone could approve its own client.
        # - On a local bind address, both are optional but accepted.
        # @param auth_token [String, nil] expected static Bearer token
        # @param oauth_enabled [Boolean] whether OAuth PKCE flow is enabled
        # @param bind [String] bind address
        def check_auth_config(auth_token, oauth_enabled, bind)
          Aspera.assert(auth_token.nil? || !auth_token.to_s.empty?, type: Cli::BadArgument) { 'auth_token must not be empty' }
          Aspera.assert(!auth_token.nil? || LOCAL_BIND_ADDRESSES.include?(bind.to_s), type: Cli::BadArgument) do
            "auth_token is required#{' (asked on the consent page)' if oauth_enabled} when bind address (#{bind}) is not local (#{LOCAL_BIND_ADDRESSES.join(', ')})"
          end
        end

        # @param bind     [String]      bind address
        # @param port     [Integer]     TCP port
        # @param base_url [String, nil] URL of the server for clients, if provided by user
        # @param oauth_enabled [Boolean] whether OAuth PKCE flow is enabled
        # @return [String] URL of the server for clients, without trailing slash
        def http_base_url(bind, port, base_url, oauth_enabled)
          return base_url.to_s.chomp('/') unless base_url.nil?
          Aspera.assert(!oauth_enabled || !WILDCARD_BIND_ADDRESSES.include?(bind.to_s), type: Cli::BadArgument) do
            "base_url is required with oauth when bind address is #{bind}: URL used by clients, e.g. http://myhost:#{port}"
          end
          host = WILDCARD_BIND_ADDRESSES.include?(bind.to_s) ? 'localhost' : bind.to_s
          host = "[#{host}]" if host.include?(':')
          "http://#{host}:#{port}"
        end

        # Start HTTP transport using WEBrick (already a project dependency).
        # Rack 3 removed Rack::Handler - we build a native WEBrick servlet that
        # calls the Rack app directly instead of relying on Rack::Handler::WEBrick.
        def start_http_transport(server, mcp_options) # rubocop:disable Metrics/MethodLength
          require 'webrick'
          http_opts         = mcp_options.slice(*HTTP_KEYS)
          port              = mcp_options.fetch(:port, 3000)
          bind              = mcp_options.fetch(:bind, '127.0.0.1')
          auth_token        = mcp_options[:auth_token]
          oauth_enabled     = mcp_options.fetch(:oauth, false)
          access_token_ttl  = mcp_options.fetch(:oauth_access_token_ttl, OAuth::Server::Pkce.default_access_token_ttl)
          refresh_token_ttl = mcp_options.fetch(:oauth_refresh_token_ttl, OAuth::Server::Pkce.default_refresh_token_ttl)
          check_auth_config(auth_token, oauth_enabled, bind)
          base_url = http_base_url(bind, port, mcp_options[:base_url], oauth_enabled)
          # Secret pages are served by this server: the static token, if any, is the access code asked on the page
          web_secret = Cli::Mcp::Secrets.web_secret(base_url: base_url, access_code: auth_token)
          Cli::Mcp::Tool.web_secret = web_secret
          app = MCP::Server::Transports::StreamableHTTPTransport.new(server, **http_opts)
          # Build OAuth::Server::Pkce only when OAuth is enabled.
          # Pass MCP-specific branding via title: and description: so the external HTML
          # template is used directly without a custom callback.
          # The static token, if any, is the access code asked on the consent page.
          oauth_server = if oauth_enabled
            OAuth::Server::Pkce.new(
              base_url:          base_url,
              access_token_ttl:  access_token_ttl,
              refresh_token_ttl: refresh_token_ttl,
              title:             "Authorize #{Info::GEM_NAME} MCP server",
              description:       "the <strong>#{Info::GEM_NAME} MCP server</strong>",
              consent_secret:    auth_token
            )
          end
          rack_servlet = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
            define_method(:initialize) do |srv, rack_app, server_info, static_token, auth_opts|
              @app           = rack_app
              @server_info   = server_info
              @auth_token    = static_token
              @oauth_server  = auth_opts[:oauth_server]
              @oauth_enabled = auth_opts[:oauth_enabled]
              @base_url      = auth_opts[:base_url]
              @web_secret    = auth_opts[:web_secret]
              super(srv)
            end

            # ------------------------------------------------------------------ helpers

            # @return [Boolean] true if no auth is configured OR the request carries a valid token
            define_method(:authorized?) do |req|
              return true if @auth_token.nil? && !@oauth_enabled
              # Static token check
              scheme, value = req['Authorization'].to_s.split(' ', 2)
              return false unless scheme.to_s.casecmp?('Bearer')
              return true if @auth_token && OpenSSL.secure_compare(value.to_s, @auth_token.to_s)
              # OAuth access token check
              @oauth_server&.authorized?(req['Authorization'])
            end

            define_method(:json_error) do |res, status, error, description = nil|
              res.status = status
              res['Content-Type'] = 'application/json'
              body = {error: error}
              body[:error_description] = description if description
              res.body = JSON.generate(body)
            end

            # ------------------------------------------------------------------ main dispatch

            %w[GET POST DELETE].each do |http_method|
              define_method(:"do_#{http_method}") do |req, res|
                case req.path
                when '/'
                  # Discovery endpoint (server metadata, no auth required)
                  res.status = 200
                  res['Content-Type'] = 'application/json'
                  res.body = JSON.generate(@server_info)
                when '/.well-known/oauth-authorization-server'
                  @oauth_server ? @oauth_server.handle_discovery(req, res) : json_error(res, 404, 'not_found')
                when '/oauth/register'
                  if http_method == 'POST'
                    @oauth_server ? @oauth_server.handle_register(req, res) : json_error(res, 404, 'not_found')
                  else
                    json_error(res, 405, 'method_not_allowed')
                  end
                when '/oauth/authorize'
                  @oauth_server ? @oauth_server.handle_authorize(req, res) : json_error(res, 404, 'not_found')
                when '/oauth/token'
                  if http_method == 'POST'
                    @oauth_server ? @oauth_server.handle_token(req, res) : json_error(res, 404, 'not_found')
                  else
                    json_error(res, 405, 'method_not_allowed')
                  end
                when ->(path) { path.start_with?(Cli::WebSecret::PATH_PREFIX) }
                  # Page opened by the user in a browser (no bearer token), protected by the access code
                  @web_secret.handle(req, res)
                else
                  # All other paths are MCP endpoints — require authorization
                  unless authorized?(req)
                    res.status = 401
                    res['Content-Type'] = 'application/json'
                    res['WWW-Authenticate'] = if @oauth_enabled
                      @oauth_server.www_authenticate_header
                    else
                      'Bearer'
                    end
                    res.body = JSON.generate(error: 'Unauthorized')
                    next
                  end
                  env = rack_env_from_webrick(req)
                  status, headers, rack_body = @app.call(env)
                  res.status = status
                  headers.each { |k, v| res[k] = v }
                  if rack_body.respond_to?(:call)
                    rack_proc = rack_body
                    res.chunked = true
                    res.body = proc do |socket|
                      stream = Object.new
                      stream.define_singleton_method(:write) { |data| socket.write(data) }
                      stream.define_singleton_method(:flush) { socket.flush rescue nil }
                      stream.define_singleton_method(:close) { socket.close rescue nil }
                      rack_proc.call(stream)
                    end
                  else
                    buf = +''
                    rack_body.each { |chunk| buf << chunk }
                    rack_body.close if rack_body.respond_to?(:close)
                    res.body = buf
                  end
                end
              end
            end

            define_method(:rack_env_from_webrick) do |req|
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
          # WEBrick logs Errno::ECONNRESET as ERROR when a client disconnects mid-stream
          # (normal for SSE/streaming connections). Suppress those noisy non-fatal errors.
          quiet_logger = WEBrick::Log.new($stderr).tap do |log|
            log.define_singleton_method(:error) do |msg|
              return if msg.to_s.include?('ECONNRESET') || msg.to_s.include?('Broken pipe')
              super(msg)
            end
          end
          webrick = WEBrick::HTTPServer.new(
            BindAddress: bind,
            Port:        port,
            Logger:      quiet_logger,
            AccessLog:   []
          )
          server_info = {
            name:        server.name,
            version:     server.version,
            description: server.description
          }
          webrick.mount(
            '/', rack_servlet, app, server_info, auth_token,
            {oauth_server: oauth_server, oauth_enabled: oauth_enabled, base_url: base_url, web_secret: web_secret}
          )
          Log.log.info { "MCP HTTP server listening on http://#{bind}:#{port}/" }
          Log.log.info { 'OAuth 2.0 PKCE enabled (dynamic registration)' } if oauth_enabled
          trap('INT') { webrick.shutdown }
          trap('TERM') { webrick.shutdown }
          webrick.start
        end
      end
    end
  end
end
