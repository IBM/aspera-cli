# frozen_string_literal: true

# cspell:ignore ascli

require 'json'
require 'aspera/log'
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
      # Default maximum byte size of the JSON text content returned for list results.
      # Items are appended whole until the limit is reached; the full list is always
      # available in structuredContent.
      DEFAULT_MAX_TEXT_BYTES = 100_000
      # Default extra arguments automatically prepended to every ascli call.
      # Keeps the AI from having to remember mandatory flags on every invocation.
      DEFAULT_EXTRA_ARGS = ['--interactive=no', '--transfer.asynchronous=true'].freeze

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

        AUTOMATIC FLAGS
          The server automatically prepends extra_args to every call (default:
          --interactive=no and --transfer.asynchronous=true).
          Do NOT repeat these flags in your args array — they are already injected.
          If you explicitly need to override one (e.g. --interactive=yes), include it
          in your args; your value will take precedence because it appears after the
          injected ones.
          If credentials are missing or incomplete, the command will return an error;
          report it and stop, never wait for input.

        DISCOVERY — recommended sequence
          Step 1 — enumerate all commands:
            ["config", "commands"]
            Returns { syntax, description } for every leaf command of every plugin.
            Syntax notation: <arg> mandatory, [<arg>] optional, <a|b> enum, <arg...> variadic.
            This single call covers all 800+ commands — no other discovery step is needed
            unless you want details about a specific command or its Hash arguments.
            IMPORTANT: never guess command names from training data. If you are unsure of
            the exact subcommand name (e.g. shared_folders vs shared_inboxes), always call
            ["config", "commands"] first to find the correct name.

          Step 2 — inspect a Hash argument schema BEFORE calling any command with <data>:
            MANDATORY: whenever the command syntax shows a <data> argument, you MUST call
            "help" offline first. Never infer field names from server error messages.
            ["<plugin>", "<cmd>", ..., "help"]
            Replace the Hash positional argument with the literal string "help".
            Returns a table of field names, types, and descriptions for that argument.
            Example: ["aoc", "admin", "user", "create", "help"]
            Note: only works for Hash-typed arguments, not for plain String arguments.

          Step 2b — discover available query/filter parameters for list commands:
            ["<plugin>", "<cmd>", ..., "--query=help"]
            Add --query=help to any list command to see all supported filter parameters
            with their types and descriptions.
            Example: ["aoc", "admin", "user", "list", "--query=help"]
            Example: ["faspex5", "admin", "packages", "list", "--query=help"]
            Note: only works on commands that support --query filtering (list/delete).

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
          For list results, text content is limited to #{DEFAULT_MAX_TEXT_BYTES} bytes (whole items only).
          When truncated, a WARNING block is appended: "WARNING: result truncated to N of TOTAL items."
          You MUST read structuredContent.items to obtain the full dataset — never report
          counts, totals, or search results from a truncated text block.

        FILE LIST FOR TRANSFERS
          For all transfers (upload, download, package send, …), append source file paths
          at the end of the args array — no --sources flag needed.
          ["server", "upload", "--to-folder=/dst", "/local/file1", "/local/file2"]
          ["aoc", "packages", "send", "@:", "name=pkg", "recipients.0=user@example.com", "END",
           "/local/file1", "/local/file2"]

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
          ["server", "upload", "--url=https://host", "--username=user", "--password=secret",
           "--to-folder=/uploads", "/local/file1.txt", "/local/file2.txt"]
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
        attr_accessor :max_text_bytes, :extra_args

        def call(args:, server_context: nil)
          effective_args = Array(extra_args || DEFAULT_EXTRA_ARGS) + args
          Log.dump(:mcp_execute, effective_args)
          runner = Runner.new(effective_args)
          result = runner.run_with_result
          case result
          when Result::Nothing, Result::Empty, NilClass
            MCP::Tool::Response.new([{type: 'text', text: ''}])
          when Result::SingleObject, Result::ObjectList, Result::ValueList
            # Apply --select filter in place (affects both text and structuredContent).
            runner.context.formatter.filter_columns_on_select(result.data) if result.data.is_a?(Array)
            # MCP spec requires structuredContent to be a JSON object (not an array).
            structured = result.data.is_a?(Array) ? {items: result.data} : result.data
            content = if result.data.is_a?(Array)
              text_limit = max_text_bytes || DEFAULT_MAX_TEXT_BYTES
              truncated_items = truncate_items_by_bytes(result.data, text_limit)
              total = result.data.size
              if truncated_items.size < total
                [
                  {type: 'text', text: JSON.generate(truncated_items)},
                  {type: 'text', text: "WARNING: result truncated to #{truncated_items.size} of #{total} items. Full dataset available in structuredContent."}
                ]
              else
                [{type: 'text', text: JSON.generate(result.data)}]
              end
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

        # Returns the largest prefix of +items+ whose JSON serialization fits within +max_bytes+.
        # Items are appended whole — no item is ever split mid-JSON.
        def truncate_items_by_bytes(items, max_bytes)
          buf = +''
          items.each_with_index do |item, i|
            fragment = (i.zero? ? '[' : ',') + JSON.generate(item)
            break if buf.bytesize + fragment.bytesize + 1 > max_bytes # +1 for closing ']'
            buf << fragment
          end
          buf.empty? ? [] : JSON.parse("#{buf}]")
        end
      end
    end
  end
end
