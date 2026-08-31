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
- **Ruby Runtime**: Ruby ≥ 3.1 interpreter
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
- Pre-parses early options (`--log-level`, `--log-format`, `--logger`) before full initialization
- Fixes the home directory on Windows via `Environment.instance.fix_home`
- Delegates to the main CLI processor

```ruby
#!/usr/bin/env ruby
# Pre-parses --log-level, --log-format, --logger before full initialization
ARGV.each { |arg| ... }
require 'aspera/environment'
require 'aspera/cli/runner'
Aspera::Environment.instance.fix_home
Aspera::Cli::Runner.new(ARGV).run
```

#### Runner and Context

**Files**: [`lib/aspera/cli/runner.rb`](../lib/aspera/cli/runner.rb), [`lib/aspera/cli/context.rb`](../lib/aspera/cli/context.rb)

The `Runner` class orchestrates the full command lifecycle:

- **`run`**: Main entry point — calls `run_with_result`, displays the result via `Formatter`, handles all exceptions, and exits with the appropriate status code.
- **`run_with_result`**: Pure computation entry point — initializes all agents and options, resolves the target plugin, executes the action, and returns a `Result` object. Raises on error. Used by the MCP server to run commands in-process.

All shared objects (options manager, transfer agent, config plugin, formatter, preset manager, HTTP config, etc.) are held in a `Context` instance and passed to plugins by reference.

#### CLI Options

**File**: [`lib/aspera/cli/options.rb`](../lib/aspera/cli/options.rb)

The `Cli::Options` class handles:

- **Option Parsing**: Custom command-line argument processing
- **Extended Value Syntax**: Support for complex parameter types (JSON, YAML, Ruby expressions, `@preset:`, `@vault:`, `@args:`)
- **Option Validation**: Type checking and value constraints
- **Configuration Management**: Integration with persistent configuration

Key responsibilities:

- Declare and validate CLI options
- Support for boolean, string, integer, array, hash types
- Handle sensitive data (passwords, secrets) with masking
- Provide option inheritance and defaults

#### Plugin System

**Directory**: [`lib/aspera/cli/plugins/`](../lib/aspera/cli/plugins/)

The plugin architecture enables modular command implementation for different Aspera products:

**Base Plugin** ([`base.rb`](../lib/aspera/cli/plugins/base.rb)):

- Defines standard CRUD operations: `create`, `list`, `modify`, `show`, `delete`
- Provides bulk operation support
- Implements resource identifier resolution (including percent-selector syntax)
- Manages plugin context (options, transfer agent, config, formatter)

**Product Plugins** (registered and exposed as top-level commands):

- [`aoc.rb`](../lib/aspera/cli/plugins/aoc.rb) - Aspera on Cloud
- [`ats.rb`](../lib/aspera/cli/plugins/ats.rb) - Aspera Transfer Service
- [`faspex.rb`](../lib/aspera/cli/plugins/faspex.rb) - Faspex 4
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

**Utility Plugins** (registered commands but not product-specific):

- [`config.rb`](../lib/aspera/cli/plugins/config.rb) - Configuration management (includes `AscpActions`, `PresetActions`, `GemChecker`, `VaultManager`, `SyncActions` mixins)
- [`preview.rb`](../lib/aspera/cli/plugins/preview.rb) - File preview generation
- [`mcp.rb`](../lib/aspera/cli/plugins/mcp.rb) - Model Context Protocol server (exposes `ascli` to AI assistants)

**Internal Base Classes** (excluded from factory registration via `IGNORE_PLUGINS`):

- [`base.rb`](../lib/aspera/cli/plugins/base.rb) - Abstract base class for all plugins
- [`basic_auth.rb`](../lib/aspera/cli/plugins/basic_auth.rb) - Abstract base class for plugins using basic authentication (url/username/password)
- [`oauth.rb`](../lib/aspera/cli/plugins/oauth.rb) - OAuth token utility (not a product plugin)
- [`factory.rb`](../lib/aspera/cli/plugins/factory.rb) - Plugin factory (singleton)

#### Command DSL

All plugins declare their command tree using a class-level DSL defined in `Base`. This
replaced the former `ACTIONS` + `execute_action` `case/when` pattern, making the full
command tree statically introspectable, self-documenting, and testable without execution.

**Key files**:

- [`lib/aspera/cli/command_spec.rb`](../lib/aspera/cli/command_spec.rb) — data classes: `CommandSpec`, `ArgumentSpec`, `OptionSpec`
- [`lib/aspera/cli/command_registry.rb`](../lib/aspera/cli/command_registry.rb) — flat registry keyed by full path (`Array<Symbol>`)

**Command declaration** (`Base.command`):

| Parameter | Type | Meaning |
| --- | --- | --- |
| `id` | `Symbol` | Unique identifier within its parent's namespace |
| `parent` | `Symbol \| Array<Symbol> \| nil` | Full path to parent; `nil` for root commands |
| `description` | `String` | User-facing help text |
| `options` | `Array<Symbol>` | Option names consumed by this command |
| `arguments` | `Array<ArgumentSpec>` | Positional arguments in parse order |
| `handler` | `Symbol \| Proc \| nil` | Handler for the leaf command. Three forms: **(1)** omitted → convention `handle_<full_path_joined_by_underscores>` is called; **(2)** `Symbol` → named instance method (use when body > 3 lines); **(3)** `Proc` / lambda → inline handler (use when body ≤ 3 lines — prefer `->{ ... }` for zero or keyword-only args, `lambda do \|arg\| … end` for multi-line bodies) |
| `setup` | `Symbol \| nil` | Instance method called before dispatching to children; returns a `Hash` merged into the context (`ctx`) passed down |
| `root_setup` | `Symbol \| nil` | Instance method called once before the root dispatch (class-level DSL method); used when state must exist before root command conditions are evaluated |
| `delegates_to` | `Symbol \| Array<Symbol> \| nil` | Re-enter the command tree at this path (for delegation loops) |
| `delegate_instance` | `Symbol \| nil` | Instance method returning a different plugin object; dispatcher calls `dispatch_from_registry` on that object |
| `aliases` | `Hash{Symbol => Symbol}` | Accepted shortcuts resolving to declared sibling command names |
| `entity_execute` | `Hash \| nil` | Shorthand that expands to `Base#entity_execute` (five standard CRUD verbs) |
| `transfer_paths` | `:send \| :receive \| nil` | File-list resolution delegated to `TransferAgent`; mutually exclusive with `arguments:` |
| `condition` | `Symbol \| nil` | Instance method returning `Boolean`; if `false`, command is hidden from dispatch but shown in help with an annotation |

**`entity_command` helper** (`Base.entity_command`):

A higher-level DSL shorthand that wraps `command(id, …, entity_execute: {…})`. Use it to declare a CRUD command in a single line:

```ruby
entity_command :dropboxes, api: :@dropboxes_api, entity: 'admin/dropboxes'
# equivalent to:
command(:dropboxes, description: 'Manage dropboxes', entity_execute: {api: :@dropboxes_api, entity: 'admin/dropboxes'})
```

| Parameter | Type | Meaning |
| --- | --- | --- |
| `id` | `Symbol` | Command identifier |
| `api` | `Symbol` | Method name (`:method`) or instance variable (`:@ivar`) resolved at runtime to the REST API object |
| `entity` | `String` | API sub-path (e.g. `'admin/dropboxes'`) |
| `description` | `String \| nil` | User-facing help text; defaults to `"Manage <last segment of entity>"` when omitted |
| `**kwargs` | `Hash` | Any extra `entity_execute` params forwarded verbatim (`display_fields:`, `command:`, `is_singleton:`, …) |

**Argument declaration** (`ArgumentSpec`):

| Parameter | Type | Meaning |
| --- | --- | --- |
| `name` | `Symbol` | Name used in help and error messages |
| `description` | `String` | User-facing description |
| `type` | `Class \| Array<Class> \| :identifier` | Validated type; `:identifier` triggers `instance_identifier` |
| `mandatory` | `Boolean` | Default `true`; optional arguments must come after all mandatory ones |
| `multiple` | `Boolean` | If `true`, consume all remaining positional arguments |
| `default` | `Object \| nil` | Default value when `mandatory: false` and no argument provided |
| `schema` | `String \| nil` | JSON schema name for validation and help introspection |

**Dispatcher algorithm** (`Base#dispatch_from_registry`):

The dispatcher operates in two phases for each node:

1. **Setup** — if the current node declares a `setup:` method, it is called first; its return value is merged into the context hash `ctx` and passed to all descendants.
2. **Dispatch** — the next positional argument is consumed and matched against the node's children. `condition:` commands are excluded from runtime dispatch but included in help output.

```text
dispatch_from_registry(current_path, ctx = {})
  # Phase A: setup on the current node
  ctx = ctx.merge(send(spec.setup)) if spec&.setup

  # Phase B: select child command
  command = options.get_next_command(available_children, aliases: ...)
  child   = available[command]

  # Delegation to another plugin instance
  return target.dispatch_from_registry(child.delegates_to, {}) if child.delegate_instance

  # Path delegation (loops)
  return dispatch_from_registry(child.delegates_to, ctx) if child.delegates_to

  # CRUD shorthand
  return run_entity_execute(child.entity_execute, ctx) if child.entity_execute

  if grandchildren.any?
    dispatch_from_registry(current_path + [command], ctx)   # intermediate node
  else
    send(handler_for(child), **ctx)                          # leaf: call handler
  end
end
```

Key properties of the `ctx` hash:

- **Additive**: each `setup:` call enriches the accumulated context; descendants can rely on all ancestor setups.
- **Setup runs before child selection**: matches the imperative pattern where local variables are created before `get_next_command`.
- `transfer_paths:` bypasses argument resolution entirely; `TransferAgent#ts_source_paths` handles the argument stream conditionally based on `--sources`.

#### Handler style convention

| Condition | Preferred form |
| --- | --- |
| 1 line, no args | `handler: ->{…}` |
| 1 line, with args | `handler: ->(arg:){…}` |
| 2–3 lines, inline | `command(:x, …, handler: lambda do … end)` |
| > 3 lines | named method `def handle_<full_path>` |

The 3-line threshold is deliberately informal. The deciding factor is readability at the call site: if the handler fits on one line without obscuring the `command(...)` declaration, an inline `->` is preferred. If the body needs local variables, loops, or `rescue`, a named method is clearer.

**Precedence rule**: `lambda do...end` has low binding priority — if `command` is called without parentheses, Ruby attaches the `do...end` to `command` instead of `lambda`, causing `tried to create Proc object without a block` at class load time. Always use `command(...)` with parentheses when the handler is a `lambda do...end`.

**Do not** use `lambda{ }` (braces with `lambda` keyword): rubocop's `SpaceInsideBlockBraces` forbids inner spaces, making multi-line bodies unreadable. The codebase uses `->{}` for one-liners and `lambda do...end` for multi-line — no other form.

**Notable design decisions**:

| Decision | Rationale |
| --- | --- |
| Flat registry keyed by full path `Array<Symbol>` | Avoids recursive data structures; path lookup is O(1) |
| `setup:` runs on the current node before dispatching | Matches the imperative pattern; no virtual/synthetic nodes needed |
| `condition:` commands visible in help but excluded at runtime | Static documentation is complete; runtime filtering via a method |
| `entity_execute:` shorthand | Keeps CRUD declarations DRY while preserving introspectability |
| `entity_command` helper | One-liner alternative to `command(…, entity_execute: {…})` when no extra `command` parameters are needed; `api:` is resolved at runtime so the API object can be created lazily |
| `delegate_instance:` separate from `delegates_to:` | The `node access_keys do v3` case needs a different API object, not just a different path |
| `transfer_paths: :send\|:receive` instead of positional args | The `--sources` mechanism in `TransferAgent` is incompatible with static argument declaration |
| Opaque private helpers for highly dynamic sub-trees | `execute_resource_action` (aoc), `execute_admin_entity_type` (shares), etc. contain runtime-dynamic dispatch that cannot be statically declared |
| `define_method` for homogeneous command groups | Avoids repetitive handler definitions for commands sharing the same one-line body |

#### Transfer Agent Abstraction

**File**: [`lib/aspera/cli/transfer_agent.rb`](../lib/aspera/cli/transfer_agent.rb)

The Transfer Agent provides a unified interface for initiating transfers across different FASP clients:

**Responsibilities**:

- Abstract transfer initiation across multiple agent types
- Manage transfer specifications (transfer_spec)
- Handle file list sources (`@args`, `@ts`, arrays)
- Coordinate transfer progress monitoring
- Send transfer completion notifications

**Agent Base Class** ([`lib/aspera/agent/base.rb`](../lib/aspera/agent/base.rb)):

```ruby
class Base
  # Start a transfer asynchronously (must be implemented by subclass)
  def start_transfer(transfer_spec)

  # Wait for all transfers to complete and return per-session statuses (must be implemented)
  def wait_for_transfers_completion

  # Wait for completion and validate statuses (public API)
  def wait_for_completion

  # Optional: release resources
  def shutdown
end
```

**Supported Agents**:

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
- **Session Management**: Connection pooling, SSL/TLS configuration

Features:

- Automatic JSON parsing for API responses
- Custom error classes for different HTTP status codes
- Support for streaming large file transfers
- Configurable retry policies for transient failures

#### Node API Client

**File**: [`lib/aspera/api/node.rb`](../lib/aspera/api/node.rb)

Specialized client for Aspera Node API with:

- **Access Key Management**: Gen4 access key support
- **Bearer Token Generation**: JWT-based authentication
- **File Operations**: Browse, upload, download, delete
- **Permission Management**: Fine-grained access control
- **Transfer Spec Generation**: Automatic transfer parameter creation
- **Caching**: Optional Redis-based response caching

#### OAuth Implementation

**Directory**: [`lib/aspera/oauth/`](../lib/aspera/oauth/)

Modular OAuth 2.0 support:

- **Generic OAuth** ([`generic.rb`](../lib/aspera/oauth/generic.rb)): Standard OAuth 2.0 flows
- **JWT** ([`jwt.rb`](../lib/aspera/oauth/jwt.rb)): JSON Web Token authentication
- **Web** ([`web.rb`](../lib/aspera/oauth/web.rb)): Browser-based OAuth flows
- **URL JSON** ([`url_json.rb`](../lib/aspera/oauth/url_json.rb)): Token from URL

### FASP Transfer Layer

#### ASCP Installation Manager

**File**: [`lib/aspera/ascp/installation.rb`](../lib/aspera/ascp/installation.rb)

Singleton class managing `ascp` binary location and SDK resources:

- **Product Detection**: Automatically finds installed Aspera products
- **SDK Installation**: Downloads and installs Transfer SDK
- **Path Resolution**: Locates `ascp` executable and supporting files
- **SSH Key Management**: Handles client SSH keys for authentication

Supported product detection:

- Aspera Desktop Client
- Aspera Connect
- Aspera Transfer SDK (`transferd`)
- Aspera for Desktop
- Aspera HSTS/ATS installations

#### Transfer Specification

**File**: [`lib/aspera/transfer/spec.rb`](../lib/aspera/transfer/spec.rb)

Transfer specifications define all parameters for a FASP transfer:

- Source and destination paths
- Transfer direction (upload/download)
- Rate control (target rate, min rate, policy)
- Encryption settings
- Resume policies
- Authentication credentials
- Protocol options (UDP/TCP ports, SSH options)

### Remote Systems Layer

The CLI communicates with various IBM Aspera components:

#### Web Applications (HTTPS)

- **Aspera on Cloud (AoC)**: Cloud-based file sharing and collaboration
- **Aspera Transfer Service (ATS)**: Managed transfer service
- **Faspex**: Secure package exchange (v4 and v5)
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
- SSH for authentication and session management

#### Third-Party Integrations

- **gRPC**: Transfer Daemon communication
- **MCP**: Model Context Protocol for AI assistant integration
- **External Tools**: Integration with system utilities

## Data Flow

### Typical Command Execution Flow

1. **Command Parsing**:

   ```text
   User Input &rarr; bin/ascli &rarr; CLI Options &rarr; Option Parsing
   ```

2. **Plugin Selection**:

   ```text
   Command &rarr; Plugin Factory &rarr; Specific Plugin (e.g., aoc, faspex)
   ```

3. **API Communication**:

   ```text
   Plugin &rarr; REST Client &rarr; Remote API &rarr; JSON Response
   ```

4. **Transfer Initiation**:

   ```text
   Plugin &rarr; Transfer Agent &rarr; Agent Selection &rarr; ascp/trSDK/Connect
   ```

5. **Transfer Execution**:

   ```text
   Transfer Agent &rarr; FASP Protocol &rarr; Remote Server &rarr; Progress Updates
   ```

6. **Result Formatting**:

   ```text
   Response Data &rarr; Formatter &rarr; Output (table/json/yaml/csv)
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

Each plugin declares its command tree at class level using the `command(...)` DSL method.
The base class dispatcher (`dispatch_from_registry`) traverses the registry and calls the
appropriate handler on the plugin instance.

#### Convention: inline lambda vs. named method

**1 line** — inline `->` directly on the `command` call (no parentheses needed):

```ruby
command :info, description: 'Show node info',
  handler: ->{Result::SingleObject.new(@api_node.read('info'))}

command :show, description: 'Show a package',
  handler: ->(package_id:, **){Result::SingleObject.new(@api.read("packages/#{package_id}"))}
```

**2–3 lines, inline** — `lambda do...end` with `command(...)` parentheses (mandatory — see precedence rule above):

```ruby
command(
  :flush, description: 'Delete all cached OAuth tokens',
  handler: lambda do
    require 'aspera/api/node'
    Result::ValueList.new(OAuth::Factory.instance.flush_tokens, name: 'file')
  end
)
```

**> 3 lines** — named method, convention `handle_<full_path_joined_by_underscores>`:

```ruby
command :package, description: 'Manage packages'
commands_under(:package) do
  command :receive, description: 'Receive a package'
end

def handle_package_receive
  # many lines of logic...
end
```

All forms receive the `ctx` hash as keyword arguments and behave identically at runtime.

### Mixin / Module Pattern

Large classes are decomposed into focused mixins included by the host class:

- `Config` plugin includes `AscpActions`, `PresetActions`, `GemChecker`, `Mailer`, `VaultManager`, `SyncActions`
- Each mixin owns a single responsibility and depends on `options`, `context`, and other accessors provided by the host

## Configuration Management

### Configuration File

**Location**: `~/.aspera/ascli/config.yaml`

Stores:

- Preset configurations for different environments
- Default options and parameters
- Authentication credentials (encrypted)
- Transfer agent preferences

### Preset System

Presets allow saving commonly used option combinations:

```yaml
presets:
  my_aoc:
    url: https://mycompany.ibmaspera.com
    username: user@example.com
    password: "@vault:aoc_password"
```

### Secret Management

Integration with secure storage:

- **Keychain**: macOS Keychain integration
- **Vault**: HashiCorp Vault support
- **Encrypted Hash**: Built-in encryption

## Error Handling

### Error Hierarchy

```text
StandardError
├── Aspera::Cli::Error (CLI base)
│   ├── BadArgument
│   ├── MissingArgument
│   ├── NoSuchElement
│   └── BadIdentifier
├── Aspera::RestCallError (HTTP call errors — lib/aspera/rest_call_error.rb)
├── Aspera::Rest::EntityNotFound (resource not found — lib/aspera/rest.rb)
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

## Testing Architecture

### Test Structure

**Directory**: [`tests/`](../tests/)

- Unit tests for individual components
- Integration tests for API interactions
- End-to-end transfer tests
- Mock servers for offline testing

### CI/CD Integration

GitHub Actions workflows:

- Multi-version Ruby testing (3.1, 3.2, 3.3, 3.4, JRuby)
- Automated smoke tests
- Code quality checks (RuboCop)
- Security scanning (CodeQL)

## Extension Points

### Adding a New Plugin

1. Create plugin file in `lib/aspera/cli/plugins/`
2. Inherit from `Plugins::Base`
3. Declare commands with the `command(...)` DSL at class level
4. Implement `handle_<path>` methods for each leaf command
5. Register in plugin factory

### Adding a New Transfer Agent

1. Create agent file in `lib/aspera/agent/`
2. Inherit from `Agent::Base`
3. Implement required methods:
   - `start_transfer`
   - `wait_for_transfers_completion`
4. Register in `Agent::Factory`

### Adding a New Output Format

1. Extend `Formatter` class
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
- **Caching**: Optional response caching
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
- Vault integration

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

## Future Architecture Considerations

From [`CONTRIBUTING.md`](../CONTRIBUTING.md#future-improvements):

- Replace custom REST implementation with standard gems (`rest-client`)
- Replace custom OAuth with standard gem (`oauth2`)
- Explore Traveling Ruby for distribution

## References

- [Main Documentation](README.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [API Documentation](https://www.rubydoc.info/gems/aspera-cli)
- [IBM Aspera Documentation](https://www.ibm.com/docs/en/aspera)
