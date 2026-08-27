# Migration Plan: Declarative DSL for ascli Commands

## Overview

This document describes a **progressive, opt-in migration** from the current imperative
`ACTIONS` + `case/when` dispatch pattern to a declarative DSL that makes the full command
tree introspectable, self-documenting, and testable without execution.

The migration is additive: the DSL infrastructure is introduced first in `Base`, then
plugins are migrated one by one in order of complexity. Plugins that have not yet been
migrated continue to work exactly as before.

---

## Background: Current Architecture

Every plugin today follows the same pattern:

```ruby
ACTIONS = %i[foo bar baz].freeze          # flat list of top-level sub-commands

def execute_action
  command = options.get_next_command(ACTIONS)
  case command
  when :foo
    sub = options.get_next_command(%i[list create])
    obj = build_api_object(...)            # context variable used in sub-levels
    case sub
    when :list  then ...obj...
    when :create then ...obj...
    end
  when :bar
    ...
  end
end
```

### Problems with the current approach

| Problem | Consequence |
|---|---|
| Command tree is implicit in imperative code | Cannot generate complete help/documentation without executing |
| Arguments and options scattered inside `when` bodies | No single declaration site per command |
| `ACTIONS` lists only the top level | `add_manual_header` produces incomplete output |
| Context variables (API objects, lambdas) flow down through closure scope | Cannot be expressed as pure data |
| Macros like `entity_execute` are used imperatively | Their semantics are hidden in code |
| The "loop" in `node` (`Node.new(...).execute_action(...)`) is opaque | Impossible to know statically that `node access_keys do v3 browse` exists |

---

## Key Constraints Discovered in the Codebase

### 1. Context Variables Between Nesting Levels

Nested sub-commands often consume variables built by a parent level.
These variables are **not** CLI inputs — they are derived objects (API clients, closures, computed paths).

Concrete examples found:

- **`shares.rb:131–133`** — `api_shares_admin` and `lookup_share` lambda are created at
  the `:admin` level, then consumed by every child command (`:node`, `:share`, `:user`, `:group`).
- **`shares.rb:161–164`** — `entity_type`, `entities_location`, `entities_prefix`,
  `entities_path` are computed at the `:user/:group` level, then used by the `:entity_verb` level.
- **`faspio.rb:54–79`** — `api` REST client is built (with conditional JWT/basic auth) before
  the command is dispatched, then used by both `:health` and `:bridges`.
- **`cos.rb:47`** — `node_plugin` is constructed at the `:node` level; the delegated
  `execute_action` call consumes it.
- **`node.rb:825`** — `asyncs_id` is resolved at the `:ssync` level and used by every
  sub-command except the CRUD group.

**Implication for the DSL**: a command node must be able to declare a **setup block** that
runs before its children are dispatched, and pass its output (a context hash) down to them.

### 2. Shared Macros (`entity_execute`, `do_bulk_operation`, `execute_resource_action`)

Three macro patterns exist at different levels of abstraction:

**`entity_execute`** (defined in `Base`, used across all plugins) covers the five standard
CRUD verbs (`create`, `list`, `show`, `modify`, `delete`) for a single REST resource path.
It is a low-level building block: fixed verbs, one REST path, optional identifier lookup.

**`do_bulk_operation`** (defined in `Base`) wraps create/delete with optional bulk mode.
It is called by `entity_execute` and directly by plugins for custom bulk flows.

**`execute_resource_action`** (defined in `aoc.rb`, used only there) is a **higher-order
macro** that sits one level above `entity_execute`. It receives a `resource_type` symbol
from `ADMIN_OBJECTS` and *configures itself* at runtime:

```
execute_resource_action(:workspace)
  → resource_class_path  = "workspaces"
  → supported_operations = Operations::ALL + [:shared_folder, :dropbox]
  → list_default_fields  = %w[id name]
  → get_next_command(supported_operations)
      when *Operations::ALL  → entity_execute(...)
      when :shared_folder    → deep sub-tree (list / node / member → list)
      when :dropbox          → sub-tree (list)
```

The key distinction from `entity_execute`:
- `entity_execute` is **fixed-schema**: same 5 verbs, one REST path, called once.
- `execute_resource_action` is **polymorphic**: the available verbs, REST path, display
  fields, and even the sub-trees change depending on `resource_type`. It is essentially a
  parametric plugin embedded inside `aoc.rb`.

**Implication for the DSL**: `execute_resource_action` cannot be collapsed into a single
`entity_execute:` shorthand. It must be modelled as a **parameterised command group** — a
named template that is instantiated once per `resource_type`:

```ruby
# Conceptual DSL for aoc.rb:

# Declare the template once
resource_command_group :admin_resource,
  operations: ->(rt){ RESOURCE_OPERATIONS[rt] },          # per-type verbs
  path:       ->(rt){ RESOURCE_PATHS[rt] },               # per-type REST path
  fields:     ->(rt){ RESOURCE_FIELDS[rt] },              # per-type default fields
  extensions: ->(rt){ RESOURCE_EXTENSIONS[rt] }           # per-type extra sub-trees

# Instantiate it for each resource type in ADMIN_OBJECTS
ADMIN_OBJECTS.each do |rt|
  command rt, parent: :admin,
    description: "Manage #{rt} objects",
    resource_group: :admin_resource,
    resource_type:  rt
end
```

The `resource_group:` field in `CommandSpec` tells the dispatcher to expand the command
into its parameterised sub-tree rather than looking for children in the flat registry.

The per-type extension sub-trees (`:shared_folder → node → …`, `:node → do → …`) are
still declared as regular commands in the flat registry, parented under the resource
command path, using the `resource_type` value as a dynamic path segment.

Rather than trying to collapse `execute_resource_action` into the DSL on the first pass,
it is treated as an **opaque handler** during Phase 5 migration and refactored only if
the pattern appears in more than one plugin.

### 3. The Delegation Loop in `node`

`node access_keys do v3 <command>` creates a new `Node` instance and calls
`execute_action(command_legacy)` on it, where `command_legacy` is any command from
`V3_IN_V4_ACTIONS`. This is a **dynamic re-entry** into the same command tree.

In the DSL this is expressed with a `delegates_to:` field that points to another registered
command group, making the loop explicit and statically visible.

### 4. Optional Positional Arguments and Multi-Argument Signatures

Not all positional arguments are mandatory. Two patterns appear in the codebase:

**a) Trailing optional argument with a typed default and schema** — `async_info_from_args`
in [`sync_actions.rb:29-31`](lib/aspera/cli/sync_actions.rb:29):

```ruby
path      = options.get_next_argument('path')                            # mandatory String
sync_info = options.get_next_argument('sync info',
              mandatory: false, validation: Hash,
              default: {}, schema: Schema::Registry::SYNC_CONF)          # optional Hash
```

The second argument is consumed only if present; otherwise a default value is used.
The command signature is: `sync <direction> <path> [<sync_info>]`

**b) Optional multiple trailing arguments** — [`server.rb:225`](lib/aspera/cli/plugins/server.rb:225):

```ruby
command_arguments = options.get_next_argument(
  'ascmd command arguments', multiple: true, mandatory: false)
```

Zero or more trailing string arguments; the command works with an empty list.

**Implication for the DSL**: `ArgumentSpec` must support `mandatory: false` and `default:`.
Declaration order in the `arguments:` array defines the parsing order — mandatory
arguments first, optional trailing arguments last.

### 5. Conditional Positional Arguments Controlled by `--sources`

`upload` and `download` commands read the list of files from the positional argument stream
**only when** the option `--sources` equals its default value `@args`. If the user sets
`--sources=@ts` (paths from `--ts` transfer spec) or `--sources=@json:[...]` (inline
list), the positional argument stream is **not consumed at all**.

This logic lives entirely in [`transfer_agent.rb:199-231`](lib/aspera/cli/transfer_agent.rb:199):

```
--sources=@args   → consume all remaining positional arguments as file paths
--sources=@ts     → paths already in --ts, consume nothing from arg stream
--sources=[...]   → inline Array, consume nothing from arg stream
```

The plugins never call `options.get_next_argument` for file paths; they call
`transfer.ts_source_paths` (or `transfer.start` which calls it internally).

**This is categorically different from a positional argument**:
- Consumption of the argument stream is **conditional** on the value of `--sources`.
- It consumes **all remaining** arguments when active.
- It is not declared at the command level — it is an implicit contract between the
  `upload`/`download` handler and `TransferAgent`.

**Implication for the DSL**: transfer commands declare a special attribute
`transfer_paths: :send | :receive` instead of a positional argument. The dispatcher
recognises this attribute and delegates file-list resolution to `TransferAgent`:

```ruby
command :upload, parent: :files,
  description: 'Upload files to the node',
  transfer_paths: :send     # file list resolved by TransferAgent from --sources

command :download, parent: :files,
  description: 'Download files from the node',
  transfer_paths: :receive
```

`transfer_paths:` is mutually exclusive with `arguments:` in any single command
declaration; a command either consumes an explicit positional argument list or delegates
entirely to `TransferAgent`.

### 6. Aliases

`options.get_next_command` supports an `aliases:` hash (e.g. `{repository: :files}` in
`shares.rb`). Aliases must be first-class in the DSL declaration.

---

## Proposed DSL — Core Concepts

### Flat registry with parent paths

Every command is declared once, at class level, with a `parent:` key that is either `nil`
(root / plugin level) or an `Array<Symbol>` representing the full path from the plugin
root to the immediate parent.

```ruby
# In a plugin class body (class-level DSL):

command :transfer, description: 'Manage transfers'

command :list, parent: :transfer,
  description: 'List active transfers',
  options: [:query, :once_only]

command :cancel, parent: :transfer,
  description: 'Cancel a transfer by identifier',
  arguments: [{ name: :id, description: 'Transfer ID', type: :identifier }]
```

Because the registry is flat and keyed by full path, there are no recursive data structures.
Loops are expressed via `delegates_to:`.

### Command declaration parameters

| Parameter | Type | Meaning |
|---|---|---|
| `id` | `Symbol` | Unique identifier within its parent's namespace |
| `parent` | `Symbol \| Array<Symbol> \| nil` | Full path to parent; `nil` for root commands |
| `description` | `String` | User-facing help text |
| `options` | `Array<Symbol>` | Option names (declared separately) consumed by this command |
| `arguments` | `Array<ArgumentSpec>` | Positional arguments, in order |
| `handler` | `Symbol \| nil` | Instance method name called when this is a leaf command |
| `setup` | `Symbol \| nil` | Instance method called on the **parent** node just before dispatching to its children; returns a Hash merged into `ctx` and passed down |
| `delegates_to` | `Symbol \| Array<Symbol> \| nil` | Re-enter the command tree at this path (for loops) |
| `delegate_instance` | `Symbol \| nil` | Instance method returning a different plugin object; dispatcher calls `dispatch_from_registry` on that object |
| `aliases` | `Hash{Symbol => Symbol}` | Accepted shortcuts that resolve to declared sibling command names; forwarded as-is to `get_next_command` |
| `entity_execute` | `Hash \| nil` | Shorthand: expand to `Base#entity_execute` with these parameters |
| `transfer_paths` | `:send \| :receive \| nil` | Signals that file-list resolution is delegated to `TransferAgent`; mutually exclusive with `arguments:` |
| `condition` | `Symbol \| nil` | Instance method returning `Boolean`; if `false` at runtime, command is hidden from dispatch but shown in help with an annotation |

### Argument declaration parameters

| Parameter | Type | Meaning |
|---|---|---|
| `name` | `Symbol` | Name used in help and error messages |
| `description` | `String` | User-facing description |
| `type` | `Class \| Array<Class> \| :identifier` | Validated type; `:identifier` triggers `instance_identifier` |
| `mandatory` | `Boolean` | Default `true`; optional arguments must come after all mandatory ones |
| `multiple` | `Boolean \| String` | `true`: consume all remaining; `String`: consume until named marker |
| `default` | `Object \| nil` | Default value when `mandatory: false` and no argument provided on command line |
| `schema` | `String \| nil` | JSON schema name for validation and `--help` introspection |

### Option declaration parameters

Options are declared separately (one declaration per option name, globally or per plugin)
and referenced by name from command declarations. This mirrors the existing `options.declare`
call but associates the option with the command(s) that use it.

---

## Architecture

### New files

| File | Role |
|---|---|
| `lib/aspera/cli/command_spec.rb` | Data classes: `CommandSpec`, `ArgumentSpec`, `OptionSpec` |
| `lib/aspera/cli/command_registry.rb` | Registry: stores specs, resolves paths, validates the graph |

### Changes to existing files

| File | Change |
|---|---|
| `lib/aspera/cli/plugins/base.rb` | Add DSL class methods (`command`, `option`); add `dispatch_from_registry`; keep `execute_action` as fallback for non-migrated plugins |
| Each plugin file | Replace `ACTIONS` + `execute_action` case/when with DSL declarations + handler methods |

### Dispatcher algorithm

The dispatcher operates in two distinct phases for each node:

**Phase A — Setup (on the current node, before consuming the next argument)**:
The `setup:` method of the *current* node is called first, its result merged into `ctx`.
This matches the imperative pattern where variables are built *before* `get_next_command`.

**Phase B — Dispatch (consume one argument, select child)**:
The next argument is consumed and matched against the node's children. Conditional
commands (those with a `condition:` method returning `false`) are excluded from dispatch
but included in help output with an annotation.

```
dispatch_from_registry(current_path, ctx = {})
  spec = registry[current_path]   # nil if root call

  # Phase A: setup on the current node before dispatching to children
  if spec&.setup
    ctx = ctx.merge(send(spec.setup))
  end

  # Phase B: dispatch to a child
  children  = registry.children_of(current_path)
  available = children.reject { |_, c| c.condition && !send(c.condition) }
  aliases   = children.flat_map { |_, c| c.aliases&.to_a }.to_h
  command   = options.get_next_command(available.keys, aliases: aliases)
  child     = available[command]

  # Loop / instance delegation
  if child.delegate_instance
    target = send(child.delegate_instance)
    return target.dispatch_from_registry(child.delegates_to || [], {})
  end
  if child.delegates_to
    return dispatch_from_registry(child.delegates_to, ctx)
  end

  # Shorthand macro expansion
  if child.entity_execute
    return run_entity_execute(child.entity_execute, ctx)
  end

  grandchildren = registry.children_of(current_path + [command])
  if grandchildren.any?
    # Intermediate node: recurse (child's setup will run at the top of next call)
    dispatch_from_registry(current_path + [command], ctx)
  else
    # Leaf: resolve arguments, handle transfer_paths, call handler
    if child.transfer_paths
      # File list is delegated to TransferAgent; no positional args consumed here
      return send(child.handler, **ctx)
    end
    args = (child.arguments || []).map { |a| resolve_argument(a) }
    send(child.handler, *args, **ctx)
  end
end
```

Key properties:
- `setup:` always runs on the **current node** at the start of its dispatch call — i.e.,
  it is called once, before its children are considered, matching the closure pattern.
- `condition:` commands are **visible in help** but **unavailable at runtime** when the
  condition is false (e.g. ascmd commands annotated `[SSH only]`).
- `ctx` is **additive** (merged, never replaced): each `setup:` call enriches the
  accumulated context passed to all descendants.
- `transfer_paths:` bypasses argument resolution entirely; `TransferAgent#ts_source_paths`
  handles the argument stream conditionally based on `--sources`.

---

## Migration Phases

### Phase 0a — Data classes and registry
**Status: [ ] pending**

**Intent**: Define the pure data structures that describe commands. No runtime behavior,
no changes to `Base` or any plugin. Can be reviewed and tested in complete isolation.

**Expected outcomes**:
- `CommandSpec`, `ArgumentSpec`, and `OptionSpec` exist as keyword-argument Structs
  with all fields documented in the DSL parameter tables above.
- `CommandRegistry` stores specs indexed by full path (`Array<Symbol>`), exposes
  `register(spec)`, `children_of(path)`, `[]( path)`, `all_paths`, and `validate!`.
- `validate!` raises on: duplicate paths, `delegates_to` pointing to unknown paths,
  `delegate_instance` without `delegates_to`, `transfer_paths` combined with `arguments`.
- Unit tests cover path resolution, duplicate detection, alias reconstruction, and
  validation errors.

**Todo**:
1. Create `lib/aspera/cli/command_spec.rb`:
   - `ArgumentSpec`: `name`, `description`, `type`, `mandatory` (default `true`),
     `multiple` (default `false`), `default`, `schema`.
   - `OptionSpec`: `name`, `description`, `allowed`, `default`, `short`.
   - `CommandSpec`: all fields from the parameter table; `full_path` computed from
     `parent` + `id`.
2. Create `lib/aspera/cli/command_registry.rb`:
   - Per-class instance (not shared across the inheritance chain).
   - `register(spec)` stores spec; raises on duplicate `full_path`.
   - `children_of(path)` returns `Hash{Symbol => CommandSpec}` of direct children,
     including their `aliases` expanded to the parent `get_next_command` format.
   - `validate!` performs cross-spec consistency checks.
3. Write unit tests for `CommandRegistry` covering all validation rules.

**Relevant context**:
- DSL parameter tables above (single source of truth for field names and types)
- `lib/aspera/cli/options.rb:470` — `get_next_command` signature to understand the
  `aliases:` format expected

---

### Phase 0b — Dispatcher and DSL methods in `Base`
**Status: [ ] pending**

**Intent**: Integrate the registry into `Base` and make it callable by migrated plugins,
while keeping all non-migrated plugins working exactly as before.

**Expected outcomes**:
- `Base` has class-level `command(...)` and `option(...)` DSL methods.
- `Base#execute_action` detects whether the subclass has DSL commands registered; if yes,
  calls `dispatch_from_registry([], {})` instead of raising `NotImplementedError`.
- Non-migrated plugins that override `execute_action` are unaffected.
- `Base#dispatch_from_registry` implements the two-phase algorithm documented above.
- `Base#run_entity_execute(spec, ctx)` wraps the existing `entity_execute`.
- `Base#resolve_argument(spec)` handles all `ArgumentSpec` types including `:identifier`.
- `Base#generate_help(path)` recursively builds a tree from the registry for help output;
  `condition:` commands are included with a `[condition_name]` annotation.

**Todo**:
1. Add `command_registry` class-level accessor to `Base`; each subclass gets its own
   instance (initialized lazily with `@command_registry ||= CommandRegistry.new`).
2. Add `Base.command(id, **kwargs)` and `Base.option(name, **kwargs)` class methods.
3. Add `Base#dispatch_from_registry(path, ctx = {})` instance method per algorithm above.
4. Add `Base#run_entity_execute(spec, ctx)`.
5. Add `Base#resolve_argument(arg_spec)` dispatching on `arg_spec.type`:
   - `Class` / `Array<Class>` → `options.get_next_argument`
   - `:identifier` → `options.instance_identifier`
6. Modify `Base#execute_action` to check `self.class.command_registry.any?` and delegate
   to `dispatch_from_registry`; otherwise raise `NotImplementedError` as today.
7. Add `Base#generate_help(path)`.

**Relevant context**:
- `lib/aspera/cli/plugins/base.rb:30–38` — `initialize` and `execute_action` current behavior
- `lib/aspera/cli/plugins/base.rb:60` — `add_manual_header` (to be replaced later)
- `lib/aspera/cli/plugins/base.rb:132` — `entity_execute` signature
- `lib/aspera/cli/options.rb:460–470` — `instance_identifier` and `get_next_command`

---

### Phase 1 — Migrate trivial plugins (1 level, no context variables)
**Status: [ ] pending**

**Intent**: Validate the DSL on the simplest real-world cases before tackling complex ones.
These plugins have a single dispatch level and no context variables passed between levels.

**Target plugins**: `httpgw.rb` (2 commands), `alee.rb` (2 commands), `faspio.rb` (2 commands + pre-setup)

**Expected outcomes**:
- Each migrated plugin has no `ACTIONS` constant and no `execute_action` method.
- All commands are declared with `command(...)` at class level.
- Handler methods are named (e.g. `handle_health`, `handle_info`), pure, and unit-testable.
- `faspio.rb` uses a `setup:` method to build the `api` object before dispatching.
- All existing integration tests for these plugins pass.

**Todo**:
1. Migrate `httpgw.rb`:
   - Declare `:health` and `:info` commands with `handler:` pointing to new methods.
   - Extract handler bodies from `execute_action` into `handle_health` and `handle_info`.
   - Note: `base_url` is read at the top of `execute_action` — move it into each handler or into a `setup:` method.
2. Migrate `alee.rb` using the same pattern.
3. Migrate `faspio.rb`:
   - The `api` object (built from auth option before dispatch) maps to a `setup:` method `:build_api` that returns `{api: ...}`.
   - Handler methods receive `api:` as a keyword argument from the context hash.
4. Run full test suite after each plugin migration.

**Relevant context**:
- `lib/aspera/cli/plugins/httpgw.rb:48–65`
- `lib/aspera/cli/plugins/faspio.rb:53–98`

---

### Phase 2 — Migrate single-level plugins with `entity_execute` expansion
**Status: [ ] pending**

**Intent**: Validate the `entity_execute:` shorthand and the pattern where a command
fully delegates to a REST macro.

**Target plugins**: `cos.rb` (1 command + delegation to `Node`), `faspio.rb` `:bridges`
(already covers `entity_execute` with no sub-commands)

**Expected outcomes**:
- A command declared with `entity_execute: { api: ..., entity: ... }` is correctly expanded
  by `run_entity_execute` into the five CRUD verbs consumed from the argument stream.
- `cos.rb` demonstrates the `delegates_to:` mechanism: the `:node` command builds an API
  object via `setup:`, then delegates to `Node`'s registered command group.

**Todo**:
1. Add `entity_execute:` hash support to `CommandSpec` and to `run_entity_execute`.
2. Migrate `cos.rb`:
   - `:node` command has `setup: :build_cos_node` (builds `api_node` and `node_plugin`).
   - `:node` command has `delegates_to: [:node_commands]` pointing to `Node`'s `COMMANDS_COS` group.
3. Ensure `delegates_to:` correctly passes the `ctx` hash (including the constructed `node_plugin`) to the delegated dispatcher.
4. Run full test suite.

**Relevant context**:
- `lib/aspera/cli/plugins/cos.rb:27–51`
- `lib/aspera/cli/plugins/base.rb:132–204` — `entity_execute`

---

### Phase 3 — Migrate medium-complexity plugins (2 levels, limited context variables)
**Status: [ ] pending**

**Intent**: Validate the `setup:` + context-passing mechanism on plugins with two nesting
levels where a context variable flows from parent to children.

**Target plugins**: `console.rb`, `ats.rb`, `orchestrator.rb`, `server.rb`

**Expected outcomes**:
- The `setup:` → context-hash → handler pattern correctly replaces closure scope in each plugin.
- All nesting levels are visible in the registry (full introspection works).

**Todo**:
1. For each plugin, map the existing `execute_action` to command declarations:
   a. Identify which variables are built before `get_next_command` — these become `setup:` methods.
   b. Identify which child commands share the same variable — these are the `ctx` consumers.
   c. Declare commands with `parent:`, `setup:`, `handler:` as appropriate.
2. Migrate `server.rb` (handles `ascmd` alias expansion — use the `aliases:` parameter).
3. Migrate `orchestrator.rb` (3-level nesting, workflow/workorder/step).
4. Run full test suite after each plugin.

**Relevant context**:
- `lib/aspera/cli/plugins/server.rb:184–244`
- `lib/aspera/cli/plugins/orchestrator.rb`

---

### Phase 4 — Migrate complex plugins (`shares`, `faspex`, `faspex5`, `preview`)
**Status: [ ] pending**

**Intent**: Validate deeper nesting (3–4 levels) and the lambda/closure context pattern.

**The `shares.rb` challenge** — this plugin is the canonical example of context flow:

```
execute_action
  when :admin
    api_shares_admin = ...                  # context variable
    lookup_share     = ->(f,v){ ... }       # context lambda
    admin_command = get_next_command(...)
      when :share
        share_command = get_next_command(...)
          when :user_permissions
            share_id = instance_identifier(&lookup_share)    # uses ctx lambda
            entity_execute(api: api_shares_admin, ...)       # uses ctx API
      when :user, :group
        entity_type = admin_command                          # ctx from this level
        entities_location = get_next_command(...)            # ctx from this level
        entities_path = "data/..."                           # derived ctx
        entity_verb = get_next_command(...)
          when *Operations::ALL
            entity_execute(api: api_shares_admin, ...)       # uses grandparent ctx
```

The context hash accumulates as it flows down:
- Level `:admin` adds `{api: api_shares_admin, lookup_share: lookup_share}`.
- Level `:user/:group` adds `{entity_type:, entities_location:, entities_path:, lookup_block:}`.
- Level `:entity_verb` consumes all of the above.

**Expected outcomes**:
- All four plugins are migrated with full context-hash propagation.
- No closure scope is used between nesting levels.

**Todo**:
1. Migrate `shares.rb` as the reference implementation for multi-level context accumulation.
2. Document the context accumulation pattern in code comments as a template for Phase 5.
3. Migrate `faspex.rb`, `faspex5.rb`, `preview.rb`.
4. Run full test suite after each plugin.

**Relevant context**:
- `lib/aspera/cli/plugins/shares.rb:103–218`

---

### Phase 5 — Migrate the two most complex plugins (`node`, `aoc`)
**Status: [ ] pending**

**Intent**: Complete the migration with the largest, most nested plugins.

**The `node.rb` loop challenge**:

The sequence `node access_keys do v3 <command>` creates a fresh `Node` instance
pointed at a different API endpoint and calls `execute_action(command_legacy)` on it.
This is a "portal" to the same command tree but via a different API object.

DSL representation:
```ruby
command :v3, parent: [:access_keys, :do],
  description: 'Access the storage node via legacy v3 commands',
  setup:        :resolve_v3_node,       # builds a new Node instance and its api
  delegates_to: []                      # re-enter the root of this plugin's command tree
```

The `setup: :resolve_v3_node` method returns `{node_instance: Node.new(...)}`.
The dispatcher, on seeing `delegates_to: []`, re-enters `dispatch_from_registry([], ctx)`
— but before dispatching the next command, it swaps `self` to `ctx[:node_instance]`
(or calls `ctx[:node_instance].dispatch_from_registry([], {})`).

This is the only case that requires **instance delegation**, not just context passing.
A dedicated mechanism `delegate_instance:` (a method name that returns the target plugin
instance) separates it cleanly from the simpler `delegates_to:`.

**Todo**:
1. Add `delegate_instance:` field to `CommandSpec`.
2. Update `dispatch_from_registry` to handle `delegate_instance:` by calling
   `target_instance.dispatch_from_registry(delegates_to_path, ctx)`.
3. Map `node.rb`'s `COMMANDS_GEN3`, `COMMANDS_GEN4`, `COMMON_ACTIONS`, `V3_IN_V4_ACTIONS`
   groups to named command sets in the registry (replacing the constant arrays).
4. Declare all commands in `node.rb` with `parent:`, `setup:`, `handler:`, `entity_execute:`,
   or `delegate_instance:` as appropriate.
5. Migrate `aoc.rb` (largest plugin; builds on patterns established in previous phases).
6. Run full test suite.

**Relevant context**:
- `lib/aspera/cli/plugins/node.rb:489–499` — the `v3` delegation loop
- `lib/aspera/cli/plugins/node.rb:139–162` — command group constants

---

### Phase 6 — Remove the old infrastructure
**Status: [ ] pending**

**Intent**: Once every plugin is migrated, remove the legacy scaffolding.

**Expected outcomes**:
- `ACTIONS` constant is gone from all plugins.
- `execute_action` override is gone from all plugins.
- `Base#add_manual_header` is replaced by `Base#generate_help`.
- `Base#execute_action` raises `NotImplementedError` only as a safety net (or is removed entirely).
- Help output is richer: all nesting levels, arguments, and options are shown per command.

**Todo**:
1. Delete `ACTIONS` from all plugin files (grep for `ACTIONS =`).
2. Delete all `execute_action` overrides.
3. Replace `add_manual_header` call in `Base#initialize` with `generate_help`.
4. Update `Runner` to call `dispatch_from_registry` instead of `execute_action`.
5. Delete the `NotImplementedError` fallback from `Base`.
6. Run full test suite and update any test that was checking `ACTIONS` contents directly.

---

## Decision Log

| # | Decision | Rationale |
|---|---|---|
| 1 | Progressive migration (opt-in) | Reduces risk; each step is independently verifiable; a regression in one plugin does not affect others |
| 2 | Flat registry keyed by full path `Array<Symbol>` | Avoids recursive data structures; makes path lookup O(1); simplifies serialization for docs |
| 3 | `setup:` runs on the **current node** before dispatching to children | Matches the imperative pattern where local variables are created before `get_next_command`; no virtual/synthetic nodes needed |
| 4 | `ctx` hash is additive (merged, never replaced) | Each `setup:` enriches the accumulated context; descendants can rely on all ancestor setups |
| 5 | `condition:` for runtime-conditional commands; all commands visible in help | Static documentation is complete; runtime filtering via `condition:` method; annotated in help output |
| 6 | `entity_execute:` shorthand in DSL | Keeps CRUD declarations DRY; preserves introspectability of the five verbs |
| 7 | `execute_resource_action` kept as opaque handler in Phase 5 | Pattern is unique to `aoc.rb`; abstracting it prematurely adds complexity without benefit |
| 8 | `delegates_to:` for command-tree loops | Makes re-entry statically visible; avoids special-casing `Node.new(...).execute_action` |
| 9 | `delegate_instance:` as a separate concept from `delegates_to:` | The `v3` case in `node` requires a different API object, not just a different path; conflating the two would complicate the dispatcher |
| 10 | `transfer_paths: :send\|:receive` instead of positional args for upload/download | The `--sources` mechanism in `TransferAgent` is incompatible with static argument declaration; the special attribute makes the contract explicit |
| 11 | Options referenced by name, not inlined | A single `option(...)` declaration drives both `options.declare` registration and DSL metadata |
| 12 | Coexistence via override of `execute_action` in non-migrated plugins | Zero changes required in non-migrated plugins; the base class fallback is the safety net |
| 13 | `Node::COMMANDS_*` constants become named groups in the `Node` registry | Other plugins (`cos.rb`, `shares.rb`, `aoc.rb`) reference these constants; named groups remain accessible as `Node.command_registry.group(:commands_cos)` |

---

## Open Questions

1. **`options.declare` timing**: should `Base.option(...)` call `options.declare` immediately
   (at class definition time, which would mean at `require` time), or should
   `dispatch_from_registry` call `options.declare` lazily at runtime just before the
   relevant command is dispatched? Lazy matches current behavior (`declare_options` called
   in `initialize`) but complicates the dispatcher. Eager is simpler but may declare options
   for plugins not in use.

2. **Test strategy during coexistence**: should migrated plugins have their own unit tests
   for handler methods (now pure instance methods with no argument-stream side-effects),
   or is the existing integration test suite sufficient for validating each migration step?

3. **`Node` command group sharing**: `Node::COMMANDS_COS`, `Node::COMMANDS_SHARES` etc. are
   referenced by other plugins. How should the DSL expose named subsets of a plugin's
   command tree for external use? Options: (a) keep the `Array<Symbol>` constants alongside
   the DSL as a transitional bridge; (b) add a `command_group(name, parent:)` DSL method
   that names a subtree and allows external plugins to reference it via
   `delegates_to: Node.command_group(:commands_cos)`.
