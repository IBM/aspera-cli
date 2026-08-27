# frozen_string_literal: true

# cspell:ignore ascli

require 'json'
require 'aspera/cli/runner'
require 'aspera/cli/error'
begin
  require 'mcp'
rescue LoadError
  raise Cli::Error, "The 'mcp' gem is required. Install it with: gem install mcp"
end

module Aspera
  module Cli
    # MCP Tool: executes an ascli command in-process.
    class McpTool < MCP::Tool
      # Default maximum number of items returned in the text content of a list result.
      # The full list is always available in structuredContent.
      DEFAULT_MAX_ITEMS = 100

      tool_name 'execute_ascli_command'

      description <<~DESC.strip
        Execute any ascli (Aspera CLI) command in-process and return its result.

        SYNTAX: provide arguments as a JSON array of strings, exactly as on the command line.
        The first element is always the plugin (top-level command), followed by the action and
        any options. Options use the long form "--option=value". Extended value prefixes are
        supported: "@json:{...}", "@preset:name", "@env:VAR_NAME", "@file:path".

        DISCOVERY: call ["help"] for full usage text, or ["config", "plugins", "list"] to list
        all available plugins. Use ["<plugin>", "--help"] to list all actions of a plugin.

        RESULT FORMAT: structured data is always in structuredContent (a JSON object). The text
        content may be truncated to the first 20 items when the result is a list; use
        structuredContent for the complete dataset.

        AVAILABLE PLUGINS: aoc, faspex5, node, server, config, console, orchestrator, ats,
        preview, shares, cos, httpgw, faspio, alee.

        EXAMPLES:
          ["config", "gem", "version"]
          ["config", "plugins", "list"]
          ["server", "browse", "/", "--url=https://host", "--username=user", "--password=secret"]
          ["aoc", "packages", "list", "--workspace=MyWorkspace"]
          ["node", "info", "--url=https://node-host", "--username=user", "--password=pass"]
          ["faspex5", "packages", "list", "--url=https://faspex-host", "--username=user", "--password=pass"]
      DESC

      input_schema(
        properties: {
          args: {
            type:        'array',
            items:       {type: 'string'},
            minItems:    1,
            description: 'ascli arguments: first element is the plugin name, followed by action and --option=value flags'
          }
        },
        required: ['args']
      )

      class << self
        attr_accessor :max_items

        def call(args:, server_context: nil)
          result = Runner.new(args).run_with_result
          case result
          when Result::Nothing, Result::Empty, NilClass
            MCP::Tool::Response.new([{type: 'text', text: ''}])
          when Result::SingleObject, Result::ObjectList, Result::ValueList
            # MCP spec requires structuredContent to be a JSON object (not an array).
            structured = result.data.is_a?(Array) ? {items: result.data} : result.data
            # Truncate text content to avoid overwhelming the client; full data is in structuredContent.
            limit = max_items || DEFAULT_MAX_ITEMS
            text_data = result.data.is_a?(Array) ? result.data.first(limit) : result.data
            MCP::Tool::Response.new(
              [{type: 'text', text: JSON.generate(text_data)}],
              structured_content: structured
            )
          else
            MCP::Tool::Response.new([{type: 'text', text: result.data.to_s}])
          end
        rescue SystemExit => e
          MCP::Tool::Response.new([{type: 'text', text: "exited with status #{e.status}"}], error: !e.status.zero?)
        rescue => e
          MCP::Tool::Response.new([{type: 'text', text: "#{e.class}: #{e.message}"}], error: true)
        end
      end
    end
  end
end
