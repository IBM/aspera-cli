# ascli MCP Server — Live Test Plan

This document describes the test plan for validating the `ascli` MCP server end-to-end
with a live AI assistant.
It focuses on scenarios a real human would ask when working with IBM Aspera through an
AI agent, including introspection, administration, file transfers, and package delivery.

> **Note**: tests are grouped by prerequisite level so you can stop at any tier if live
> credentials are unavailable.

---

## Prerequisites

| Requirement | Details |
|---|---|
| `ascli` installed | `ascli config gem version` prints a version string |
| `mcp` gem installed | `gem install mcp` |
| MCP-capable AI client | Bob, Claude Desktop, VS Code Copilot, … |
| AoC credentials (Tier 2) | Admin preset `aoc_admin` configured, or credentials at hand |
| Faspex 5 credentials (Tier 3) | Preset `faspex5` configured, or credentials at hand |
| Aspera Desktop Client installed (Tier 2) | Required for the desktop-agent download test |

---

## Tier 0 — Introspection (no live server needed)

These tests validate that the AI can discover and reason about `ascli` entirely through
the MCP tool, without any prior knowledge of the CLI.

### T0-1 · Tool visibility

**Human ask**: "What tools do you have available?"

**Expected**: the AI lists `execute_ascli_command` and describes it as running `ascli`
commands in-process.

**Pass criterion**: `execute_ascli_command` is named; the description mentions Aspera or
`ascli`.

---

### T0-2 · Full command catalogue

**Human ask**: "Give me a list of all commands supported by ascli."

**Expected MCP call**: `["config", "commands"]`

**Pass criterion**: the response includes commands from at least three plugins (`aoc`,
`faspex5`, `server`) with their argument syntax. The AI must not fabricate command names.

**Truncation check**: result has 800+ items. The AI should report the correct total by
reading `structuredContent`, not just the truncated text block.

---

### T0-3 · Hash schema discovery

**Human ask**: "What information do I need to provide to send a package on Faspex 5?"

**Expected MCP call**: `["faspex5", "packages", "send", "help"]`

**Pass criterion**: the AI returns the schema fields for the package data Hash, including
at minimum `title` and `recipients`.

---

### T0-4 · Option listing for a plugin

**Human ask**: "What authentication options does the AoC plugin support? List the allowed
values for each."

**Expected MCP call**: `["config", "options", "aoc"]`

**Pass criterion**: the AI reports `--auth` with its allowed values (e.g. `basic`,
`oauth2`, `web`, `jwt`) and documents `--url`, `--username`, `--private-key`.

---

### T0-5 · Documentation section retrieval

**Human ask**: "How do I configure a saved preset for Aspera on Cloud?"

**Expected MCP calls**:
1. `["config", "documentation", "toc"]` — find the relevant anchor
2. `["config", "documentation", "local", "<anchor>"]` — read the section

**Pass criterion**: the AI returns actionable steps (wizard or manual `config preset
update`) without reading the full README.

---

### T0-6 · Transfer agent catalogue

**Human ask**: "What transfer agents does ascli support? Describe each one briefly."

**Expected MCP call**: `["config", "agents", "list"]`

**Pass criterion**: the response lists at least `direct`, `node`, `connect`, `desktop`,
`transferd`, `httpgw` with a one-line description of each.

---

### T0-7 · Async transfer documentation

**Human ask**: "How does asynchronous transfer mode work in ascli? How do I start a
transfer and check its status later?"

**Expected MCP calls**:
- `["config", "documentation", "toc"]` to locate the async section
- `["config", "documentation", "local", "asynchronous-transfer-mode"]` to read it

**Pass criterion**: the AI explains the `--transfer.asynchronous=true` flag and the
`config transfer status <job_id>` / `config transfer list` / `config transfer cleanup`
lifecycle commands.

---

### T0-8 · Error handling

**Human ask**: "Run `ascli config options no_such_plugin_xyz`."

**Expected MCP call**: `["config", "options", "no_such_plugin_xyz"]`

**Pass criterion**: the AI surfaces the error message (plugin not found) without
crashing or inventing a workaround.

---

### T0-9 · Credential safety

**Human ask**: "Show me the current value of the password option."

**Pass criterion**: no real secret appears in plain text. The AI either reports that
it cannot retrieve sensitive values or returns a masked/redacted string.

---

## Tier 1 — Demo server (public, no account needed)

These tests use the Aspera public demo server: `ssh://eudemo.asperademo.com:33001`,
username `asperaweb`, password `demoaspera`.

### T1-1 · Browse the demo server

**Human ask**: "Browse the root of the Aspera demo server at
`ssh://eudemo.asperademo.com:33001` using username `asperaweb` and password `demoaspera`."

**Expected MCP call**:
```json
["server", "browse", "/",
 "--url=ssh://eudemo.asperademo.com:33001",
 "--username=asperaweb", "--password=demoaspera"]
```

**Pass criterion**: a file and folder listing is returned without errors.

---

### T1-2 · Download a file (direct agent)

**Human ask**: "Download the file `/aspera-test-dir-small/10KB.1` from the demo server
(same credentials) to `/tmp`."

**Expected MCP call**:
```json
["server", "download", "/aspera-test-dir-small/10KB.1",
 "--url=ssh://eudemo.asperademo.com:33001",
 "--username=asperaweb", "--password=demoaspera",
 "--to-folder=/tmp"]
```

**Pass criterion**: the AI reports a successful transfer. The file exists at `/tmp/10KB.1`.

---

### T1-3 · Server info

**Human ask**: "Show me system information about the demo server."

**Expected MCP call**:
```json
["server", "info",
 "--url=ssh://eudemo.asperademo.com:33001",
 "--username=asperaweb", "--password=demoaspera"]
```

**Pass criterion**: the AI returns server platform, OS, and version details.

---

## Tier 2 — IBM Aspera on Cloud (AoC credentials required)

> Provide the AI with your AoC URL and admin credentials, or a saved preset name such
> as `aoc_admin`.

### T2-1 · List admin users

**Human ask**: "List the admin users in my AoC organisation. Show their email and role."

**Expected MCP call** (example with preset):
```json
["aoc", "--preset=aoc_admin", "admin", "user", "list"]
```

**Pass criterion**: a table of users with `email` and `role` columns is returned.

---

### T2-2 · List workspaces

**Human ask**: "Show me all workspaces in my AoC organisation."

**Expected MCP call**:
```json
["aoc", "--preset=aoc_admin", "admin", "workspace", "list"]
```

**Pass criterion**: a list of workspace names and IDs is returned.

---

### T2-3 · Browse AoC Files

**Human ask**: "Browse my AoC Files home folder."

**Expected MCP call**:
```json
["aoc", "--preset=<preset>", "files", "browse", "/"]
```

**Pass criterion**: a file/folder listing is returned.

---

### T2-4 · Download a file using the Desktop Client agent

**Human ask**: "Download the file `<path>` from AoC Files to `/tmp`, using the Aspera
Desktop Client."

**Expected MCP call** (agent flag added by the AI):
```json
["aoc", "--preset=<preset>", "files", "download",
 "--to-folder=/tmp", "--transfer.agent=desktop", "<path>"]
```

**Pass criterion**: the Desktop Client handles the transfer; the AI reports success.
The Aspera Desktop Client must be running locally.

---

### T2-5 · AoC user schema introspection (no network call)

**Human ask**: "What fields do I need to create a new AoC user?"

**Expected MCP call**: `["aoc", "admin", "user", "create", "help"]`

**Pass criterion**: the AI identifies `email` as a required field and lists optional
fields such as `first_name`, `last_name`, `name`, `role`.

---

### T2-6 · List AoC packages

**Human ask**: "List the packages in my AoC inbox."

**Expected MCP call**:
```json
["aoc", "--preset=<preset>", "packages", "list"]
```

**Pass criterion**: a list of packages with title, sender, and date is returned.

---

## Tier 3 — IBM Aspera Faspex 5 (Faspex 5 credentials required)

> Provide the AI with your Faspex 5 URL and credentials, or a saved preset name such as
> `faspex5`.

### T3-1 · List Faspex 5 packages (inbox)

**Human ask**: "List the packages in my Faspex 5 inbox."

**Expected MCP call**:
```json
["faspex5", "--preset=faspex5", "packages", "list"]
```

**Pass criterion**: a list of packages is returned.

---

### T3-2 · Send a package (direct agent, asynchronous)

**Human ask**: "Send a test package titled 'AI test' to `<recipient_email>` on Faspex 5,
attaching the file `/tmp/10KB.1`. Use direct agent in asynchronous mode and give me the
job ID so I can check it later."

**Expected AI workflow**:
1. Discover the `packages send` schema: `["faspex5", "packages", "send", "help"]`
2. Discover the async transfer option: `["config", "agents", "parameters", "direct"]`
   or read the async documentation section
3. Start the transfer asynchronously:
```json
["faspex5", "--preset=faspex5", "packages", "send",
 "@json:{\"title\":\"AI test\",\"recipients\":[{\"name\":\"<recipient_email>\"}]}",
 "/tmp/10KB.1",
 "--transfer.agent=direct",
 "--transfer.asynchronous=true"]
```
4. Return the `job_id` to the user

**Pass criterion**: a `job_id` is returned; the package appears as in-progress or
completed in Faspex 5.

---

### T3-3 · Check async transfer status

**Human ask**: "What is the status of the transfer with job ID `<job_id>`?"

**Expected MCP call**: `["config", "transfer", "status", "<job_id>"]`

**Pass criterion**: the AI returns the current status (e.g. `completed`, `running`,
`failed`) for the given job.

---

### T3-4 · List async transfers and cleanup

**Human ask**: "Show me all pending or completed async transfer jobs, then clean up the
completed ones."

**Expected MCP calls**:
1. `["config", "transfer", "list"]` — returns all jobs
2. `["config", "transfer", "cleanup"]` — removes completed/failed entries

**Pass criterion**: the AI lists current jobs and confirms cleanup was performed.

---

### T3-5 · List shared inboxes

**Human ask**: "Show me all shared inboxes available on Faspex 5."

**Expected MCP call**:
```json
["faspex5", "--preset=faspex5", "shared_folders", "list"]
```

**Pass criterion**: a list of shared inbox names and IDs is returned.

---

## Tier 4 — Multi-step reasoning

These scenarios require the AI to chain several MCP calls and reason about intermediate
results, without being told which commands to use.

### T4-1 · AoC: create a user and add to a workspace

**Human ask**: "Create an AoC user with email `test-ai@example.com`, first name `Test`,
last name `AI`, then add them to the workspace named `Engineering`."

**Expected AI workflow** (minimum 4 calls):
1. `["aoc", "admin", "user", "create", "help"]` — inspect schema
2. `["aoc", "--preset=aoc_admin", "admin", "workspace", "list"]` — resolve name → id
3. `["aoc", "--preset=aoc_admin", "admin", "user", "create", "@json:{...}"]` — create
4. `["aoc", "--preset=aoc_admin", "admin", "workspace_membership", "create", "@json:{...}"]`

**Pass criterion**: the AI completes all four steps autonomously; the user appears in
the AoC admin console.

---

### T4-2 · Faspex 5: send, wait, and confirm

**Human ask**: "Send a package titled 'Confirmation test' to `<email>` on Faspex 5 with
the file `/tmp/10KB.1`, wait for it to complete, then confirm it arrived."

**Expected AI workflow**:
1. Schema discovery for send
2. Send the package (synchronous or async + poll)
3. `["faspex5", "--preset=faspex5", "packages", "list", "--box=outbox"]` — confirm sent

**Pass criterion**: the AI reports the package as sent and confirmed in the outbox.

---

## Checklist summary

| ID | Test | Tier | Live server needed |
|---|---|:---:|:---:|
| T0-1 | Tool visible to AI | 0 | — |
| T0-2 | Full command catalogue + truncation | 0 | — |
| T0-3 | Hash schema: `packages send help` | 0 | — |
| T0-4 | Plugin options: `aoc` auth values | 0 | — |
| T0-5 | Documentation section retrieval | 0 | — |
| T0-6 | Transfer agent catalogue | 0 | — |
| T0-7 | Async mode documentation | 0 | — |
| T0-8 | Error handling | 0 | — |
| T0-9 | Credential safety | 0 | — |
| T1-1 | Browse demo server | 1 | Demo (public) |
| T1-2 | Download from demo server (direct) | 1 | Demo (public) |
| T1-3 | Server info | 1 | Demo (public) |
| T2-1 | AoC: list admin users | 2 | AoC |
| T2-2 | AoC: list workspaces | 2 | AoC |
| T2-3 | AoC: browse Files | 2 | AoC |
| T2-4 | AoC: download via Desktop agent | 2 | AoC + Desktop Client |
| T2-5 | AoC: user schema (no network) | 2 | — |
| T2-6 | AoC: list packages | 2 | AoC |
| T3-1 | Faspex 5: list inbox | 3 | Faspex 5 |
| T3-2 | Faspex 5: send async (direct agent) | 3 | Faspex 5 |
| T3-3 | Faspex 5: check async status | 3 | Faspex 5 |
| T3-4 | Faspex 5: list + cleanup async jobs | 3 | Faspex 5 |
| T3-5 | Faspex 5: list shared inboxes | 3 | Faspex 5 |
| T4-1 | AoC: create user + add to workspace | 4 | AoC (admin) |
| T4-2 | Faspex 5: send, wait, confirm | 4 | Faspex 5 |
