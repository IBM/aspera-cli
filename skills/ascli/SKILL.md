---
name: ascli
description: 'Operate IBM Aspera products with the ascli command line: Aspera on Cloud, Faspex 5, High-Speed Transfer Server, Node API, Shares, Console, Orchestrator, Cloud Object Storage. Use when the user wants to transfer files with FASP (ascp), send or receive packages, browse or manage remote files, administer users, workspaces, nodes or access keys, analyze ascp logs, or develop Orchestrator or Aspera on Cloud Automation workflows.'
license: Apache-2.0
compatibility: Requires the ascli command (Ruby gem aspera-cli) in the shell, or the ascli MCP server.
---

# ascli: command line interface for IBM Aspera

> `ascli` (Ruby gem `aspera-cli`) is the command line interface for IBM Aspera products.
> An AI assistant that can run a shell command, or that is connected to the `ascli` MCP server, can use it to operate these products for the user:
> transfer files with the FASP protocol (`ascp`), send and receive packages, browse and manage remote files, and administer the applications (users, groups, workspaces, nodes, access keys, workflows).

If the user asks for something that involves an IBM Aspera product, and `ascli` is available, use it: do not write calls to the REST APIs by hand.

## Products and plugins

The first word after `ascli` is a plugin: one per product.

- `aoc`: IBM Aspera on Cloud (files, packages, administration, Automation workflows)
- `faspex5`: IBM Aspera Faspex 5 (packages, shared inboxes, administration)
- `server`: IBM Aspera High-Speed Transfer Server, over SSH (browse, upload, download, `ascp` logs)
- `node`: Node API of a transfer server (files, access keys, transfers, sync)
- `shares`: IBM Aspera Shares
- `console`: IBM Aspera Console
- `orchestrator`: IBM Aspera Orchestrator (workflows, work orders, plugins, development guide)
- `ats`: IBM Aspera Transfer Service
- `cos`: IBM Cloud Object Storage
- `httpgw`, `faspio`, `alee`: HTTP Gateway, faspio Gateway, license entitlement
- `preview`: generation of previews of files
- `transferd`: Transfer Daemon of the Transfer SDK (install, service)
- `config`: local configuration: presets, secrets (`vault`), `ascp`, documentation
- `mcp`: Model Context Protocol server

## Two ways to use it

- Shell: run `ascli <plugin> <command...> [arguments] [--option=value]`.
  Add `--interactive=no` so that a missing value is an error instead of a prompt, and `--format=json` to get results as JSON.
- MCP: the user starts `ascli mcp server` (transport `stdio` or `http`). It provides one tool, `execute_ascli_command`, whose argument `args` is the command line as an array of strings.
  The description of the tool repeats the rules below.

## Discover, do not guess

Command names, argument fields and options differ between plugins and versions: read them from the tool itself.

1. Commands of a plugin, with their syntax: `ascli config commands <plugin>`. Sub-commands of a path: `ascli config commands <plugin> <command...>`.
2. Fields of a structured argument (shown `<name:Hash>` in the syntax): put the word `help` in place of the argument, e.g. `ascli aoc admin user create help`.
3. Filter parameters of a list command: `--query=help`.
4. Options of a plugin, with allowed values: `ascli config options <plugin>`.
5. Manual: `ascli config documentation toc` lists the sections (level, title, anchor), `ascli config documentation local <anchor>` displays one section.

## Workflow development

Before writing or modifying a workflow, read the development guide with `ascli`: it is large, so list its sections with `toc`, then read the ones needed with `section <anchor>`. No connection to the product is needed.

- IBM Aspera Orchestrator: `ascli orchestrator workflows development guide toc`, then `ascli orchestrator workflows development guide section <anchor>` (start with `quick-start` and `authoring-checklist`).
  Other documents: `templates` (Action Template Reference) and `manual` (Plugin Manual), with the same `toc` and `section`.
  Specification of an action plugin (template attributes, inputs, outputs): `ascli orchestrator plugins spec toc`, then `ascli orchestrator plugins spec show <plugin>`.
  Check a workflow file before importing it, and fix all errors: `ascli orchestrator workflows check_import <file>`.
- IBM Aspera on Cloud Automation: `ascli aoc automation guide toc`, then `ascli aoc automation guide section <anchor>`.
  Start with the section of each trigger and action used (for example, "Send a package" is action type `package_transfer`, section `package-transfer`),
  then `payload-rules-enforced-by-the-api` and `finding-the-identifiers`.

## Rules

- Structured values: `@json:{...}` (preferred), or `@: key=value key2.sub=value`. See section `extended-value-syntax` of the manual.
- Extended values inside JSON (e.g. a vault secret in a parameter file): write `"@vault:<label>.<field>@"` (closing `@`) in the file, and give `@json:@extend:@file:<path>`. Without `@extend:`, or without the closing `@`, the value stays a literal string. Check with `ascli config echo`.
- Credentials: saved in presets. List them with `ascli config preset overview`, select one with `--preset=<name>`; a plugin may have a default preset.
- Secrets: never ask the user to type a secret in the conversation. Use a preset, the vault (`@vault:<label>.<field>`), or `@secret:<name>`, which asks the user outside of the conversation. Values of secrets are hidden in results.
- Results: filter and reshape with `--out.query` (JMESPath), `--out.select` and `--out.fields`, instead of post-processing a large output.
- Transfers: source paths are the last arguments, the destination is `--to-folder=<path>`, other transfer parameters are in `--ts=@json:{...}` (schema: `ascli config ascp spec`).
- Exit code: `0` success, other values give the category of error (usage, authentication, not found, transfer, network): see `ascli -h`.
- Show the user the command line that was executed.

## Examples

```shell
ascli config commands faspex5
ascli faspex5 packages send help
ascli faspex5 packages send @json:'{"title":"Report","recipients":["user@example.com"]}' /path/to/file.pdf
ascli aoc files browse / --format=json
ascli server upload /path/to/file --to-folder=/Upload
ascli config ascp logs diagnostics /path/to/aspera-scp-transfer.log
```

## Documentation

- [Manual](https://raw.githubusercontent.com/IBM/aspera-cli/refs/heads/main/docs/README.md): complete reference, in Markdown (large: read sections with `config documentation`)
- [Release notes](https://raw.githubusercontent.com/IBM/aspera-cli/refs/heads/main/CHANGELOG.md)
- [Testing the MCP server with an AI agent](https://raw.githubusercontent.com/IBM/aspera-cli/refs/heads/main/docs/test-mcp-with-ai.md)
- [Source](https://github.com/IBM/aspera-cli)
