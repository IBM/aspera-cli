# frozen_string_literal: true

# cspell:ignore ascli jsonrpc pkce

require 'aspera/cli/plugins/base'
require 'aspera/cli/info'
require 'aspera/cli/version'
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
      #   auth_token:             String  - if set, require "Authorization: Bearer <token>" on MCP requests
      #   oauth:                  Boolean - enable OAuth 2.0 PKCE flow with dynamic client registration (RFC 7591)
      #   oauth_access_token_ttl: Integer - access token lifetime in seconds (default 3600)
      #   oauth_refresh_token_ttl: Integer - refresh token lifetime in seconds (default 2592000 = 30 days)
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
        # Extended-value handlers disabled in MCP server mode to prevent code execution
        # and local resource access from a network-accessible client.
        UNSAFE_EXTENDED_VALUE_HANDLERS = %i[ruby file uri stdin env].freeze
        private_constant :SERVER_KEYS, :CONFIG_KEYS, :STDIO_KEYS, :HTTP_KEYS, :TOOL_KEYS, :UNSAFE_EXTENDED_VALUE_HANDLERS

        command :server, description: 'Start the MCP (Model Context Protocol) server',
          arguments:   [{name: :mcp_options, type: [Hash], mandatory: false, schema: 'opts:components.schemas.McpServerOptions'}]

        def action_server(mcp_options: nil, **)
          require 'aspera/cli/mcp_tool'
          require 'aspera/cli/extended_value'
          mcp_options = (mcp_options || {}).transform_keys(&:to_sym)
          unknown = mcp_options.keys - SERVER_KEYS - CONFIG_KEYS - STDIO_KEYS - HTTP_KEYS - TOOL_KEYS -
            %i[transport port bind auth_token oauth oauth_access_token_ttl oauth_refresh_token_ttl]
          Aspera.assert(unknown.empty?, type: Cli::BadArgument) { "Unknown MCP option(s): #{unknown.join(', ')}" }
          Cli::McpTool.max_text_bytes = mcp_options.delete(:max_text_bytes)
          Cli::McpTool.extra_args     = mcp_options.delete(:extra_args)
          transport = mcp_options.delete(:transport) || 'stdio'
          raise Cli::BadArgument, "Unknown transport: #{transport}. Use 'stdio' or 'http'" \
            unless %w[stdio http].include?(transport.to_s)
          # Disable extended-value handlers that allow arbitrary code execution or
          # local resource access when called from a network-accessible MCP client.
          # @ruby: evaluates attacker-supplied Ruby; @file:/@uri:/@stdin:/@env: expose
          # the server's filesystem, environment, and internal network.
          UNSAFE_EXTENDED_VALUE_HANDLERS.each do |handler|
            ExtendedValue.instance.on(handler) { |_| raise Cli::BadArgument, "@#{handler}: extended value is disabled in MCP server mode" }
          end
          Log.log.info { "Starting MCP server (transport=#{transport})..." }
          start_mcp_server(transport: transport.to_sym, mcp_options: mcp_options)
          Result::Nothing.new
        end

        private

        # Build the MCP::Server from the options hash.
        # @param mcp_options [Hash] symbolized options
        # @return [MCP::Server]
        def build_mcp_server(mcp_options)
          tool = Cli::McpTool
          config_opts = mcp_options.slice(*CONFIG_KEYS)
          server_opts = mcp_options.slice(*SERVER_KEYS)
          server_opts[:instructions] ||= DEFAULT_INSTRUCTIONS
          server_opts[:description]  ||= "#{Info::GEM_NAME} MCP server (IBM Aspera file transfer and management)"
          configuration = config_opts.empty? ? nil : MCP::Configuration.new(**config_opts)
          MCP::Server.new(
            name:          Info::GEM_NAME,
            version:       VERSION,
            tools:         [tool],
            configuration: configuration,
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
            stdio_opts = mcp_options.slice(*STDIO_KEYS)
            MCP::Server::Transports::StdioTransport.new(server, **stdio_opts).open
          when :http
            start_http_transport(server, mcp_options)
          end
        end

        LOCAL_BIND_ADDRESSES = %w[127.0.0.1 ::1 localhost].freeze
        OAUTH_ACCESS_TOKEN_TTL  = 3600        # 1 hour
        OAUTH_REFRESH_TOKEN_TTL = 2_592_000   # 30 days
        OAUTH_CODE_TTL          = 120         # 2 minutes
        private_constant :LOCAL_BIND_ADDRESSES, :OAUTH_ACCESS_TOKEN_TTL, :OAUTH_REFRESH_TOKEN_TTL, :OAUTH_CODE_TTL

        # Validate auth configuration.
        # - On a non-local bind address, auth_token or oauth_enabled is mandatory for security.
        # - On a local bind address, both are optional but accepted.
        # @param auth_token [String, nil] expected static Bearer token
        # @param oauth_enabled [Boolean] whether OAuth PKCE flow is enabled
        # @param bind [String] bind address
        def check_auth_config(auth_token, oauth_enabled, bind)
          require 'openssl'
          Aspera.assert(auth_token.nil? || !auth_token.to_s.empty?, type: Cli::BadArgument) { 'auth_token must not be empty' }
          has_auth = !auth_token.nil? || oauth_enabled
          Aspera.assert(has_auth || LOCAL_BIND_ADDRESSES.include?(bind.to_s), type: Cli::BadArgument) do
            "auth_token or oauth is required when bind address (#{bind}) is not local (#{LOCAL_BIND_ADDRESSES.join(', ')})"
          end
        end

        # Build the OAuth 2.0 authorization server metadata (RFC 8414).
        # @param base_url [String] e.g. "http://host:port"
        # @return [Hash]
        def oauth_metadata(base_url)
          {
            issuer:                                base_url,
            authorization_endpoint:                "#{base_url}/oauth/authorize",
            token_endpoint:                        "#{base_url}/oauth/token",
            registration_endpoint:                 "#{base_url}/oauth/register",
            response_types_supported:              ['code'],
            grant_types_supported:                 %w[authorization_code refresh_token],
            code_challenge_methods_supported:      ['S256'],
            token_endpoint_auth_methods_supported: ['none']
          }
        end

        # Verify PKCE: SHA-256(code_verifier) == code_challenge (base64url, no padding).
        # @param verifier [String]
        # @param challenge [String]
        # @return [Boolean]
        def pkce_valid?(verifier, challenge)
          require 'openssl'
          require 'base64'
          digest = OpenSSL::Digest::SHA256.digest(verifier)
          computed = Base64.urlsafe_encode64(digest, padding: false)
          OpenSSL.secure_compare(computed, challenge)
        end

        # HTML page shown to the user during the OAuth authorization step.
        # @param params [Hash] query parameters from the authorization request
        # @param base_url [String]
        # @return [String] HTML body
        def oauth_authorize_html(params, base_url)
          client_id    = WEBrick::HTMLUtils.escape(params['client_id'].to_s)
          redirect_uri = WEBrick::HTMLUtils.escape(params['redirect_uri'].to_s)
          state        = WEBrick::HTMLUtils.escape(params['state'].to_s)
          challenge    = WEBrick::HTMLUtils.escape(params['code_challenge'].to_s)
          method       = WEBrick::HTMLUtils.escape(params['code_challenge_method'].to_s)
          <<~HTML
            <!DOCTYPE html>
            <html lang="en">
            <head><meta charset="utf-8"><title>Authorize #{Info::GEM_NAME} MCP server</title>
            <style>
              body{font-family:system-ui,sans-serif;max-width:480px;margin:4rem auto;padding:1rem}
              h1{font-size:1.2rem}
              .client{font-weight:bold}
              button{margin:.5rem .5rem 0 0;padding:.5rem 1.2rem;cursor:pointer}
              .allow{background:#0f62fe;color:#fff;border:none;border-radius:4px}
              .deny{background:#fff;color:#da1e28;border:1px solid #da1e28;border-radius:4px}
            </style>
            </head>
            <body>
            <h1>Authorization request</h1>
            <p>The client <span class="client">#{client_id}</span> is requesting access to the
            <strong>#{Info::GEM_NAME} MCP server</strong>.</p>
            <p>Do you want to allow it?</p>
            <form method="POST" action="#{base_url}/oauth/authorize">
              <input type="hidden" name="client_id"             value="#{client_id}">
              <input type="hidden" name="redirect_uri"          value="#{redirect_uri}">
              <input type="hidden" name="state"                 value="#{state}">
              <input type="hidden" name="code_challenge"        value="#{challenge}">
              <input type="hidden" name="code_challenge_method" value="#{method}">
              <button class="allow" type="submit" name="decision" value="allow">Allow</button>
              <button class="deny"  type="submit" name="decision" value="deny">Deny</button>
            </form>
            </body></html>
          HTML
        end

        # Start HTTP transport using WEBrick (already a project dependency).
        # Rack 3 removed Rack::Handler - we build a native WEBrick servlet that
        # calls the Rack app directly instead of relying on Rack::Handler::WEBrick.
        def start_http_transport(server, mcp_options) # rubocop:disable Metrics/MethodLength
          require 'webrick'
          http_opts        = mcp_options.slice(*HTTP_KEYS)
          port             = mcp_options.fetch(:port, 3000)
          bind             = mcp_options.fetch(:bind, '127.0.0.1')
          auth_token        = mcp_options[:auth_token]
          oauth_enabled     = mcp_options.fetch(:oauth, false)
          access_token_ttl  = mcp_options.fetch(:oauth_access_token_ttl, OAUTH_ACCESS_TOKEN_TTL)
          refresh_token_ttl = mcp_options.fetch(:oauth_refresh_token_ttl, OAUTH_REFRESH_TOKEN_TTL)
          check_auth_config(auth_token, oauth_enabled, bind)
          # In-memory stores (all guarded by @store_mutex in the servlet)
          oauth_clients   = []  # dynamically registered clients, populated at runtime
          pending_codes   = {}  # code  => {client_id, redirect_uri, code_challenge, expires_at}
          access_tokens   = {}  # token => expires_at
          refresh_tokens  = {}  # token => {access_token, expires_at}
          base_url        = "http://#{bind == '0.0.0.0' ? 'localhost' : bind}:#{port}"
          app = MCP::Server::Transports::StreamableHTTPTransport.new(server, **http_opts)
          oauth_ctx = {
            plugin:            self,
            auth_token:        auth_token,
            oauth_enabled:     oauth_enabled,
            clients:           oauth_clients,
            pending_codes:     pending_codes,
            access_tokens:     access_tokens,
            refresh_tokens:    refresh_tokens,
            access_token_ttl:  access_token_ttl,
            refresh_token_ttl: refresh_token_ttl,
            base_url:          base_url
          }
          rack_servlet = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
            define_method(:initialize) do |srv, rack_app, server_info, ctx|
              @app               = rack_app
              @server_info       = server_info
              @auth_token        = ctx[:auth_token]
              @oauth_enabled     = ctx[:oauth_enabled]
              @oauth_clients     = ctx[:clients]
              @pending_codes     = ctx[:pending_codes]
              @access_tokens     = ctx[:access_tokens]
              @refresh_tokens    = ctx[:refresh_tokens]
              @access_token_ttl  = ctx[:access_token_ttl]
              @refresh_token_ttl = ctx[:refresh_token_ttl]
              @base_url          = ctx[:base_url]
              @plugin            = ctx[:plugin]
              @store_mutex       = Mutex.new
              super(srv)
            end

            # ------------------------------------------------------------------ helpers

            # @return [Boolean] true if no auth is configured OR the request carries a valid token
            define_method(:authorized?) do |req|
              return true if @auth_token.nil? && !@oauth_enabled
              scheme, value = req['Authorization'].to_s.split(' ', 2)
              return false unless scheme.to_s.casecmp?('Bearer')
              # Static token check
              return true if @auth_token && OpenSSL.secure_compare(value.to_s, @auth_token.to_s)
              # OAuth access token check
              @store_mutex.synchronize do
                expire_at = @access_tokens[value]
                expire_at && expire_at > Time.now
              end
            end

            define_method(:oauth_client_allowed?) do |client_id|
              @oauth_clients.any? { |c| c[:client_id] == client_id }
            end

            define_method(:json_error) do |res, status, error, description = nil|
              res.status = status
              res['Content-Type'] = 'application/json'
              body = {error: error}
              body[:error_description] = description if description
              res.body = JSON.generate(body)
            end

            define_method(:purge_expired) do
              now = Time.now
              @pending_codes.delete_if  { |_, v| v[:expires_at] < now }
              @access_tokens.delete_if  { |_, exp| exp < now }
              @refresh_tokens.delete_if { |_, v| v[:expires_at] < now }
            end

            define_method(:issue_tokens) do
              access  = SecureRandom.urlsafe_base64(32)
              refresh = SecureRandom.urlsafe_base64(48)
              now = Time.now
              @store_mutex.synchronize do
                purge_expired
                @access_tokens[access] = now + @access_token_ttl
                @refresh_tokens[refresh] = {access_token: access, expires_at: now + @refresh_token_ttl}
              end
              {
                access_token:  access,
                token_type:    'Bearer',
                expires_in:    @access_token_ttl,
                refresh_token: refresh
              }
            end

            # ------------------------------------------------------------------ OAuth endpoints

            # POST /oauth/register — Dynamic Client Registration (RFC 7591)
            # Accepts any client, assigns a generated client_id, and adds it to the
            # in-memory allow-list so subsequent authorize calls succeed.
            define_method(:handle_register) do |req, res|
              body = req.body.to_s.empty? ? {} : (JSON.parse(req.body.to_s) rescue {})
              client_id = SecureRandom.urlsafe_base64(16)
              @store_mutex.synchronize { @oauth_clients << {client_id: client_id} }
              Log.log.info { "OAuth dynamic registration: client_id=#{client_id} name=#{body['client_name']}" }
              res.status = 201
              res['Content-Type'] = 'application/json'
              res['Cache-Control'] = 'no-store'
              res.body = JSON.generate({
                client_id:                  client_id,
                client_id_issued_at:        Time.now.to_i,
                grant_types:                %w[authorization_code refresh_token],
                response_types:             ['code'],
                token_endpoint_auth_method: 'none',
                redirect_uris:              body['redirect_uris'] || []
              })
            end

            # GET /.well-known/oauth-authorization-server
            define_method(:handle_discovery) do |_req, res|
              res.status = 200
              res['Content-Type'] = 'application/json'
              res.body = JSON.generate(@plugin.send(:oauth_metadata, @base_url))
            end

            # GET /oauth/authorize  → show consent page
            define_method(:handle_authorize_get) do |req, res|
              params = req.query
              client_id = params['client_id']
              unless oauth_client_allowed?(client_id)
                json_error(res, 400, 'unauthorized_client', "Unknown client_id: #{client_id}")
                next
              end
              unless params['code_challenge'] && params['code_challenge_method'] == 'S256'
                json_error(res, 400, 'invalid_request', 'PKCE with S256 is required')
                next
              end
              res.status = 200
              res['Content-Type'] = 'text/html; charset=utf-8'
              res.body = @plugin.send(:oauth_authorize_html, params, @base_url)
            end

            # POST /oauth/authorize  → process consent form
            define_method(:handle_authorize_post) do |req, res|
              params = WEBrick::HTTPUtils.parse_query(req.body.to_s)
              client_id    = params['client_id']
              redirect_uri = params['redirect_uri']
              state        = params['state']
              decision     = params['decision']
              if decision != 'allow'
                target = "#{redirect_uri}?error=access_denied"
                target += "&state=#{WEBrick::HTTPUtils.escape(state)}" unless state.to_s.empty?
                res.status = 302
                res['Location'] = target
                next
              end
              unless oauth_client_allowed?(client_id)
                json_error(res, 400, 'unauthorized_client', "Unknown client_id: #{client_id}")
                next
              end
              code = SecureRandom.urlsafe_base64(24)
              @store_mutex.synchronize do
                purge_expired
                @pending_codes[code] = {
                  client_id:      client_id,
                  redirect_uri:   redirect_uri,
                  code_challenge: params['code_challenge'],
                  expires_at:     Time.now + OAUTH_CODE_TTL
                }
              end
              target = "#{redirect_uri}?code=#{WEBrick::HTTPUtils.escape(code)}"
              target += "&state=#{WEBrick::HTTPUtils.escape(state)}" unless state.to_s.empty?
              res.status = 302
              res['Location'] = target
            end

            # POST /oauth/token
            define_method(:handle_token) do |req, res|
              params     = WEBrick::HTTPUtils.parse_query(req.body.to_s)
              grant_type = params['grant_type']
              case grant_type
              when 'authorization_code'
                code = params['code']
                code_verifier = params['code_verifier']
                stored = @store_mutex.synchronize { @pending_codes.delete(code) }
                if stored.nil? || stored[:expires_at] < Time.now
                  json_error(res, 400, 'invalid_grant', 'Authorization code expired or unknown')
                  next
                end
                unless @plugin.send(:pkce_valid?, code_verifier.to_s, stored[:code_challenge])
                  json_error(res, 400, 'invalid_grant', 'PKCE verification failed')
                  next
                end
                res.status = 200
                res['Content-Type'] = 'application/json'
                res['Cache-Control'] = 'no-store'
                res.body = JSON.generate(issue_tokens)
              when 'refresh_token'
                rt_value = params['refresh_token']
                stored = @store_mutex.synchronize do
                  entry = @refresh_tokens[rt_value]
                  if entry && entry[:expires_at] > Time.now
                    # Rotate: revoke old access token and issue fresh pair
                    @access_tokens.delete(entry[:access_token])
                    @refresh_tokens.delete(rt_value)
                  end
                  entry
                end
                if stored.nil?
                  json_error(res, 400, 'invalid_grant', 'Refresh token expired or unknown')
                  next
                end
                res.status = 200
                res['Content-Type'] = 'application/json'
                res['Cache-Control'] = 'no-store'
                res.body = JSON.generate(issue_tokens)
              else
                json_error(res, 400, 'unsupported_grant_type', "Unsupported grant_type: #{grant_type}")
              end
            end

            # ------------------------------------------------------------------ main dispatch

            %w[GET POST DELETE].each do |http_method|
              define_method(:"do_#{http_method}") do |req, res|
                case req.path
                when '/'
                  # Discovery endpoint (server metadata, no auth required)
                  body = JSON.generate(@server_info)
                  res.status = 200
                  res['Content-Type'] = 'application/json'
                  res.body = body
                when '/.well-known/oauth-authorization-server'
                  handle_discovery(req, res)
                when '/oauth/authorize'
                  if http_method == 'GET'
                    handle_authorize_get(req, res)
                  elsif http_method == 'POST'
                    handle_authorize_post(req, res)
                  else
                    json_error(res, 405, 'method_not_allowed')
                  end
                when '/oauth/register'
                  if http_method == 'POST'
                    handle_register(req, res)
                  else
                    json_error(res, 405, 'method_not_allowed')
                  end
                when '/oauth/token'
                  if http_method == 'POST'
                    handle_token(req, res)
                  else
                    json_error(res, 405, 'method_not_allowed')
                  end
                else
                  # All other paths are MCP endpoints — require authorization
                  unless authorized?(req)
                    res.status = 401
                    res['Content-Type'] = 'application/json'
                    # Advertise OAuth discovery if clients are configured
                    res['WWW-Authenticate'] = if @oauth_enabled
                      "Bearer realm=\"#{@base_url}\", " \
                        "resource_metadata=\"#{@base_url}/.well-known/oauth-authorization-server\""
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
          webrick.mount('/', rack_servlet, app, server_info, oauth_ctx)
          Log.log.info { "MCP HTTP server listening on http://#{bind}:#{port}/" }
          Log.log.info { "OAuth 2.0 PKCE enabled (dynamic registration + #{oauth_clients.size} pre-registered client(s))" } \
            if oauth_enabled
          trap('INT') { webrick.shutdown }
          trap('TERM') { webrick.shutdown }
          webrick.start
        end
      end
    end
  end
end
