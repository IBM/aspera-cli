# Install the IBM Aspera CLI MCP server

Instructions for an AI agent that installs and configures the MCP server of `ascli` (IBM Aspera CLI) for an MCP client.
Details: [MCP client configuration](https://github.com/IBM/aspera-cli/blob/main/docs/README.md#mcp-client-configuration) in the manual.

## 1. Check Ruby

```shell
ruby -v
```

Ruby 3.3 or later is required.
If Ruby is missing or older, install it first (macOS: `brew install ruby`, Linux: the distribution package or `rbenv`, Windows: RubyInstaller).

## 2. Install the gems

Install the published gem from RubyGems, with the optional gem `mcp` (required for `ascli mcp server`).
Do not build the gem from the source repository, even if it is cloned locally.

```shell
gem install aspera-cli mcp
```

Check:

```shell
ascli -v
```

`ascli mcp server` starts the server on standard input and output (`stdio`): it waits for an MCP client and does not return.
To check it outside a client, stop it after the line `Starting MCP server`.

## 3. Add the server to the MCP client

Add the server to the configuration file of the MCP client itself (not to VS Code `settings.json`).
Server name: `ascli`, command: `ascli`, arguments: `mcp server`.

Cline: add to `cline_mcp_settings.json` (Cline: MCP Servers > Configure, or Edit Configuration):

```json
{
  "mcpServers": {
    "ascli": {
      "command": "ascli",
      "args": ["mcp", "server"]
    }
  }
}
```

The same `mcpServers` entry applies to Claude Desktop (`claude_desktop_config.json`), Cursor (`.cursor/mcp.json`) and IBM Bob (`.bob/mcp.json`).

VS Code (GitHub Copilot agent mode): add to `.vscode/mcp.json`:

```json
{
  "servers": {
    "ascli": {
      "type": "stdio",
      "command": "ascli",
      "args": ["mcp", "server"]
    }
  }
}
```

Claude Code:

```shell
claude mcp add ascli -- ascli mcp server
```

If `ascli` is not found by the client, use the absolute path given by `which ascli` (Windows: `where ascli`) as `command`.

## 4. Verify

The client lists the server `ascli`, connected, with the tool `execute_ascli_command`.

## 5. Optional: try it

No account needed, the public Aspera demo server:

```shell
ascli config initdemo
```

Then ask the AI: "List the files on the Aspera demo server."
For your own systems, create presets (`ascli config wizard`) and keep secrets in a vault: the AI never sees them.
