# frozen_string_literal: true

# cspell:ignore ascli

require 'json'
require 'aspera/cli/runner'
require 'aspera/cli/error'
unless defined?(MCP::Tool)
  begin
    require 'mcp'
  rescue LoadError
    raise Cli::Error, "The 'mcp' gem is required. Install it with: gem install mcp"
  end
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

        SYNTAX
          args is a JSON array of strings mirroring the CLI command line.
          Element 0 : plugin name (aoc, faspex5, node, server, config, …).
          Elements 1+: sub-commands, then --option=value flags in any order.
          Passing structured values: use an extended-value prefix on the relevant element:
            "@json:{...}"   — inline JSON object or array (use for Hash/Array arguments)
            "@preset:name"  — expand a saved credential preset
            "@env:VAR"      — read value from environment variable
            "@file:/path"   — read value from a file

        DISCOVERY — recommended sequence
          Step 1 — enumerate all commands:
            ["config", "commands"]
            Returns { syntax, description } for every leaf command of every plugin.
            Syntax notation: <arg> mandatory, [<arg>] optional, <a|b> enum, <arg...> variadic.
            This single call covers all 800+ commands — no other discovery step is needed
            unless you want details about a specific command or its Hash arguments.

          Step 2 — inspect a Hash argument schema (only when <data> appears in the syntax):
            ["<plugin>", "<cmd>", ..., "help"]
            Replace the Hash positional argument with the literal string "help".
            Returns a table of field names, types, and descriptions for that argument.
            Example: ["aoc", "admin", "user", "create", "help"]
            Note: only works for Hash-typed arguments, not for plain String arguments.

          Step 3 — list all options for a plugin as structured data:
            ["config", "options", "<plugin>"]
            Returns { option, description, allowed, deprecated } for every --flag
            accepted by that plugin (global + plugin-specific, ~80 entries).
            Use when you need to know the exact allowed values or find a specific flag.

          Full documentation:
            ["config", "documentation", "toc"]
            Returns the table of contents: { level, title, anchor } for every heading.
            ["config", "documentation", "local", "<anchor>"]
            Returns only the section matching that anchor (same slugs as GitHub).
            ["config", "documentation", "local", "--ui=text"]
            Returns the complete README (~300 KB). Use only when a specific section
            is insufficient and you need broader narrative context.

        RESULT FORMAT
          Structured data is always in structuredContent (a JSON object).
          When a list result exceeds #{DEFAULT_MAX_ITEMS} items, text content is truncated and
          a second text block is appended: "WARNING: result truncated to N of TOTAL items."
          Always use structuredContent for the complete dataset when truncation occurs.

        EXAMPLES
          ["config", "commands"]                       ← Step 1: full capability map
          ["aoc", "admin", "user", "create", "help"]   ← Step 2: schema of <data> Hash
          ["config", "options", "aoc"]                 ← Step 3: all --flags for aoc plugin
          ["config", "documentation", "toc"]           ← TOC of local README
          ["config", "documentation", "local",
           "leveraging-ai-assistance"]                 ← single README section by anchor
          ["aoc", "admin", "user", "create",
           '@json:{"email":"a@b.com","name":"Alice"}',
           "--url=https://org.ibmaspera.com", "--username=admin@org.com",
           "--password=secret"]
          ["server", "browse", "/",
           "--url=https://host", "--username=user", "--password=secret"]
          ["aoc", "packages", "list", "--workspace=MyWorkspace"]
          ["node", "info", "--url=https://node-host",
           "--username=user", "--password=pass"]
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
            content = if result.data.is_a?(Array) && result.data.size > limit
              total = result.data.size
              [
                {type: 'text', text: JSON.generate(result.data.first(limit))},
                {type: 'text', text: "WARNING: result truncated to #{limit} of #{total} items. Full dataset available in structuredContent."}
              ]
            else
              [{type: 'text', text: JSON.generate(result.data)}]
            end
            MCP::Tool::Response.new(content, structured_content: structured)
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
