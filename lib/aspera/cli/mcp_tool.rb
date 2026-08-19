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
      tool_name 'execute_ascli_command'

      description <<~DESC.strip
        Execute an ascli (Aspera CLI) command in-process.
        Provide arguments exactly as on the command line, but as a JSON array of strings.
        Structured results are returned in structuredContent.
        Refer to `ascli` manual for full options and syntax.
        Examples:
          ["config", "gem", "version"]
          ["config", "plugins", "list"]
          ["server", "browse", "/", "--url=https://host", "--username=user", "--password=secret"]
      DESC

      input_schema(
        properties: {
          args: {
            type:        'array',
            items:       {type: 'string'},
            minItems:    1,
            description: 'ascli arguments, e.g. ["aoc", "packages", "list"]'
          }
        },
        required: ['args']
      )

      class << self
        def call(args:, server_context: nil)
          result = Runner.new(args).run_with_result
          case result
          when Result::Nothing, Result::Empty, NilClass
            MCP::Tool::Response.new([{type: 'text', text: ''}])
          when Result::SingleObject, Result::ObjectList, Result::ValueList
            # MCP spec requires structuredContent to be a JSON object (not an array).
            structured = result.data.is_a?(Array) ? {items: result.data} : result.data
            # Truncate text content to avoid overwhelming the client; full data is in structuredContent.
            text_data = result.data.is_a?(Array) ? result.data.first(20) : result.data
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
