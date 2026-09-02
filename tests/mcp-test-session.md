**Ground rules — read before starting:**

1. You must use **only** the `execute_ascli_command` MCP tool to answer every task.
   Do not use any shell tool, terminal, or `run_command`-style tool to call `ascli`
   directly on the command line.
2. Do not read any local file from the `aspera-cli` source tree (Ruby source files,
   YAML files, markdown docs, etc.). All information must come from MCP tool calls.
3. If you already know an answer from training data, still verify it through the MCP
   tool before reporting it — this session is a live validation, not a knowledge quiz.
4. For each task, state explicitly:
   - the MCP tool call(s) you made, with the exact arguments,
   - the result you received,
   - whether the task succeeded or was skipped (and why).

**Before starting the tasks**, use `["config", "preset", "list"]` to discover which
presets are configured. If a given plugin has a default preset in the default section, just do not specify url or credentials, as it will use the default ones.

You are helping me perform a set of Aspera file transfer and administration tasks
using the ascli tool available through the MCP server.

---

**Task 1 — Discover all available commands**

List all commands supported by ascli and tell me how many there are in total.
Make sure you report the correct total count, not just the first page of results.

---

**Task 2 — Understand the transfer agents**

List all transfer agents supported by ascli and give me a one-line description of each.

---

**Task 3 — Learn the async transfer workflow**

Explain how asynchronous transfer mode works in ascli.
What flag do I use to start a transfer asynchronously, and how do I check its status
or cancel it afterwards? Use the built-in ascli documentation to answer.

---

**Task 4 — Discover what I need to send a Faspex 5 package**

Without connecting to any server, tell me what fields are required to send a package
using the Faspex 5 plugin. Find the answer by inspecting the command's schema directly.

---

**Task 5 — Understand AoC authentication options**

What authentication modes does the AoC plugin support?
List all allowed values for the `--auth` option.

---

**Task 6 — Browse the Aspera demo server**

Look up the preset configured for the `server` plugin (`config preset list`), then
browse the root folder of the demo server using that preset.
Show me the directory listing.

---

**Task 7 — Download a file from the demo server**

Using the same `server` preset, download the file `/aspera-test-dir-small/10KB.1`
to `/tmp`.
Report whether the transfer succeeded.

---

**Task 8 — Show demo server information**

Using the same `server` preset, show me the system information for that server
(platform, OS version, and any relevant details).

---

**Task 9 — List AoC admin users**

Look up the preset configured for the AoC plugin (`config preset list`), then list all
users in the AoC organisation. Show at minimum their email address and role.

---

**Task 10 — List AoC workspaces**

Using the same AoC preset, list all workspaces in the organisation.

---

**Task 11 — Browse AoC Files**

Using the same AoC preset, browse my AoC Files home folder.
Show me what is there.

---

**Task 12 — Download a file from AoC using the Desktop Client**

Using the same AoC preset, download the first file you found in Task 11 to `/tmp`,
using the Aspera for Desktop Client as the transfer agent.
The Desktop Client must already be running locally.

---

**Task 13 — List packages in my AoC inbox**

Using the same AoC preset, list the packages in my AoC inbox.
Show the package name, sender, and date for each one.

---

**Task 14 — List Faspex 5 inbox**

Look up the preset configured for the Faspex 5 plugin, then list the packages currently
in my Faspex 5 inbox.

---

**Task 15 — Send a package on Faspex 5 using async mode**

Using the Faspex 5 preset you found earlier, send a package titled "AI validation test"
to the first recipient email you can find in the Faspex 5 user list (or use the current
user's own email if no list is available).
Use `faux:///test_payload?1k` as the source file (this is a built-in ascli test source
that generates 1 KB of data without needing a real file on disk).
Use the direct transfer agent in asynchronous mode.
Give me the job ID so I can check the status myself.

---

**Task 16 — Check the async transfer status**

What is the current status of the async transfer job from the previous task?
Use the job ID you just obtained.

---

**Task 17 — List and clean up async jobs**

Show me all async transfer jobs currently tracked by ascli.
Then clean up any jobs that are completed or failed.

---

**Task 18 — List Faspex 5 shared inboxes**

Using the Faspex 5 preset, list all shared inboxes (or shared folders) available.

---

**Task 19 — Multi-step: create an AoC user and add to a workspace**

Using the AoC preset you found earlier:

1. Inspect the schema for creating an AoC user to find out what fields are required.
2. Create a new AoC user with email `ai-test-mcp@example.com`, first name `AI`,
   last name `Test`.
3. Find the ID of the workspace named "Default" (or the first workspace in the list
   if "Default" does not exist).
4. Add the new user as a member of that workspace.

Do all four steps without asking me for extra information.

---

**Task 20 — Error handling check**

Run the ascli command to list options for a plugin named `no_such_plugin_xyz` and
tell me exactly what error message you get.
