# Architecture Documentation

## Overview

The IBM Aspera CLI (`ascli`) is a Ruby-based command-line interface that provides unified access to IBM Aspera's high-speed file transfer products and services. The architecture follows a modular, plugin-based design that separates concerns between command processing, API communication, and transfer execution.

## System Architecture

![Architecture Diagram](architecture.png)

The architecture diagram illustrates the layered structure of `ascli` and its interactions with external components.

## Architectural Layers

### Local System Layer

The foundation layer consists of the local execution environment:

- **Operating System**: Cross-platform support (Linux, macOS, Windows)
- **Ruby Runtime**: Ruby ≥ 3.1 interpreter (CI tests 3.1 → 4.0 and JRuby)
- **Ruby Gems**: Third-party dependencies managed via Bundler
- **Transfer Agents**: Multiple FASP client implementations
  - `ascp` (client): The core FASP protocol implementation
  - Transfer SDK (trSDK): gRPC-based transfer daemon
  - Connect: Browser-based transfer client
  - HTTPGW: HTTP Gateway for firewall-friendly transfers
  - Desktop: Aspera Desktop Client integration
  - Node: Direct Node API transfers

### Core Application Layer (`aspera-cli` gem)

The central green component in the diagram represents the Ruby gem that implements all CLI functionality.

#### Entry Point

**File**: [`bin/ascli`](../bin/ascli)

The main executable script that:

- Sets up UTF-8 encoding for internationalization
- Pre-parses early logging options before full initialization: `--log-level` / `--log.level`, `--log-format` / `--log.format`, `--logger` / `--log.type`
- Loads optional code coverage (`aspera/coverage`)
- Fixes the home directory on Windows via `Environment.instance.fix_home`
- Delegates to the main CLI processor

```ruby
#!/usr/bin/env ruby
# Pre-parses logging options before full initialization
ARGV.each { |arg| ... }
require 'aspera/coverage'
require 'aspera/environment'
require 'aspera/cli/runner'
Aspera::Environment.instance.fix_home
Aspera::Cli::Runner.new(ARGV).run
```

#### Runner and Context

**Files**: [`lib/aspera/cli/runner.rb`](../lib/aspera/cli/runner.rb), [`lib/aspera/cli/context.rb`](../lib/aspera/cli/context.rb)

The `Runner` class orchestrates the full command lifecycle:

- **`run`**: Main entry point — calls `run_with_result`, displays the result via `Formatter`, handles all exceptions, and exits with the appropriate status code.
- **`run_with_result`**: Pure computation entry point — initializes all agents and options, resolves the target plugin, executes the action, and returns a `Result` object. Raises on error. Used by the MCP server ([`mcp_tool.rb`](../lib/aspera/cli/mcp_tool.rb)) to run commands in-process.

All shared objects are held in a `Context` instance and passed to plugins by reference.
Members: `options` (`Parser`), `transfer` (`TransferAgent`), `config` (`Plugins::Config`), `formatter`, `persistency`, `man_header`, `presets` (`PresetManager`), `http_config`, `main_folder`, `mailer` (`Mailer`), `secret_finder`, plus `progress_bar`, `pac_executor` and `help_requested`.

#### CLI Options

**Files**:

- [`parser.rb`](../lib/aspera/cli/parser.rb) — `Cli::Parser`: command-line argument processing, `get_next_command`, `get_next_argument`, `instance_identifier`
- [`option_declarator.rb`](../lib/aspera/cli/option_declarator.rb), [`option_registry.rb`](../lib/aspera/cli/option_registry.rb), [`option_value.rb`](../lib/aspera/cli/option_value.rb), [`option_types.rb`](../lib/aspera/cli/option_types.rb) — option declaration, storage and type validation
- [`extended_value.rb`](../lib/aspera/cli/extended_value.rb) — Extended Value Syntax (`@json:`, `@yaml:`, `@ruby:`, `@preset:`, `@vault:`, `@args:`, …)
- [`options.schema.yaml`](../lib/aspera/cli/options.schema.yaml) — schema for global options

Key responsibilities:

- Declare and validate CLI options (boolean, string, integer, array, hash types)
- Composite options with dot-notation sub-keys (e.g. `--out.format=json`, `--log.level=debug`)
- Handle sensitive data (passwords, secrets) with masking ([`secret_hider.rb`](../lib/aspera/secret_hider.rb))
- Provide option inheritance and defaults from presets

#### Plugin System

**Directory**: [`lib/aspera/cli/plugins/`](../lib/aspera/cli/plugins/)

The plugin architecture enables modular command implementation for different Aspera products:

**Base Plugin** ([`base.rb`](../lib/aspera/cli/plugins/base.rb)):

- Provides the Command DSL (`command`, `commands_under`, `crud_commands`, `option`, …) and the dispatcher
- Provides standard CRUD operations: `create`, `list`, `modify`, `show`, `delete` (`Base::Operations`)
- Provides bulk operation support (`--bulk`, `--bfail`)
- Implements resource identifier resolution (including percent-selector syntax)
- Manages plugin context (options, transfer agent, config, formatter)

**Product Plugins** (registered and exposed as top-level commands):

- [`aoc.rb`](../lib/aspera/cli/plugins/aoc.rb) - Aspera on Cloud
- [`ats.rb`](../lib/aspera/cli/plugins/ats.rb) - Aspera Transfer Service
- [`faspex5.rb`](../lib/aspera/cli/plugins/faspex5.rb) - Faspex 5
- [`shares.rb`](../lib/aspera/cli/plugins/shares.rb) - Aspera Shares
- [`node.rb`](../lib/aspera/cli/plugins/node.rb) - Node API
- [`console.rb`](../lib/aspera/cli/plugins/console.rb) - Aspera Console
- [`orchestrator.rb`](../lib/aspera/cli/plugins/orchestrator.rb) - Aspera Orchestrator
- [`server.rb`](../lib/aspera/cli/plugins/server.rb) - HSTS (High-Speed Transfer Server)
- [`cos.rb`](../lib/aspera/cli/plugins/cos.rb) - IBM Cloud Object Storage
- [`httpgw.rb`](../lib/aspera/cli/plugins/httpgw.rb) - HTTP Gateway
- [`faspio.rb`](../lib/aspera/cli/plugins/faspio.rb) - Fasp.io Gateway
- [`alee.rb`](../lib/aspera/cli/plugins/alee.rb) - Aspera Line Enterprise Edition

The Faspex 4 plugin was removed (end of support).

**Utility Plugins** (registered commands but not product-specific):

- [`config.rb`](../lib/aspera/cli/plugins/config.rb) - Configuration management (includes `SyncActions`, `VaultManager`, `GemChecker`, `AscpActions`, `PresetActions`, `TransferActions` mixins)
- [`preview.rb`](../lib/aspera/cli/plugins/preview.rb) - File preview generation
- [`mcp.rb`](../lib/aspera/cli/plugins/mcp.rb) - Model Context Protocol server (exposes `ascli` to AI assistants)

**Internal Base Classes** (excluded from factory registration via `IGNORE_PLUGINS`):

- [`base.rb`](../lib/aspera/cli/plugins/base.rb) - Abstract base class for all plugins
- [`basic_auth.rb`](../lib/aspera/cli/plugins/basic_auth.rb) - Abstract base class for plugins using basic authentication (url/username/password)
- [`oauth.rb`](../lib/aspera/cli/plugins/oauth.rb) - Abstract base class for plugins using OAuth
- [`factory.rb`](../lib/aspera/cli/plugins/factory.rb) - Plugin factory (singleton); discovers plugins by scanning the plugin folders

#### Command DSL

All plugins declare their command tree using a class-level DSL defined in `Base`, which makes the full command tree statically introspectable, self-documenting, and testable without execution.

**Key files**:

- [`lib/aspera/cli/command_spec.rb`](../lib/aspera/cli/command_spec.rb) — data classes: `CommandSpec`, `ArgumentSpec`, `OptionSpec`
- [`lib/aspera/cli/command_registry.rb`](../lib/aspera/cli/command_registry.rb) — flat registry keyed by full path (`Array<Symbol>`), with `validate!`
- [`lib/aspera/cli/plugins/base.rb`](../lib/aspera/cli/plugins/base.rb) — DSL class methods and dispatcher

**DSL class methods** (in `Base`):

| Method | Purpose |
| --- | --- |
| `command(id, **kwargs)` | Register a `CommandSpec`; `parent:` defaults to the enclosing `commands_under` scope |
| `commands_under(parent, description: nil) { … }` | Scope block setting the default parent for nested `command` calls. Re-entrant; `parent` is relative to the current scope. Auto-declares the parent node (`"Manage <name>"`) if not yet declared |
| `crud_commands(api:, entity:, operations:, name:, lookup:, **kwargs)` | Declare one leaf command per CRUD verb for a REST entity (see below) |
| `define_action_method(path) { … }` | `define_method` with the conventional `action_<path>` name; used for homogeneous generated commands |
| `option(name, description:, short:, allowed:, default:, handler:, deprecation:, schema:)` | Declare a plugin option (stored as `OptionSpec`, declared on the parser in `Base#initialize`). Raises if an ancestor already declares it |
| `use_options(source)` | Include options declared by another plugin class or `OptionDeclarator` module |
| `root_setup(method_name)` | Method called once before root dispatch; its `Hash` result seeds `ctx`. Used when root `condition:` methods depend on setup state (e.g. `server.rb`) |
| `application_name(name)` | Human-readable application name shown in wizards |

**Command declaration** (`CommandSpec` attributes):

| Parameter | Type | Meaning |
| --- | --- | --- |
| `id` | `Symbol` | Unique identifier within its parent's namespace |
| `parent` | `Symbol \| Array<Symbol> \| nil` | Full path to parent; `nil` for root commands (usually implied by `commands_under`) |
| `description` | `String` | User-facing help text |
| `options` | `Array<Symbol>` | Option names consumed by this command |
| `arguments` | `Array<ArgumentSpec \| Hash>` | Positional arguments in parse order. On an **intermediate** node they are resolved before child dispatch (e.g. parent instance id); on a **leaf** they are resolved just before the action |
| `action` | `Symbol \| Proc \| nil` | Leaf action. **(1)** omitted → convention `action_<full_path_joined_by_underscores>`; **(2)** `Symbol` → named instance method; **(3)** `Proc` → inline, executed with `instance_exec` |
| `setup` | `Symbol \| nil` | Instance method called with `**ctx` after the node's `arguments` are resolved; returns a `Hash` merged into `ctx` for all descendants |
| `aliases` | `Array<Symbol> \| nil` | Alternative names accepted for this command (e.g. `aliases: [:recv]`) |
| `transfer_paths` | `:send \| :receive \| nil` | File-list resolution delegated to `TransferAgent` (reads what remains after declared `arguments`) |
| `condition` | `Symbol \| nil` | Instance method returning `Boolean`; if `false`, command is excluded from dispatch but shown in help with an annotation |
| `query_schema` | `String \| nil` | Schema path for `--query` help; the runner then hints `--query=help` |
| `mount` | `Hash \| nil` | Expose a sub-tree of another plugin class under this node (see [Mounting another plugin's commands](#mounting-another-plugins-commands)) |

**Argument declaration** (`ArgumentSpec`, usually given as a `Hash`):

| Parameter | Type | Meaning |
| --- | --- | --- |
| `name` | `Symbol` | Key in `ctx`, also used in help and error messages |
| `description` | `String` | User-facing description |
| `type` | `Class \| Array<Class> \| :identifier` | Validated type; `:identifier` resolves via `options.instance_identifier` (supports percent-selector) |
| `mandatory` | `Boolean` | Default `true`; optional arguments must come after all mandatory ones |
| `multiple` | `Boolean \| String` | `true`: consume all remaining; `String`: consume until the named marker |
| `default` | `Object \| nil` | Default value when `mandatory: false` and no argument provided |
| `schema` | `String \| nil` | JSON schema name for validation and `--help` introspection |
| `bulk` | `Boolean` | Result is always an `Array`; with `--bulk=yes` the argument is read as an array |
| `lookup` | `Symbol \| Proc \| nil` | Percent-selector resolver for `:identifier`: `send(lookup, field, value, **ctx)` or `instance_exec(field, value, **ctx, &lookup)` |
| `allowed` | `Array<Symbol> \| nil` | Allowed values (accept list) |
| `interactive` | `Boolean` | Prompt for the value when missing (sets `ask_missing_mandatory`) |

Arguments already present in `ctx` are not read again from the command line: this is how a caller (e.g. a mount seed) or a leaf `setup:` provides a value.

**Rule**: every positional argument is declared with `arguments:`, so that `--help`, completion and `config commands` show it. Plugins never read positional arguments themselves (`options.get_next_argument`, `options.instance_identifier`). When an argument may come from elsewhere, declare it anyway and let the leaf `setup:` inject it in `ctx`, since a leaf setup runs before its arguments are resolved:

```ruby
command :show, description: 'Show a package', setup: :setup_package_id,
  arguments: [{name: :package_id, type: :identifier}],
  action: ->(package_id:, **) { ... }

# With a public link to a package, the id comes from the link and is not read from the command line
def setup_package_id(**)
  return {} unless @api_v5.pub_link_context&.key?('package_id')
  {package_id: @api_v5.pub_link_context['package_id']}
end
```

**`crud_commands` helper**:

For each verb in `operations:` (default `Operations::ALL` = `create list modify show delete`) it registers a leaf command whose action calls `entity_<verb>(api:, entity:, **kwargs, **ctx)`:

- `show` / `modify` / `delete` get an `{name: :id, type: :identifier, lookup: lookup}` argument (unless `is_singleton:`); `delete` is bulk-capable
- `create` / `modify` get a `data` `Hash` argument; with `body_component:` its schema is taken from the OpenAPI registry
- `api:` is resolved at runtime: `:@ivar` → instance variable, other `Symbol` → method call, `Proc` → `instance_exec`
- `entity:` may be a `Symbol`, resolved at runtime from `ctx` (e.g. `:sf_entity` injected by a parent `setup:`)
- other `**kwargs` (`display_fields:`, `items_key:`, `is_singleton:`, …) are forwarded to every `entity_<verb>`

```ruby
commands_under :workflows do
  crud_commands api: :@automation_api, entity: 'workflows'
end
```

**Dispatcher algorithm** (`Base#execute_action` → `dispatch_from_registry`):

`execute_action` validates the registry once per class (`CommandRegistry#validate!`), runs `root_setup` if declared, then calls `dispatch_from_registry([], init_ctx)`.

```text
dispatch_from_registry(current_path, ctx = {})
  spec    = registry[current_path]
  is_leaf = spec has no children

  # Phase A (skipped when --help)
  if !is_leaf
    resolve spec.arguments into ctx          # e.g. parent instance id (:identifier + lookup)
  ctx = ctx.merge(send(spec.setup, **ctx)) if spec.setup

  # Phase B
  if is_leaf
    dispatch_leaf:  raise HelpRequest if --help
                    execute_leaf: resolve spec.arguments into ctx, invoke action_for(spec) with **ctx
  else
    dispatch_child: raise HelpRequest if --help and no more args
                    command = options.get_next_command(children not hidden by condition, aliases:)
                    raise HelpRequest if --help and no more args
                    if child is mounted and not --help
                      return dispatch_mount(...)   # continue on the target plugin instance
                    dispatch_from_registry(current_path + [command], ctx)
```

Key properties of the `ctx` hash:

- **Additive**: each resolved argument and each `setup:` call enriches the accumulated context; descendants can rely on everything resolved by ancestors.
- **Intermediate node**: arguments and setup are resolved before the child command is selected, so context is available to all children.
- **Leaf node**: setup runs, then arguments are resolved, then the action receives `ctx` as keyword arguments.
- `transfer_paths:` — `TransferAgent#ts_source_paths` reads the file list from what remains in the argument stream, depending on `--sources`.

#### Action style convention

| Condition | Preferred form |
| --- | --- |
| 1 statement, no args | `action: ->{…}` |
| 1 statement, with args | `action: ->(arg:, **){…}` |
| 2–3 statements, inline | `command(:x, …, action: lambda do … end)` |
| > 3 statements | named method `def action_<full_path>` |
| shared logic (called from multiple places) | named method regardless of size |

The 3-statement threshold is deliberately informal. The deciding factor is readability at the call site: if the action fits on one line without obscuring the `command(...)` declaration, an inline `->` is preferred. If the body needs local variables, loops, or `rescue`, a named method is clearer. Logic shared between several commands must always live in a named method, regardless of its size. The same convention applies to `lookup:`.

**Precedence rule**: `lambda do...end` has low binding priority — if `command` is called without parentheses, Ruby attaches the `do...end` to `command` instead of `lambda`, causing `tried to create Proc object without a block` at class load time. Always use `command(...)` with parentheses when the action is a `lambda do...end`.

**Do not** use `lambda{ }` (braces with `lambda` keyword): rubocop's `SpaceInsideBlockBraces` forbids inner spaces, making multi-line bodies unreadable. The codebase uses `->{}` for one-liners and `lambda do...end` for multi-line — no other form.

Examples:

```ruby
# 1 line
command :info, description: 'Show node info',
  action: ->{Result::SingleObject.new(@api_node.read('info'))}

command :show, description: 'Show a package',
  arguments: [{name: :package_id, type: :identifier}],
  action: ->(package_id:, **){Result::SingleObject.new(@api.read("packages/#{package_id}"))}

# 2–3 statements: parentheses are mandatory
command(
  :flush, description: 'Delete all cached OAuth tokens',
  action: lambda do
    require 'aspera/api/node'
    Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
  end
)

# > 3 statements: implicit named method
commands_under :package do
  command :receive, description: 'Receive a package'
end

def action_package_receive(**)
  # many lines of logic...
end
```

All forms receive the `ctx` hash as keyword arguments and behave identically at runtime.

**Notable design decisions**:

| Decision | Rationale |
| --- | --- |
| Flat registry keyed by full path `Array<Symbol>` | Avoids recursive data structures; path lookup is O(1) |
| `arguments:` on intermediate nodes | Parent instance ids are declared statically, so help shows them and dispatch resolves them before child selection |
| `setup:` runs on the current node before dispatching | Derived context (API objects, entity paths) computed once for the whole sub-tree; no virtual nodes needed |
| `condition:` commands visible in help but excluded at runtime | Static documentation is complete; runtime filtering via a method |
| `crud_commands` generates one leaf per verb | CRUD declarations stay DRY while each verb remains a real, introspectable `CommandSpec`; `api:` is resolved at runtime so the API object can be created lazily |
| `mount:` instead of re-declaring another plugin's commands | The target sub-tree is declared once: dispatch, `--help`, completion and `config commands` see it entirely, and changes in the target need no change in the hosts |
| `transfer_paths: :send\|:receive` | The `--sources` mechanism in `TransferAgent` cannot be expressed as static arguments |
| `define_action_method` for homogeneous command groups | Avoids repetitive action definitions for commands sharing the same body (e.g. `ADMIN_OBJECTS` in `aoc.rb`, `RESOURCE_CONFIG` in `faspex5.rb`) |

#### Entity identifier placement

**Convention**: The CLI uses two distinct argument-order patterns depending on the depth of the command tree:

| Pattern | Argument order | When to use |
| --- | --- | --- |
| **Leaf CRUD** | `<entity> <verb> <id>` | The id identifies the *target* of a terminal verb (`show`, `delete`, `modify`). The id comes **after** the verb. |
| **Intermediate selector** | `<entity> <sub-tree> <id> <verb>` | The id selects a *parent instance* whose children will be further dispatched. The id comes **before** the sub-tree verb. |

The second pattern is declared with an `:identifier` argument **on the intermediate node** — never read inside the leaf actions. If children need derived values (entity path, API object), add a `setup:` on the same node; it runs after the argument is resolved.

**Wrong** — identifier for an intermediate node read in the leaf action (too late):

```ruby
# BAD: forces the user to write: workspace dropbox list <id>
# but the convention requires:  workspace dropbox <id> list
def action_admin_workspace_dropbox_list(**)
  ws_id = options.instance_identifier   # ← consumed AFTER command selection
  ...
end
```

**Correct** — identifier declared on the intermediate node, derived context from `setup:` (from `faspex5.rb`):

```ruby
commands_under %i[admin nodes] do
  command :shared_folders, description: 'Manage shared folders',
    arguments: [{name: :node_id, type: :identifier, lookup: :lookup_node_id}],
    setup: :setup_admin_nodes_shared_folders
end

commands_under %i[admin nodes shared_folders] do
  crud_commands entity: :sf_entity, api: :@api_v5, name: 'shared folder',
    lookup: :lookup_sf_id, items_key: 'shared_folders'
end

# node_id: already in ctx from arguments: on :shared_folders
def setup_admin_nodes_shared_folders(node_id:, **)
  {sf_entity: "nodes/#{node_id}/shared_folders"}
end
```

**Quick test**: if the id selects *which* sub-tree to enter (further commands follow), it belongs in the intermediate node's `arguments:`. If the id identifies the *object* of the terminal operation (nothing follows), it belongs in the leaf's `arguments:`.

**Examples in the codebase**:

| Node | Argument | Setup → injects into ctx |
| --- | --- | --- |
| `aoc admin workspace dropbox` | `workspace_id` | [`setup_admin_workspace_dropbox`](../lib/aspera/cli/plugins/aoc.rb) → `ws_res_id:` |
| `aoc admin workspace shared_folder` | `workspace_id` | [`setup_admin_workspace_shared_folder`](../lib/aspera/cli/plugins/aoc.rb) → `ws_res_id:`, `shared_folders:` |
| `faspex5 admin nodes shared_folders` | `node_id` | [`setup_admin_nodes_shared_folders`](../lib/aspera/cli/plugins/faspex5.rb) → `sf_entity:` |
| `faspex5 admin nodes shared_folders user` | `sf_id` | [`setup_admin_nodes_shared_folders_user`](../lib/aspera/cli/plugins/faspex5.rb) → `user_path:` |
| `node access_keys do` | `access_key_id` | [`setup_access_key_do`](../lib/aspera/cli/plugins/node.rb) → `do_root_file_id:` |
| `node access_keys do <id> permission` | `path` | [`setup_access_key_do_permission`](../lib/aspera/cli/plugins/node.rb) → `apifid:` |
| `aoc packages shared_inboxes short_link` | `link_type`, `dropbox_id` | [`setup_packages_short_link`](../lib/aspera/cli/plugins/aoc.rb) → `sl_shared_data:`, … |

---

#### Mounting another plugin's commands

Several plugins expose commands of another plugin, typically `Node` (COS bucket, AoC files, ATS access key, Shares files).
The `mount:` attribute of a command node exposes the children of a node of another plugin class, instead of re-declaring them:

```ruby
command :node, description: 'Execute COS node commands',
  mount: {plugin: Node, instance: :cos_node_plugin, only: Node::COMMANDS_COS}

def cos_node_plugin(**)
  Node.new(context: context, api: Api::CosNode.new(...))
end
```

| Key | Meaning |
| --- | --- |
| `plugin` | Target plugin class |
| `at` | Path in the target registry whose children are mounted (default `[]`: root) |
| `instance` | Host method called with `**ctx` (after the node's own `arguments:` and `setup:`), returning the target instance, or `[instance, seed_ctx]` |
| `only` / `except` | Filter the mounted children |
| `arguments` | Arguments read by the host right after the mounted command, before the target's own arguments, and passed to `instance` in `ctx` (mandatory only) |

Semantics:

- **Registry**: `CommandRegistry#[]`, `children_of`, `leaf_paths` follow mounts, with paths in the host namespace. Host children declared under the mount node are merged with the mounted ones and take precedence on an id conflict.
- **Dispatch**: when a mounted child is selected, `dispatch_mount` resolves the mount `arguments`, calls `instance`, then `target.dispatch_from_registry(at + [command], seed_ctx)`. Arguments and setups **below** the mount point run normally in the target; those of `at` and its ancestors do not run: `seed_ctx` provides what they would have put in `ctx` (e.g. `do_root_file_id:` for `at: %i[access_keys do]`).
- **Arguments**: `CommandRegistry#arguments_at(path)` returns the mount `arguments` followed by the node's own, e.g. `aoc packages ls <package_id> <path>`: `--help` and `config commands` use it.
- **Help**: with `--help`, the host keeps walking its mount-aware registry: the target is never instantiated (no API connection), and `condition:` of mounted commands is not evaluated.
- **Validation**: `validate!` checks that `instance` exists, that `at` and the `only`/`except` ids exist in the target, that the mount node has no `action:`, and that mount `arguments` are mandatory.

Mount points:

| Host | Target |
| --- | --- |
| `cos node` | `Node` root, `only: COMMANDS_COS` |
| `shares files` | `Node` root, `only: COMMANDS_SHARES` |
| `ats access_key node <id>` | `Node` `access_keys do` |
| `aoc files`, `aoc admin node do <id>`, `aoc admin workspace shared_folder <id> node <id>` | `Node` `access_keys do` (plus the AoC-specific `transfer`, and `short_link` for `files`) |
| `aoc packages` | `Node` `access_keys do`, `only: NODE4_READ_ACTIONS`, `arguments: <package_id>` |
| `aoc admin ats` | `Ats` root |
| `node access_keys do <id> v3` | `Node` root (a mount on itself: `leaf_paths` does not expand a cycle twice) |

`mount:` is the only cross-plugin delegation mechanism of the DSL.

#### Legitimate residual imperative reads

Plugin-level imperative dispatch and argument reads have been eliminated. The remaining occurrences are infrastructure and are intentional:

| File | Location | Role |
| --- | --- | --- |
| [`parser.rb`](../lib/aspera/cli/parser.rb) | `get_next_command` | Infrastructure — defines `get_next_command` |
| [`base.rb`](../lib/aspera/cli/plugins/base.rb) | `dispatch_child` | Infrastructure — the DSL dispatcher itself calls `get_next_command` |
| [`runner.rb`](../lib/aspera/cli/runner.rb) | `run_with_result` | Top-level plugin selector (`case command_sym`), not a per-plugin dispatch |
| [`base.rb`](../lib/aspera/cli/plugins/base.rb) | `dispatch_from_registry`, `execute_leaf`, `resolve_argument` | Infrastructure — resolution of declared `arguments:` |

No plugin file uses `get_next_command`, `get_next_argument` or `instance_identifier`.

#### Transfer Agent Abstraction

**File**: [`lib/aspera/cli/transfer_agent.rb`](../lib/aspera/cli/transfer_agent.rb)

The Transfer Agent provides a unified interface for initiating transfers across different FASP clients:

**Responsibilities**:

- Abstract transfer initiation across multiple agent types
- Manage transfer specifications (transfer_spec)
- Handle file list sources (`@args`, `@ts`, arrays)
- Coordinate transfer progress monitoring ([`transfer_progress.rb`](../lib/aspera/cli/transfer_progress.rb))
- Send transfer completion notifications
- Track asynchronous transfers: jobs are persisted by `job_id` in [`async_transfer_store.rb`](../lib/aspera/cli/async_transfer_store.rb) and can be re-queried later

**Agent Base Class** ([`lib/aspera/agent/base.rb`](../lib/aspera/agent/base.rb)):

```ruby
class Base
  # Optional: re-query a previously started transfer by id (desktop, node, connect, transferd, ...)
  def self.transfer_status(transfer_id, agent_params)

  # Start a transfer asynchronously (must be implemented by subclass)
  def start_transfer(transfer_spec, token_regenerator: nil)

  # Wait for all transfers to complete and return per-session statuses (must be implemented)
  def wait_for_transfers_completion

  # Wait for completion; returns Transfer::Result::Success or Transfer::Result::Error (public API)
  def wait_for_completion

  # Job id of the last submitted transfer (in-process agents)
  def last_job_id

  # Optional: release resources
  def shutdown
end
```

Transfer outcomes are typed ([`transfer/result.rb`](../lib/aspera/transfer/result.rb)): `Transfer::Result::Success`, `Transfer::Result::Error`, `Transfer::Result::Async`.

**Supported Agents** ([`lib/aspera/agent/`](../lib/aspera/agent/), created by `Agent::Factory`):

- **Direct**: Direct `ascp` execution (default)
- **Connect**: Aspera Connect browser plugin
- **Node**: Node API-based transfers
- **HTTPGW**: HTTP Gateway for restricted networks
- **Desktop**: Aspera Desktop Client
- **Transfer Daemon (trSDK)**: gRPC-based transfer service ([`transferd.rb`](../lib/aspera/agent/transferd.rb))

### API Communication Layer

#### REST Client

**File**: [`lib/aspera/rest.rb`](../lib/aspera/rest.rb)

A custom HTTP client implementation providing:

- **HTTP Methods**: GET, POST, PUT, PATCH, DELETE, CANCEL
- **Authentication**: Basic, Bearer token, OAuth 2.0
- **Content Types**: JSON, form-encoded, multipart
- **Error Handling**: Automatic retry logic, error analysis
- **Progress Tracking**: File upload/download progress
- **Session Management**: Connection pooling, SSL/TLS configuration, proxy auto-config ([`proxy_auto_config.rb`](../lib/aspera/proxy_auto_config.rb))

Global HTTP settings are held in the `RestParameters` singleton. Paginated listing is handled by [`rest_list.rb`](../lib/aspera/rest_list.rb).

#### Product API Clients

**Directory**: [`lib/aspera/api/`](../lib/aspera/api/) — `aoc`, `ats`, `alee`, `cos_node`, `faspex`, `httpgw`, `node`

**Node API Client** ([`node.rb`](../lib/aspera/api/node.rb)):

- **Access Key Management**: Gen4 access key support
- **Bearer Token Generation**: JWT-based authentication
- **File Operations**: Browse, upload, download, delete
- **Permission Management**: Fine-grained access control
- **Transfer Spec Generation**: Automatic transfer parameter creation
- **Cache control**: optional request header to bypass the server-side (Redis) cache

#### API Schemas

**Directory**: [`lib/aspera/schema/`](../lib/aspera/schema/)

OpenAPI definitions of the product APIs (AoC, Faspex 5, Node, Shares, faspio) and `Schema::Registry`, used to:

- document request bodies of `create` / `modify` (`body_component:` in `crud_commands`)
- document `--query` parameters (`query_schema:`, shown with `--query=help`)

#### OAuth Implementation

**Directory**: [`lib/aspera/oauth/`](../lib/aspera/oauth/)

Modular OAuth 2.0 support, instantiated through `OAuth::Factory` (which also caches tokens):

- **Generic OAuth** ([`generic.rb`](../lib/aspera/oauth/generic.rb)): Standard OAuth 2.0 flows
- **JWT** ([`jwt.rb`](../lib/aspera/oauth/jwt.rb)): JSON Web Token authentication
- **Web** ([`web.rb`](../lib/aspera/oauth/web.rb)): Browser-based OAuth flows; the local callback server lives in [`lib/aspera/web_auth/`](../lib/aspera/web_auth/)
- **URL JSON** ([`url_json.rb`](../lib/aspera/oauth/url_json.rb)): Token from URL
- **Boot** ([`boot.rb`](../lib/aspera/oauth/boot.rb))

### FASP Transfer Layer

#### ASCP Installation Manager

**File**: [`lib/aspera/ascp/installation.rb`](../lib/aspera/ascp/installation.rb)

Singleton class managing `ascp` binary location and SDK resources:

- **Product Detection**: Automatically finds installed Aspera products ([`lib/aspera/products/`](../lib/aspera/products/))
- **SDK Installation**: Downloads and installs Transfer SDK
- **Path Resolution**: Locates `ascp` executable and supporting files
- **SSH Key Management**: Handles client SSH keys for authentication

Supported product detection:

- Aspera Desktop Client
- Aspera Connect
- Aspera Transfer SDK (`transferd`)
- Aspera HSTS/ATS installations

#### Transfer Specification

**File**: [`lib/aspera/transfer/spec.rb`](../lib/aspera/transfer/spec.rb) (schema: [`spec.schema.yaml`](../lib/aspera/transfer/spec.schema.yaml))

Transfer specifications define all parameters for a FASP transfer:

- Source and destination paths
- Transfer direction (upload/download)
- Rate control (target rate, min rate, policy)
- Encryption settings
- Resume policies
- Authentication credentials
- Protocol options (UDP/TCP ports, SSH options)

#### Async Sync

**Directory**: [`lib/aspera/sync/`](../lib/aspera/sync/) — `async` (Aspera Sync) arguments, configuration schemas and database access, used by `SyncActions`.

### Remote Systems Layer

The CLI communicates with various IBM Aspera components:

#### Web Applications (HTTPS)

- **Aspera on Cloud (AoC)**: Cloud-based file sharing and collaboration
- **Aspera Transfer Service (ATS)**: Managed transfer service
- **Faspex 5**: Secure package exchange
- **Shares**: File sharing and synchronization
- **Console**: Central management console
- **Orchestrator**: Workflow automation

Communication via:

- REST APIs over HTTPS
- OAuth 2.0 authentication
- JSON request/response payloads

#### Transfer Servers (FASP Protocol)

- **IBM Cloud Object Storage (COS)**: S3-compatible object storage with FASP
- **Aspera Transfer Server (ATS)**: Dedicated transfer endpoints
- **HSTS Node**: High-Speed Transfer Server with Node API

Communication via:

- FASP protocol (TCP/UDP) for data transfer
- Node API (HTTPS) for control operations
- SSH for authentication and session management (and `ascmd` file operations)

#### Third-Party Integrations

- **gRPC**: Transfer Daemon communication
- **JSON-RPC**: Desktop client communication ([`lib/aspera/json_rpc/`](../lib/aspera/json_rpc/))
- **MCP**: Model Context Protocol for AI assistant integration
- **External Tools**: Integration with system utilities (e.g. ffmpeg, ImageMagick, LibreOffice for previews)

## Data Flow

### Typical Command Execution Flow

1. **Command Parsing**:

   ```text
   User Input &rarr; bin/ascli &rarr; Runner &rarr; Parser (options + positional args)
   ```

2. **Plugin Selection**:

   ```text
   Command &rarr; Plugin Factory &rarr; Specific Plugin (e.g., aoc, faspex5)
   ```

3. **Command Dispatch**:

   ```text
   Plugin#execute_action &rarr; dispatch_from_registry &rarr; action (method or Proc)
   ```

4. **API Communication**:

   ```text
   Action &rarr; REST Client &rarr; Remote API &rarr; JSON Response
   ```

5. **Transfer Initiation**:

   ```text
   Action &rarr; Transfer Agent &rarr; Agent Selection &rarr; ascp/trSDK/Connect/...
   ```

6. **Transfer Execution**:

   ```text
   Transfer Agent &rarr; FASP Protocol &rarr; Remote Server &rarr; Progress Updates
   ```

7. **Result Formatting**:

   ```text
   Result object &rarr; Formatter &rarr; Output (table/json/yaml/csv/...)
   ```

## Key Design Patterns

### Plugin Architecture

Each Aspera product is implemented as a plugin inheriting from `Plugins::Base`:

- Consistent command structure across products
- Standard CRUD operations
- Extensible for product-specific features

### Factory Pattern

Used for creating instances based on configuration:

- **Agent Factory**: Selects appropriate transfer agent
- **OAuth Factory**: Creates authentication handlers
- **Plugin Factory**: Instantiates product plugins
- **Keychain Factory**: Selects the secret storage backend

### Singleton Pattern

Used for global configuration and state:

- **Installation**: ASCP binary location
- **RestParameters**: HTTP client settings
- **Log**: Logging configuration

### Strategy Pattern

Transfer agents implement a common interface with different strategies:

- Direct execution via `ascp`
- Browser-based via Connect
- API-based via Node
- Gateway-based via HTTPGW

### Command DSL Pattern

Each plugin declares its command tree at class level (see [Command DSL](#command-dsl)); the base class dispatcher (`dispatch_from_registry`) traverses the registry and calls the appropriate action on the plugin instance.

### Mixin / Module Pattern

Large classes are decomposed into focused mixins included by the host class:

- `Config` plugin includes `SyncActions`, `VaultManager`, `GemChecker`, `AscpActions`, `PresetActions`, `TransferActions`
- Each mixin owns a single responsibility and depends on `options`, `context`, and other accessors provided by the host

## Configuration Management

### Configuration File

**Location**: `~/.aspera/ascli/config.yaml`

Stores:

- Preset configurations for different environments
- Default options and parameters
- Authentication credentials (or references to the vault)
- Transfer agent preferences

### Preset System

Presets allow saving commonly used option combinations ([`preset_manager.rb`](../lib/aspera/cli/preset_manager.rb), [`preset_actions.rb`](../lib/aspera/cli/preset_actions.rb)):

```yaml
presets:
  my_aoc:
    url: https://mycompany.ibmaspera.com
    username: user@example.com
    password: "@vault:aoc_password"
```

- `config preset set` accepts dot-notation keys (deep-merged, with type coercion)
- Keys starting with `_` (e.g. `_comment`) are ignored

### Secret Management

**Directory**: [`lib/aspera/keychain/`](../lib/aspera/keychain/) (selected by `Keychain::Factory`, managed by `VaultManager`)

- **file**: Built-in encrypted hash
- **system**: macOS Keychain
- **vault**: HashiCorp Vault
- **1password**: 1Password (API or CLI)

## Error Handling

### Error Hierarchy

```text
StandardError
├── Aspera::Error (lib/aspera/assert.rb)
│   ├── Aspera::EntityNotFound (resource not found — lib/aspera/rest.rb)
│   └── Aspera::Ssh::Error
├── Aspera::Cli::Error (CLI base)
│   ├── BadArgument
│   ├── MissingArgument
│   ├── NoSuchElement
│   └── BadIdentifier
├── Aspera::Cli::HelpRequest (control flow: --help reached in dispatch)
├── Aspera::RestCallError (HTTP call errors — lib/aspera/rest_call_error.rb)
└── Aspera::Transfer::Error (transfer failures — lib/aspera/transfer/error.rb)
```

### Error Analysis

**File**: [`lib/aspera/rest_error_analyzer.rb`](../lib/aspera/rest_error_analyzer.rb)

Analyzes API errors and provides:

- Human-readable error messages
- Suggested remediation steps
- Context-specific guidance

## Logging and Debugging

### Log Levels

- `trace2`: Finest-grained tracing (most verbose)
- `trace1`: Fine-grained tracing
- `debug`: Detailed debugging information
- `info`: General informational messages
- `warn`: Warning messages
- `error`: Error messages
- `fatal`: Fatal errors
- `unknown`: Unknown severity

### Debug Features

- HTTP request/response logging
- Transfer specification display
- API call tracing
- Progress monitoring
- Secrets are masked in logs ([`secret_hider.rb`](../lib/aspera/secret_hider.rb))

## Testing Architecture

### Test Structure

**Directory**: [`spec/`](../spec/)

- Unit tests, fully self-contained, e.g.:
  - `base_dsl_spec.rb` — `Base` DSL dispatcher
  - `command_registry_spec.rb` — `CommandRegistry` validation rules
  - `aoc_registry_spec.rb` — `Aoc.command_registry.validate!(plugin_class: Aoc)` consistency (every leaf has an action or a matching `action_*` method)
  - `parser_spec.rb`, `option_declarator_spec.rb`, `preset_actions_spec.rb`, `runner_spec.rb`, `mcp_tool_spec.rb`
  - `async_transfer_store_spec.rb`, `transfer_agent_async_spec.rb`, `transfer_result_spec.rb`, `agent_transfer_status_spec.rb`
  - `rest_spec.rb`, `secret_hider_spec.rb`, `proxy_auto_config_spec.rb`, `schema_reader_spec.rb`, `string_ext_spec.rb`, `uri_reader_spec.rb`, …
- Integration tests requiring a live server (`integration_helper.rb`, e.g. `ascmd_ssh_integration_spec.rb`)

### CI/CD Integration

GitHub Actions workflows (`.github/workflows/`):

- Multi-version Ruby testing (3.1, 3.2, 3.3, 3.4, 4.0, JRuby)
- Code quality checks (RuboCop)
- Security scanning (CodeQL)
- Release, deploy, certificate renewal

## Extension Points

### Adding a New Plugin

1. Create plugin file in `lib/aspera/cli/plugins/` (or in a plugin lookup folder)
2. Inherit from `Plugins::Base` (or `BasicAuth` / `Oauth`)
3. Declare options with `option(...)` and commands with `command(...)` / `commands_under` / `crud_commands` at class level
4. Implement `action_<path>` methods for leaf commands without an inline `action:`

The plugin factory discovers the plugin automatically; `CommandRegistry#validate!` checks the tree at first execution.

### Adding a New Transfer Agent

1. Create agent file in `lib/aspera/agent/`
2. Inherit from `Agent::Base`
3. Implement required methods:
   - `start_transfer`
   - `wait_for_transfers_completion`
   - optionally `self.transfer_status` (async support) and `shutdown`
4. Register in `Agent::Factory`

### Adding a New Output Format

1. Extend `Formatter` class ([`formatter.rb`](../lib/aspera/cli/formatter.rb))
2. Implement format-specific rendering
3. Register format in formatter factory

## Performance Considerations

### Transfer Optimization

- **Multi-session**: Parallel transfer sessions for large files
- **Adaptive Rate**: Dynamic bandwidth adjustment
- **Resume**: Sparse checksum-based resume
- **Compression**: Optional in-flight compression

### API Optimization

- **Pagination**: Efficient handling of large result sets
- **Token Caching**: OAuth tokens cached on disk
- **Connection Pooling**: Reuse HTTP connections
- **Batch Operations**: Bulk create/delete operations

## Security Architecture

### Authentication Methods

1. **OAuth 2.0**: Token-based authentication
2. **JWT**: JSON Web Tokens
3. **Basic Auth**: Username/password
4. **SSH Keys**: Public key authentication
5. **Access Keys**: Node API access keys

### Credential Storage

- Encrypted configuration file
- System keychain integration
- Environment variables
- Vault integration (HashiCorp Vault, 1Password)

### Secure Communication

- TLS/SSL for HTTPS
- SSH for FASP control channel
- Encrypted FASP data transfer
- Certificate validation

## Deployment Models

### Installation Methods

1. **Ruby Gem**: `gem install aspera-cli`
2. **Single Executable**: Standalone binary
3. **Container**: Docker image
4. **Package Managers**: Homebrew, Chocolatey

### Runtime Requirements

- Ruby ≥ 3.1
- FASP client (ascp or Transfer SDK)
- Network connectivity
- Sufficient disk space for transfers

## References

- [Main Documentation](README.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [API Documentation](https://www.rubydoc.info/gems/aspera-cli)
- [IBM Aspera Documentation](https://www.ibm.com/docs/en/aspera)
