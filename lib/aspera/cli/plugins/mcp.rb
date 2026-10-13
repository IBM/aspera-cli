# frozen_string_literal: true

# cspell:ignore ascli jsonrpc pkce

require 'aspera/cli/plugins/base'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'aspera/oauth/server/pkce'
require 'aspera/cli/security'
require 'aspera/secret_strength'
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
      #   auth_token_min_bits:    Integer - minimum estimated strength of auth_token in bits (default 80, 0 disables)
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
        # Extended-value handlers disabled in MCP server mode whatever the security level:
        # @stdin: is the JSON-RPC stream (stdio).
        # Other unsafe handlers depend on the security level, see Security.
        # @secret: is entered on a web page instead of the terminal, see Mcp::Secrets.
        DISABLED_EXTENDED_VALUE_HANDLERS = %i[stdin].freeze
        # Security level when not set by option `security`
        DEFAULT_SECURITY_LEVEL = :high
        private_constant :SERVER_KEYS, :CONFIG_KEYS, :STDIO_KEYS, :HTTP_KEYS, :TOOL_KEYS, :DISABLED_EXTENDED_VALUE_HANDLERS, :DEFAULT_SECURITY_LEVEL

        command :server, description: 'Start the MCP (Model Context Protocol) server',
          arguments:   [{name: :mcp_options, type: [Hash], mandatory: false, schema: 'opts:components.schemas.McpServerOptions'}]

        def action_server(mcp_options: nil, **)
          require 'aspera/cli/mcp/tool'
          require 'aspera/cli/extended_value'
          mcp_options = (mcp_options || {}).transform_keys(&:to_sym)
          unknown = mcp_options.keys - SERVER_KEYS - CONFIG_KEYS - STDIO_KEYS - HTTP_KEYS - TOOL_KEYS -
            %i[transport port bind base_url auth_token auth_token_min_bits oauth oauth_access_token_ttl oauth_refresh_token_ttl]
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
          # Applies to commands of the client, and to presets, which the client can modify
          Security.instance.lock('in MCP server mode', default: DEFAULT_SECURITY_LEVEL)
          Log.log.info { "Starting MCP server (transport=#{transport}, security level #{Security.instance.level})..." }
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
        # - A weak auth_token is refused.
        # @param auth_token [String, nil] expected static Bearer token
        # @param oauth_enabled [Boolean] whether OAuth PKCE flow is enabled
        # @param bind [String] bind address
        # @param min_bits [Integer] minimum estimated strength of auth_token, in bits
        def check_auth_config(auth_token, oauth_enabled, bind, min_bits: SecretStrength::DEFAULT_MIN_BITS)
          Aspera.assert(auth_token.nil? || !auth_token.to_s.empty?, type: Cli::BadArgument) { 'auth_token must not be empty' }
          unless auth_token.nil?
            bits = SecretStrength.bits(auth_token.to_s)
            Aspera.assert(bits >= min_bits, type: Cli::BadArgument) do
              "auth_token is too weak: about #{bits.round} bits, minimum #{min_bits} (auth_token_min_bits). Generate one with: openssl rand -hex 32"
            end
          end
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

        # Start HTTP transport, see Mcp::HttpServlet
        def start_http_transport(server, mcp_options)
          require 'aspera/cli/mcp/http_servlet'
          port              = mcp_options.fetch(:port, 3000)
          bind              = mcp_options.fetch(:bind, '127.0.0.1')
          auth_token        = mcp_options[:auth_token]
          oauth_enabled     = mcp_options.fetch(:oauth, false)
          access_token_ttl  = mcp_options.fetch(:oauth_access_token_ttl, OAuth::Server::Pkce.default_access_token_ttl)
          refresh_token_ttl = mcp_options.fetch(:oauth_refresh_token_ttl, OAuth::Server::Pkce.default_refresh_token_ttl)
          check_auth_config(auth_token, oauth_enabled, bind, min_bits: mcp_options.fetch(:auth_token_min_bits, SecretStrength::DEFAULT_MIN_BITS))
          base_url = http_base_url(bind, port, mcp_options[:base_url], oauth_enabled)
          # Secret pages are served by this server: the static token, if any, is the access code asked on the page
          web_secret = Cli::Mcp::Secrets.web_secret(base_url: base_url, access_code: auth_token)
          Cli::Mcp::Tool.web_secret = web_secret
          # Build OAuth::Server::Pkce only when OAuth is enabled.
          # Pass MCP-specific branding via title: and description: so the external HTML
          # template is used directly without a custom callback.
          # The static token, if any, is the access code asked on the consent page.
          oauth_server = if oauth_enabled
            Log.log.info { 'OAuth 2.0 PKCE enabled (dynamic registration)' }
            OAuth::Server::Pkce.new(
              base_url:          base_url,
              access_token_ttl:  access_token_ttl,
              refresh_token_ttl: refresh_token_ttl,
              title:             "Authorize #{Info::GEM_NAME} MCP server",
              description:       "the <strong>#{Info::GEM_NAME} MCP server</strong>",
              consent_secret:    auth_token
            )
          end
          Cli::Mcp::HttpServlet.start(
            bind:         bind,
            port:         port,
            app:          MCP::Server::Transports::StreamableHTTPTransport.new(server, **mcp_options.slice(*HTTP_KEYS)),
            server_info:  {name: server.name, version: server.version, description: server.description},
            web_secret:   web_secret,
            auth_token:   auth_token,
            oauth_server: oauth_server
          )
        end
      end
    end
  end
end
