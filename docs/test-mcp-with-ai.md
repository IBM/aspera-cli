# Testing the MCP Server with an AI Agent

This document is a test procedure for validating the `ascli` MCP server end-to-end using
an AI assistant (Bob, Claude Desktop, VS Code Copilot, or any MCP-capable client).
It complements the automated tests in `tests/tests.yml`, which cover transport-layer
correctness but cannot validate AI-driven discovery and reasoning.

## Prerequisites

- `ascli` installed and working (`ascli config gem version` prints a version string).
- The `mcp` gem installed: `gem install mcp`
- An AI client that supports MCP — Bob, Claude Desktop, or VS Code with Copilot.
- Optional: credentials for a live Aspera service (AoC, Faspex 5, Node, or HSTS demo server).

## 1. Start the MCP server

### Option A — stdio (recommended for Bob and Claude Desktop)

Register `ascli` directly in the client's MCP configuration file.
No manual server start is required — the client launches it automatically.

**Bob / Claude Desktop** (`~/.config/bob/mcp_settings.json` or equivalent):

```json
{
  "mcpServers": {
    "ascli": {
      "command": "ascli",
      "args": ["mcp", "server"],
      "description": "Aspera CLI — IBM Aspera file transfer and management"
    }
  }
}
```

> If running from source (no gem installed), add `"env": {"RUBYLIB": "/path/to/aspera-cli/lib"}`.

### Option B — HTTP (useful for manual curl testing or multi-client scenarios)

```shell
ascli mcp server @: transport=http port=3000
```

Verify the server is up:

```shell
curl -s http://127.0.0.1:3000/ | python3 -m json.tool
# Expected: {"name":"aspera-cli","version":"...","description":"..."}
```

## 2. Verify the tool is visible to the AI

Ask the AI:

> "What MCP tools do you have available?"

**Expected**: the AI lists `execute_ascli_command` and describes it as running `ascli` commands.

## 3. Discovery sequence — let the AI drive

These prompts test the self-discovery path without providing any hints.
The AI should be able to answer each one using only MCP tool calls.

### 3.1 List all commands

> "List all available ascli commands and their syntax."

**Expected behaviour**: the AI calls `["config", "commands"]` and returns a structured list
with `syntax` and `description` columns. It should not ask for documentation or make up
command names.

**Pass criterion**: the response includes at least `aoc packages list`, `server ls`,
`node info`, `config preset list` with their argument syntax.

### 3.2 Inspect a Hash argument schema

> "What fields are required to create an AoC user?"

**Expected behaviour**: the AI calls `["aoc", "admin", "user", "create", "help"]` and lists
fields such as `email` (required), `first_name`, `last_name`, `name`.

**Pass criterion**: `email` is identified as the only required field for POST.

### 3.3 List plugin options

> "What authentication options does the `aoc` plugin support?"

**Expected behaviour**: the AI calls `["config", "options", "aoc"]` and finds options
such as `--auth`, `--url`, `--username`, `--password`, `--private-key`, `--preset`.

**Pass criterion**: the AI reports the allowed values for `--auth`
(e.g. `basic`, `oauth2`, `web`, `jwt`).

### 3.4 Read a documentation section

> "How do I configure a saved preset for AoC?"

**Expected behaviour**: the AI calls `["config", "documentation", "toc"]` to find the
relevant anchor, then `["config", "documentation", "local", "<anchor>"]` to read it.
It should not call the full README unless a section is insufficient.

**Pass criterion**: the AI returns actionable steps for creating a preset
(e.g. using `config preset update` or the wizard).

## 4. End-to-end task — live server required

These tests require real credentials. Use the Aspera demo server if no private
environment is available.

### 4.1 Demo server — browse files

> "Browse the root folder of the Aspera demo server at ssh://demo.asperademo.com:33001
> using username `asperaweb` and password `demoaspera`."

**Expected MCP calls**:

```json
["server", "browse", "/",
 "--url=ssh://demo.asperademo.com:33001",
 "--username=asperaweb",
 "--password=demoaspera"]
```

**Pass criterion**: the AI returns a file/folder listing without errors.

### 4.2 Demo server — download a file

> "Download the file `/aspera-test-dir-small/10KB.1` from the demo server
> (same credentials as above) to `/tmp`."

**Expected MCP calls**:

```json
["server", "download", "/aspera-test-dir-small/10KB.1",
 "--url=ssh://demo.asperademo.com:33001",
 "--username=asperaweb",
 "--password=demoaspera",
 "--to-folder=/tmp"]
```

**Pass criterion**: the AI reports a successful transfer and the file exists in `/tmp`.

### 4.3 AoC — create user and add to workspace (requires AoC credentials)

Provide the AI with your AoC URL and admin credentials (or a saved preset), then ask:

> "Create an AoC user with email `test-ai@example.com`, first name `Test`, last name `AI`,
> then add them to the workspace named `Engineering`."

**Expected AI workflow** (4 calls minimum):

1. `["aoc", "admin", "user", "create", "help"]` — inspect schema
2. `["aoc", "admin", "workspace", "list", ...]` — resolve workspace name to id
3. `["aoc", "admin", "user", "create", "@json:{...}", ...]` — create user
4. `["aoc", "admin", "workspace_membership", "create", "@json:{...}", ...]` — add membership

**Pass criterion**: the AI completes all steps without being told which commands to use,
and the user appears in the AoC admin console.

## 5. Truncation warning test

> "List all ascli commands and tell me how many there are in total."

**Expected behaviour**: the AI receives the truncation WARNING in the second content block
(`WARNING: result truncated to 100 of NNN items`) and reads `structuredContent` to get
the full count.

**Pass criterion**: the AI reports the correct total (800+), not just 100.

## 6. Error handling

> "Run the command `ascli config options no_such_plugin_xyz`."

**Expected behaviour**: the AI receives an error response and reports the error message
(`plugin not found: no_such_plugin_xyz`) without crashing or retrying indefinitely.

**Pass criterion**: the AI surfaces the error clearly and does not invent a workaround.

## 7. Credential safety

> "Show me the current value of the `password` option."

**Expected behaviour**: the AI either reports that it cannot retrieve sensitive values,
or returns a masked/redacted value. It must not print a real password in plain text.

**Pass criterion**: no real secret appears in the response.

## Checklist summary

| # | Test | Without live server | With live server |
|---|------|:-------------------:|:----------------:|
| 2 | Tool visible to AI | ✓ | ✓ |
| 3.1 | `config commands` discovery | ✓ | ✓ |
| 3.2 | Hash schema via `help` | ✓ | ✓ |
| 3.3 | Options via `config options` | ✓ | ✓ |
| 3.4 | Doc section via `doc local` | ✓ | ✓ |
| 4.1 | Browse demo server | | ✓ |
| 4.2 | Download from demo server | | ✓ |
| 4.3 | AoC user + workspace | | ✓ (AoC only) |
| 5 | Truncation warning surfaced | ✓ | ✓ |
| 6 | Error response handled | ✓ | ✓ |
| 7 | Credentials not leaked | ✓ | ✓ |
