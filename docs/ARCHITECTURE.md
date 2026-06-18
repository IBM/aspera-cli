# Architecture Documentation

## Overview

The IBM Aspera CLI (`ascli`) is a Ruby-based command-line interface that provides unified access to IBM Aspera's high-speed file transfer products and services. The architecture follows a modular, plugin-based design that separates concerns between command processing, API communication, and transfer execution.

## System Architecture

![Architecture Diagram](architecture.png)

The architecture diagram illustrates the layered structure of `ascli` and its interactions with external components.

## Architectural Layers

### 1. Local System Layer

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

### 2. Core Application Layer (`aspera-cli` gem)

The central green component in the diagram represents the Ruby gem that implements all CLI functionality.

#### 2.1 Entry Point

**File**: [`bin/ascli`](../bin/ascli)

The main executable script that:

- Sets up UTF-8 encoding for internationalization
- Initializes logging subsystem
- Parses early command-line options (log level, format)
- Delegates to the main CLI processor

```ruby
#!/usr/bin/env ruby
Encoding.default_internal = Encoding::UTF_8
Encoding.default_external = Encoding::UTF_8
require 'aspera/cli/runner'
Aspera::Cli::Runner.new(ARGV).process_command_line
```

#### 2.2 CLI Manager

**File**: [`lib/aspera/cli/manager.rb`](../lib/aspera/cli/manager.rb)

The CLI Manager handles:

- **Option Parsing**: Command-line argument processing using `OptionParser`
- **Extended Value Syntax**: Support for complex parameter types (JSON, YAML, Ruby expressions)
- **Option Validation**: Type checking and value constraints
- **Configuration Management**: Integration with persistent configuration

Key responsibilities:

- Declare and validate CLI options
- Support for boolean, string, integer, array, hash types
- Handle sensitive data (passwords, secrets) with masking
- Provide option inheritance and defaults

#### 2.3 Plugin System

**Directory**: [`lib/aspera/cli/plugins/`](../lib/aspera/cli/plugins/)

The plugin architecture enables modular command implementation for different Aspera products:

**Base Plugin** ([`base.rb`](../lib/aspera/cli/plugins/base.rb)):

- Defines standard CRUD operations: `create`, `list`, `modify`, `show`, `delete`
- Provides bulk operation support
- Implements resource identifier resolution (including percent-selector syntax)
- Manages plugin context (options, transfer agent, config, formatter)

**Product Plugins**:

- [`aoc.rb`](../lib/aspera/cli/plugins/aoc.rb) - Aspera on Cloud / ATS
- [`faspex.rb`](../lib/aspera/cli/plugins/faspex.rb) - Faspex 4
- [`faspex5.rb`](../lib/aspera/cli/plugins/faspex5.rb) - Faspex 5
- [`shares.rb`](../lib/aspera/cli/plugins/shares.rb) - Aspera Shares
- [`node.rb`](../lib/aspera/cli/plugins/node.rb) - Node API
- [`console.rb`](../lib/aspera/cli/plugins/console.rb) - Aspera Console
- [`orchestrator.rb`](../lib/aspera/cli/plugins/orchestrator.rb) - Aspera Orchestrator
- [`server.rb`](../lib/aspera/cli/plugins/server.rb) - HSTS (High-Speed Transfer Server)
- [`cos.rb`](../lib/aspera/cli/plugins/cos.rb) - IBM Cloud Object Storage
- [`httpgw.rb`](../lib/aspera/cli/plugins/httpgw.rb) - HTTP Gateway

**Utility Plugins**:

- [`config.rb`](../lib/aspera/cli/plugins/config.rb) - Configuration management
- [`preview.rb`](../lib/aspera/cli/plugins/preview.rb) - File preview generation
- [`oauth.rb`](../lib/aspera/cli/plugins/oauth.rb) - OAuth authentication

#### 2.4 Transfer Agent Abstraction

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
  # Start a transfer asynchronously
  def start_transfer(transfer_spec)
  
  # Wait for all transfers to complete
  def wait_for_transfers_completion
  
  # Progress notification callback
  def notify_progress(event_data)
end
```

**Supported Agents**:

- **Direct**: Direct `ascp` execution (default)
- **Connect**: Aspera Connect browser plugin
- **Node**: Node API-based transfers
- **HTTPGW**: HTTP Gateway for restricted networks
- **Desktop**: Aspera Desktop Client
- **Transfer Daemon (trSDK)**: gRPC-based transfer service

### 3. API Communication Layer

#### 3.1 REST Client

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

#### 3.2 Node API Client

**File**: [`lib/aspera/api/node.rb`](../lib/aspera/api/node.rb)

Specialized client for Aspera Node API with:

- **Access Key Management**: Gen4 access key support
- **Bearer Token Generation**: JWT-based authentication
- **File Operations**: Browse, upload, download, delete
- **Permission Management**: Fine-grained access control
- **Transfer Spec Generation**: Automatic transfer parameter creation
- **Caching**: Optional Redis-based response caching

#### 3.3 OAuth Implementation

**Directory**: [`lib/aspera/oauth/`](../lib/aspera/oauth/)

Modular OAuth 2.0 support:

- **Generic OAuth** ([`generic.rb`](../lib/aspera/oauth/generic.rb)): Standard OAuth 2.0 flows
- **JWT** ([`jwt.rb`](../lib/aspera/oauth/jwt.rb)): JSON Web Token authentication
- **Web** ([`web.rb`](../lib/aspera/oauth/web.rb)): Browser-based OAuth flows
- **URL JSON** ([`url_json.rb`](../lib/aspera/oauth/url_json.rb)): Token from URL

### 4. FASP Transfer Layer

#### 4.1 ASCP Installation Manager

**File**: [`lib/aspera/ascp/installation.rb`](../lib/aspera/ascp/installation.rb)

Singleton class managing `ascp` binary location and SDK resources:

- **Product Detection**: Automatically finds installed Aspera products
- **SDK Installation**: Downloads and installs Transfer SDK
- **Path Resolution**: Locates `ascp` executable and supporting files
- **SSH Key Management**: Handles client SSH keys for authentication

Supported product detection:

- Aspera Desktop Client
- Aspera Connect
- Transfer SDK (transferd)
- IBM Aspera CLI SDK
- HSTS/ATS installations

#### 4.2 Transfer Specification

**File**: [`lib/aspera/transfer/spec.rb`](../lib/aspera/transfer/spec.rb)

Transfer specifications define all parameters for a FASP transfer:

- Source and destination paths
- Transfer direction (upload/download)
- Rate control (target rate, min rate, policy)
- Encryption settings
- Resume policies
- Authentication credentials
- Protocol options (UDP/TCP ports, SSH options)

### 5. Remote Systems Layer

The CLI communicates with various IBM Aspera components:

#### 5.1 Web Applications (HTTPS)

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

#### 5.2 Transfer Servers (FASP Protocol)

- **IBM Cloud Object Storage (COS)**: S3-compatible object storage with FASP
- **Aspera Transfer Server (ATS)**: Dedicated transfer endpoints
- **HSTS Node**: High-Speed Transfer Server with Node API

Communication via:

- FASP protocol (TCP/UDP) for data transfer
- Node API (HTTPS) for control operations
- SSH for authentication and session management

#### 5.3 Third-Party Integrations

- **gRPC**: Transfer Daemon communication
- **External Tools**: Integration with system utilities

## Data Flow

### Typical Command Execution Flow

1. **Command Parsing**:

   ```
   User Input → bin/ascli → CLI Manager → Option Parsing
   ```

2. **Plugin Selection**:

   ```
   Command → Plugin Factory → Specific Plugin (e.g., aoc, faspex)
   ```

3. **API Communication**:

   ```
   Plugin → REST Client → Remote API → JSON Response
   ```

4. **Transfer Initiation**:

   ```
   Plugin → Transfer Agent → Agent Selection → ascp/trSDK/Connect
   ```

5. **Transfer Execution**:

   ```
   Transfer Agent → FASP Protocol → Remote Server → Progress Updates
   ```

6. **Result Formatting**:

   ```
   Response Data → Formatter → Output (table/json/yaml/csv)
   ```

## Key Design Patterns

### 1. Plugin Architecture

Each Aspera product is implemented as a plugin inheriting from `Plugins::Base`:

- Consistent command structure across products
- Standard CRUD operations
- Extensible for product-specific features

### 2. Factory Pattern

Used for creating instances based on configuration:

- **Agent Factory**: Selects appropriate transfer agent
- **OAuth Factory**: Creates authentication handlers
- **Plugin Factory**: Instantiates product plugins

### 3. Singleton Pattern

Used for global configuration and state:

- **Installation**: ASCP binary location
- **RestParameters**: HTTP client settings
- **Log**: Logging configuration

### 4. Strategy Pattern

Transfer agents implement a common interface with different strategies:

- Direct execution via `ascp`
- Browser-based via Connect
- API-based via Node
- Gateway-based via HTTPGW

### 5. Template Method Pattern

Base plugin defines the operation flow, subclasses implement specifics:

```ruby
class Base
  def execute_action
    # Template method
  end
end

class Faspex < Base
  def execute_action
    # Faspex-specific implementation
  end
end
```

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

```
StandardError
├── Aspera::Error (base)
│   ├── Cli::Error (CLI-specific)
│   │   ├── BadArgument
│   │   └── NoSuchIdentifier
│   ├── RestCallError (HTTP errors)
│   └── EntityNotFound
```

### Error Analysis

**File**: [`lib/aspera/rest_error_analyzer.rb`](../lib/aspera/rest_error_analyzer.rb)

Analyzes API errors and provides:

- Human-readable error messages
- Suggested remediation steps
- Context-specific guidance

## Logging and Debugging

### Log Levels

- `debug`: Detailed debugging information
- `info`: General informational messages
- `warn`: Warning messages
- `error`: Error messages

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
3. Define `ACTIONS` constant
4. Implement `execute_action` method
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

From [`CONTRIBUTING.md`](../CONTRIBUTING.md#L319-L325):

- Replace custom REST implementation with standard gems (`rest-client`)
- Replace custom OAuth with standard gem (`oauth2`)
- Integrate standard CLI framework (`thor`)
- Explore Traveling Ruby for distribution

## References

- [Main Documentation](README.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [API Documentation](https://www.rubydoc.info/gems/aspera-cli)
- [IBM Aspera Documentation](https://www.ibm.com/docs/en/aspera)
