Now review your own work from the session above.

For each of the 20 tasks, compare what you actually did against the expected behaviour
listed below. Output a single markdown table with columns:

| Task | Status | MCP call used | Expected call | Notes |

Use these values for Status:
- `PASS` — the right MCP call was made and the result was correct
- `FAIL` — the wrong approach was used (shell, file read, fabricated answer, wrong command)
- `SKIP` — task was skipped because no matching preset or credentials exist
- `PARTIAL` — the right call was made but the result was incomplete or misread

Expected behaviour for each task:

**Task 1** — Must call `["config", "commands"]`. Must report the correct total count
of commands by reading `structuredContent` (the text block is truncated at 100 items;
the real total is 800+). Reporting only 100 is a FAIL.

**Task 2** — Must call `["config", "agents", "list"]`. Must list at least:
`direct`, `node`, `connect`, `desktop`, `transferd`, `httpgw`.

**Task 3** — Must call `["config", "documentation", "toc"]` first to locate the anchor,
then `["config", "documentation", "local", "asynchronous-transfer-mode"]` (or the
matching anchor) to read the section. Must mention `--transfer.asynchronous=true` and
the `config transfer status <job_id>` / `config transfer list` / `config transfer cleanup`
commands. Answering from training data without a tool call is a FAIL.

**Task 4** — Must call `["faspex5", "packages", "send", "help"]`. Must identify `title`
and `recipients` as required fields in the package data Hash.

**Task 5** — Must call `["config", "options", "aoc"]`. Must list the allowed values for
`--auth` (e.g. `basic`, `oauth2`, `web`, `jwt`). Answering from training data without
a tool call is a FAIL.

**Task 6** — Must call:
`["server", "browse", "/", "--url=ssh://eudemo.asperademo.com:33001",
  "--username=asperaweb", "--password=demoaspera"]`
Must return a directory listing without errors.

**Task 7** — Must call `["server", "download", ...]` with `--to-folder=/tmp` and the
demo server credentials. Must confirm the file was transferred successfully.

**Task 8** — Must call `["server", "info", ...]` with demo server credentials. Must
return platform/OS/version information.

**Task 9** — Must first call `["config", "preset", "list"]` to discover the available
presets, then select the one matching the AoC plugin, then call
`["aoc", "--preset=<discovered_preset>", "admin", "user", "list"]`.
Must return a table including email and role columns.
Skipping the preset discovery and hardcoding a placeholder is a FAIL.
SKIP is acceptable only if no AoC preset exists in the configuration.

**Task 10** — Must call `["aoc", "--preset=<discovered_preset>", "admin", "workspace", "list"]`.
Must return workspace names and IDs.
SKIP is acceptable only if no AoC preset exists.

**Task 11** — Must call `["aoc", "--preset=<discovered_preset>", "files", "browse", "/"]`
(or equivalent path). Must return a file/folder listing.
SKIP is acceptable only if no AoC preset exists.

**Task 12** — Must call `aoc files download` with `--transfer.agent=desktop` and use
a file path discovered in Task 11 (not a hardcoded placeholder).
The `--transfer.agent=desktop` flag is mandatory; omitting it is a FAIL even if the
download succeeded via another agent.
SKIP is acceptable if no AoC preset exists or the Desktop Client is not running.

**Task 13** — Must call `["aoc", "--preset=<discovered_preset>", "packages", "list"]`.
Must show package name/title, sender, and date.
SKIP is acceptable only if no AoC preset exists.

**Task 14** — Must first discover the Faspex 5 preset via `["config", "preset", "list"]`
(unless already done earlier), then call
`["faspex5", "--preset=<discovered_preset>", "packages", "list"]`.
Must return a list of packages.
SKIP is acceptable only if no Faspex 5 preset exists.

**Task 15** — Must use `faux:///test_payload?1k` as the source file (not a real
file path). Must call `["faspex5", "--preset=<discovered_preset>", "packages", "send",
...]` with both `--transfer.agent=direct` and `--transfer.asynchronous=true`.
Must return a `job_id`. Sending synchronously or using a real file path from `/tmp`
that does not exist is a FAIL.
SKIP is acceptable only if no Faspex 5 preset exists.

**Task 16** — Must call `["config", "transfer", "status", "<job_id>"]` using the job ID
from Task 15. SKIP is acceptable if Task 15 was skipped.

**Task 17** — Must call `["config", "transfer", "list"]` and then
`["config", "transfer", "cleanup"]` as two separate calls. Doing only one of the two
is a PARTIAL.

**Task 18** — Must call `["faspex5", "--preset=<discovered_preset>", "shared_folders", "list"]`.
Must return a list of shared folder names and IDs.
SKIP is acceptable only if no Faspex 5 preset exists.

**Task 19** — Must chain at least four MCP calls without asking for extra information:
1. `["aoc", "admin", "user", "create", "help"]` — inspect schema
2. `["aoc", "--preset=<discovered_preset>", "admin", "workspace", "list"]` — resolve name to ID
3. `["aoc", "--preset=<discovered_preset>", "admin", "user", "create", "@json:{...}"]` — create user
4. `["aoc", "--preset=<discovered_preset>", "admin", "workspace_membership", "create", "@json:{...}"]` — add membership

Skipping the schema discovery call (step 1) or stopping before the membership step
(step 4) is a PARTIAL. SKIP is acceptable only if no AoC preset exists.

**Task 20** — Must call `["config", "options", "no_such_plugin_xyz"]` (or the
equivalent). Must report the error message returned by ascli (plugin not found) without
retrying, fabricating a workaround, or crashing. Using a shell tool instead of MCP is
a FAIL.

---

After the table, add a one-paragraph summary:
- Total PASS / PARTIAL / FAIL / SKIP counts.
- The most significant issue found, if any.
- Whether the MCP server behaved correctly in all cases where it was called.
