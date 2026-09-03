# frozen_string_literal: true

# cspell:ignore ascli jsonrpc

require 'aspera/cli/plugins/base'
require 'aspera/cli/info'
require 'aspera/cli/version'
require 'json'

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
          Refer to the tool description for full syntax, discovery steps, and examples.

          Key plugins: aoc (Aspera on Cloud), faspex5 (Faspex 5), node (Node API),
          server (FASP/SSH server), config (local configuration), console, orchestrator,
          ats (Aspera Transfer Service), preview, shares, cos, httpgw, faspio, alee.

          Recommended workflow for any task:
          1. Call ["config", "commands"] to map all 800+ commands to their syntax.
             Never guess subcommand names from training data — always verify with this call.
          2. For any command whose syntax shows a <data> argument, call it with "help"
             instead of the real value to see the full field schema before constructing
             the @json:{...} payload. This is mandatory — never infer fields from errors.
          2b. For any list command, add --query=help to discover available filter parameters.
              Example: ["aoc", "admin", "user", "list", "--query=help"]
          3. Call ["config", "options", "<plugin>"] to list every --flag accepted by a
             plugin with its allowed values (e.g. --auth=basic|oauth2|..., --url, --preset).
          4. When credentials are already saved, use --preset=name instead of inline
             credentials. Call ["config", "preset", "list"] to see saved presets.

          AUTOMATIC FLAGS
          The server automatically injects --interactive=no and --transfer.asynchronous=true
          before every command. Do NOT add them yourself — they are already applied.
          If credentials are missing, the command returns an error; report it and stop.
          The transfer agent defaults to "direct" (in-process ascp). To use the IBM Aspera
          Desktop Client for all transfers, the server can be started with extra_args including
          --transfer.agent=desktop:
            ascli mcp server @json:{"extra_args":["--interactive=no","--transfer.asynchronous=true","--transfer.agent=desktop"]}

          CREDENTIAL INTEGRITY
          Use saved presets by default — do not specify server address or credentials if a
          default preset is already configured, unless the user asks otherwise.
          Call ["config", "preset", "overview"] to check available presets.
          Some plugins support web-based authentication: the user logs in via a browser
          (use --auth=web or follow the wizard).
          If the user explicitly provides credentials inline (--url, --username, --password,
          --private-key), use those exact values verbatim — never silently substitute a
          preset or a different server. Report errors as-is and stop.

          TRANSFER OPTIONS
          Any flags explicitly requested by the user (--transfer.agent=<agent>, --to-folder,
          etc.) must be passed verbatim. Never omit or replace them.
          The agent is selected with "--transfer.agent=<agent>" (e.g. "--transfer.agent=desktop",
          "--transfer.agent=direct", "--transfer.agent=node").
          For a graphical transfer (IBM Aspera Desktop Client), use --transfer.agent=desktop.
          Because --transfer.asynchronous=true is injected automatically, transfer commands
          return a job_id immediately — never retry a command that already returned one.
          Async transfer lifecycle:
            submit  → e.g. ["server", "download", "/file", "--to-folder=/tmp"] → returns job_id
            monitor → ["config", "transfer", "status", "<job_id>"]
            list    → ["config", "transfer", "list"]
            cleanup → ["config", "transfer", "cleanup"]

          FILE LIST FOR TRANSFERS
          For all transfers (upload, download, package send, …), append source file paths
          at the end of the args array — no --sources flag needed.
          ["server", "upload", "--to-folder=/dst", "/local/a.txt", "/local/b.txt"]
          ["aoc", "packages", "send", "@:", "name=pkg", "recipients.0=u@example.com", "END",
           "/local/a.txt", "/local/b.txt"]
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
        private_constant :SERVER_KEYS, :CONFIG_KEYS, :STDIO_KEYS, :HTTP_KEYS, :TOOL_KEYS

        command :server, description: 'Start the MCP (Model Context Protocol) server',
          arguments:   [{name: :mcp_options, type: [Hash], mandatory: false, schema: 'opts:components.schemas.McpServerOptions'}]

        def action_server(mcp_options: nil, **)
          require 'aspera/cli/mcp_tool'
          mcp_options = (mcp_options || {}).transform_keys(&:to_sym)
          unknown = mcp_options.keys - SERVER_KEYS - CONFIG_KEYS - STDIO_KEYS - HTTP_KEYS - TOOL_KEYS - %i[transport port bind]
          Aspera.assert(unknown.empty?, type: Cli::BadArgument){"Unknown MCP option(s): #{unknown.join(', ')}"}
          Cli::McpTool.max_text_bytes = mcp_options.delete(:max_text_bytes)
          Cli::McpTool.extra_args     = mcp_options.delete(:extra_args)
          transport = mcp_options.delete(:transport) || 'stdio'
          raise Cli::BadArgument, "Unknown transport: #{transport}. Use 'stdio' or 'http'" \
            unless %w[stdio http].include?(transport.to_s)
          Log.log.info{"Starting MCP server (transport=#{transport})..."}
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

        # Start HTTP transport using WEBrick (already a project dependency).
        # Rack 3 removed Rack::Handler - we build a native WEBrick servlet that
        # calls the Rack app directly instead of relying on Rack::Handler::WEBrick.
        def start_http_transport(server, mcp_options)
          require 'webrick'
          http_opts = mcp_options.slice(*HTTP_KEYS)
          port      = mcp_options.fetch(:port, 3000)
          bind      = mcp_options.fetch(:bind, '127.0.0.1')
          app       = MCP::Server::Transports::StreamableHTTPTransport.new(server, **http_opts)
          rack_servlet = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
            define_method(:initialize) do |srv, rack_app, server_info|
              @app = rack_app
              @server_info = server_info
              super(srv)
            end
            %w[GET POST DELETE].each do |http_method|
              define_method(:"do_#{http_method}") do |req, res|
                # Serve a discovery endpoint on GET / (used by Bob and other MCP clients
                # to display server metadata without initiating a full MCP session).
                if http_method == 'GET' && req.path == '/'
                  body = JSON.generate(@server_info)
                  res.status = 200
                  res['Content-Type'] = 'application/json'
                  res.body = body
                  next
                end
                env = rack_env_from_webrick(req)
                status, headers, rack_body = @app.call(env)
                res.status = status
                headers.each{ |k, v| res[k] = v}
                if rack_body.respond_to?(:call)
                  # Rack streaming body (SSE): wrap the WEBrick socket in a stream object
                  # that exposes write/flush/close, then hand off a Proc to WEBrick so it
                  # calls us back with the raw socket once headers have been flushed.
                  rack_proc = rack_body
                  res.chunked = true
                  res.body = proc do |socket|
                    stream = Object.new
                    stream.define_singleton_method(:write){ |data| socket.write(data)}
                    stream.define_singleton_method(:flush){socket.flush rescue nil}
                    stream.define_singleton_method(:close){socket.close rescue nil}
                    rack_proc.call(stream)
                  end
                else
                  buf = +''
                  rack_body.each{ |chunk| buf << chunk}
                  rack_body.close if rack_body.respond_to?(:close)
                  res.body = buf
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
          webrick.mount('/', rack_servlet, app, server_info)
          Log.log.info{"MCP HTTP server listening on http://#{bind}:#{port}/"}
          trap('INT'){webrick.shutdown}
          trap('TERM'){webrick.shutdown}
          webrick.start
        end
      end
    end
  end
end
