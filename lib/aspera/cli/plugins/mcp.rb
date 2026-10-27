# frozen_string_literal: true

require 'aspera/cli/plugins/base'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'aspera/oauth/server/pkce'
require 'aspera/cli/security'
require 'aspera/cli/deprecation'
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
      #   url:                    String  - address and port the server listens on (default "http://127.0.0.1:3000"), https:// for TLS
      #   cert, key, chain:       String  - TLS certificate, private key or PKCS12 passphrase, chain, see WebServerSimple
      #   auth_token:             String  - if set, require "Authorization: Bearer <token>" on MCP requests,
      #                                     and asked on the OAuth consent page (mandatory when url or public_url is not loopback)
      #   auth_token_min_bits:    Integer - minimum estimated strength of auth_token in bits (default 80, 0 disables)
      #   oauth:                  Boolean - enable OAuth 2.0 PKCE flow with dynamic client registration (RFC 7591)
      #   oauth_access_token_ttl: Integer - access token lifetime in seconds (default 3600)
      #   oauth_refresh_token_ttl: Integer - refresh token lifetime in seconds (default 2592000 = 30 days)
      #   public_url:             String  - URL of the server for clients, used in OAuth metadata and secret pages
      #                                     (default: from url, mandatory with oauth on a wildcard address)
      #   port, bind:             deprecated, replaced by url
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
      #   ascli mcp server @json:{"transport":"http","url":"http://127.0.0.1:3000"}
      #   ascli mcp server @json:{"protocol_version":"2024-11-05","max_line_bytes":1048576}
      class Mcp < Base
        application_name 'Model Context Protocol Server'

        # Instruction for AI agents to always display the equivalent CLI command in their output.
        COMMAND_DISPLAY_INSTRUCTIONS = <<~INST.strip
          COMMAND DISPLAY (MANDATORY)
            Whenever you execute an ascli command or present its results, you MUST ALWAYS explicitly
            show the equivalent command line in your response to the user as bash syntax
            (e.g. `ascli plugin command --option=value`).
        INST

        # Default instructions shown to the AI client when none are provided by the user.
        DEFAULT_INSTRUCTIONS = <<~INST.strip
          This is the Aspera CLI (ascli) MCP server (IBM Aspera file transfer and management).
          It exposes a single tool, execute_ascli_command, which runs any ascli command in-process.
          Its description gives the syntax and the discovery sequence: follow it before any
          command whose syntax you have not verified in this session.

          #{COMMAND_DISPLAY_INSTRUCTIONS}

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

          ORCHESTRATOR WORKFLOW DEVELOPMENT
          Before writing or modifying an Orchestrator workflow, read the documentation for workflow
          development (file format, graph, execution, recipes, authoring checklist):
            ["orchestrator", "workflows", "development", "authoring"]
          For the template attributes (allowed values), inputs and outputs of an action plugin, and the
          template settings they depend on, read its specification (fields: section "plugin-specifications"
          of the authoring guide); without plugin name, the list of plugins:
            ["orchestrator", "plugins", "spec", "<PluginClass>"]
          For the functional description and the setup of a plugin (for example the API client of Faspex),
          read its section of the Plugin Manual (large: read one section):
            ["orchestrator", "workflows", "development", "manual", "<anchor>"]
          The anchor "toc" lists the sections of a document, up to a default level, or the level given after it.
          Before importing a workflow file, check it (graph, templates, inputs of steps) and fix all errors:
            ["orchestrator", "workflows", "check_import", "<file>"]
        INST

        # Keys forwarded to MCP::Server constructor (symbolized)
        SERVER_KEYS      = %i[instructions description].freeze
        # Keys forwarded to MCP::Configuration
        CONFIG_KEYS      = %i[protocol_version validate_tool_call_arguments].freeze
        # Keys forwarded to StdioTransport
        STDIO_KEYS       = %i[max_line_bytes].freeze
        # Keys forwarded to StreamableHTTPTransport
        HTTP_KEYS        = %i[stateless allowed_origins allowed_hosts session_idle_timeout max_sessions].freeze
        # Keys of the HTTP server, consumed locally
        HTTP_SERVER_KEYS = %i[url cert key chain port bind public_url auth_token auth_token_min_bits oauth oauth_access_token_ttl oauth_refresh_token_ttl].freeze
        # Keys consumed locally (not forwarded to MCP gem)
        TOOL_KEYS        = %i[max_text_bytes extra_args].freeze
        # Extended-value handlers disabled in MCP server mode whatever the security level:
        # @stdin: is the JSON-RPC stream (stdio).
        # Other unsafe handlers depend on the security level, see Security.
        # @secret: is entered on a web page instead of the terminal, see Mcp::Secrets.
        DISABLED_EXTENDED_VALUE_HANDLERS = %i[stdin].freeze
        # Security level when not set by option `security`
        DEFAULT_SECURITY_LEVEL = :high
        private_constant :SERVER_KEYS, :CONFIG_KEYS, :STDIO_KEYS, :HTTP_KEYS, :HTTP_SERVER_KEYS, :TOOL_KEYS, :DISABLED_EXTENDED_VALUE_HANDLERS, :DEFAULT_SECURITY_LEVEL

        command :server, description: 'Start the MCP (Model Context Protocol) server',
          arguments:   [{name: :mcp_options, type: [Hash], mandatory: false, schema: 'opts:components.schemas.McpServerOptions'}]

        def action_server(mcp_options: nil, **)
          require 'aspera/cli/mcp/tool'
          require 'aspera/cli/extended_value'
          mcp_options = (mcp_options || {}).transform_keys(&:to_sym)
          unknown = mcp_options.keys - SERVER_KEYS - CONFIG_KEYS - STDIO_KEYS - HTTP_KEYS - HTTP_SERVER_KEYS - TOOL_KEYS - %i[transport]
          Aspera.assert(unknown.empty?, type: Cli::BadArgument) { "Unknown MCP option(s): #{unknown.join(', ')}" }
          Cli::Mcp::Tool.max_text_bytes = mcp_options.delete(:max_text_bytes)
          Cli::Mcp::Tool.extra_args     = mcp_options.delete(:extra_args)
          transport = mcp_options.delete(:transport) || 'stdio'
          raise Cli::BadArgument, "Unknown transport: #{transport}. Use 'stdio' or 'http'" \
            unless %w[stdio http].include?(transport.to_s)
          # Options of the other transport would be ignored
          ignored = mcp_options.keys & (transport.to_s.eql?('stdio') ? HTTP_KEYS + HTTP_SERVER_KEYS : STDIO_KEYS)
          Aspera.assert(ignored.empty?, type: Cli::BadArgument) { "MCP option(s) not used with transport #{transport}: #{ignored.join(', ')}" }
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

        # Addresses listening on all interfaces: not a host name usable by clients
        WILDCARD_BIND_ADDRESSES = %w[0.0.0.0 ::].freeze
        # Address of the HTTP transport, when not set by option `url`
        DEFAULT_HTTP_URL = 'http://127.0.0.1:3000'
        private_constant :WILDCARD_BIND_ADDRESSES, :DEFAULT_HTTP_URL

        # @param mcp_options [Hash] symbolized options
        # @return [Hash] Parameters of WebServerSimple.serve: `url`, and `cert`, `key`, `chain` if set
        def http_server_parameters(mcp_options)
          url = mcp_options[:url]
          bind, port = mcp_options.values_at(:bind, :port)
          unless bind.nil? && port.nil?
            Aspera.assert(url.nil?, type: Cli::BadArgument) { 'url cannot be used with bind or port' }
            Log.log.warn { "MCP options bind and port are #{Deprecation.new(last: '4.27.5', message: 'use url')}" }
            uri = URI.parse(DEFAULT_HTTP_URL)
            uri.hostname = bind.to_s unless bind.nil?
            uri.port = port unless port.nil?
            url = uri.to_s
          end
          url ||= DEFAULT_HTTP_URL
          # Paths of the servlet are absolute
          Aspera.assert(['', '/'].include?(URI.parse(url).path), type: Cli::BadArgument) { "url shall have no path (the MCP endpoint is /mcp): #{url}" }
          {url: url, **mcp_options.slice(:cert, :key, :chain)}
        end

        # @param uri      [URI]         Address the server listens on
        # @param public_url [String, nil] URL of the server for clients, if provided by user
        # @param oauth_enabled [Boolean] whether OAuth PKCE flow is enabled
        # @return [String] URL of the server for clients, without trailing slash
        def http_base_url(uri, public_url, oauth_enabled)
          return public_url.to_s.chomp('/') unless public_url.nil?
          wildcard = WILDCARD_BIND_ADDRESSES.include?(uri.hostname)
          Aspera.assert(!oauth_enabled || !wildcard, type: Cli::BadArgument) do
            "public_url is required with oauth when listening on #{uri.hostname}: URL used by clients, e.g. #{uri.scheme}://myhost:#{uri.port}"
          end
          URI.parse("#{uri.scheme}://#{wildcard ? 'localhost' : uri.host}:#{uri.port}").to_s
        end

        # Start HTTP transport, see Mcp::HttpServlet.
        # On an address that is not loopback, `auth_token` is mandatory, also with OAuth:
        # it is the secret asked on the consent page, else anyone could approve its own client.
        def start_http_transport(server, mcp_options)
          require 'aspera/cli/mcp/http_servlet'
          require 'aspera/web_server_simple'
          parameters        = http_server_parameters(mcp_options)
          uri               = WebServerSimple.url(parameters)
          auth_token        = mcp_options[:auth_token]
          oauth_enabled     = mcp_options.fetch(:oauth, false)
          access_token_ttl  = mcp_options.fetch(:oauth_access_token_ttl, OAuth::Server::Pkce.default_access_token_ttl)
          refresh_token_ttl = mcp_options.fetch(:oauth_refresh_token_ttl, OAuth::Server::Pkce.default_refresh_token_ttl)
          min_bits          = mcp_options.fetch(:auth_token_min_bits, SecretStrength::DEFAULT_MIN_BITS)
          SecretStrength.assert_strong(auth_token, name: 'auth_token', min_bits: min_bits, type: Cli::BadArgument) unless auth_token.nil?
          base_url = http_base_url(uri, mcp_options[:public_url], oauth_enabled)
          what = "auth_token#{' (asked on the consent page)' if oauth_enabled}"
          # Clients reach the server at public_url (e.g. through a reverse proxy), whatever the address it listens on
          unless mcp_options[:public_url].nil?
            public_host = URI.parse(base_url).hostname
            Aspera.assert(!auth_token.nil? || WebServerSimple.loopback?(public_host), type: Cli::BadArgument) do
              "#{what} is required when public_url is not loopback (localhost, 127.0.0.0/8, ::1): #{public_host}"
            end
          end
          WebServerSimple.serve(
            parameters,
            Cli::Mcp::HttpServlet,
            protected: !auth_token.nil?,
            what:      what,
            type:      Cli::BadArgument
          ) do
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
            [{
              app:             MCP::Server::Transports::StreamableHTTPTransport.new(server, **mcp_options.slice(*HTTP_KEYS)),
              server_info:     {name: server.name, version: server.version, description: server.description},
              web_secret:      web_secret,
              auth_token:      auth_token,
              oauth_server:    oauth_server,
              allowed_hosts:   mcp_options[:allowed_hosts],
              # Pages of the server (consent, secret) are opened at base_url, also behind a reverse proxy that changes Host
              allowed_origins: [*mcp_options[:allowed_origins], ServletHelpers.origin(base_url)]
            }]
          end
        end
      end
    end
  end
end
