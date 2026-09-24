# frozen_string_literal: true

# cspell:ignore ascli

require 'json'
require 'aspera/log'
require 'aspera/secret_hider'
require 'aspera/cli/runner'
require 'aspera/cli/error'
require 'aspera/schema/reader'
require 'aspera/schema/registry'
unless defined?(MCP::Tool)
  begin
    require 'mcp'
  rescue LoadError
    raise Cli::Error, "The 'mcp' and 'rack' gems are required. Install them with: gem install mcp rack"
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
          Elements 1+: sub-commands, positional arguments, and --option=value flags in any order.
          Structured values use an extended-value prefix on the relevant element:
            "@json:{...}"   — inline JSON object or array (preferred: no shell quoting)
            "@preset:name"  — expand a saved preset
            "@env:VAR"      — read value from environment variable
            "@file:/path"   — read value from a file

        AUTOMATIC FLAGS
          The server prepends extra_args to every call (default: #{DEFAULT_EXTRA_ARGS.join(' ')}).
          Do NOT repeat them. To override one, include it in args: later values take precedence.
          Commands never prompt: if credentials are missing, an error is returned; report it and stop.

        DISCOVERY — never guess command or field names from training data
          Step 1 — commands of a plugin, with syntax:
            ["config", "commands", "<plugin>"]
            Returns { syntax, description } for every command of that plugin.
            Notation: <arg> mandatory, [<arg>] optional, <a|b> enum, <arg...> variadic, <arg:Hash> typed.
            A line ending with <command...> and "(see: <plugin> <path>)" provides the commands of that path:
            list them with ["config", "commands", "<plugin>", "<command>", ...] (command words only).
            Omit <plugin> to list the commands of all plugins (large).
          Step 2 — schema of a Hash argument (shown <name:Hash>), MANDATORY before calling such a command:
            ["<plugin>", "<cmd>", ..., "help"]
            Put the literal "help" in place of the Hash argument. Returns field names, types,
            required flags and descriptions. Never infer fields from server error messages.
          Step 2b — filter parameters of a list command:
            ["<plugin>", "<cmd>", ..., "--query=help"]
          Step 3 — all --flags of a plugin, with allowed values:
            ["config", "options", "<plugin>"]
          Documentation:
            ["config", "documentation", "toc"]              → { level, title, anchor } per heading
            ["config", "documentation", "local", "<anchor>"] → one README section
          Presets (saved credentials):
            ["config", "preset", "overview"]

        RESULT FORMAT
          Structured data is always in structuredContent (a JSON object; lists are under "items").
          For lists, text content is limited to #{DEFAULT_MAX_TEXT_BYTES} bytes (whole items only);
          when truncated, a WARNING line gives the real total. Read structuredContent.items for
          the full dataset — never report counts or search results from a truncated text block.

        FILE LIST FOR TRANSFERS
          For all transfers (upload, download, package send, …), append source paths at the
          end of args — no --sources flag needed.

        EXAMPLES
          ["config", "commands", "aoc"]
          ["aoc", "admin", "user", "create", "help"]
          ["config", "options", "aoc"]
          ["config", "documentation", "local", "leveraging-ai-assistance"]
          ["aoc", "--preset=myaoc", "packages", "list"]
          ["aoc", "--preset=myaoc", "admin", "user", "create", '@json:{"email":"a@b.com","name":"Alice"}']
          ["aoc", "--preset=myaoc", "packages", "send",
           '@json:{"name":"pkg","recipients":["user@example.com"]}', "/local/a.txt", "/local/b.txt"]
          ["server", "--preset=myserver", "upload", "--to-folder=/uploads", "/local/a.txt"]
          ["server", "browse", "/", "--url=ssh://host:33001", "--username=user", "--password=secret"]
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
            # Secrets never reach the AI client, whatever the output format requested in args.
            SecretHider.instance.deep_remove_secret(result.data)
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
            MCP::Tool::Response.new([{type: 'text', text: SecretHider.instance.hide_secrets_in_string(result.data.to_s, all: true)}])
          end
        rescue Cli::SchemaRequest => e
          schema_path = e.path
          if schema_path.nil?
            MCP::Tool::Response.new([{type: 'text', text: "#{e.class}: #{e.message} (no schema available)"}], error: true)
          else
            rows = schema_to_rows(Schema::Registry.instance.reader(schema_path))
            structured = {items: rows}
            MCP::Tool::Response.new([{type: 'text', text: JSON.generate(rows)}], structured_content: structured)
          end
        rescue SystemExit => e
          MCP::Tool::Response.new([{type: 'text', text: "exited with status #{e.status}"}], error: !e.status.zero?)
        rescue => e
          MCP::Tool::Response.new([{type: 'text', text: "#{e.class}: #{dedupe_lines(e.message)}"}], error: true)
        end

        # Delegate to Schema::Reader#to_rows — semantic fields, no ANSI, MCP/JSON-ready.
        def schema_to_rows(reader)
          reader.to_rows
        end

        # Collapse consecutive duplicate lines in a multi-line message.
        # Each run of identical lines is replaced by one line + "(×N)" suffix when N > 1.
        def dedupe_lines(msg)
          return msg unless msg.include?("\n")
          msg.split("\n").chunk_while { |a, b| a == b }.map do |group|
            group.size > 1 ? "#{group.first} (x#{group.size})" : group.first
          end.join("\n")
        end

        # Returns the largest prefix of `items` whose JSON serialization fits within `max_bytes`.
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
