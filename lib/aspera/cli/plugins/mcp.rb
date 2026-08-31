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
      #   max_items:              Integer - max items in text content of list results (default 100)
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

          Key plugins: aoc (Aspera on Cloud), faspex5 (Faspex 5), node (Node API),
          server (FASP/SSH server), config (local configuration), console, orchestrator,
          ats (Aspera Transfer Service), preview, shares, cos, httpgw, faspio, alee.

          Workflow tips:
          - Call ["config", "plugins", "list"] to enumerate available plugins.
          - Call ["<plugin>", "--help"] to list all actions of a plugin.
          - Credentials can be stored in named presets and referenced with --preset=name.
          - Call ["config", "preset", "list"] to list saved presets.
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
        TOOL_KEYS   = %i[max_items].freeze
        private_constant :SERVER_KEYS, :CONFIG_KEYS, :STDIO_KEYS, :HTTP_KEYS, :TOOL_KEYS

        command :server, description: 'Start the MCP (Model Context Protocol) server',
          arguments:   [ArgumentSpec.new(name: :mcp_options, type: [Hash], mandatory: false)]

        def action_server(mcp_options = nil)
          require 'aspera/cli/mcp_tool'
          mcp_options = (mcp_options || {}).transform_keys(&:to_sym)
          unknown = mcp_options.keys - SERVER_KEYS - CONFIG_KEYS - STDIO_KEYS - HTTP_KEYS - TOOL_KEYS - %i[transport port bind]
          raise Cli::BadArgument, "Unknown MCP option(s): #{unknown.join(', ')}" unless unknown.empty?
          Cli::McpTool.max_items = mcp_options.delete(:max_items)
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
