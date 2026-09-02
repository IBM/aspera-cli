# ascli MCP Server — Test Guide

This guide explains how to run the live MCP validation session.

| File | Purpose |
|---|---|
| [`mcp-test-plan.md`](mcp-test-plan.md) | Full test plan: expected MCP calls, pass criteria, checklist |
| [`mcp-test-session.md`](mcp-test-session.md) | **The prompt to paste into the agent** |
| [`mcp-test-validation.md`](mcp-test-validation.md) | Second prompt to verify the agent's results |

---

## Step 1 — Prepare your environment

Fill in the placeholders in [`mcp-test-session.md`](mcp-test-session.md) before pasting.

| Placeholder | Replace with |
|---|---|
| `AOC_PRESET` | Name of your AoC preset, e.g. `aoc_admin` |
| `F5_PRESET` | Name of your Faspex 5 preset, e.g. `faspex5` |
| `RECIPIENT_EMAIL` | A valid email address to send a test package to |
| `AOC_FILE_PATH` | A path that exists in your AoC Files space, e.g. `/myfiles/report.pdf` |

---

## Step 2 — Open a clean agent session

1. **Change to a neutral working directory** (e.g. `~/Desktop` or `~`), not inside the
   `aspera-cli` source tree. Without a workspace pointing at the source tree, the agent
   has no automatic access to source files, YAML tests, or local docs.
2. Confirm that the `ascli` MCP server is registered in your AI client.
3. Make sure **no shell/terminal tool** and **no file-reader tool** pointing at the
   source tree is active in this session — the MCP tool must be the only path to
   `ascli` information.

---

## Step 3 — Run the session prompt

Copy the entire content of [`mcp-test-session.md`](mcp-test-session.md) and paste it
as your first message. The agent will work through all 20 tasks in order.

---

## Step 4 — Verify the results

After the agent has finished, copy the entire content of
[`mcp-test-validation.md`](mcp-test-validation.md) and paste it as a follow-up message
in the **same session**. The agent will self-assess each task against the expected
outcomes and produce a pass/fail report.
