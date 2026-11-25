# Command Line Interface for IBM Aspera products
<!--
EDITING GUIDELINES:
- This file is the source template for the generated README.md. Edit this file, not README.md.
- Do not use Unicode characters unless strictly necessary
  (e.g. wizard menu labels that must match the actual on-screen UI text). 
  Use plain ASCII equivalents instead:
    apostrophe : ' (not ' or ')
    dash       : - (not en-dash U+2013, not em-dash U+2014, not --)
    ellipsis   : ... (not U+2026)
- Emphasis style: use **bold** (double asterisks) only. Do not use *single asterisk italic*, _underscore_, or __double underscore__ style.
<%=doc_warn('Yes edit this file!')%>
-->

<!-- gfm2pdf
common:
  metadata:
    subtitle: "<%=cmd%> <%=build_version%>"
    author: "<%=gemspec.authors.join(', ')%>"
-->

<!-- Admonitions: NOTE CAUTION WARNING IMPORTANT TIP INFO -->

<!-- markdownlint-disable MD028 -->
<!-- markdownlint-disable MD024 -->
<!-- markdownlint-disable MD060 -->

## Introduction

### Overview

**The automation interface for IBM Aspera. From command line to AI agents.**

The IBM Aspera Command Line Interface (<%=tool%>) is an enterprise-grade tool that provides comprehensive command-line access to IBM Aspera's suite of high-speed file transfer products and services.
Designed for automation, scripting, and integration scenarios, <%=tool%> enables organizations to leverage Aspera's FASP technology within their existing workflows and DevOps pipelines.

> [!TIP]
> For any question about <%=tool%> (behavior, options), or to build a command line, give this manual to an AI assistant as a reference and ask it.
> See [Leveraging AI Assistance](#leveraging-ai-assistance).

![Architecture: transfer agents, IBM Aspera applications and transfer servers](<%=link_repo('docs/architecture.svg')%>)

### Key Features

**Multi-Product Integration**
: Unified interface supporting Aspera on Cloud, Faspex 5, Shares, Node API, Console, Orchestrator, and High-Speed Transfer Server (HSTS).

**Flexible Authentication**
: Support for OAuth 2.0, JWT, Basic Authentication, and SSH key-based authentication across different Aspera products.

**Transfer Automation**
: High-speed FASP transfers with multiple agent support (Direct, Connect, Node, HTTP Gateway, Transfer Daemon).

**Configuration Management**
: Persistent configuration presets, environment variables, and flexible option handling for streamlined operations.

**Structured Output**
: JSON, YAML, CSV or tables, with filtering and JMESPath queries, for scripts, schedulers and CI/CD pipelines.

**Secrets Management**
: Secrets kept in a vault (encrypted file, HashiCorp Vault, Keeper, 1Password, macOS keychain, Linux Secret Service), never in scripts.

**AI Assistants and Agents**
: AI assistants and agents (IBM Bob, Claude, GitHub Copilot, Cursor, agents built with Langflow) operate IBM Aspera products with <%=tool%>, in a shell (with `llms.txt` or the agent skill) or through the built-in MCP server, with restrictions and without seeing secrets.

**Developer Friendly**
: Comprehensive logging, debugging capabilities, and API exploration tools for development and troubleshooting.

### Target Audience

This manual is intended for:

- **System Administrators** managing Aspera infrastructure
- **DevOps Engineers** integrating Aspera into CI/CD pipelines
- **Developers** building automation scripts and workflows
- **IT Professionals** performing file transfer operations

### Document Structure

This manual is organized into the following sections:

1. **Quick Start** - Getting started with basic operations
1. **Installation** - Setup procedures for various platforms
1. **Command Line Interface** - Syntax, options, configuration, transfers, and usage patterns
1. **Plugin sections** (one per product: AoC, ATS, HSTS, Faspex 5, and so on) - Product-specific operations and examples
1. **Operational Utilities** - Sync, hot folders, health checks, email notifications
1. **Common problems** - Common issues and solutions
1. **About** - History and references

### When to use and when not to use

| Need | Best choice | Why |
| ---- | ----------- | --- |
| Script or schedule transfers, packages, file management or administration of Aspera products (shell, `cron`, CI/CD) | <%=tool%> | One tool for all products, presets and vault per environment, structured output, automatic resume |
| Let an AI assistant or agent operate Aspera products | <%=tool%>: in a shell, or its MCP server | Same commands as people, restrictions, secrets never shown (see [Leveraging AI Assistance](#leveraging-ai-assistance)) |
| Give an AI agent built with Langflow (or another agent builder) access to Aspera products | <%=tool%> MCP server | No code: component **MCP Tools**, one tool for all Aspera products (see [Langflow](#langflow)) |
| Administer, troubleshoot, or analyze `ascp` logs, interactively | <%=tool%> | Commands for every product, `ascp` log diagnostics |
| Learn or test an Aspera REST API | <%=tool%> | Shows the API calls (see [Logging, Debugging](#logging-debugging)) |
| Simple transfer with an HSTS, where nothing else can be installed | `ascp` | Included with every Aspera transfer product (see [<%=tool%> or `ascp`?](#ascli-or-ascp)) |
| Build an application (C/C++, Go, Python, Java, .NET, NodeJS...) | Aspera REST APIs and Transfer Daemon (gRPC) | Better for long-term development and maintenance |
| Users who transfer files with a graphical interface | IBM Aspera for Desktop, or the web interface of the application | Interactive use, no command line |

> [!NOTE]
> If you are scripting or automating transfers from the command line, <%=tool%> is the right choice.
> If you are developing an application, prefer the APIs or SDKs instead.

<%=tool%> is designed for command-line interaction with IBM Aspera products, enabling users to execute remote commands and perform high-performance file transfers.
It supports both interactive terminal operations (for example, maintenance tasks on VT100-compatible terminals) and scripting use cases (for example, batch jobs via shell scripts or `cron`).

Internally, <%=tool%> integrates several components:

- A configuration file (`config.yaml`) for persistent settings
- Advanced command-line options (see [Extended Value](#extended-value-syntax))
- REST API calls, including OAuth (like `curl`)
- Aspera's `ascp` for high-speed file transfers

For programmatic integration with languages such as C/C++, Go, Python, NodeJS, and others, it is recommended to use the [Aspera APIs](https://ibm.biz/aspera_api) directly.
These include:

- REST APIs for products like Aspera on Cloud (AoC), Faspex 5, and Node
- The Transfer Daemon with gRPC interfaces and language-specific stubs (C/C++, Python, .NET/C#, Java, Go, Ruby, Rust, and so on)

These APIs are generally more suitable for long-term development and maintenance.
Example implementations can be found at: <https://github.com/laurent-martin/aspera-api-examples>.

For scripting and ad hoc command-line tasks, <%=tool%> is ideal.
It is developer-friendly and well-suited for testing and learning Aspera APIs (see [Logging, Debugging](#logging-debugging)).

### <%=tool%> or `ascp`?

`ascp` is the low-level command-line utility that implements the FASP protocol and is used for actual data transfers.
Every Aspera transfer involves an `ascp` process on both the client and server sides.
<%=tool%> is not an alternative transfer engine: it starts `ascp` (directly or through another [transfer agent](#agent-direct)), so transfer performance is identical.

Other low-level command line tools are included with Aspera transfer products, and <%=tool%> is a front end for them too:

- `async`: the IBM Aspera Sync utility, to synchronize folders (see [IBM Aspera Sync](#ibm-aspera-sync)).
- `ascp4`: an alternate transfer engine, selected with transfer spec parameter `use_ascp4`. `ascp4` will be deprecated: use `ascp` unless one of its specific features is needed.

Used directly, `ascp` is limited to sending and receiving files:

- Connection parameters (address, ports, user, credentials) must be provided on each command line: there are no connection profiles.
- The remote server cannot be browsed: remote paths must be known in advance.
- With Aspera applications (AoC, Faspex, Shares, Node API), the transfer address and token must first be obtained through the application's REST API.
- Multi-session requires starting and monitoring one `ascp` process per session (option `-C`).
- On interruption, `ascp` exits with an error: data already at destination is skipped on the next run (option `-k`), but restarting is up to the caller.

<%=tool%> adds:

- Configuration presets, with secrets protected in a vault (see [Option Preset](#option-preset) and [Secret Vault](#secret-vault))
- Detection of the Aspera application from its URL, and automatic retrieval of transfer parameters and tokens (see [Wizard](#wizard))
- Remote file browsing and management: list, create folder, rename, copy, delete, checksum
- Built-in multi-session, with an aggregated progress bar (see [Multi-session transfer](#multi-session-transfer))
- Automatic resume on retry-able errors, with increasing delay and token renewal (see [Agent: Direct](#agent-direct))
- Choice of transfer agents: Direct, Node, Connect, HTTP Gateway, Transfer Daemon
- Structured output (table, JSON, YAML, CSV) for scripting (see [Output](#output))

All `ascp` options remain available, either through transfer spec parameters (listed with `config ascp spec`), or by passing `ascp` arguments directly when using the `direct` agent (via `ascp_args` in option `transfer`).

Using `ascp` directly remains relevant when:

- <%=tool%> cannot be installed: `ascp` is included with every Aspera transfer product.
- The need is limited to simple transfers with an HSTS using SSH credentials.

To use `ascp` directly as a command line, refer to the IBM Aspera documentation of either [Desktop Client](https://www.ibm.com/docs/en/asdc), [Endpoint](https://www.ibm.com/docs/en/ahte) or [Transfer Server](https://www.ibm.com/docs/en/ahts) - each of which includes [a dedicated section on `ascp`](https://www.ibm.com/docs/en/ahts/4.4?topic=linux-ascp-transferring-from-command-line).

### Notations, Shell, Examples

Examples of command-line operations are shown using a shell such as: `bash` (Linux) or `zsh` (macOS).
Using [Windows PowerShell or cmd](#shell-parsing-for-windows) is also possible.

Command line examples listed in sections titled **<%=sample_commands_title(:_plugin_name_)%>** are verified during version validation.

Command line arguments formatted as `<%=ph :name%>` in examples represent user-provided values, not literal values.

<%=tool%> is an API **Client** toward the remote Aspera application **Server** (Faspex, HSTS, and so on).

Some commands will start an Aspera transfer (for example, `upload`).
The transfer is not implemented directly in <%=tool%>; rather, <%=tool%> uses one of the external Aspera Transfer Clients called **[Transfer Agents](#transfer-clients-agents)**.

> [!NOTE]
> A **[Transfer Agent](#transfer-clients-agents)** is a client for the remote Transfer Server (HSTS/HSTE).
> It can be local, or remote.
> For example, a remote Aspera Transfer Server may be used as a transfer agent through its Node API, using option `--transfer=node`.

## Quick Start

This section walks you through your first interaction with <%=tool%> on Linux.

### Prerequisites

- Get the <%=tool%> binary for Linux (.tgz) in the [release section of the GitHub repository](https://github.com/IBM/aspera-cli/releases).

- Decompress the archive to get the executable:

```shell
mkdir -p $HOME/bin
tar -C $HOME/bin -zxvf <%=cmd%>-<%=build_version%>-linux-x86_64.tgz
export PATH=$PATH:$HOME/bin
```

> [!NOTE]
> For other operating systems, complete the [Installation](#installation) section (Ruby, Gem, FASP) to get <%=tool%> set up on your system.

- Once installed, confirm <%=tool%> is accessible by checking its version:

```shell
<%=cmd%> -v
```

```text
<%=build_version%>
```

- Install the Aspera transfer runtime (tested version), as it is not included in the <%=tool%> package:

```shell
<%=cmd%> transferd install
```

### Option A - Test with the Aspera Demo Server

- Run the following command to initialize the demo environment:

```shell
<%=cmd%> config initdemo
```

- Check the configuration:

```shell
<%=cmd%> config preset overview
```

- Browse the remote file system:

```shell
<%=cmd%> server browse /
```

```text
╭────────────┬──────┬───────────┬───────┬───────────────────────────┬───────────────────────╮
│ zmode      │ zuid │ zgid      │ size  │ mtime                     │ name                  │
╞════════════╪══════╪═══════════╪═══════╪═══════════════════════════╪═══════════════════════╡
│ dr-xr-xr-x │ xfer │ demousers │ 4096  │ 2014-11-05 16:01:56 +0100 │ aspera-test-dir-large │
│ drwxrwxr-x │ xfer │ demousers │ 94208 │ 2025-03-31 11:27:33 +0200 │ Upload                │
│ dr-xr-xr-x │ xfer │ demousers │ 4096  │ 2014-11-05 16:01:56 +0100 │ aspera-test-dir-small │
│ dr-xr-xr-x │ xfer │ demousers │ 4096  │ 2014-11-05 16:01:56 +0100 │ aspera-test-dir-tiny  │
╰────────────┴──────┴───────────┴───────┴───────────────────────────┴───────────────────────╯
```

- Download a file:

```shell
<%=cmd%> server download /aspera-test-dir-small/10MB.1
```

```text
Time: 00:00:02 ====================================== 100% 100 Mbps Time: 00:00:00
complete
```

### Option B - Test with Your Own HSTS

To use <%=tool%> with a server of your own, it is recommended to save its connection details as an [Option Preset](#option-preset).
This avoids repeating credentials on every command.
The steps below create a preset, set it as the default for the server plugin, browse a remote directory, and download a file:

- Create a preset with your server's connection details:

```shell
<%=cmd%> config preset set <%=ph :server_preset_name%> @: url=ssh://hsts.example.com:33001 username=<%=ph :username%> password=<%=ph :password%>
```

```text
INFO Saving config file: /home/john/.aspera/<%=cmd%>/config.yaml
Updated: <%=ph :server_preset_name%>
```

- Set the preset as the default for the server plugin:

```shell
<%=cmd%> config preset set default server <%=ph :server_preset_name%>
```

```text
INFO Updated: default: server <- <%=ph :server_preset_name%>
INFO Saving config file: /home/john/.aspera/<%=cmd%>/config.yaml
```

- Once your preset is set, follow the same browse and download steps as in [Option A](#option-a---test-with-the-aspera-demo-server).

### Option C - Test with Aspera on Cloud

If you'd prefer to test against Aspera on Cloud, skip ahead to the [AoC Wizard](#aoc-configuration-using-wizard) section.

### Leveraging AI Assistance

You can significantly accelerate your workflow by using an AI assistant with <%=tool%>.
There are three ways, the first one is the simplest:

- **The AI executes commands in a shell** (coding agents): nothing to set up, and no limitation: the AI uses <%=tool%> as you do, with your configuration.
  Give it the file [`llms.txt`](https://raw.githubusercontent.com/IBM/aspera-cli/refs/heads/main/llms.txt), located at the root of the gem and of the GitHub repository.
  It tells the AI what <%=tool%> does with IBM Aspera products, and how to discover commands, arguments and options (`config commands`, `help`, `config options`, `config documentation`).
  The same content is displayed by `<%=cmd%> config skill`: an AI that can execute <%=tool%> can read it with no file to find.
  With an AI client that supports agent skills, install the skill instead: the AI loads it by itself when a request is about IBM Aspera.
  The skill, in the [Agent Skills](https://agentskills.io) format, is the folder `skills/<%=cmd%>` of the gem (and of the GitHub repository): copy it to the skills folder of the AI client, for example:

  ```shell
  cp -R "$(gem contents <%=gemspec.name%> | grep 'skills/<%=cmd%>/SKILL.md$' | xargs dirname)" ~/.claude/skills/
  ```

  With Claude Code, install it as a plugin from the GitHub repository, which is also a plugin marketplace: it is updated with the repository.

  ```text
  /plugin marketplace add IBM/aspera-cli
  /plugin install <%=cmd%>@aspera-cli
  ```

- **The AI executes commands through MCP**: for an AI client without a shell, or an agent built with [Langflow](#langflow), start the [MCP server](#plugin-mcp-model-context-protocol-server) and register it in the AI client.
  The AI discovers commands and their arguments by itself, and executes them.
  By default, the server restricts what the AI can do (see [Security](#security)), and the AI never sees secrets.

- **The AI generates commands that you execute** (chat assistant that cannot execute commands): it cannot read the documentation through <%=tool%>, so provide it as context, as described below.

In the first two ways, the AI reads the documentation by itself, one section at a time, with `<%=cmd%> config documentation`: there is no need to provide the manual.

Recommended Workflow for a chat assistant:

- **Contextualize**: Download the project manual (this manual in Markdown format, [`docs/README.md`](https://raw.githubusercontent.com/IBM/aspera-cli/refs/heads/main/docs/README.md)) from the GitHub repository.

- **Upload**: Attach the file to your AI assistant's prompt to ensure it uses specific, up-to-date syntax.

- **Inquire**: Use a detailed prompt that specifies your requirements and environment.

> [!TIP]
> Specify your environment.
> Quoting rules and syntax vary significantly between shells.
> Always mention if you are using `bash`, **PowerShell** 5 or 7, or Windows `CMD`.

Example Prompt:

```text
Use only the attached <%=cmd%> manual (it matches the version I use).
Generate a command to send a package via Aspera on Cloud using the Bash shell.
Set a custom title and note.
Define specific recipients.
Cap the transfer speed at 300Mbps.
```

By providing the documentation as a direct reference, you reduce "hallucinations" and receive accurate, executable commands in seconds.

### Next Steps

- Learn the CLI: Read [Command Line Interface](#command-line-interface) to understand configuration, options, and commands.

- Explore plugins: Jump to the section for the relevant product, for example: [Aspera on Cloud](#plugin-aoc-ibm-aspera-on-cloud), [HSTS](#plugin-server-ibm-aspera-high-speed-transfer-server-ssh), [Faspex 5](#plugin-faspex5-ibm-aspera-faspex-v5).

## Installation

There are several ways to install <%=tool%>:

- Using a Ruby environment directly on the host operating system (Linux, macOS, Windows).

  This is the most general method.
  It consists of installing:
  - The [Ruby language](#ruby),
  - The [<%=gemspec.name%>](#ruby-gem-aspera-cli) Ruby gem,<!-- markdownlint-disable-line -->
  - [Aspera Transfer Daemon (`ascp`)](#fasp-protocol-ascp).
- As a [single file executable](#single-file-executable)

  This method is simple, but only a limited number of platforms are supported.
- On Linux, as a [portable package](#linux-portable-package)

  This method is simple on Linux: extract and run, without root access. It includes Ruby, gems and `ascp`.
- On Windows, as a [portable package](#windows-portable-package)

  This method is the simplest on Windows: extract and run. It includes Ruby, gems and `ascp`.
- On Windows, with the [Chocolatey package](#windows-chocolatey-package): it installs the portable package and adds `<%=cmd%>` to the `PATH`.
- As a [container](#container) (`docker`, `podman`, `singularity`).

The following sections describe the various installation methods.

An internet connection is required during installation.
If you do not have internet access, see [Installing in an air-gapped environment](#installing-in-an-air-gapped-environment).

### Single file executable

> [!WARNING]
> Available only on a limited number of platforms.

<%=tool%> is available as a single **platform-dependent executable** in the [Releases](https://github.com/IBM/aspera-cli/releases).
This executable includes the Ruby runtime and gems, but not the transfer SDK.

#### Installing the single file executable

> [!NOTE]
> Replace `<%=ph :version%>` and `<%=ph :platform%>` with the values of the downloaded archive, for example: `linux-x86_64-glibc2.28-ocran`.
> The archive contains the executable `<%=cmd%>` and its `README.<%=cmd%>.md`.
> Installation of `ascp` is still required separately.
> See [Install `ascp`](#installing-ascp-through-transferd).

```shell
tar zxvf <%=gemspec.name%>-<%=ph :version%>-<%=ph :platform%>.tgz
./<%=cmd%> transferd install
```

#### Linux: Checking the GLIBC version

> [!WARNING]
> On Linux, the executable requires a minimum GLIBC version, specified in the archive name on the download site (for example: `glibc2.28`).
> If the minimum version is not met, then executables (`ascp`, `transferd`) will exit with error.

On Linux, you can check your system's GLIBC version on this site: [repology.org](https://repology.org/project/glibc/versions), or check your GLIBC version with `ldd`:

```shell
ldd --version | head -n1
```

```text
ldd (GNU libc) 2.34
```

Check an executable's (for example, `/bin/bash`, <%=tool%>, `ascp`) minimum required GLIBC version:

```shell
objdump -p /bin/bash | sed -n 's/^.*GLIBC_//p' | sort -V | tail -n1
```

```text
2.34
```

> [!NOTE]
> If `objdump` is not available, then use `strings` or `grep -z 'GLIBC_'|tr \\0 \\n`

The required GLIBC version for `ascp` can be found in the [Release Notes of HSTS](https://www.ibm.com/docs/en/ahts) or [on this page](https://eudemo.asperademo.com/download/sdk.html).

### Linux: Portable package

A ready-to-use archive for Linux (x86_64) is available in the [Releases](https://github.com/IBM/aspera-cli/releases): `<%=gemspec.name%>-<%=ph :version%>-linux-x86_64-glibc2.28-portable.tgz`.

It contains the Ruby runtime with the shared libraries it needs, the <%=gemspec.name%> gem with its dependencies, and the Aspera Transfer SDK (`ascp`).
No installation step, no root access, and no internet access are required.
The GLIBC of the system must be at least the version in the archive name, see [Checking the GLIBC version](#linux-checking-the-glibc-version).

1. Extract the archive, for example in `~/.local/share`, and check that <%=tool%> runs:

   ```shell
   tar -xzf <%=gemspec.name%>-<%=ph :version%>-linux-x86_64-glibc2.28-portable.tgz -C ~/.local/share
   ~/.local/share/<%=gemspec.name%>-<%=ph :version%>-linux-x86_64-glibc2.28-portable/<%=cmd%> -v
   ```

2. Optionally, place a symbolic link to the launcher in a folder of the `PATH`.
   Then, <%=tool%> can be used from any folder:

   ```shell
   ln -s ~/.local/share/<%=gemspec.name%>-<%=ph :version%>-linux-x86_64-glibc2.28-portable/<%=cmd%> ~/.local/bin/<%=cmd%>
   <%=cmd%> -v
   ```

> [!NOTE]
> The launcher `<%=cmd%>` uses the `ascp` located in folder `sdk` of the package, unless environment variable `ASCLI_SDK_FOLDER` is set.
> So, `<%=cmd%> transferd install` is not needed.

The configuration is stored in the [main folder](#main-configuration-and-persistency-folder), like for other installation methods.
To upgrade, extract the new version, and update the symbolic link.
To uninstall, delete the folder, and the symbolic link if it was created.

### Windows: Portable package

A ready-to-use ZIP archive for Windows (x64) is available in the [Releases](https://github.com/IBM/aspera-cli/releases): `<%=gemspec.name%>-<%=ph :version%>-windows-x86_64-portable.zip`.

It contains the Ruby runtime, the <%=gemspec.name%> gem with its dependencies, and the Aspera Transfer SDK (`ascp`).
Apart from the prerequisite below, no installation step, no administrator rights, and no internet access are required.

> [!IMPORTANT]
> The package does not include the Microsoft Visual C++ Redistributable (x64), which `ascp` requires.
> If it is not already present on the system, install it from [Microsoft Visual C++ Redistributable latest supported downloads](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) (administrator rights required), otherwise transfers fail.

1. Download the ZIP archive, then right-click on it and select **Extract All...**.
   Preferably, extract in a folder writable by the user, for example: `%LOCALAPPDATA%\Programs`.

2. In a terminal, in the extracted folder, check that <%=tool%> runs:

   ```batchfile
   .\<%=cmd%>.cmd -v
   ```

3. Optionally, double-click on `add_to_path.cmd` to add the folder to the user's `PATH`.
   Then, in a new terminal, <%=tool%> can be used from any folder:

   ```batchfile
   <%=cmd%> -v
   ```

4. Optionally, activate the [shell completion](#shell-completion) of PowerShell (the folder must be in the `PATH`).

> [!NOTE]
> The launcher `<%=cmd%>.cmd` uses the `ascp` located in folder `sdk` of the package, unless environment variable `ASCLI_SDK_FOLDER` is set.
> So, `<%=cmd%> transferd install` is not needed.

The configuration is stored in the [main folder](#main-configuration-and-persistency-folder), like for other installation methods.
To upgrade, extract the new version, and update the `PATH` if the folder name changed.
To uninstall, delete the folder, and remove it from the `PATH` if it was added.

### Windows: Chocolatey package

If you use [Chocolatey](https://chocolatey.org/), <%=tool%> can be installed with the `aspera-cli` package.
It installs the [portable package](#windows-portable-package) (Ruby, gems and `ascp` included, checked with its SHA-256) and adds only the command `<%=cmd%>` to the `PATH`: no Ruby installation is needed.

In a PowerShell as Administrator:

```pwsh
choco install aspera-cli -y
```

Upgrade with `choco upgrade aspera-cli`, uninstall with `choco uninstall aspera-cli` (the configuration is kept).

### Ruby

A Ruby interpreter is required to run <%=tool%>.

Required Ruby version is <%=ruby_version%>.

**Ruby can be installed using any of the following methods**: `rpm`, `yum`, `dnf`, `rvm`, `rbenv`, `brew`, Windows installer, ...

**First**, refer to the official Ruby documentation:

- [Official Ruby Installation Guide](https://www.ruby-lang.org/en/documentation/installation/)
- [Official Ruby Download](https://www.ruby-lang.org/en/downloads/)

For convenience, you may refer to the following sections for a proposed method for specific operating systems.

<%=tool%> supports a Ruby version until 6 months after its [end of official support](https://www.ruby-lang.org/en/downloads/branches/).
The minimum version is increased accordingly, and announced in advance.
If only an older Ruby version must be used due to system constraints, use an older version of <%=tool%> that supports it; refer to [rubygems.org](<%=gemspec.metadata['rubygems_uri']%>).

The following table summarizes Ruby version life cycles and <%=tool%> support status:

<%= ruby_support_table %>

#### Windows: Installer

Manual installation:

- Navigate to [https://rubyinstaller.org/](https://rubyinstaller.org/) &rarr; **Downloads**.
- Download the latest Ruby installer **"with devkit"**. (`Msys2` is needed to install some native extensions, such as `grpc`)
- Execute the installer, which installs by default in: `C:\RubyVV-x64` (`VV` is the version number)
- At the end of the installation procedure, the `Msys2` installer is automatically executed, select option 3 (`Msys2` and `mingw`)
- Then install the `<%=gemspec.name%>` gem and Aspera Transfer Daemon (see next sections)

Automated installation (with internet access):

The Ruby installer supports silent installation. To see the options, execute it with `/help`, or refer to the [Ruby Installer FAQ](https://github.com/oneclick/rubyinstaller2/wiki/FAQ).

Download the Ruby installer executable from <https://rubyinstaller.org/downloads/> and then install:

```batchfile
rubyinstaller-devkit-3.2.2-1-x64.exe /silent /currentuser /noicons /dir=C:\aspera-cli
```

#### Windows: Chocolatey

If you use [Chocolatey](https://chocolatey.org/), then install Ruby with:

```powershell
choco install ruby
```

#### macOS: `brew`

If you use [Homebrew](https://brew.sh/), then install Ruby with:

```shell
brew install ruby
```

> [!NOTE]
> This is the recommended method.

> [!WARNING]
> **macOS** comes with Ruby 2.6.
> It is an old unsupported version and [Apple has deprecated it](https://developer.apple.com/documentation/macos-release-notes/macos-catalina-10_15-release-notes).
> It will be removed from macOS in the future.
> Do not use it.
> Use the required version of Ruby.

This installs a recent Ruby version suitable for <%=tool%>.

After installation, Homebrew's Ruby is not on the `PATH` by default (this is shown at the end of the `brew install ruby` output and by `brew info ruby`).
Add it to your shell configuration file:

- **zsh** (default shell on macOS; run this once in a terminal):

  ```shell
  echo 'PATH="$(brew --prefix ruby)/bin:$($(brew --prefix ruby)/bin/gem env gemdir)/bin:$PATH"' >> ~/.zprofile
  source ~/.zprofile
  ```

- **bash**: replace `~/.zprofile` with `~/.bash_profile` in the commands above.

#### Linux: Package

<%=tool%> supports Linux distributions that are officially maintained by their vendor (Red Hat for RHEL / UBI, Canonical for Ubuntu LTS).

- **GLIBC Requirement:** The Transfer SDK executables (`ascp`, `transferd`) and the Linux portable package require **`glibc >= <%= sdk_glibc_version %>`**.
- **Installation Compatibility:**
  - If the OS provides a Ruby package or DNF module stream meeting the required version (≥ <%= Aspera::Cli::Info::RUBY_MINIMUM_VERSION %>), the `<%= gemspec.name %>` gem can be installed directly with `gem install`.
  - If the OS is under maintenance but ships an older default system Ruby (e.g. Ubuntu 22.04 LTS with Ruby 3.0), <%=tool%> is fully supported via the [Linux portable package](#linux-portable-package), the [container image](#container), or a Ruby version manager (`rbenv`, `rvm`).

The following table summarizes supported Linux distributions, vendor end of support dates, GLIBC versions, available Ruby streams, and recommended <%=tool%> installation modes:

<%= linux_support_table %>

If your Linux distribution provides a standard Ruby package, you can use it provided that the version is supported.

**Example:** RHEL 8+, Rocky Linux 8+: with extensions to compile native gems:

- Check available Ruby versions:

  ```shell
  dnf module list ruby
  ```

- If Ruby was already installed with an older version, remove it:

  ```shell
  dnf module -y reset ruby
  ```

- Install packages needed to build native gems:
  
  ```shell
  dnf install -y make automake gcc gcc-c++ kernel-devel
  ```

- Enable the Ruby version you selected:

  ```shell
  dnf module -y enable ruby:3.3

  dnf install -y ruby-devel
  ```

**Example:** Ubuntu

```shell
apt-get install -y ruby-full
```

**Other examples:**

```shell
yum install -y ruby ruby-devel rubygems ruby-json
```

```shell
apt install -y ruby ruby-dev rubygems ruby-json
```

One can remove all installed gems, for example to start fresh:

```shell
ls $(gem env gemdir)/gems/|sed -e 's/-[^-]*$//'|sort -u|xargs gem uninstall -axI
rm -f Gemfile.lock
```

#### Unix-like: RVM: Single user installation (not root)

Install `rvm`.
Follow [https://rvm.io/](https://rvm.io/).

Execute the shell/curl command.
As regular user, it installs in the user's home: `~/.rvm`.

```shell
\curl -sSL https://get.rvm.io | bash -s stable
```

Follow on-screen instructions to install keys, and then re-execute the command.

Upon RVM installation, open a new terminal or initialize with:

```shell
source ~/.rvm/scripts/rvm
```

It is advised to use one of the precompiled Ruby versions; you can list them with:

```shell
rvm list --remote
```

Install the chosen pre-compiled Ruby version:

```shell
rvm install 3.2.2
```

Ruby is now installed for the user, go to [Gem installation](#ruby-gem-aspera-cli). <!-- markdownlint-disable-line -->

Alternatively RVM can be installed system-wide, for this execute as `root`.
It then installs by default in `/usr/local/rvm` for all users and creates `/etc/profile.d/rvm.sh`.
One can install in another location with:

```shell
curl -sSL https://get.rvm.io | bash -s -- --path /usr/local
```

As root, verify that this will not collide with other applications using Ruby (for example, Faspex).
If so, one can rename the environment script so that it is not loaded by default:

```shell
mv /etc/profile.d/rvm.sh /etc/profile.d/rvm.sh.ok
```

To activate Ruby (and <%=cmd%>) later, source it:

```shell
source /etc/profile.d/rvm.sh.ok
```

```shell
rvm version
```

On macOS, one way to force use of OpenSSL 3.0 is:

```shell
RUBY_CONFIGURE_OPTS="--with-openssl-dir=$(brew --prefix openssl@3.0)" rvm install 3.4.0
```

#### Unix-like: `rbenv`

If you do not have root access, you can install Ruby in your home directory using `rbenv`, see [`rbenv-installer`](https://github.com/rbenv/rbenv-installer#rbenv-installer):

```shell
curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
```

Then open a new terminal, or `source` the shell initialization script:

```shell
source ~/.bashrc
```

Then install Ruby:

```shell
rbenv install 3.2.2
```

#### Other Unixes (AIX)

Ruby is sometimes made available as an installable package through third party providers.
For example for AIX, one can look at:

<https://www.ibm.com/support/pages/aix-toolbox-open-source-software-downloads-alpha#R>

If your Unix does not provide a pre-built Ruby, you can get it using one of those [methods](https://www.ruby-lang.org/en/documentation/installation/).

For instance, to build from source and install in `/opt/ruby`:

```shell
wget https://cache.ruby-lang.org/pub/ruby/x.y/ruby-x.y.z.tar.gz

gzip -d ruby-x.y.z.tar.gz

tar xvf ruby-x.y.z.tar

cd ruby-x.y.z

./configure --prefix=/opt/ruby

make ruby.imp

make

make install
```

#### JRuby

<%=tool%> can also run with the [JRuby](https://www.jruby.org/) interpreter.
All that is needed is a JVM (Java Virtual Machine) on your system (`java`).
The JRuby package comes pre-compiled and does not require compilation of native extensions.
Use a version of JRuby compatible with a Ruby version supported by <%=tool%>.
See [the Wikipedia page](https://en.wikipedia.org/wiki/JRuby) to match JRuby and Ruby versions.
Choose the latest version from:

<https://www.jruby.org/download>

> [!WARNING]
> The startup time is slightly longer using `jruby` than the native Ruby.
> See the [JRuby wiki](https://github.com/jruby/jruby/wiki) for details.
> This can be reduced by using the `--dev` option.
> The transfer speed is not impacted (executed by `ascp` binary).

> [!NOTE]
> JRuby can be [installed](https://www.jruby.org/getting-started) using `rvm`.

Example: Start <%=tool%> with JRuby and reduce startup time:

```shell
export JRUBY_OPTS=--dev
<%=cmd%> -v
```

Or:

```shell
JRUBY_OPTS=--dev <%=cmd%> -v
```

#### Installing optional gems

Some additional gems are required for either development or specific runtime features.
For JRuby, some of them have a replacement gem, and others are not available.
Those are not installed as part of dependencies because they involve compilation of native code but concern less-used features.

See [Gemfile](<%=link_repo('Gemfile')%>):

<%=gem_opt_md_list%>

Install like this:

```shell
<%=gem_opt_cmd%>
```

### Ruby gem: `<%=gemspec.name%>`

Once you have Ruby and rights to install gems, install the `<%=gemspec.name%>` gem and its dependencies:

```shell
gem install <%=gemspec.name%><%=gem_install_option%>
```

To upgrade to the latest version:

```shell
gem update <%=gemspec.name%>
```

During execution, <%=tool%> checks weekly whether a new version is available and notifies the user via a WARN log entry.
To deactivate this feature, globally set the option `version_check_days` to `0`, or specify a different period in days.

To check if a new version is available (independently of `version_check_days`):

```shell
<%=cmd%> config check_update
```

#### Verifying gem installation signature

The gem is signed with a private key, and the public certificate is available in the GitHub repository (`certs/aspera-cli-public-cert.pem`).
When installing the gem, the signature may optionally be verified.

For [secure installation](https://guides.rubygems.org/security/#using-gems), one can install the gem with the public key:

Import the verification certificate:

```shell
gem cert --add <(curl -Ls https://raw.githubusercontent.com/IBM/aspera-cli/main/certs/aspera-cli-public-cert.pem)
```

The user installs the gem with `HighSecurity` or `MediumSecurity`: this will succeed only if the gem is trusted:

```shell
gem install -P MediumSecurity <%=gemspec.name%>
```

#### Installing the development version of the gem

The development version of the gem is built from the branch `main` of the GitHub repository, every day it changes, and attached to the pre-release [`nightly`](https://github.com/IBM/aspera-cli/releases/tag/nightly).
It is not a release, and it is not signed.

Its version is the version in development followed by the number of commits of `main`, e.g. `4.30.0.pre.5592`: the build of a newer commit has a higher number, and the release (`4.30.0`) is higher than all.

On Linux/macOS, install in a terminal:

```shell
curl -sLo <%=gemspec.name%>-nightly.gem https://github.com/IBM/aspera-cli/releases/download/nightly/<%=gemspec.name%>-nightly.gem
gem install <%=gemspec.name%>-nightly.gem
```

On Windows, download the file `<%=gemspec.name%>-nightly.gem` from the link, then install it with `gem install <%=gemspec.name%>-nightly.gem`.

### FASP Protocol: `ascp`

File transfers are primarily performed using the **FASP** protocol via the `ascp` utility.

To execute an Aspera transfer, only two additional files are required; both are included with the Aspera Transfer Daemon:

- `ascp` - the transfer executable

- `aspera-license` - the license file (located in the same directory as `ascp` or in `../etc`)

These components can be installed either by installing the Aspera transfer software or by running the <%=tool%> command.

#### Installing `ascp` through `transferd`

The easiest option to install `ascp` is through the use of the IBM Aspera Transfer Daemon (`transferd`).
Install it using <%=tool%> (for the current platform) with:

```shell
<%=cmd%> transferd install
```

The installation of the transfer binaries follows those steps:

- **Select the SDK package to use**. Check the `sdk_url` option:
  - If the value is **not** the default value (`DEF`), it directly specifies the archive URL to download.
  - If the value is `DEF`, <%=tool%> downloads the YAML file from the URLs specified by the `locations_url` option.
    - URLs are tried in order until one succeeds. All but the last are tried with a short timeout and no retry.
      By default: <https://ibm.biz/sdk_location>, then its target on GitHub.
    - This YAML file lists supported architectures (OS, CPU) and Aspera Transfer Daemon versions with their associated package URLs.
    - The SDK version is selected as follows: if an additional **positional parameter** is provided it specifies the version; if the special value `LATEST` is given the latest available version is used; otherwise the version tested with this release of <%=tool%> is used.
    - The package URL matching the current system architecture is then used.
    - The request for the YAML file includes the version of <%=tool%> in the HTTP header `Referer`.
    - The YAML file is not read if the requested version is already installed, or if option `sdk_url` gives the archive.
- **Extract the archive**
  - By default, the archive is extracted to `$HOME/.aspera/sdk`.
  - The destination folder can be changed by setting the `sdk_folder` option.

| Option        | Description                                                  |
|---------------|--------------------------------------------------------------|
| `sdk_url`     | URL to download the Aspera Transfer Daemon archive.<%=br%>Default: `DEF` (select from available archives.) |
| `locations_url` | List of URLs to get download URLs of Aspera Transfer Daemon from IBM official repository, tried in order.<%=br%>A list given in options replaces the default list.<%=br%>Default:<%=br%>- `https://ibm.biz/sdk_location`<%=br%>- `https://raw.githubusercontent.com/IBM/aspera-cli/refs/heads/main/docs/sdk_location.yaml`|
| `sdk_folder`  | Folder where the SDK archive is extracted.<%=br%>Default: `$HOME/.aspera/sdk` |

> [!NOTE]
> Commands `config transferd ...` and `config ascp install` are deprecated aliases of `transferd ...` and `transferd install`.

Transfer Daemon versions available from `locations_url` can be listed with: `<%=cmd%> transferd list`

To install a specific version, for example, 1.1.3:

```shell
<%=cmd%> transferd install 1.1.3
```

To get the download URL for a specific platform and version:

```shell
<%=cmd%> transferd list --select.platform=osx-arm64 --select.version=1.1.3 --fields=url
```

To download it, pipe to `config download`:

```shell
<%=cmd%> transferd list --select.platform=osx-arm64 --select.version=1.1.3 --fields=url | <%=cmd%> config download @stdin:
```

To install from a local file (air-gapped installation) instead of fetching from the internet, specify the location of the SDK file with option `sdk_url`:

```shell
<%=cmd%> transferd install --sdk-url=file:///macos-arm64-1.1.3-c6c7a2a.zip
```

The format is: `file:///<%=ph :path%>` (canonical form) or `file:<%=ph :path%>` (short form), where `<%=ph :path%>` can be either a relative path (not starting with `/`), or an absolute path (starting with `/`).

| Form      | Relative example            | Absolute example                 |
|-----------|-----------------------------|----------------------------------|
| Canonical | `file:///mydir/archive.zip` | `file:////home/user/archive.zip` |
| Short     | `file:mydir/archive.zip`    | `file:/home/user/archive.zip`    |

Supported platforms are listed in the [Release Notes](https://developer.ibm.com/apis/catalog/aspera--aspera-transfer-sdk/Release+notes) and archives can be downloaded from [Downloads](https://developer.ibm.com/apis/catalog/aspera--aspera-transfer-sdk/downloads/downloads.json).

#### Installing `ascp` through another component

If the embedded method is not used, the following packages are also suitable:

- IBM Aspera Connect Client (Free, to be deprecated in 2027, use IBM Aspera for Desktop)
- IBM Aspera Desktop Client (Free)
- IBM Aspera for Desktop (Free)
- IBM Aspera High Speed Transfer Server (Licensed)
- IBM Aspera High Speed Transfer Endpoint (Licensed)

For instance, Aspera Connect Client can be installed by visiting the page:
[https://www.ibm.com/aspera/connect/](https://www.ibm.com/aspera/connect/).

<%=tool%> detects most Aspera transfer products in standard locations and use the first one found by default.
See [FASP](#fasp-configuration) for details on how to select a client or set path to the FASP protocol.

Several methods are provided to start a transfer.
Use of a local client ([`direct`](#agent-direct) transfer agent) is one of them, but other methods are available.
See [Transfer Agents](#transfer-clients-agents).

### Installing in an air-gapped environment

For an air-gapped installation, two alternatives are available:

1. Get the installation components from a system with internet access:

   - Ruby installation packages (depends on system)
   - Gems

      Use the gem pack of the release.
      It includes the `<%=gemspec.name%>` gem.
      On the air-gapped system, extract the archive and run:

      ```shell
      gem install *.gem
      ```

   - Transfer SDK

      On a system with internet access, retrieve the SDK archive for the target platform and version:

      ```shell
      <%=cmd%> transferd list --select.platform=<%=ph :platform%> --select.version=<%=ph :version%> --fields=url | <%=cmd%> config download @stdin:
      ```

      On the air-gapped system, install from the downloaded file using option `--sdk-url`:

      ```shell
      <%=cmd%> transferd install --sdk-url=file:///<%=ph :sdk_archive_path%>
      ```

2. Retrieve the [single file executable](#single-file-executable) from the release, if available, and the SDK (not included) as described above.

#### Packaging gem files and dependencies

Releases include gem packs: `gempack.zip` contains the minimal bundle of required gems.

Alternatively, the necessary gems can be packaged into a `tar.gz` archive as follows:

```shell
mkdir temp_folder
gem install <%=gemspec.name%>:<%=build_version%> --no-document --install-dir temp_folder
find temp_folder
mv temp_folder/cache <%=gemspec.name%>-<%=build_version%>-gems
rm -fr temp_folder
tar zcvf <%=gemspec.name%>-<%=build_version%>-gems.tgz <%=gemspec.name%>-<%=build_version%>-gems
```

#### Unix-like: Alternative installation using `rvm`

The following procedure applies when using RVM for the Ruby installation:

1. Follow the non-root installation procedure with RVM, including gem installation.

2. Archive the main RVM folder (includes <%=cmd%>):

   ```shell
   cd $HOME && tar zcvf rvm-<%=cmd%>.tgz .rvm
   ```

3. Download the Transfer Daemon archive for the target architecture. See [Install `ascp`](#installing-ascp-through-transferd).

4. Transfer the two archive files to the target system.

5. On the target system, run:

   ```shell
   cd $HOME
   tar zxvf rvm-<%=cmd%>.tgz
   source ~/.rvm/scripts/rvm
   <%=cmd%> transferd install --sdk-url=file:///<%=ph :sdk_archive_path%>
   ```

6. Add the following line to the shell environment file (`.profile`):

   ```shell
   source ~/.rvm/scripts/rvm
   ```

#### Windows: Installing in an air-gapped environment

> [!TIP]
> The simplest method is to use the [portable package](#windows-portable-package), which requires no internet access on the target system.

The procedure is similar to the internet-connected Windows installation. Copy the required files from a system with internet access, then install them on the target system.

1. Download the Ruby installer from <https://rubyinstaller.org/downloads/>:

   ```shell
   v=$(curl -s https://rubyinstaller.org/downloads/ | sed -nEe 's|.*(https://.*/releases/download/.*exe).*|\1|p' | head -n 1)
   curl -o ${v##*/} $v
   ```

2. Create a gem archive as described in [Packaging gem files and dependencies](#packaging-gem-files-and-dependencies).

3. Download the Transfer Daemon. See [Install `ascp`](#installing-ascp-through-transferd).

4. Create a Zip archive containing all the files above and transfer it to the target system.

On the target system:

1. Extract the archive.

2. Run the Ruby installer:

   ```batchfile
   <%=ph :ruby_installer_exe%> /silent /currentuser /noicons /dir=<%=ph :install_dir%>
   ```

3. Install the gems: extract the gem archive, then run:

   ```batchfile
   gem install --force --local *.gem
   ```

4. Install the Aspera Transfer Daemon SDK:

   ```shell
   <%=cmd%> transferd install --sdk-url=file:///<%=ph :sdk_archive_path%>
   ```

### Container

The container image is: [`<%=container_image%>`](https://hub.docker.com/r/<%=container_image%>).
The container contains: Ruby, <%=tool%> and the Aspera Transfer Daemon.
To use the container, ensure that you have `podman` (or `docker`) installed.

```shell
podman --version
```

#### Container: Quick start

To start an interactive shell, run:

```shell
podman run --rm --tty --interactive --entrypoint bash <%=container_image%>:latest
```

> [!NOTE]
> This command changes the entry point to an interactive shell instead of direct execution of <%=tool%>.

Then, execute individual <%=tool%> commands such as:

```shell
<%=cmd%> config initdemo
<%=cmd%> config preset overview
<%=cmd%> config ascp info
<%=cmd%> server ls /
```

That is simple, but there are limitations:

- Everything happens in the container.
- Any file generated in the container, including configuration files and downloaded files, is lost when the container (shell) exits.
- Files located on the host system cannot be uploaded.

#### Container: Details

The container image is built from this [Dockerfile](<%=link_repo('build/container/Dockerfile.tmpl.erb')%>).
The entry point is <%=tool%> and the default command is `help`.

The container can be executed for individual commands like this: (add <%=tool%> commands and options at the end of the command line, for example, `-v` to display the version)

```shell
podman run --rm --tty --interactive <%=container_image%>:latest
```

For more convenience, you may define a shell alias:

```shell
alias <%=cmd%>='podman run --rm --tty --interactive <%=container_image%>:latest'
```

Then, you can execute the container like a local command:

```shell
<%=cmd%> -v
```

```text
<%=build_version%>
```

To persist the configuration on the host, specify your user's configuration folder as a volume for the container.
To enable write access, a possibility is to run as `root` in the container (and set the default configuration folder to `/home/cliuser/.aspera/<%=cmd%>`).
Add options:

```shell
--user root --env <%=opt_env :home%>=/home/cliuser/.aspera/<%=cmd%> --volume $HOME/.aspera/<%=cmd%>:/home/cliuser/.aspera/<%=cmd%>
```

> [!NOTE]
> If you are using a `podman machine`, for example, on macOS, ensure that the folder is also shared between the VM and the host, so that sharing is:
>
> container &rarr; VM &rarr; Host: `podman machine init ... --volume="/Users:/Users"`

As shown in the quick start, if you prefer to keep a running container with a shell and <%=tool%> available, you can change the entry point, add option:

```shell
--entrypoint bash
```

> [!WARNING]
> <%=tool%> is run inside the container, so transfers are also executed inside the container and do not have access to host storage by default.

You may also want files downloaded in the container to be available on the host.
For example, files transferred with <%=tool%> through folder `/xferfiles` (right-hand side) would be available on the host in `$HOME/xferdir`.
In this case, you also need to specify the shared transfer folder as a volume:

```shell
--volume $HOME/xferdir:/xferfiles
```

To combine all the above options:

```shell
alias <%=cmd%>sh="podman run --rm --tty --interactive --user root --env <%=opt_env :home%>=/home/cliuser/.aspera/<%=cmd%> --volume $HOME/.aspera/<%=cmd%>:/home/cliuser/.aspera/<%=cmd%> --volume $HOME/xferdir:/xferfiles --entrypoint bash <%=container_image%>:latest"
```

```shell
export xferdir=$HOME/xferdir
mkdir -p $xferdir
chmod -R 777 $xferdir
mkdir -p $HOME/.aspera/<%=cmd%>
<%=cmd%>sh
```

#### Container: Sample start script

A convenience sample script is also provided: download the script [`d<%=cmd%>`](<%=link_repo('build/container/d'+cmd)%>) from [the GitHub repository](https://raw.githubusercontent.com/IBM/aspera-cli/main/build/container/d<%=cmd%>).

Some environment variables can be set for this script to adapt its behavior:

| env var        | Description                        | Default                  | Example                  |
|----------------|------------------------------------|--------------------------|--------------------------|
| `<%=opt_env :home%>` | Configuration folder (persistency) | `$HOME/.aspera/<%=cmd%>` | `$HOME/.<%=cmd%>_config` |
| `docker_args`  | Additional options to `podman`     | &lt;empty&gt;            | `--volume /Users:/Users` |
| `image`        | Container image name               | `<%=container_image%>`   | n/a                      |
| `version`      | Container image version            | Latest                   | `4.8.0.pre`              |

The wrapping script maps the folder `$<%=opt_env :home%>` on the host to `/home/cliuser/.aspera/<%=cmd%>` in the container (the configuration folder expected in the container).
This keeps the configuration persistent on the host.

To add local storage as a volume, you can use the env var `docker_args`:

Example of use:

```shell
curl -o <%=cmd%> https://raw.githubusercontent.com/IBM/aspera-cli/main/build/container/d<%=cmd%>
chmod a+x <%=cmd%>
export xferdir=$HOME/xferdir
mkdir -p $xferdir
chmod -R 777 $xferdir
export docker_args="--volume $xferdir:/xferfiles"

./<%=cmd%> config initdemo

echo 'Local file to transfer' > $xferdir/samplefile.txt
./<%=cmd%> server upload /xferfiles/samplefile.txt --to-folder=/Upload
```

> [!NOTE]
> The local file path is the one seen from the container (`/xferfiles/samplefile.txt`), where `/xferfiles` is mapped to the host folder `$HOME/xferdir`.

> [!WARNING]
> Do not use too many volumes, as the legacy `aufs` driver limits their number.
> Prefer the `overlay2` driver.

#### Container: Installing in an air-gapped environment

- First create the image archive:

```shell
podman pull <%=container_image%>
podman save <%=container_image%>|gzip><%=cmd%>_image_latest.tar.gz
```

- Then, on the air-gapped system:

```shell
podman load -i <%=cmd%>_image_latest.tar.gz
```

#### Container: `aspera.conf`

`ascp`'s configuration file `aspera.conf` is located in the container at: `/ibm_aspera/aspera.conf` (see Dockerfile).
As the container is immutable, modifying this file is not recommended.
To change the configuration, tell `ascp` to use another file using `ascp` option `-f`, for example, by locating it on the host folder `$HOME/.aspera/<%=cmd%>` mapped to the container folder `/home/cliuser/.aspera/<%=cmd%>`:

```shell
echo '<CONF/>' > $HOME/.aspera/<%=cmd%>/aspera.conf
```

Then, tell `ascp` to use that other configuration file:

```shell
--transfer=@json:'{"ascp_args":["-f","/home/cliuser/.aspera/<%=cmd%>/aspera.conf"]}'
```

#### Container: Singularity

Singularity is another container runtime.

On Linux install:

```shell
dnf install singularity-ce
```

Build an image like this:

```shell
singularity build <%=cmd%>.sif docker://<%=container_image%>
```

Then, start <%=tool%> like this:

```shell
singularity run <%=cmd%>.sif
```

Or get a shell with access to <%=tool%> like this:

```shell
singularity shell <%=cmd%>.sif
```

### Configuring the SSL library

<%=tool%> uses the Ruby `openssl` gem which uses by default the system's `openssl` library and its CA certificate bundle.

To display the version of **OpenSSL** used in <%=tool%>:

```shell
<%=cmd%> config echo @ruby:OpenSSL::OPENSSL_VERSION --format=text
```

To use another SSL library or version, execute:

```shell
gem install openssl -- --with-openssl-dir=[openssl library folder]
```

Where `[openssl library folder]` is the path to the folder containing the `lib` and `include` folders of the `openssl` library.

For example, on macOS, to use the `openssl@3` library installed with `brew`:

```shell
openssl version -e|sed -n 's|ENGINESDIR: "\(.*\)/lib[^/]*/.*|\1|p'
```

```text
/opt/homebrew/Cellar/openssl@3/3.3.0
```

Then install the `openssl` gem with:

```shell
gem install openssl -- --with-openssl-dir=$(openssl version -e|sed -n 's|ENGINESDIR: "\(.*\)/lib[^/]*/.*|\1|p')
```

### Configuring the SSL CA certificate bundle

SSL certificates are validated using a certificate store.
By default, it is the one of the system's `openssl` library.

To display the default trusted certificate store locations:

```shell
<%=cmd%> config echo '@ruby:[OpenSSL::X509::DEFAULT_CERT_DIR,OpenSSL::X509::DEFAULT_CERT_FILE]'
```

Certificates are checked against the [Ruby default certificate store](https://ruby-doc.org/stdlib-3.0.3/libdoc/openssl/rdoc/OpenSSL/X509/Store.html) `OpenSSL::X509::DEFAULT_CERT_FILE` and `OpenSSL::X509::DEFAULT_CERT_DIR`, which are typically the ones of `openssl` on Unix-like systems (Linux, macOS, and so on).
Ruby's default values can be overridden using env vars: `SSL_CERT_FILE` and `SSL_CERT_DIR`.
If neither these env vars are set nor the default locations exist (for example, a single executable built on another Linux distribution), <%=tool%> sets `SSL_CERT_FILE` to the first system CA bundle found: `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/ca-bundle.pem`, `/etc/ssl/cert.pem`.

To get certificate validation, the CA certificate bundle must be up-to-date.
Check this repository on how to update the system's CA certificate bundle: [https://github.com/millermatt/osca](https://github.com/millermatt/osca).

For example, on RHEL/Rocky Linux:

```shell
dnf install -y ca-certificates
update-ca-trust extract
```

The SSL CA certificate bundle can be specified using the `cert_stores` option, which accepts a list of files or directories.
By default, Ruby's system certificate store is used.

When `cert_stores` is provided:

- It overrides the default locations, which can still be included explicitly using the special value `DEF`.
- The option accepts either a `String` (single path) or an `Array` (multiple paths).
- Each use of the option appends to the list of search paths incrementally.
- If a directory is specified, all files within that directory are automatically included.

> [!NOTE]
> JRuby uses its own implementation and CA bundles.

For example, on Linux, to force the use of the system's certificate store:

```shell
--cert-stores=$(openssl version -d|cut -f2 -d'"')/cert.pem
```

`ascp` also needs to validate certificates when using **WSS** for transfer TCP part (instead of **SSH**).

By default, `ascp` uses a hard-coded root location `OPENSSLDIR`.
Original `ascp`'s hard-coded locations can be found using:

```shell
<%=cmd%> config ascp info --fields=openssldir
```

For example, on macOS: `/Library/Aspera/ssl`.
Then trusted certificates are taken from `[OPENSSLDIR]/cert.pem` and files in `[OPENSSLDIR]/certs`.
<%=tool%> overrides the default hard-coded location used by `ascp` for WSS and uses the same locations as specified in `cert_stores` (using the `-i` option of `ascp`).

To update trusted root certificates for <%=tool%>, update the system's root certificate store (see the locations displayed above).

An up-to-date version of the certificate bundle can also be retrieved with:

```shell
<%=cmd%> config echo @uri:https://curl.se/ca/cacert.pem --format=text
```

To download that certificate store:

```shell
<%=cmd%> config echo @uri:https://curl.se/ca/cacert.pem --format=text --out.file=/tmp/cacert.pem
```

Then, use this store by setting the option `cert_stores` (or env var `SSL_CERT_FILE`).

To trust a specific certificate (for example, self-signed), **provided that the `CN` is correct**, save the certificate chain to a file:

```shell
<%=cmd%> config remote_certificate chain https://localhost:9092 --insecure=yes --out.file=<%=ph :server_preset_name%>.pem
```

> [!NOTE]
> Use command `name` to display the remote common name of the remote certificate.

Then, use this file as certificate store (for example, here, Node API):

```shell
<%=cmd%> config echo @uri:https://localhost:9092/ping --cert-stores=<%=ph :server_preset_name%>.pem
```

## Command Line Interface

The command line tool is: <%=tool%>

The `<%=gemspec.name%>` gem provides a command line interface (CLI) which interacts with Aspera Products (mostly using REST APIs):

- IBM Aspera High Speed Transfer Server (FASP and Node)
- IBM Aspera on Cloud (including ATS)
- IBM Aspera Faspex
- IBM Aspera Shares
- IBM Aspera Console
- IBM Aspera Orchestrator
- And more...

<%=tool%> provides the following features:

- Commands to Aspera server products (on-premise and SaaS)
- Any command line **options** (products URL, credentials or any option) can be provided on command line, in configuration file, in env var, in files, ...
- Commands, Options, and Option values shortcuts
- FASP [Transfer Agents](#transfer-clients-agents) can be: local `ascp`, or Connect Client, or any transfer node
- Transfer parameters can be altered by modification of [**transfer-spec**](#transfer-specification), this includes requiring multi-session
- Allows transfers from products to products, essentially at node level (using the node transfer agent)
- FASPStream creation (using Node API)
- **Watchfolder** creation (using Node API)
- Additional command plugins can be written by the user
- Download of Faspex and Aspera on Cloud "external" links
- **Legacy** SSH based FASP transfers and remote commands (`ascmd`)

Basic usage is displayed by executing:

```shell
<%=cmd%> -h
```

See [Usage](#usage).

> [!NOTE]
> Not all features of <%=tool%> are documented here: explore commands on the command line, using `-h`.

### Command Line Arguments

Command line arguments are the units of command line typically separated by spaces (the `argv` of C).

<%=tool%> handles the following types of command line arguments:

- [**Options**](#options): absolute position is not important, but relative order is, as a given option may be provided several times
- [**Plugins**](#plugins) for example, `config`, on first position
- [**Resource Types**](#resource-types) for example, `users`
- [**Verbs**](#verbs) for example, `create`, to act on those resources or plugins.
- [**Identifiers**](#identifiers) for example, `123`, uniquely identifying a resource
- [**Command Parameters**](#command-parameters) arguments, for example, creation data, can be an [Extended Value](#extended-value-syntax).

Command line arguments that are not options are referred to as **Positional Arguments**.

For example:

```shell
<%=cmd_skip%> plugin command verb --option-name=VAL1 VAL2
```

- **Positional Arguments**: `plugin command verb VAL2`
- One **Option**: `option_name` and its **value**: `VAL1`

Enumeration values (positional arguments and option names/values) support prefix matching.
See [Enumerations](#enumerations) for details.

For example `<%=cmd_skip%> config pre ov --for=c` is the same as `<%=cmd_skip%> config preset overview --format=csv`.

The value of **Options** and **Command Parameters** is evaluated with the [Extended Value](#extended-value-syntax) syntax.

#### Positional Arguments

When options (beginning with `--`) are removed from the command line, the remaining arguments are **Positional Arguments** with a significant, pre-defined order.

**Plugins**, **Resource Types** and **Verbs** are [Enumerations](#enumerations).

**Identifiers** and **Command Parameters** are open values, but a given type is expected, either a simple `String` or an [Extended Value](#extended-value-syntax).

The general structure of positional arguments is:

```text
<%=cmd%> <%=ph :plugin%> <%=ph :resource%> <%=ph :command%> [<%=ph :ID%>] [<%=ph :parameters%>]
```

If a sub-resource is used:

```text
<%=cmd%> <%=ph :plugin%> <%=ph :resource1%> <%=ph :sub_resource%> [<%=ph :ID%>1] <%=ph :command2%> [<%=ph :ID2%>] [<%=ph :parameters%>]
```

Example:

```shell
<%=cmd%> config ascp info
```

- <%=tool%> is the executable executed by the shell
- `config` is the name of the plugin to be used
- `ascp` is the name of the resource (singleton, so no identifier is provided)
- `info` is the verb to be performed (action on selected resource)

#### Resource types

They identify a type of resource accessible in a given context.
A resource type can be a singleton, or have multiple instances (identified by their identifier).
A plugin is a kind of resource type singleton.
A resource type can also be a grouping of other resource types, for example `admin` or `files`, like a singleton.

#### Verbs

Standard resource **Verbs** are: `create`, `show`, `list`, `modify`, `delete`.
Some entities also support additional verbs.
When such additional commands relate to a resource also accessible in another context, they are placed under the `do` command.
Such subcommands appear after the resource identifier, for example, in `<%=cmd%> aoc admin node do <%=ph :node_id%> browse /`, `browse` is a subcommand of `node`.

Typically, the `create` verb takes resource creation data as a parameter.
`show`, `modify` and `delete` take an identifier, unless manipulating a singleton.
`list` typically uses the `query`, `select` options.
`list` and `show` typically use the `fields` option.

#### Identifiers

Identifiers uniquely identify a resource.
They are typically located immediately after a verb like `show`, `modify` or `delete`, itself placed after the resource type, for example: `user show foobar`.
Some resources can also be selected by a unique field other than the native identifier (typically: `id`), using the [**percent selector**](#percent-selector).

##### Percent selector

The **percent selector** is a special syntax that lets you identify a resource by any unique field, instead of its default identifier (typically a numeric `id`).

Syntax: `%<%=ph :field%>:<%=ph :value%>`

- The leading `%` marks the argument as a percent selector (not a plain identifier).
- `<%=ph :field%>` is the name of the field to match on (e.g. `name`, `email`).
- `<%=ph :value%>` is the expected value of that field.

The tool then looks up the resource whose `<%=ph :field%>` equals `<%=ph :value%>` and uses its native identifier internally.

For example, to show the user whose `name` field is `john`:

```shell
<%=cmd%> aoc admin user show %name:john
```

#### Command Parameters

**Command Parameters** are typically mandatory values for a command, such as resource creation data.

> [!NOTE]
> A Command Parameter could also have been designed as an option.
> However, since it is mandatory and such data typically do not need to be stored in a configuration file, using a Command Parameter is the better design choice.
> The advantages over an option are: a shorter command line (no option name, only position), a clearly mandatory value, and a position that unambiguously indicates its role.
> [Extended Value](#extended-value-syntax) syntax is supported, so it is possible to retrieve a value from the configuration file (using `@preset:`) or an environment variable (using `@env:`).

If a **Command Parameter** begins with `-`, then either use the `@val:` syntax (see [Extended Value](#extended-value-syntax)), or use the `--` separator (see below).

A few **Command Parameters** are optional: they are always located at the end of the command line.

#### Enumerations

**Enumerations** are arguments that must match a value from a predefined list in a given context.

The following are enumerations:

- **Plugins**, **Resource Types**, and **Verbs** (positional arguments)
- Option names (for example, `--log-level`)
- Some option values (for example, `debug` for `--log-level`)

**Prefix matching**: You can use a unique prefix instead of the full value, provided it uniquely identifies the value in that context.

Examples:

- Positional: `<%=cmd_skip%> config pre ov --for=c` is the same as `<%=cmd_skip%> config preset overview --format=csv`
- Option name: `--log-l=debug` is the same as `--log-level=debug`
- Option value: `--format=c` is the same as `--format=csv`

> [!NOTE]
> While prefix matching works for option names, using full names is recommended for clarity.

**Error handling**: If an invalid or missing enumeration value is provided, an error message displays the list of valid values for that context.

#### Dot-path Notation

<%=tool%> uses a unified [dot-path](#dot-path-notation) notation in several places on the command line and in output.
Understanding this concept once makes it immediately usable everywhere it appears.

[Dot-path](#dot-path-notation) notation is used in four distinct places in <%=tool%>:

| Surface        | Syntax                | in/out | read/write |
|----------------|-----------------------|--------|------------|
| [Option](#options) names  | `--opt.key.sub=value` | Input  | write     |
| [Positional arguments](#positional-arguments) | `@: key.sub=value ... [END]` | Input | write |
| [Extended value](#extended-value-syntax) `@preset:` | `@preset:key.sub` | Input | read  |
| [Output field names](#filtering-results) | `--out.fields=key.sub` | Output | read |

A [dot-path](#dot-path-notation) is a `String` where segments are separated by `.` (dot), each segment designating a key in a nested structure:

- A **string segment** designates a key in a `Hash` (associative array).
- An **integer segment** designates an index in an `Array`.

For example, the path `a.b.0` means: key `a`, then key `b`, then the first element of an array.

When a **value** is assigned to the path (**write** with `=`), it is automatically converted to the simplest matching type: `Boolean`, `Integer`, `Float`, or `String`.
Values `true` and `yes` are converted to `Boolean` `true`, and values `false` and `no` to `false`.
For an option expecting a list of values that includes `yes` or `no` (e.g. `--out.table.pivot=no`), the `Boolean` is converted back to that value.

> [!NOTE]
> A value of `1` will be automatically converted to an `Integer`.
> When a specific type is required for the value, the [Extended Value](#extended-value-syntax) syntax modifiers `@json:` or `@ruby:` can be used.
> For example: `--opt.x=1` generates `{"x": 1}`.
> To get a `String`: `--opt.x=@json:\"1\"` or `--opt.x=@ruby:%q{1}`.
> Likewise, to get the `String` `yes`: `--opt.x=@json:\"yes\"`.

Example: [dot-path](#dot-path-notation) to JSON output

```shell
<%=cmd%> config echo @: a.b=1 a.c=2 a.d.0=hello a.d.1=world --format=json
```

```json
{"a":{"b":1,"c":2,"d":["hello","world"]}}
```

Example: JSON to [dot-path](#dot-path-notation) output

```shell
<%=cmd%> config echo @json:'{"a":{"b":1,"c":2,"d":["hello","world"]}}'
```

```text
╭───────┬───────╮
│ field │ value │
╞═══════╪═══════╡
│ a.b   │ 1     │
│ a.c   │ 2     │
│ a.d   │ hello │
│       │ world │
╰───────┴───────╯
```

##### Positional Arguments with Dot-path

The `@:` syntax is a specialized argument type used for **in-place definition** of nested data structures.
It allows you to construct complex parameters (`Hash`es and `Array`s) directly from the command line, serving as a readable alternative to providing a single, serialized JSON string.

**Usage and Syntax**:

The general syntax for this argument is:

```text
@:[<%=ph :marker%>] <%=ph :dot_path%>=<%=ph :value%> [<%=ph :dot_path%>=<%=ph :value%>] ... [<%=ph :marker%>]
```

- `@:[<%=ph :marker%>]`: A standalone argument that starts collecting [dot-path](#dot-path-notation) assignments into a single data structure.
  The optional text after `:` sets the end marker. If it is empty, the marker is `END`.

- `<%=ph :dot_path%>=<%=ph :value%>`: An assignment using the standard [dot-path](#dot-path-notation) notation. Multiple assignments can be provided in sequence to build a complex object.
  The value is converted like any [dot-path](#dot-path-notation) value, and can be an [Extended Value](#extended-value-syntax), for example `public_key=@file:~/.ssh/id_rsa.pub`.
  Options placed among the assignments are not collected: they are processed as usual, for example `@: a=1 --format=json b=2`.

- `<%=ph :marker%>` (`END` by default): An optional argument that ends the collection.

  - Without the marker: **All** remaining positional arguments are collected, and each one must contain `=`.

  - With the marker: **Only** arguments between `@:` and the marker are used for the structure. Arguments after the marker are passed to the command as normal positional arguments.

  - Example with a custom marker: `@:STOP a=1 STOP`.

> [!IMPORTANT]
> Use `END` whenever any positional argument must follow the object built with `@:` (for example, a file list, or any other subsequent positional parameter).
> Without `END`, those arguments are collected as [dot-path](#dot-path-notation) assignments instead of being passed to the command: an argument without `=` causes an error, and an argument containing `=` is silently added to the structure.

**Example**: Sending a package with a file list using `@:` for package information.

```shell
<%=cmd%> aoc packages send @: name="<%=ph :title%>" recipients.0=user@example.com END file1.dat file2.dat
```

> [!CAUTION]
> In the above example, removing `END` causes an error, because `file1.dat` is read as a [dot-path](#dot-path-notation) assignment and does not contain `=`.

> [!NOTE]
> `@:` can also be used as an option value (for example, `--query=@: a=b`).
> In that case, only positional arguments **after the option's position** in the original command line are consumed, so sub-commands before the option are not affected.
> Use `END` as usual to stop collection when further positional arguments must follow: `<%=cmd%> aoc tier_restrictions --query=@: a=b END other_arg`.

#### Options

Command-line options, such as `--log-level=debug`, follow these conventions:

- **Prefix**:
  All options begin with `--`.
- **Naming**:
  Option names on command line use lowercase letters and hyphens (`-`) as word separators.
  Option names in the configuration file use underscores (`_`) as word separators.
  Example: `--log-level=debug` is `log_level` in config file.
- **Values**:
  An option's value is assigned using `=` (for example, `--log-level=debug`).
  Alternatively, the value can be provided as a separate, space-separated token (for example, `--log-level debug`).
  Both forms are equivalent.
- **Prefix Usage**:
  Options support prefix matching (see [Enumerations](#enumerations)), though full names are recommended.
- **Optionality**:
  Most options are optional; they either have a default value or do not require one.
- **Order**:
  Options can appear in any position on the command line, but their order may affect processing.

Exceptions and Special Cases:

- **Short Forms**

  Some options have short forms.
  For example, `-Ptoto` and `-P toto` are both equivalent to `--preset=toto` and `--preset toto`.
  See the manual or `-h` for details.
- **Flags**

  Certain options are flags and do not require a value (for example, `-N`).
- **Option Terminator**

  The special option `--` ends option parsing.
  All subsequent arguments, including those starting with `-`, are treated as positional arguments.
- [**dot-path notation**](#dot-path-notation)
- **Cumulative Hashes**

  When an option of type `Hash` is set, the value is deep-merged with any existing value.
  Setting to `@json:{}` starts from an empty hash (the existing value is discarded for that merge step).
  Setting to `@none:` explicitly disables the option: it is set to `nil` and any preset or default value is prevented from restoring it.
  This is useful, for example, to disable a vault or any Hash option that is configured in a default preset.

Example:

```shell
<%=cmd%> config echo -- --sample
```

```text
--sample
```

> [!NOTE]
> Here, `--sample` is taken as an argument, and not as an option, due to `--`.

Options may have a (hard coded) default value.

Options can be placed anywhere on command line and are evaluated in order.
Usually the last value evaluated overrides previous values, but some options are cumulative, for example, `ts`.

Options are typically optional: to change the default behavior.
But some are mandatory, so they can be placed in a configuration file, for example: connection information.

The value for **any** options can come from the following locations (in this order, last value evaluated overrides previous value):

- [Configuration file](#configuration-file)
- Environment variable
- Command line

Environment variables starting with prefix <%=opt_env ''%> are taken as option values, for example, `<%=opt_env :option_name%>` is for `--option-name`.

Option `show_config` dry runs the configuration, and then returns currently set values for options.

`<%=cmd%> --show-config` outputs global options only, and `<%=cmd%> [plugin] --show-config` outputs global and plugin default options.
In addition, option `--show-config` can be added at the end of any full command line, this displays the options that would be used for the command.

A command line argument is typically designed as option if:

- It is optional, or
- It is a mandatory parameter with a default value that would benefit from being set persistently (that is, in a configuration file or environment variable, for example, URL and credentials).

### Interactive Input

Some options and **Command Parameters** are mandatory and others are optional.
By default, <%=tool%> raises an error for missing mandatory options or **Command Parameters**.

The behavior can be controlled with:

- `--interactive=<yes|no>` (default=no)
  - `yes`: Missing mandatory parameters/arguments are asked to the user.
  - `no`: Missing mandatory parameters/arguments raise an error message.
- `--ask-options=<yes|no>` (default=no)
  - `yes`: Optional parameters/arguments are asked to the user.

#### Hidden Input

Secrets (passwords, `@secret:`, code or URL pasted after a web login) are read without displaying them.
On a terminal, a mark shows the state of the input, without revealing its length:

| Mark | ASCII | State |
|------|-------|-------|
| `🔑` | `***` | Waiting for input: nothing typed or pasted yet. |
| `…`  | `...` | Something was typed or pasted. |
| `✓` (green) | `valid` | Checked input: it is valid. |
| `✗` (red) | `invalid` | Checked input: it is not valid (yet), e.g. incomplete, mistyped or expired. |

The ASCII form is used when the locale does not support Unicode.

Some inputs are checked while they are typed or pasted, e.g. the code displayed by Shares after login (see [Authentication of SAML users](#authentication-of-saml-users)): `✓` or `✗` replaces `…`.
If `Enter` is pressed on an input that is not valid, the error is displayed and the input is asked again (`Ctrl-C` to stop).
If the standard input is not a terminal, an input that is not valid is an error.

Keys:

| Key | Action |
|-----|--------|
| `Enter` | End the input. |
| `Backspace` | Erase the last character. |
| `Ctrl-W` | Erase the last word. |
| `Ctrl-U` | Erase all (for example, to paste again). |
| `Ctrl-D` (Unix), `Ctrl-Z` (Windows) | End the input; if empty: error (end of input). |
| `Ctrl-C` | Stop <%=tool%>. |

If the standard input is not a terminal (for example, a pipe), the line is read as is, without mark.
It is the same if the terminal does not support reading characters one by one (raw mode).

To read secrets without any mark (no feedback, as `getpass`), set option `ui.hidden_silent` to `yes`:

```shell
<%=cmd%> config preset set GLOBAL ui.hidden_silent yes
```

### Output

Command execution will result in output (terminal, stdout/stderr).
The information displayed depends on the action.

To redirect results to a file, use option `--out.file`.

#### Types of output data

Depending on action, the output will contain:

| Result Type     | Description                                                                       |
|-----------------|-----------------------------------------------------------------------------------|
| `single_object` | Displayed as a two-dimensional table: one line per field, first column is field name, and second is field value. Nested hashes are collapsed. |
| `object_list`   | Displayed as a two-dimensional table: one line per item, one column per field. |
| `value_list`    | A table with one column. |
| `empty`         | nothing |
| `status`        | A message. |
| `other_struct`  | A complex structure that cannot be displayed as an array. |

With a structured format (`json`, `jsonpp`, `yaml`, `ruby`), the output is always valid in this format: a status is a string, an empty list is `[]`, and no result is `null`.

#### Enhanced display of special values

Special values are highlighted as follows in `format=table`:

| Value          | Display          |
|----------------|------------------|
| `nil`          | `<null>`         |
| empty `String` | `<empty string>` |
| empty `Array`  | `<empty list>`   |
| empty `Hash`   | `<empty dict>`   |

Example:

```shell
<%=cmd%> config echo @json:'{"ni":null,"es":"","ea":[],"eh":{}}'
```

```text
╭───────┬────────────────╮
│ field │ value          │
╞═══════╪════════════════╡
│ ni    │ <null>         │
│ es    │ <empty string> │
│ ea    │ <empty list>   │
│ eh    │ <empty dict>   │
╰───────┴────────────────╯
```

#### Filtering results

The result of a command can be filtered on the server side, by the API, and then on the client side, by <%=tool%>.
Filtering on the server side reduces the data transferred, while filtering on the client side accepts any condition.

Options are evaluated in this order:

![Order of evaluation of the options that filter results](<%=link_repo('docs/filtering-order.svg')%>)

1. `--query`: parameters sent to the API.
2. `--out.secrets`: secrets are hidden first, so that an expression cannot reveal them.
3. `--out.query`: JMESPath expression or Ruby lambda, applied to the data as returned by the API.
4. `--out.select`: selection of items (rows).
5. `--out.fields`: selection of fields (columns).
6. Display in the format set by `--out.format`.

| To                                       | Use                                      |
|------------------------------------------|------------------------------------------|
| Limit what the API returns               | `--query`, with parameters `max` and `pmax` |
| Filter on any condition, reshape, count  | `--out.query`                            |
| Select items by the value of fields      | `--out.select`                           |
| Choose the fields displayed              | `--out.fields`                           |

##### Option: `--query`: Parameters of the API

The `query` option can generally be used to add URL parameters to commands that list resources.
It takes a `Hash`, corresponding to key/value pairs that appear in the query part of the request.

For example: `--query=@json:'{"p1":"v1","p2":"v2"}'` leads to query: `?p1=v1&p2=v2`.

If the same parameter needs to be provided several times, then it is also possible to provide an `Array`.

For example: `--query=@json:'{"p":["v1","v2"]}'` leads to query: `?p=v1&p=v2`.

If PHP-style arrays are expected in the API, add `[]` to the name of the parameter.

For example: `--query=@json:'{"p[]":["v1","v2"]}'` leads to query: `?p[]=v1&p[]=v2`.

Commands that read a list by pages (for example, `aoc admin user list`) also accept parameters `max` and `pmax`.
They are processed by <%=tool%>, not sent to the API: they limit the number of items (`max`) and of pages (`pmax`) requested.

For example: `--query.max=10` reads the first 10 items.

> [!TIP]
> Use `--query=help` on any `list` command to display the available query parameters and their types, as documented in the API.
> For example: `<%=cmd%> faspex5 admin accounts list --query=help`

##### Option: `--out.query`: JMESPath expression

Option `--out.query` applies a [JMESPath](https://jmespath.org) expression to the result of a command, when it is an object or a list.
JMESPath is a standard query language for JSON, also used by option `--query` of the AWS and Azure CLIs.

The expression is applied to the data as returned by the API (secrets hidden), before options `--out.select` and `--out.fields`.
Its syntax is checked before the command is executed.
Results of other types (status, no result) are not changed.

Examples:

```shell
# Name and email of ATS administrators
<%=cmd%> aoc admin user list --out.query='[?ats_admin].{name: name, email: email}'
# Number of users
<%=cmd%> aoc admin user list --out.query='length(@)'
# Email of users, one per line, for use in a shell loop
<%=cmd%> aoc admin user list --out.query='[].email' --format=text
```

> [!TIP]
> Enclose the expression in single quotes for the shell.
> In JMESPath, literal values are enclosed in backticks, for example: ``[?size > `1000`]``.
> An expression with string literals in single quotes (`'...'`) is enclosed in double quotes, for example: `"[?name=='Ann']"`.

For processing that JMESPath does not provide (regular expressions, string manipulation, grouping), the value can be a Ruby lambda (`@ruby:`): it is called with the data, and returns the new data, converted to JSON data (for example, symbols and dates become strings).
It is refused at [Security Level](#security-level) `medium` and `high`.

```shell
# Number of users per email domain
<%=cmd%> aoc admin user list --out.query=@ruby:'->(users){users.group_by{|u|u["email"].split("@").last}.transform_values(&:count)}'
```

The result of the query is displayed according to its type: a list of objects as a table, a list of values with one value per line, a single value as is.
A list of lists (for example, `[].[name, email]`) is displayed only with a structured format (`json`, `yaml`, ...): to display a table, or CSV, use a multi-select hash instead, for example, `[].{name: name, email: email}`.

> [!NOTE]
> Option `--query` gives filtering parameters to the API, while option `--out.query` filters and reshapes the result received.
> Option `--out.query` is the equivalent of option `--query` of the AWS and Azure CLIs.

##### Option: `--out.select`: Selection of items

A list of objects (`object_list`) can be filtered with option `--out.select` (or `--select`).
Its value is either a `Hash` or a `Proc`:

- `Hash`: an item is selected if each key of the `Hash` is a field of the item with the same value, and the same type: `true` (`Boolean`) is not `"true"` (`String`).
- `Proc`: a Ruby lambda called with each item (`Hash`), that returns `true` to select it, or `false` to remove it.

Example:

```shell
<%=cmd%> aoc admin user list --out.fields=name,email,ats_admin --query=@json:'{"sort":"name"}' --out.select=@json:'{"ats_admin":true}'
```

```text
╭────────────────┬─────────────────────┬───────────╮
│ name           │ email               │ ats_admin │
╞════════════════╪═════════════════════╪═══════════╡
│ John Curtis    │ john@example.com    │ true      │
│ Laurent Martin │ laurent@example.com │ true      │
╰────────────────┴─────────────────────┴───────────╯
```

In the above example, the same result is obtained with option:

```shell
--out.select=@ruby:'->(i){i["ats_admin"]}'
```

A key can be a [dot-path](#dot-path-notation), for example, `directory_user.type`, with all formats.

##### Option: `--out.fields`: Selection of fields

Depending on the command, results may include by default all fields, or only some selected fields.
It is possible to define specific columns to be displayed, by setting option `--out.fields` (or `--fields`).

The `--out.fields` option is a list that can be either a comma-separated list or an [Extended Value](#extended-value-syntax) `Array`.

Individual elements of the list can be:

- **property**: add property to the current list
- `-`**property**: remove property from the current list
- `DEF`: default list of fields (that is the default, when not set)
- `ALL`: all fields
- A Ruby `RegEx`: using `@ruby:'/.../'`, or `@re:...` add those matching to the list

To display a **property** inside a complex structure (`Hash`, `Array`), use [dot-path](#dot-path-notation) notation, only with `--format=table` or `csv` (see option `--out.flat`).
With other formats, use a JMESPath multi-select hash with option `--out.query`, for example: `--out.query='[].{name: name, type: directory_user.type}'`.

Examples:

- `a,b,c`: the list of attributes specified as a comma-separated list (overrides the default)
- `@list:,a,b,c`: `Array` [Extended Value](#extended-value-syntax): same as above
- `@json:'["a","b","c"]'`: `Array` [Extended Value](#extended-value-syntax): same as above
- `b,DEF,-a`: default property list, remove `a` and add `b` in first position
- `@ruby:'/^server/'`: Display all fields whose name begins with `server`

##### `--out.select` or `--out.query`

Option `--out.select` is shorter for a test of equality, while option `--out.query` accepts any condition.

| Condition                | `--out.select`                                     | `--out.query`                                    |
|--------------------------|----------------------------------------------------|--------------------------------------------------|
| Equal to a `Boolean`     | `@json:'{"ats_admin":true}'`                       | `'[?ats_admin]'`                                 |
| Equal to a `String`      | `@json:'{"name":"Ann"}'`                           | `"[?name=='Ann']"`                               |
| Field of a nested object | `@json:'{"directory_user.type":"active_directory"}'` | `"[?directory_user.type=='active_directory']"` |
| Several conditions (and) | `@json:'{"ats_admin":true,"name":"Ann"}'`          | `"[?ats_admin && name=='Ann']"`                  |
| Negation, or             | Ruby lambda (`@ruby:`)                             | `'[?!ats_admin]'`, or: see [Recipes](#recipes)   |
| Number comparison        | Ruby lambda (`@ruby:`)                             | ``'[?size > `1000000`]'``                        |
| Substring                | Ruby lambda (`@ruby:`)                             | ``'[?contains(email, `@example`)]'``             |
| Choice of fields         | With option `--out.fields`                         | `'[].{name: name, email: email}'`                |
| Count                    | Not possible                                       | `'length(@)'`                                    |

> [!WARNING]
>
> - Values are compared with their type. With `--out.select`, `"true"` (`String`) does not match `true` (`Boolean`). In JMESPath, ``[?ats_admin == `true`]`` matches, but `[?ats_admin == 'true']` does not: `'...'` is a string literal.
> - After `--out.query`, the default fields of the command no longer apply: all the fields of the result are displayed. Choose fields in the expression (multi-select hash), or with option `--out.fields`.
> - Secrets are hidden before `--out.query` is applied, so that the expression cannot reveal them.

##### Recipes

```shell
# Users of Active Directory, with user name and email
<%=cmd%> shares admin user all list --out.query="[?directory_user.type=='active_directory'].{username: username, email: email}"
# Users without directory (field missing or null)
<%=cmd%> shares admin user all list --out.query='[?directory_user == null].username'
# Number of ATS administrators
<%=cmd%> aoc admin user list --out.query='length([?ats_admin])'
# Users who are ATS administrators, or have no email
<%=cmd%> aoc admin user list --out.query='[?ats_admin || !email].name'
# Emails of a domain, one per line
<%=cmd%> aoc admin user list --out.query='[?ends_with(email, `@example.com`)].email' --format=text
# Largest file of a folder
<%=cmd%> node browse / --out.query='max_by([?type==`file`], &size).path'
# Files larger than 1 MB
<%=cmd%> node browse / --out.query='[?size > `1000000`].{path: path, size: size}'
# Files modified since a date
<%=cmd%> node browse / --out.query='[?mtime >= `"2025-06-01"`].path'
```

> [!NOTE]
> The JMESPath implementation of <%=tool%> (gem `jmespath`) also compares strings with `<`, `<=`, `>` and `>=`, which the JMESPath specification defines only for numbers.
> Dates in ISO 8601 format, in the same time zone, are compared in chronological order.

The result in JSON (`--format=json`) can also be processed by other tools, such as [`jq`](https://jqlang.org), whose language differs from JMESPath: for example, `jq 'map(select(.directory_user.type == "active_directory"))'`.

##### Other filters

Some commands provide their own filters:

- [Percent selector](#percent-selector) `%<field>:<value>`: selects a single resource by the value of one of its fields.
- `find` of plugin `node` (gen4) and `aoc files find`: recursive search of files on the client side, with a glob or a Ruby lambda (see [Operation `find`](#operation-find-on-gen4access-key)).
- `faspex5 packages list`: a Ruby lambda as last argument (see [Faspex 5: List packages](#faspex-5-list-packages)).
- `console transfer`: query parameter `filter` (see [Transfer filter](#transfer-filter)).
- `preview`: options `--filter` and `--skip-folders` (see [Candidate detection](#candidate-detection-for-creation-or-update-or-deletion)).

#### Option: `--out.format`

The style of output can be set using option `--out.format` (or `--format`):

| `format` | Output formatting         |
| -------- | -------- |
| `table`  | Text table (default)      |
| `text`   | Value as `String`         |
| `ruby`   | Ruby code                 |
| `json`   | JSON code                 |
| `jsonpp` | JSON pretty printed       |
| `yaml`   | YAML                      |
| `csv`    | Comma Separated Values    |
| `image`  | URL or data for a [picture/video](#image-and-video-thumbnails) |
| `nagios` | Suitable for Nagios       |

By default, results of type `single_object` and `object_list` are displayed using format `table`.

#### Option: `--out.table`

The way `format`: `table` and `csv` are generated can be customized with option `--out.table` which expects a `Hash`.

For `format=table`, options are the ones described in gem [`terminal-table`](https://github.com/tj/terminal-table).

For example, to display a table with thick Unicode borders:

```shell
<%=cmd%> config preset overview --out.table=@ruby:'{border: :unicode_thick_edge}'
```

> [!NOTE]
> Other border styles exist, not limited to: `:unicode`, `:unicode_round`.

By default, if the terminal supports Unicode (see [`--out.utf8`](#terminal-rendering-colors-and-utf-8)), then `border=unicode_round` is used.

A special parameter is defined: `str_lst_sep` (`String`), default is `\n`.
It defines how lists of strings are displayed.
Alternatively, set to `,`.

When the output is a terminal, the table is fitted to the terminal width: columns with text (e.g. `description`) are wrapped, the widest first.
If not enough, other columns (names, identifiers) are wrapped too, preferably after a punctuation (`-`, `_`, `.`, `/`).
If the table cannot fit, columns are narrowed to their minimum width (20 characters for text, 10 for others, or heading).
Parameter `width` (`Integer`) sets the maximum table width (e.g. `--out.table.width=100`), also when the output is not a terminal.

For `format=csv`, options are described in gem [`csv`](https://ruby.github.io/csv/CSV.html#class-CSV-label-Options+for+Generating).

For example, to display a CSV with headers and quotes:

```shell
<%=cmd%> config echo @json:'[{"name":"foo","id":1},{"name":"bar","id":8}]' --format=csv --out.table=@json:'{"headers":true,"force_quotes":true}'
```

#### Option: `--out.flat`: Single level `Hash`

This option controls how object fields are displayed for complex objects.

Effective only when `format` is `table` or `csv` to display `single_object` or `object_list`.

If value is `no`, then object's `field` names are only the first level keys of the `Hash` result and values that are `Hash` are displayed as such in Ruby syntax.

If value is `yes` (default), then objects are "flattened" using [dot-path](#dot-path-notation) notation with a variation:

- Final arrays are displayed as a list of values, one per line (see `str_lst_sep` in `--out.table` above)
- `Array` of `Hash` with only `name` keys are displayed as comma separated list of values
- `Array` of `Hash` with only `name` and `value` keys are displayed like a `Hash` with value of `name` as key.

Example: The result of the command is a single object:

```shell
<%=cmd%> config echo @json:'{"A":"a","B":[{"name":"B1","value":"b1"},{"name":"B2","value":"b2"}],"C":[{"C1":"c1"},{"C2":"c2"}],"D":{"D1":"d1","D2":"d2"}}'
```

```text
╭────────┬───────╮
│ field  │ value │
╞════════╪═══════╡
│ A      │ a     │
│ B.B1   │ b1    │
│ B.B2   │ b2    │
│ C.0.C1 │ c1    │
│ C.1.C2 │ c2    │
│ D.D1   │ d1    │
│ D.D2   │ d2    │
╰────────┴───────╯
```

For the same command, adding option `--out.flat=no`:

```text
╭───────┬────────────────────────────────────────────────────────────────────────╮
│ field │ value                                                                  │
╞═══════╪════════════════════════════════════════════════════════════════════════╡
│ A     │ a                                                                      │
│ B     │ [{"name" => "B1", "value" => "b1"}, {"name" => "B2", "value" => "b2"}] │
│ C     │ [{"C1" => "c1"}, {"C2" => "c2"}]                                       │
│ D     │ {"D1" => "d1", "D2" => "d2"}                                           │
╰───────┴────────────────────────────────────────────────────────────────────────╯
```

#### Option: `--out.table.pivot`

This option controls how result fields are displayed as columns or lines, when option `format` is set to `table`.
Values are `false` (default), `true` or `single`.
On command line, `no` and `yes` can be used as well (converted to `Boolean`, see [dot-path](#dot-path-notation)), but a structured value (e.g. `--out=@json:'{"table":{"pivot":true}}'`) expects a `Boolean`.
There are two types of results that are affected by this option:

| Result          | Description                                 |
|-----------------|---------------------------------------------|
| `single_object` | A single item with multiple fields.         |
| `object_list`   | A list of items, each with multiple fields. |

An item (object) is displayed in one of those 2 ways:

| Display    | rows   | columns             |
|------------|--------|---------------------|
| Simple     | Fields | `field` and `value` |
| Transposed | Items  | Fields              |

The display of result is as follows:

| Result          | `false`    | `true`      | `single`                            |
|-----------------|------------|-------------|-------------------------------------|
| `single_object` | Simple     | Simple      | Simple                              |
| `object_list`   | Transposed | Simple<%=br%>(Multiple objects) | Simple if 1 object.<%=br%>transposed if 2+ objects. |

This parameter can be set as a global default with:

```shell
<%=cmd%> config preset set GLOBAL out.table.pivot single
```

Examples:

Simulate a result by executing this command:

```shell
<%=cmd%> config echo @json:'<%=ph :json_value%>' --out.table.pivot=<no|yes|single>
```

Example 1: A list of one object

```json
[{"user":{"id":1,"name":"toto"},"project":"blash"}]
```

Display with `no` (Transposed):

```text
╭─────────┬───────────┬─────────╮
│ user.id │ user.name │ project │
╞═════════╪═══════════╪═════════╡
│ 1       │ toto      │ blash   │
╰─────────┴───────────┴─────────╯
```

Display with `yes` and `single` (Simple):

```text
╭───────────┬───────╮
│ field     │ value │
╞═══════════╪═══════╡
│ user.id   │ 1     │
│ user.name │ toto  │
│ project   │ blash │
╰───────────┴───────╯
```

Example 2: A list of two objects:

```json
[{"id":1,"speed":111},{"id":"2","speed":222}]
```

Display with `no` and `single` (Transposed):

```text
╭────┬───────╮
│ id │ speed │
╞════╪═══════╡
│ 1  │ 111   │
│ 2  │ 222   │
╰────┴───────╯
```

Display with `yes` (multiple Simple):

```text
╭───────┬───────╮
│ field │ value │
╞═══════╪═══════╡
│ id    │ 1     │
│ speed │ 111   │
╰───────┴───────╯
╭───────┬───────╮
│ field │ value │
╞═══════╪═══════╡
│ id    │ 2     │
│ speed │ 222   │
╰───────┴───────╯
```

#### Option: `--out.level`: Verbosity of output

Output messages are categorized into three types:

- `info` output contains additional information, such as the number of elements in a table
- `data` output contains the actual output of the command (object, or list of objects)
- `error` output contains error messages

The option `--out.level` controls the level of output:

- `info` displays all messages: `info`, `data`, and `error`
- `data` displays `data` and `error` messages
- `error` displays only error messages

#### Option: `--out.secrets`: Hide or show secrets in results

- If value is `no` (default), then secrets are redacted from command results: replaced with `🔑`, or `***` if the terminal does not support Unicode (see [`--out.utf8`](#terminal-rendering-colors-and-utf-8)).
- If value is `yes`, then secrets are shown in clear in results.

#### Terminal rendering: Colors and UTF-8

By default, <%=tool%> detects the capabilities of the terminal:

| Option         | Effect when `yes`                                             | Auto-detection (default)                                                       |
|--|--|--|
| `--out.colors` | ANSI colors and styles in results, messages and logs          | `no` if [`NO_COLOR`](https://no-color.org) is set or results are written to a file (`--out.file`), else `yes` if `CLICOLOR_FORCE` is set and not `0`, else `yes` if both `stdout` and `stderr` are terminals, `TERM` is not `dumb` and `CLICOLOR` is not `0` |
| `--out.utf8`   | Unicode characters: table borders, check marks, hidden secrets, symbols in messages, half blocks in images (else ASCII equivalents) | `yes` if `stdout` is a terminal and the locale is UTF-8, or on Windows, the terminal is Windows Terminal, VS Code, Git Bash, ConEmu, or sets `TERM` to `xterm*` |

Set either option to `yes` or `no` to override detection, for example to keep colors when piping to `less -R`, or to get plain ASCII output in a terminal:

```shell
<%=cmd%> config preset overview --out.colors=no --out.utf8=no
```

> [!NOTE]
> Logs issued before the option is processed (e.g. at startup) use the detected value.

### Polling: Option `poll`

Option `--poll` executes a read-only command several times, and displays its results, for example to wait for a state: a work order complete, a task waiting for a user, a package received.
It replaces a shell loop with `sleep`: arguments are read once (identifiers looked up once), the command runs again in the same process.

Its value is a `Hash` (also with dot-notation, e.g. `--poll.interval=10`):

<%=schema_to_table(Aspera::Schema::Registry::POLL_OPTIONS)%>

`interval` and `timeout` are durations: a number of seconds, or a `String` with units `w`, `d`, `h`, `m`, `s`, e.g. `30s`, `2m`, `1h 30m`, `1d 02:00:00`, as for the [HTTP socket parameters](#http-socket-parameters).

```shell
# Wait for a work order to complete, check every 10 seconds, at most 30 times
<%=cmd%> orchestrator workorders status <%=ph :workorder_id%> --poll=@json:'{"interval":10,"max":30,"until":"status == `Complete`"}'
# Same, with dot-notation, and a timeout of 10 minutes
<%=cmd%> orchestrator workorders status <%=ph :workorder_id%> --poll.interval=10s --poll.timeout=10m --poll.until='status == `Complete`'
# Wait for a task waiting for a user (a non-empty list), display only the last result
<%=cmd%> orchestrator tasks list --poll=@json:'{"interval":5,"max":60,"until":"@","show":"last"}' --format=json
# Display the status of the resources of a pool, each time it changes, until interrupted (Ctrl-C)
<%=cmd%> orchestrator pools status <%=ph :pool_name%> --poll.interval=5
```

Behavior:

- Polling stops at the first run where `until` is true, or after `max` runs, or at `timeout`.
- Without `until`, the command runs `max` times (or until `timeout`, or until interrupted), and the exit status is success.
- If `until` is not true after the last run, the command fails with `condition not met after <N> runs` (exit status `1`).
- `until` is evaluated on the data of the result (as seen by `--out.query`: JSON values), after `--out.select`, before `--out.fields` and `--out.query`.
  Expression `@` is true for a non-empty result: e.g. a list with at least one item.
- Options `--format`, `--out.fields`, `--out.select` and `--out.query` apply to each result displayed.
  With `show=change` (default), a result is displayed when its display differs from the previous one.
- Before each result displayed, a status line on `stderr` gives the run number and the time, e.g. `poll: run 3/30 2026-01-02 10:20:30`.
  Output is flushed after each result: it can be read line by line by another program, e.g. with `--format=json` (one line per result).
- An error of a run (e.g. an API error) ends the command with this error, unless `errors` is `retry`: then the run counts as one where `until` is false.
- `Ctrl-C` ends polling: with `show=last`, the last result is displayed, and the exit status is `130`.

For safety, option `poll` is refused, before anything is executed, on a command that is not marked read-only: a command that creates, modifies, deletes, sends, starts or cancels something, e.g. `faspex5 packages send`.
Commands named `list`, `show`, `status`, `info`, `health`, `ls`, `browse` and `find` are read-only (except `preview show`, which generates a preview file), and some others, e.g. `orchestrator workflows workorders`, `server du`, `node ssync state`.
It is also refused with options `once_only` (state saved at each run) and `notify_to` (email sent at each run), with format `nagios`, and in [MCP server](#plugin-mcp-model-context-protocol-server) mode (the client calls the tool again instead).

### Exit status

The exit code of <%=tool%> indicates the category of error, so that scripts can react to it:

<%=exit_codes_md_table%>

With format `nagios`, the exit code is the status of the check: `0` (OK), `1` (WARNING), `2` (CRITICAL), and `3` (UNKNOWN) if the command fails, following the [Nagios plugin guidelines](https://nagios-plugins.org/doc/guidelines.html).

Example:

```bash
<%=cmd%> aoc files download /report.csv
case $? in
  0) echo 'Downloaded' ;;
  6) echo 'Network failure, retry later' ;;
  *) echo 'Failed' ;;
esac
```

### Extended Value Syntax

An **Extended Value** is a structured value - typically a `Hash` (key/value dictionary) or `Array`, potentially nested - that is passed on the command line wherever a simple string is not sufficient.

Most options and arguments are specified by a simple string (for example, `username` or `url`).
However, some situations require a complex structure:

- An option expects a **structured value** (`Hash`, `Array`) rather than a plain string.
- The value is too long or complex to type inline (for example, a PEM private key, a JSON body).
- The value must be **read from a file, an environment variable, or a URL** at runtime rather than embedded in the command.
- The value needs **type coercion**: for example, an integer `1` instead of the string `"1"`, or a boolean `true`.

The **Extended Value** syntax addresses all of these needs with a uniform, composable mechanism.
It lets you specify **what the value is** and **how to obtain or decode it**, entirely on the command line.

#### Syntax and Decoders

The syntax is:

```text
<0 or more decoders><some text value or nothing>
```

Decoders act like a function with its parameter on right-hand side and are recognized by the prefix: `@` and suffix `:`

```text
@<%=ph :name%>:
```

##### Available Decoders

The following decoders are supported:

| Decoder  | Parameter| Returns  | Description                                                                              |
|----------|----------|----------|------------------------------------------------------------------------------------------|
| `base64` | `String` | `String` | Decode a base64 encoded string. |
| `csvt`   | `String` | `Array`  | Decode a titled CSV value. |
| `env`    | `String` | `String` | Read from the named environment variable. For example, `--password=@env:MYPASSVAR` |
| `file`   | `String` | `String` | Read value from specified file (prefix `~/` is replaced with the user's home folder). For example, `--key=@file:~/.ssh/mykey` |
| `json`   | `String` | Any      | Decode JSON values. Convenient to provide complex structures. |
| `lines`  | `String` | `Array`  | Split a string in multiple lines and return an `Array`. |
| `list`   | `String` | `Array`  | Split a string in multiple items taking first character as separator and return an `Array`. |
| `none`   | None     | Nil      | A `null` value. |
| `path`   | `String` | `String` | Performs path expansion on specified path (prefix `~/` is replaced with the user's home folder). For example, `--config-file=@path:~/sample_config.yml` |
| `preset` | `String` | Any      | Get value from configuration file using [dot-path](#dot-path-notation) notation: a whole preset (`Hash`) or a single value. |
| `extend` | `String` | `String` | Evaluates embedded [Extended Value](#extended-value-syntax) syntax in string. |
| `re`     | `String` | `Regexp` | Ruby Regular Expression (short for `@ruby:/.../`) |
| `ruby`   | `String` | Any      | Execute specified Ruby code. |
| `s`      | Any      | `String` | Converts argument to `String`. |
| `secret` | `String` | `String` | Ask password interactively: on terminal (hides input), or on a web page if option `ui` is `graphical`. Argument is the prompt. |
| `stdin`  | `String` | `String` | Read from stdin in text mode. Argument: `<empty>`, `bin` or `chomp`. |
| `uri`    | `String` | `String` | Read value from specified URL. Supported schemes: `http:`, `https:`, `data:`, `file:`. For example, `--fpac=@uri:http://serv/f.pac` or `--key=@uri:file:/path/to/key.pem` |
| `val`    | `String` | `String` | Prevent decoding by the decoders on the right. For example, `--key=@val:@file:foo` sets the option `key` to value `@file:foo`. |
| `vault`  | `String` | `String` | Read a secret from the [Secret Vault](#secret-vault): `<label>.<field>`, or a [reference](#vault-secret-references) `//<store>/<path>[?<options>][#<field>]`. For example, `--password=@vault:my_label.password` |
| `yaml`   | `String` | Any      | Decode YAML. |
| `zlib`   | `String` | `String` | Decompress data using zlib. |
| `<empty>`| `String` | Any      | The **dot-path** modifier: argument `@:` collects the following positional arguments as `key.subkey=value` assignments and builds a `Hash` or `Array` using [dot-path](#dot-path-notation) notation. Shell-friendly alternative to `@json:` for structured values.<%=br%>Argument is the end marker: `<empty>` for `END`, or a custom marker (e.g. `@:STOP`). Use the end marker to stop collection when further positional arguments must follow.<%=br%>See [Positional Arguments with Dot-path](#positional-arguments-with-dot-path) for full syntax. |

> [!NOTE]
> A few commands support a value of type `Proc` (lambda expression).
> For example, the [Extended Value](#extended-value-syntax) `@ruby:'->(i){i["attr"]}'` is a lambda expression that returns the value for key `attr` of the `Hash` parameter named `i`.

**Chaining rule**: When multiple decoders are combined, they are applied right-to-left: the rightmost decoder runs first on the literal string, and each decoder to its left receives the output of the one to its right.

To display the result of an [Extended Value](#extended-value-syntax), use the `config echo` command.

The `extend` decoder is useful to evaluate embedded [Extended Value](#extended-value-syntax) syntax in a string.
It expects a `@` to close the embedded [Extended Value](#extended-value-syntax) syntax: `@vault:my_label.password@`.
A value inserted by `extend` is not evaluated again: `@extend:@file:<%=ph :path%>@` inserts the content of the file as is.
If the text on the right of `@extend:` is a single [Extended Value](#extended-value-syntax) without closing `@` (for example `@extend:@file:<%=ph :path%>`), it is decoded first, and embedded values in the result are then evaluated.

Example: a JSON file whose values are read from the [vault](#secret-vault):

```json
{"title":"Report","recipients":["@vault:my_label.username@"]}
```

```shell
<%=cmd%> config echo @json:@extend:@file:<%=ph :path%>
```

In the file, an embedded value without closing `@` (`"@vault:my_label.username"`) is not evaluated: it stays a string, and `@json:@file:<%=ph :path%>` does not evaluate values inside the JSON.

Option `parser` allows definition of a default parser when the positional parameter or option expects a `Hash` or `Array`.
For example, with `--parser=json`, the parameter `{}` will be parsed as an empty JSON Hash, even without prefix `@json:`.

#### Syntax Equivalences

There are four main ways to express a structured value (for example, a `Hash` with two keys).
They are all equivalent and produce the same result:

| Syntax | Example | Best for |
|--------|---------|----------|
| `@json:` | `@json:'{"name":"alice","age":30}'` | Scripts, API payloads, copy-paste from docs |
| `@yaml:` | `@yaml:@stdin:` + here-doc | Multi-line or deeply nested structures |
| `@ruby:` | `@ruby:'{"name"=>"alice","age"=>30}'` | Advanced use: lambdas, file reads, logic |
| dot-path (`key.subkey=value`) via `@:` | `@: name=alice age=30` | Interactive CLI, simple structures, no quoting |

All four examples above produce the same `Hash`: `{"name" => "alice", "age" => 30}`.

```shell
<%=cmd%> config echo @json:'{"name":"alice","age":30}' --format=json
<%=cmd%> config echo @ruby:'{"name"=>"alice","age"=>30}' --format=json
<%=cmd%> config echo @: name=alice age=30 --format=json
```

```json
{"name":"alice","age":30}
```

> [!NOTE]
> The dot-path form (`key.subkey=value` assignments via `@:`) does **not** need quotes for simple string values and is the most shell-friendly.
> The `@json:` form requires enclosing in single quotes to protect `"` from the shell.
> The `@ruby:` form accepts both single and double quotes and supports arbitrary Ruby expressions.
> The `@yaml:` form is most convenient when combined with a shell **here-document** (`<<EOF`).

##### Equivalences: Positional Parameter vs Option

The same `Hash` value `{"a":1,"b":"two"}` can be expressed differently depending on whether it is supplied as a **positional parameter** or as an **option**.

**As a positional parameter** (argument to a command):

```shell
# JSON form
some_command @json:'{"a":1,"b":"two"}'
# Dot-path form (END is optional when no positional argument follows)
some_command @: a=1 b=two
some_command @: a=1 b=two END
```

**As an option** named `opt`:

```shell
# JSON form
--opt=@json:'{"a":1,"b":"two"}'
# Dot-path form via option name (each key as a separate option flag)
--opt.a=1 --opt.b=two
# Dot-path form via option value (consumes following positional arguments)
--opt=@: a=1 b=two END
```

> [!NOTE]
> `--opt.a=1 --opt.b=two` and `--opt=@json:'{"a":1,"b":"two"}'` and `--opt=@: a=1 b=two` all produce the same `Hash` assigned to option `opt`.
> The `--opt.key=value` form is the most concise when only a few keys need to be set.
> Use `END` with `@:` when further positional arguments follow on the command line; it is optional otherwise.

#### Which Syntax to Choose?

**When in doubt: start with dot-path** (`--opt.key=value` for options, `@: key=value` for positional arguments).
It requires no quoting, auto-converts types, and reads naturally on the command line.
Switch to `@json:` when you already have a JSON payload from an API doc or external tool.

| Context | Recommended syntax | Reason |
|---------|--------------------|--------|
| Interactive CLI, simple values | dot-path `key.subkey=value` via `@:` or `--opt.key=value` | No quoting needed, auto-typed, readable |
| Shell scripts, API payloads | `@json:` | Standard, portable, easy to copy from API docs |
| Multi-line or nested structures in scripts | `@yaml:` + `@stdin:` heredoc | Readable, no escaping |
| Dynamic values, lambdas, file reads | `@ruby:` | Full Ruby expressiveness |

#### Common Usage Examples

Example: Create a `Hash` value - for a small structure, the dot-path `key.subkey=value` form (via `@:`) is simpler; for larger or API-sourced structures, use `@json:`:

```shell
<%=cmd%> config echo @: key1=value1 key2=value2
<%=cmd%> config echo @json:'{"key1":"value1","key2":"value2"}'
```

Example: read the content of the specified file, then, base64 decode, then unzip:

```shell
<%=cmd%> config echo @zlib:@base64:@file:myfile.dat
```

Example: Create a `Hash` value with one key and the value is read from a file:

```shell
<%=cmd%> config echo @ruby:'{"token_verification_key"=>File.read("mykey.txt")}'
```

Example: read a CSV file and create an `Array` of `Hash` for bulk provisioning:

```shell
cat test.csv
```

```text
name,email
lolo,laurent@example.com
toto,titi@tutu.tata
```

```shell
<%=cmd%> config echo @csvt:@file:test.csv
```

```text
╭──────┬─────────────────────╮
│ name │ email               │
╞══════╪═════════════════════╡
│ lolo │ laurent@example.com │
│ toto │ titi@tutu.tata      │
╰──────┴─────────────────────╯
```

Example: create a `Hash` with values coming from a preset named `config`

```shell
<%=cmd%> config echo @json:@extend:'{"hello":true,"version":"@preset:config.version@"}'
```

```text
╭─────────┬────────╮
│ field   │ value  │
╞═════════╪════════╡
│ hello   │ true   │
│ version │ 4.21.1 │
╰─────────┴────────╯
```

Example: Create a `Hash` from YAML provided as shell **Here document**:

```shell
<%=cmd%> config echo @yaml:@stdin: --format=json<<EOF
key1: value1
key2:
- item1
- item2
key3:
  key4: value4
  key5: value5
EOF
```

```json
{"key1":"value1","key2":["item1","item2"],"key3":{"key4":"value4","key5":"value5"}}
```

#### Schema Discovery with `help`

Any option or **Command Parameter** that expects a `Hash` value accepts the special value `help`.
Instead of performing the action, <%=tool%> displays the schema of the expected `Hash` as a table (field name, type, description), then exits with an error.

When a mandatory `Hash` argument is missing, <%=tool%> automatically hints to use `help`:

```shell
<%=cmd%> aoc packages send
```

```text
ERRR Missing: Missing argument: package (Hash)
HINT:Give `help` as argument to retrieve the schema of the missing argument.
```

Following the hint and passing `help` as the argument displays the schema:

```shell
<%=cmd%> aoc packages send help
```

```text
INFO Schema: argument: package (Hash)
╭───────────────────────┬────────┬──────────┬────────────────────────────────────────────────────────────────────────────────────────────╮
│ name                  │ type   │ required │ description                                                                                │
╞═══════════════════════╪════════╪══════════╪════════════════════════════════════════════════════════════════════════════════════════════╡
│ bcc_recipients        │ array  │ false    │ <empty string>                                                                             │
│ bcc_recipients[].id   │ string │ true     │ The ID of the recipient.                                                                   │
│ bcc_recipients[].type │ enum   │ false    │ The entity type of the recipient.                                                          │
│                       │        │          │ Allowed: user, group                                                                       │
│ name                  │ string │ true     │ Package name. Required for POST. Optional for PUT.                                         │
│ note                  │ string │ false    │ The sender's message to recipients to include with the package. Maximum characters: 65535. │
│ recipients            │ array  │ false    │ <empty string>                                                                             │
│ recipients[].id       │ string │ true     │ The ID of the recipient.                                                                   │
│ recipients[].type     │ enum   │ false    │ The entity type of the recipient.                                                          │
│                       │        │          │ Allowed: user, group                                                                       │
...
╰───────────────────────┴────────┴──────────┴────────────────────────────────────────────────────────────────────────────────────────────╯
```

The same applies to options: display the schema of the transfer-spec option `ts`:

```shell
<%=cmd%> --ts=help
```

```text
INFO Schema: option: ts
╭─────────────────────┬─────────┬──────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ name                │ type    │ required │ description                                                                                                            │
╞═════════════════════╪═════════╪══════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
│ apply_local_docroot │ boolean │ false    │ Apply local docroot to source paths.                                                                                   │
│ cipher              │ enum    │ false    │ In transit encryption algorithms.                                                                                      │
│                     │         │          │ Allowed: none, aes-128, aes-192, aes-256, aes-128-cfb, aes-192-cfb, aes-256-cfb, aes-128-gcm, aes-192-gcm, aes-256-gcm │
│ authentication      │ string  │ false    │ Set to `token` for SSH bypass keys, else password asked if not provided.                                               │
...
╰─────────────────────┴─────────┴──────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

This works for any `Hash` option or positional parameter that has a defined schema.

#### Schema Validation

The value of an option or **Command Parameter** with a schema defined by <%=tool%> (e.g. options `ts`, `transfer`, `out`, `http_options`, argument of `orchestrator workflows start`) is validated against it before the action.
An invalid value is rejected with the path of the invalid element and the reason:

```shell
<%=cmd%> config echo 1 --ts=@json:'{"direction":"sideways"}'
```

```text
ERRR Argument: Option ts: value at `/direction` is not one of: ["send", "receive"] (use --ts=help for schema)
Use option -h to get help.
```

Option values are merged from several sources (presets, command line), so mandatory fields are not checked for options.
Request bodies of product APIs (e.g. `create` and `modify` commands) are not validated by <%=tool%>: the API validates them.

#### Testing Extended Value

Two complementary commands help verify that a value is parsed as expected:

| What to check | Tool | How |
|---|---|---|
| Value of a **positional parameter** | `config echo` | Pass the expression as the sole argument |
| Value of an **option** | `--show-config` | Append `--show-config` to any command line |

**Checking a positional parameter with `config echo`**:

`config echo` takes exactly **one** argument which can use the [Extended Value](#extended-value-syntax) syntax, and displays its parsed value.
Unprocessed command line arguments are shown in the error message.

```shell
<%=cmd%> config echo @json:'{"a":1,"b":"two"}' --format=json
<%=cmd%> config echo @: a=1 b=two --format=json
```

```json
{"a":1,"b":"two"}
```

> [!NOTE]
> The value is shown after both shell command-line parsing and <%=tool%> [Extended Value](#extended-value-syntax) parsing.

Example: the shell parses three arguments (`1`, `2`, `3`), but `config echo` only processes the first:

```shell
<%=cmd%> config echo 1 2 3
```

```text
1
ERRR Argument: unprocessed values: ["2", "3"]
```

**Checking an option value with `--show-config`**:

Adding `--show-config` to any command line performs a dry run and displays the resolved value of all options that would be used, without executing the command.

To display a specific option, add `--fields=<option_name>`.
Add `--out.flat=no` when the option holds a structured value (`Hash`, `Array`) to display it as-is rather than flattened into dot-path keys:

```shell
<%=cmd_skip%> --opt=@json:'{"a":1,"b":"two"}' some_plugin --show-config --fields=opt --out.flat=no
<%=cmd_skip%> --opt.a=1 --opt.b=two some_plugin --show-config --fields=opt --out.flat=no
```

Both lines above display the same resolved value for option `opt`.

In the following examples (using a POSIX shell, such as `bash`), several equivalent commands are provided.
For all examples, most special character handling is not specific to <%=tool%>:
It depends on the underlying syntax: shell, JSON, and so on.
Depending on the case, a different `format` option is used to display the actual value.

For example, in the simple string `Hello World`, the space character is special for the shell, so it must be escaped so that a single value is represented.

Double quotes are processed by the shell to create a single string argument.
For **POSIX shells**, single quotes can also be used in this case, or protect the special character ` ` (space) with a backslash.

```shell
<%=cmd%> config echo "Hello World" --format=text
<%=cmd%> config echo 'Hello World' --format=text
<%=cmd%> config echo Hello\ World --format=text
```

```text
Hello World
```

### Security Level

On the command line, <%=tool%> can do anything that the user running it is allowed to do.
Option `security` restricts the features that access local resources or execute code, for example, when commands come from another program, such as an MCP client (see [MCP Security](#security)).
It is a `Hash` with the following keys:

| Key | Type | Default | Description |
|-----|-----|-----|-----|
| `level` | `string` | `low` | `low`, `medium`, or `high` |
| `allowed_paths` | `Array<string>` | - | With level `medium`: files and folders that `@file:` can read |
| `writable_paths` | `Array<string>` | - | With levels `medium` and `high`: folders where files can be written |

| Level | `@file:` | `@ruby:`, `@uri:`, `@env:`, and `@zlib:` | Secret processed by another extended value | Write files | Features that execute code |
|---|---|---|---|---|---|
| `low` | Allowed | Allowed | Allowed | Allowed | Allowed |
| `medium` | Only files in `allowed_paths` | Refused | Refused | Only in `writable_paths` | Refused |
| `high` | Refused | Refused | Refused | Only in `writable_paths` | Refused |

With level `medium`, the real path of the file is checked: a symbolic link leading outside of `allowed_paths` is refused.

`@zlib:` is refused with levels `medium` and `high`: a small value can decompress to gigabytes and exhaust the memory of the system.

With levels `medium` and `high`, files are written only in `writable_paths` (none by default): downloaded files (`config download`, and transfers that receive files), because a file written where the client chooses could replace a file that is used later, for example a plugin or a shell startup file.
The real path of the folder is checked: neither `..` nor a symbolic link leading outside of `writable_paths` is accepted.

A command that reads or writes a local path given by the client checks it against the security level, like `@file:`: the content read (for example `config ascp logs`, `preview show`, `orchestrator workflows import` and `check_import`, `config sync admin`), or the file written (for example `config genkey`, `config download`).
It is refused at level `high`, and at level `medium` the path must be in `allowed_paths` (read) or `writable_paths` (write); a path that does not exist and a path outside those give the same error, so the existence of a file is not revealed.

> [!NOTE]
> A transfer that uses a remote agent (`node`, or `transferd` attached to a remote daemon) sends and receives the files on the host of the agent, not the local host: those paths are not local, and are not restricted by the security level.
> At level `high`, a transfer that would run on the local host is refused (see above).

The same applies to `@file:<path>` in the parameters of stores of option `vault`, and in option `vault_password` (for example, `token`), although the file is read when used, not when the option is evaluated.

A secret (read by `@secret:`, `@vault:`, or `@preset:`) is hidden in results by its value: processed by another extended value, it could be revealed (for example, split by `@list:@vault:...`, or with a short value in a text by `@extend:`).
With levels `medium` and `high`, a secret must be the whole value of an option or argument, for example `@preset:<%=ph :preset_name%>.password` for option `password`, and it cannot be a parameter name of `config preset set`.

At levels `medium` and `high`, a secret that comes from the configuration of the server (a preset, or the environment) is not sent to a `url` given on the command line: a secret (option `password`, `client_secret`, `private_key`, `passphrase`) and the `url` it is sent to must come from the same place (both from a preset, or both given on the command line).
This prevents a client that drives <%=tool%> (for example through the MCP server) from redirecting the saved credentials of the server to a host that it chooses.

Features that execute code (own, or downloaded), load code, or write a file chosen by the client, are available only at level `low`:

| Feature | Why |
|---|---|
| Option `notify_template` | ERB template: Ruby code |
| Option `fpac` | Proxy auto configuration: JavaScript code |
| Option `ui`, key `command` | Command executed to open a URL |
| Options `sdk_url` and `locations_url` | The SDK, including `ascp`, is downloaded from this location, then executed |
| Option `out`, key `file` (and `output`), option `pid_file` | Write (or truncate, or delete) a file chosen by the client |
| Option `home` | Configuration folder: its presets, and its folder `plugins` (Ruby code) are used |
| Option `config_file` | Configuration file: its presets are used, and a command that changes presets writes it |
| Options `vault` and `vault_password` | Secret stores of `@vault:`: a file store is created and written at the path given, other stores connect to the server given |
| Option `plugin_folder` | Plugins are Ruby code |
| Plugins of the folders of option `plugin_folder` (by default, folder `plugins` of the configuration folder) | Ruby code: not loaded at other levels, also if the file was there before |
| Command `config plugins create` | Creates Ruby code, loaded as a plugin |
| Command `faspex5 postprocessing` | Executes scripts, or Ruby code |
| Commands `node emulator` (`simulator`), `aoc gateway`, `faspex5 gateway` | Start a local server that listens on the network, serves a local folder, or accepts transfers |
| Options `insecure`, `ignore_certificate`, `cert_stores`, `http_proxy`, and keys `ca_file`, `verify_mode`, `ssl_options` of option `http_options` | Disable or redirect the validation of a server certificate, or route through a proxy: a client could intercept the connections (and the credentials) of the server |
| Transfer parameters `ascp_args` (agent `direct`) and `ssh_args` (transfer spec) | Raw arguments to `ascp` or the external `ssh`: can start a local program (for example an `ssh` `ProxyCommand`) |

At other levels, an option is refused whatever the way it is set (command line, or preset), and a command is not listed by `config commands`.
Values from the environment of the process (for example `<%=opt_env :home%>`) are not restricted: they are set by the one who starts the process, not by a client.
A sub-option of an option is restricted in the same way: it is marked `x-security: low` in the schema of the option (for example, `file` of option `out`), and refused when given, by dot notation (`--out.file=...`) or in a `Hash`.
A preset is used later, maybe at level `low`: at level `medium` and `high`, `config preset set` refuses such an option, and a value that contains an extended value that the level refuses (for example `@val:@ruby:...`).

At level `high`, a transfer uses an agent that runs on a host that the user controls, not the local host: agent `node`, or agent `transferd` attached to a remote daemon (parameter `url` of a daemon on another host).
An agent that runs on the local host is refused: `direct` (local `ascp`), a local `transferd` daemon (started by `ascli`, or on a loopback address), `connect` and `desktop` (local applications), and `httpgw` (the files pass through the process).
These agents read and write local files and run local programs, so they are available at levels `low` and `medium` only.
The default agent is `direct`, so a transfer at level `high` without an agent is refused: set option `transfer` to a remote agent, for example `--transfer.agent=node`.

Options are evaluated in the order of the command line: place `--security` before options that use extended values.

```shell
<%=cmd%> config echo @file:/etc/hosts --security.level=high
```

```text
ERRR Argument: Evaluation of @file: for argument: value: @file: extended value is disabled by security level high: use level medium with the file in security.allowed_paths (option security), or give the value itself
```

### Main, configuration and Persistency Folder

<%=tool%> looks for configuration and persistency files (token cache, file lists, persistency files) in the folder specified using option `home`.
The default value is `[User's home folder]/.aspera/<%=cmd%>`.

> [!NOTE]
> The `[User's home folder]` is determined using Ruby's `Dir.home` method.
> Primary source: The HOME environment variable.
> On Windows: Ruby also checks `%HOMEDRIVE%%HOMEPATH%` and `%USERPROFILE%` (via `rb_w32_home_dir`).
> Additionally, <%=tool%> sets the `%HOME%` environment variable to the value of `%USERPROFILE%` if it exists and is valid.
> Therefore, on Windows, `%USERPROFILE%` is preferred because it is generally more reliable than `%HOMEDRIVE%%HOMEPATH%`.

The configuration folder can be displayed using:

```shell
<%=cmd%> config folder
```

```shell
/Users/kenji/.aspera/<%=cmd%>
```

> [!NOTE]
> This is equivalent to displaying the value of the `home` option.

```shell
<%=cmd%> --show-config --fields=home
```

Example (Windows):

```batchfile
set <%=opt_env :home%>=C:\Users\Kenji\.aspera\<%=cmd%>

<%=cmd%> config folder

C:\Users\Kenji\.aspera\<%=cmd%>
```

When OAuth is used (AoC, Faspex 5), <%=tool%> keeps a cache of generated bearer tokens in folder `persist_store` located in the configuration folder by default.
Option `cache_tokens` (**yes**/no) allows controlling if OAuth tokens are cached on file system, or generated for each request.
The command `config tokens flush` clears that cache.
Tokens are kept on disk for a maximum of 30 minutes and garbage collected after that.
When a token has expired, then a new token is generated, either using a `refresh_token` if it is available, or by the default method.

### Configuration file

On the first execution of <%=tool%>, an empty configuration file is created in the configuration folder (`<%=cmd%> config folder`).
There is no mandatory information required in this file.
Its use is optional, as any option can be provided on the command line.

Although the file is a standard `YAML` file, <%=tool%> provides commands to read and modify it using the `config` command.

All options for <%=tool%> can be set on command line, or by env vars, or using [Option Preset](#option-preset) in the configuration file.

A configuration file provides a way to define default values, especially for authentication options, thus avoiding having to always specify those options on the command line.

The default configuration file is: `$HOME/.aspera/<%=cmd%>/config.yaml` (this can be overridden with option `config_file`).

The configuration file is a catalog of named lists of options, called: [Option Preset](#option-preset).
Then, instead of specifying some common options on the command line (for example, address, credentials), it is possible to invoke the ones of an [Option Preset](#option-preset) (for example, `<%=ph :preset_name%>`) using the option `preset`: `--preset=<%=ph :preset_name%>` or its shortcut: `-P<%=ph :preset_name%>`.

#### Format of configuration file

The configuration file is a `Hash` in a YAML file.

**Example**:

```yaml
config:
  version: 0.3.7
default:
  config: cli_default
  server: demo_server
cli_default:
  interactive: no
demo_server:
  url: ssh://demo.asperasoft.com:33001
  username: asperaweb
  password: <%=ph :password%>
```

We can see here:

- The configuration was created with <%=tool%> version 0.3.7
- The default [Option Preset](#option-preset) to load for `server` plugin is: `demo_server`
- The [Option Preset](#option-preset) `demo_server` defines some options: the URL and credentials
- The default [Option Preset](#option-preset) to load in any case is: `cli_default`

Two [Option Presets](#option-preset) are reserved:

- `config` contains a single value: `version` showing the version used to create the configuration file.
  It is used to check compatibility.
- `default` is reserved to define the default [Option Preset](#option-preset) name used for known plugins.

The user may create as many [Option Presets](#option-preset) as needed.
For instance, a particular [Option Preset](#option-preset) can be created for a particular application instance and contain URL and credentials.

Values in the configuration also follow the [Extended Value](#extended-value-syntax) syntax.

> [!NOTE]
> If the user wants to keep the [Extended Value](#extended-value-syntax) syntax inside the configuration file, the user shall use the `@val:` prefix.

Example:

```shell
<%=cmd%> config preset set <%=ph :aoc_org%> private_key @val:@file:"$HOME/.aspera/<%=cmd%>/<%=ph :pkey_name%>"
```

This creates the [Option Preset](#option-preset):

```yaml
<%=ph :aoc_org%>:
  private_key: "@file:/Users/laurent/.aspera/<%=cmd%>/<%=ph :pkey_name%>"
```

So, the key file is read only at execution time and is not embedded in the configuration file.

> [!NOTE]
> The main use of the configuration file is to store collections of options.
> Nevertheless, it can be used to store any type of information, not only option values.
> For example, the special preset: [`default`](#special-option-preset-default).

#### Option Preset

An [Option Preset](#option-preset) is a collection of options and their associated values in a named section in the configuration file.

A named [Option Preset](#option-preset) can be modified directly using <%=tool%>, which will update the configuration file:

```text
<%=cmd%> config preset <show|delete|get|set|ask> <%=ph :preset_name%> ...
```

The syntax of all `config preset` commands, including `list` and `overview`, is displayed with `<%=cmd%> config commands config preset`.

The command `set` merges values into the configuration, at one of three levels, depending on its arguments:

| Arguments | Merged into | Example |
| --------- | ----------- | ------- |
| `<Hash>` | Presets, by name | `<%=cmd%> config preset set @: demo_server.url=ssh://demo.asperasoft.com:33001 default.server=demo_server` |
| `<preset_name> <Hash>` | Parameters of a preset | `<%=cmd%> config preset set demo_server @: url=ssh://demo.asperasoft.com:33001 username=asperaweb` |
| `<preset_name> <parameter_name> <value>` | One parameter of a preset | `<%=cmd%> config preset set demo_server password <%=ph :password%>` |

The `Hash` is usually given with [dot-path](#positional-arguments-with-dot-path) (`@:`), or with `@json:`.
Parameters have the names of options, without `--`, for example:

```shell
<%=cmd%> config preset set demo_server @: url=ssh://demo.asperasoft.com:33001 username=asperaweb password=<%=ph :password%> ts.precalculate_job_size=true
<%=cmd%> config preset set demo_server @json:'{"url":"ssh://demo.asperasoft.com:33001","username":"asperaweb","password":"<%=ph :password%>","ts":{"precalculate_job_size":true}}'
```

A preset is created if needed.
Values are **deep-merged** (as JSON Merge Patch, RFC 7396): parameters not given are kept, also in a nested `Hash`: for example, `@: out.level=data` keeps `out.format`.

The value `@none:` (`null` in JSON) **removes** a key: a parameter, a key in a nested `Hash`, or a whole preset (with its default declarations):

```shell
<%=cmd%> config preset set GLOBAL out.table.pivot @none:
<%=cmd%> config preset set demo_server @: username=@none: ts.precalculate_job_size=@none:
<%=cmd%> config preset set @: demo_server=@none:
```

The parameter name of the third form supports **dot-notation** to set nested hash options:

```shell
<%=cmd%> config preset set GLOBAL out.table.pivot single
<%=cmd%> config preset set GLOBAL out.level data
```

Values given on the command line (with `@:`, or the value of the third form) are **automatically coerced** to their natural type: integers, floats and booleans (`true`/`yes`/`false`/`no`) are stored as native YAML types rather than strings.

Options of the command line are not saved in the preset: they apply to the command `set` itself (for example `--log-level`).
The section `config` of the configuration file cannot be changed.

> [!NOTE]
> Commands `update`, `initialize` and `unset` are deprecated, and show the command to use instead:
>
> - `update <preset_name> --url=...` is replaced by `set <preset_name> @: url=...`. It takes only the options placed after `update`.
> - `initialize <preset_name> <Hash>`, which replaces a preset, is replaced by `delete <preset_name>`, then `set <preset_name> <Hash>`.
> - `unset <preset_name> <parameter_name>` is replaced by `set <preset_name> <parameter_name> @none:`.

A full terminal based overview of the configuration can be displayed using:

```shell
<%=cmd%> config preset overview
```

The list of [Option Presets](#option-preset) can be displayed using:

```shell
<%=cmd%> config preset list
```

Any key starting with `_` (underscore) in a preset is treated as a comment and is ignored when the preset is applied.
This is useful to annotate presets directly in the configuration file:

```yaml
demo_server:
  _comment: "Demo server - public credentials"
  url: ssh://demo.asperasoft.com:33001
  username: asperaweb
  password: <%=ph :password%>
```

> [!NOTE]
> Comment keys are preserved and visible in `config preset overview` for inspection, but are never injected as CLI options.

By convention, `_comment` holds a short description of the preset.
The [shell completion](#shell-completion) of preset names (e.g. `-P <tab>`) shows it next to each name.
The wizard sets it for the presets it creates: `_comment: "wizard: <application>"`.

A good practice is to not manually edit the configuration file and use modification commands instead.
If necessary, the configuration file can be opened in a text editor with:

```shell
<%=cmd%> config open
```

> [!NOTE]
> This starts the editor specified by env var `EDITOR` if defined.

It is possible to load an [Option Preset](#option-preset) from within another [Option Preset](#option-preset) using the `preset` option.
For example if `pcommon` is a preset with common options, and `pspecific` is a preset with specific options, then `pspecific` can load `pcommon` using:

```shell
<%=cmd%> config preset set pspecific preset pcommon
```

When `pspecific` is loaded, then cumulative option `preset` will be set, and it will also load `pcommon`.

#### Special Option Preset: `config`

This preset name is reserved and contains a single key: `version`.
This is the version of <%=tool%> which created the file.

#### Special Option Preset: `default`

This preset name is reserved and contains a `Hash`, where the key is the name of a plugin, and the value is the name of another preset.
Usually, [Option presets](#option-preset) are used to contain pre-defined options and values, but this preset contains names of presets to be used by default for plugins.

When a plugin is invoked, the preset associated with the name of the plugin is loaded, unless the option `--no-default` (or `-N`) is used.

> [!NOTE]
> The special plugin name `config` in the `default` preset points to a preset containing **global default options**
> (such as `--log-level`, `--vault`, `--interactive`), loaded before any plugin is invoked.
> To set global default options, use the `GLOBAL` keyword (see [Plugin: `config`](#plugin-config-configuration)).

Operations on this preset are done using regular `config` operations:

```shell
<%=cmd%> config preset set default _plugin_name_ _default_preset_for_plugin_
```

> [!NOTE]
> `default` is not a command, it is the name of the special preset.

```shell
<%=cmd%> config preset get default _plugin_name_
```

```json
"_default_preset_for_plugin_"
```

### Handling invalid filename characters

Some commands of <%=tool%> may create files or folders based on input that may contain invalid characters for the local file system.
The option `invalid_characters` allows specifying a replacement character for a list of characters that are invalid in filenames on the local file system and replaces them with the specified character.

The first character specifies the replacement character, and the following characters are the invalid ones.
This is used when a folder or file is created from a value that potentially contains invalid characters.
For example, using the option `package_folder`, a package name may contain characters not allowed, such as `/`.
The default value is `_<>:"/\|?*`, corresponding to replacement character `_` and characters not allowed on Windows.

> [!NOTE]
> This option is different from the `replace_illegal_chars` parameter in `aspera.conf`, which applies to transfers only.

### Managing temporary files

Some temporary files may be needed during runtime, for example the file list of `ascp`.
The composite option `temp` (use `--temp=help` to display this schema) controls them:

<%=schema_to_table(Aspera::Schema::Registry::TEMP_OPTIONS)%>

A plain value is the `folder`, for example: `--temp=/data/tmp`.

Temporary files of a command are deleted when it ends, unless `clean` is `false`.
If a command is interrupted (for example, killed), its `ascp` file lists remain: a later command deletes them when they are older than `expiry`.

> [!WARNING]
> `--temp.expiry=0` also deletes the file lists of transfers in progress in other executions of <%=tool%>, which may then fail: use it only when no other transfer is in progress.

> [!TIP]
> Options `temp_folder` and `clean_temp` are deprecated aliases for `temp.folder` and `temp.clean`.

### Plugin: `config`: Configuration

Plugin `config` provides general commands for <%=tool%>:

- Option Preset operations (configuration file)
- `wizard`
- `vault`
- `ascp`
- `transferd` (deprecated, use plugin [`transferd`](#plugin-transferd-transfer-daemon))

The default preset for `config` is read for any plugin invocation: this allows setting global options, such as `--log-level` or `--interactive`.
When <%=tool%> starts, it looks for the `default` Option Preset and checks the value for `config`.
If set, it loads the options independently of the plugin used.

> [!NOTE]
> If `default.config` is not set, <%=tool%> automatically uses `global_common_defaults` as the global preset name
> and saves that mapping in the configuration file the first time the `GLOBAL` keyword is used.

> [!TIP]
> If you do not know the name of the global preset, you can use `GLOBAL` to refer to it.

Show current default (global) Option Preset (`config` plugin):

```shell
<%=cmd%> config preset get default config
```

```text
global_common_defaults
```

Set a global parameter:

```shell
<%=cmd%> config preset set GLOBAL version_check_days 0
```

If you want to use a custom name instead of `global_common_defaults`:

```shell
<%=cmd%> config preset set default config <%=ph :global_options_name%>
<%=cmd%> config preset set GLOBAL version_check_days 0
```

<%=include_commands_for_plugin(:config,4)%>

#### Evaluation order of options

Some options are global, others are available only for some plugins (the plugin is the first-level command).

Options are loaded using this algorithm:

- If option `--no-default` (or `-N`) is specified, then no default value is loaded for the plugin
- Else it looks for the name of the plugin as key in section `default`, the value is the name of the default [Option Preset](#option-preset) for it, and loads it.
- If option `--preset=<%=ph :name%>` is specified (or `-P<%=ph :name%>`), this reads the [Option Preset](#option-preset) specified from the configuration file by name.
- If option `--preset=<%=ph :extended_value_hash%>` is specified, it is used as option values (`Hash` of option/value pairs).
- Environment variables are evaluated.
- Command line options are evaluated.

Options are evaluated in the order of command line.

To avoid loading the default [Option Preset](#option-preset) for a plugin, use: `-N`

On command line, words in option names are separated by a dash (`-`).
In the configuration file, the separator is an underscore.
For example, `--xxx-yyy` on command line gives `xxx_yyy` in configuration file.

The main plugin name is `config`, so it is possible to define a default [Option Preset](#option-preset) for the main plugin with:

```shell
<%=cmd%> config preset set cli_default interactive no
```

```shell
<%=cmd%> config preset set default config cli_default
```

An [Option Preset](#option-preset) value can be removed with `@none:`:

```shell
<%=cmd%> config preset set cli_default interactive @none:
```

Example: Define options using command line:

```shell
<%=cmd%> -N --url=<%=ph :url%> --password=<%=ph :password%> --username=<%=ph :username%> node --show-config
```

Example: Define options using a `Hash`:

```shell
<%=cmd%> -N --preset=@json:'{"url":"<%=ph :url%>","password":"<%=ph :password%>","username":"<%=ph :username%>"}' node --show-config
```

#### Shell Completion

<%=tool%> supports shell tab-completion for **Bash**, **Zsh**, **Fish**, and **PowerShell** (Windows PowerShell 5.1 and PowerShell 7, on any OS).
The command `<%=cmd%> config completion <shell>` displays the completion script for the given shell.

The default shell is Zsh on macOS, Bash on most Linux distributions, and PowerShell on Windows (its prompt starts with `PS`).
In Bash and Zsh, `echo $0` displays the name of the running shell.

To activate completion, add the line for your shell to its startup file:

```bash
# Bash, in ~/.bashrc
eval "$(<%=cmd%> config completion bash)"
```

```zsh
# Zsh, in ~/.zshrc, after compinit
eval "$(<%=cmd%> config completion zsh)"
```

```fish
# Fish, in ~/.config/fish/config.fish
<%=cmd%> config completion fish | source
```

```powershell
# PowerShell, in $PROFILE (edit with notepad $PROFILE)
<%=cmd%> config completion powershell | Out-String | Invoke-Expression
```

The startup file then executes <%=tool%> each time a shell starts.
Alternatively, save the script once in the completion folder of the shell (and save it again after an upgrade of <%=tool%>):

```bash
# Bash, with package bash-completion
<%=cmd%> config completion bash > ~/.local/share/bash-completion/completions/<%=cmd%>
# Zsh (the folder must be in $fpath before compinit)
<%=cmd%> config completion zsh > ~/.zsh/completions/_<%=cmd%>
# Fish
<%=cmd%> config completion fish > ~/.config/fish/completions/<%=cmd%>.fish
```

PowerShell has no completion folder: save the script, and dot-source it in `$PROFILE`:

```powershell
<%=cmd%> config completion powershell | Set-Content "$HOME\<%=cmd%>_completion.ps1"
Add-Content -Path $PROFILE -Value ". '$HOME\<%=cmd%>_completion.ps1'"
```

In PowerShell, the words proposed are kept for the session, so only the first `Tab` at a given position executes <%=tool%>.

Once active, press `Tab` to complete:

```bash
<%=cmd_skip%> <Tab>                            # plugins and global options: aoc, server, node, ..., --format, ...
<%=cmd_skip%> server <Tab>                     # sub-commands and options of plugin: upload, download, ls, ..., --url, ...
<%=cmd_skip%> aoc admin <Tab>                  # sub-commands at any depth: user, node, ...
<%=cmd_skip%> server ls --u<Tab>               # options, after any command: --url, --username, ...
<%=cmd_skip%> --format=<Tab>                   # values of option: --format=json, --format=table, ...
<%=cmd_skip%> --ts.<Tab>                       # keys of option, from its schema: --ts.direction=, --ts.target_rate_kbps=, ...
<%=cmd_skip%> --out.t<Tab>                     # a sub-structure is followed by a dot: --out.table.
<%=cmd_skip%> --ts.direction=<Tab>             # values of key: --ts.direction=send, --ts.direction=receive
<%=cmd_skip%> --transfer=<Tab>                 # plain value of option, key agent: --transfer=direct, --transfer=node, ...
<%=cmd_skip%> faspex5 admin accounts list --query.<Tab> # keys of --query, from the command: --query.limit=, ...
<%=cmd_skip%> server upload <Tab>              # local files
<%=cmd_skip%> server download --to-folder <Tab> # local folders
<%=cmd_skip%> config genkey <Tab>              # local files, where a local path is expected
<%=cmd_skip%> --temp.folder=<Tab>              # local folders, for a key of option
<%=cmd_skip%> --ts=@<Tab>                      # extended value modifiers: @json:, @file:, @preset:, @:, ...
<%=cmd_skip%> --private-key=@file:<Tab>        # local files, after @file: or @path:
<%=cmd_skip%> -P <Tab>                         # presets: also for config preset show, @preset:
<%=cmd_skip%> config preset get myconf <Tab>   # parameters of preset: url, username, ...
<%=cmd_skip%> config agents jobs status <Tab>     # asynchronous transfer jobs
<%=cmd_skip%> node access_keys do <Tab>        # type of expected value, not inserted: <identifier>
<%=cmd_skip%> aoc packages send <Tab>          # type, and keys of structure (required ones with *): <Hash> name*, workspace_id*, ...
<%=cmd_skip%> aoc packages send @: <Tab>       # keys of structure built with @:, from its schema: name=, workspace_id=, recipients.0., ...
<%=cmd_skip%> aoc packages send @: archived=<Tab> # values of key: archived=true, archived=false
<%=cmd_skip%> aoc packages send @: name=x <Tab> # end marker of structure built with @: END, and the other keys
```

No space is inserted after a word that continues: `key=`, `key.`, `@file:`, or a folder (Bash 4 and later).
Zsh, Fish and PowerShell also display the description of commands, options, keys and extended value modifiers.
In PowerShell, a word starting with `@` is inserted with quotes (e.g. `'@file:README.md'`), as required by PowerShell.
Zsh lists options once `-` is typed (zsh style `prefix-needed`).
The type of an expected value is displayed by Bash and Zsh, and by PowerShell in the list of `MenuComplete` (`Ctrl+Space`).

The scripts call `<%=cmd%> config completion candidates -- [<word>...] <current word>`, which lists the candidates for the word at the cursor, with their description, followed by a directive for the shell: `:files` or `:folders` (local paths, followed by the beginning of the word that is not part of the path, if any, e.g. `:files --private-key=@file:`), `:hint <text>` or `:`.
The words are not evaluated (e.g. `@env:` is not replaced).
The command `<%=cmd%> config completion words [<word>...]` lists the words that can follow the given ones.
It can be used directly to inspect available commands:

```bash
<%=cmd%> config completion words aoc admin
```

#### Wizard

The wizard is a command that asks the user for information and creates an [Option Preset](#option-preset) with the provided information for a given application.

It takes one optional argument: a `Hash`, usually given with [`@:`](#positional-arguments-with-dot-path) as `key=value` items, in any order:

| Key        | Description                                                                     | If not provided, <%=tool%>                 |
|------------|---------------------------------------------------------------------------------|--------------------------------------------|
| `url`      | **URL** or hostname of the application                                          | asks for it.                               |
| `plugin`   | The **plugin name** to limit search to                                          | tries to detect known plugins from the URL |
| `preset`   | The **preset name** to save in config file                                      | generates a unique preset name             |
| `default`  | Set the preset as default configuration for the plugin (`yes`/`no`)             | `yes`                                      |
| `override` | Override the existing default preset of the plugin, if it exists (`yes`/`no`)   | `no`                                       |

Options of the plugin (for example `--username`, `--password`, `--client-id`, `--private-key`), see the plugin, are given as usual on the command line: they are added to the [Option Preset](#option-preset) created by the wizard.
Options that the wizard needs, but that are not provided, are asked.
An unknown key in the `Hash` is refused.

For example:

```shell
<%=cmd%> config wizard @: url=<%=ph :url%> plugin=<%=ph :plugin%> preset=<%=ph :preset%>
```

The command `config detect` takes the same argument, with keys `url` and `plugin`, and shows the detected applications, without creating a preset.
Use `<%=cmd%> config wizard help` to show the schema of the argument.

The simplest invocation (without argument: the URL is asked) is:

```shell
<%=cmd%> config wizard
```

If the application requires a private key, the user can provide it with option `--private-key` (the key, e.g. `@file:<path>`, not only its path), or let the wizard generate one.
The user is told where to place the associated public key PEM in the application.

#### Example of configuration for a plugin

For Faspex 5, Shares, Node (including ATS, Aspera Transfer Service), Console,
only username/password and URL are required (either on command line, or from configuration file).
Those can be provided on the command line:

```shell
<%=cmd%> shares files browse / --url=https://10.25.0.6 --username=john --password=<%=ph :password%>
```

This can also be provisioned in a configuration file:

- Build [Option Preset](#option-preset)

```shell
<%=cmd%> config preset set shares06 url https://10.25.0.6
<%=cmd%> config preset set shares06 username john
<%=cmd%> config preset set shares06 password <%=ph :password%>
```

This can also be done with one single command:

```shell
<%=cmd%> config preset set shares06 @json:'{"url":"https://10.25.0.6","username":"john","password":"<%=ph :password%>"}'
```

Or:

```shell
<%=cmd%> config preset set shares06 @: url=https://10.25.0.6 username=john password=<%=ph :password%>
```

- Define this [Option Preset](#option-preset) as the default [Option Preset](#option-preset) for the specified plugin (`shares`)

```shell
<%=cmd%> config preset set default shares shares06
```

- Display the content of the configuration file in table format

```shell
<%=cmd%> config preset overview
```

- Execute a command on the **Shares** application using default options

```shell
<%=cmd%> shares files browse /
```

### Secret Vault

Secrets, for example, passwords, keys, are needed when connecting to applications.
Those secrets are usually provided as command options: on the command line, in env vars, in files, and so on.

For security reasons, those secrets shall not be exposed in clear, either:

- On terminal during input
- In logs
- In command output

Instead, they shall be hidden (logs, output) or encrypted (configuration).

Terminal output (command result) secret removal is controlled by option `--out.secrets` (default: `no`).
Log secret removal is controlled by option `log_secrets` (default: `no`).
Secrets are identified by the name of their field (for example, `password`, `token`), and by their value: values of secret options and of presets, of [Extended Values](#extended-value-syntax) `@secret:` and `@vault:`, tokens obtained or generated, and secrets of transfer specs are hidden wherever they appear, also in field names.
In presets, a secret made of digits only (for example, a password not quoted in the YAML file) is converted to a string, so that it is identified as a secret.
A value shorter than 8 characters is hidden only when it is the whole value, not inside a text, except in responses of `mcp server`, where it is also hidden as a word (not next to a letter or digit).
Mandatory command line options can be requested interactively (for example, password) using option `interactive`.
It is possible to use [Extended Value](#extended-value-syntax) `@secret:[name]` to ask for a secret interactively.
If option `ui` is `graphical` (see [Graphical Interactions](#graphical-interactions-browser-and-text-editor)), the secret is entered on a web page opened in the browser, served by a local web server on `127.0.0.1`, else on terminal.
In MCP server mode, the secret is entered on a web page, see [Secrets entered in a web page](#secrets-entered-in-a-web-page).
It is also possible to enter an option as an environment variable, for example, `<%=opt_env :password%>` for option `password` and read the env var like this:

```shell
read -s <%=opt_env :password%>
export <%=opt_env :password%>
```

Another possibility is to retrieve values from a secret vault.

Option `vault` declares named secret stores (`stores`), and the name of the default store (`default`):

- `@vault:<label>.<field>` reads field `<field>` of secret `<label>` of the default store, managed with command `config vault` (see [Vault: Operations](#vault-operations)).
- `@vault://<store>/<path>[?<options>][#<field>]` reads a secret of any store (see [Vault: Secret references](#vault-secret-references)).

<%=schema_to_table(Aspera::Schema::Registry::VAULT_STORES)%>

For example, to use as default store an encrypted file `vault.bin` in the configuration folder (see [Vault: Encrypted file](#vault-encrypted-file)):

```shell
<%=cmd%> config preset set GLOBAL vault @json:'{"default":"local","stores":{"local":{"type":"file","file":"vault.bin"}}}'
```

Parameters of a store, with `type` (see sections below):

<%=schema_to_table(Aspera::Schema::Registry::VAULT_STORE)%>

> [!NOTE]
> The parameters of one store, without `stores` (for example, `{"type":"file","name":"vault.bin"}`), are deprecated: they define a store named after its type (for example, `file`), which is the default store.
> Set the store in `stores`, and its name in `default` instead: `{"default":"local","stores":{"local":{"type":"file","file":"vault.bin"}}}`.

Secrets used to access a store (`token`, `approle.secret_id`, `password`) are the value, or `@file:<path>` (for example, a credential of `systemd`, or a token written by Vault Agent): the file is read when used, and again when it is modified.
As for extended value `@file:`, reading the file is restricted by option `security` (see [Security Level](#security-level)).
In a YAML file, quote the value: `@` cannot start a plain scalar.

The secret of the default store (`password` of type `file`, `token` of type `vault` without `approle`, of type `1password` with `source` `api`, and `config` of type `keeper`), if not in its parameters, is the value of option `vault_password`.
To avoid exposing the vault password in the shell history, provide it via an environment variable:

```shell
export <%=opt_env :vault_password%>=<%=ph :your_password%>
```

> [!TIP]
> Set it interactively using `read` so that it is not recorded in the shell history:
>
> ```shell
> read -rs <%=opt_env :vault_password%> && export <%=opt_env :vault_password%>
> ```

#### Vault: IBM HashiCorp Vault

<https://developer.hashicorp.com/vault>

Quick start macOS:

```shell
brew tap hashicorp/tap
brew install hashicorp/tap/vault
vault server -dev -dev-root-token-id=<%=ph :token%>
```

```shell
--vault=@json:'{"default":"corp","stores":{"corp":{"type":"vault","url":"http://127.0.0.1:8200"}}}' --vault-password=<%=ph :token%>
```

With a token in a file (for example, written and renewed by Vault Agent), read again when the file is modified:

```shell
--vault=@json:'{"default":"corp","stores":{"corp":{"type":"vault","url":"https://vault.example.com:8200","token":"@file:/run/vault/token"}}}'
```

With AppRole authentication, the token is obtained by login, and renewed:

```shell
--vault=@json:'{"default":"corp","stores":{"corp":{"type":"vault","url":"https://vault.example.com:8200","approle":{"role_id":"<%=ph :role_id%>","secret_id":"@file:/etc/vault/secret_id"}}}}'
```

#### Vault: System keychain

> [!WARNING]
> **macOS only**

It is possible to manage secrets in macOS keychain.
Commands `list`, `ids` and `delete` are not supported: use the **Keychain Access** app.

```shell
--vault=@json:'{"default":"keychain","stores":{"keychain":{"type":"system","name":"<%=cmd%>"}}}'
```

#### Vault: Linux Secret Service

> [!WARNING]
> **Linux only**

It is possible to manage secrets in the Linux Secret Service (GNOME Keyring, KWallet, KeePassXC...), using the `secret-tool` command of `libsecret` (for example, package `libsecret-tools` on Debian and Ubuntu).
A session with an unlocked keyring is required.
Secrets are grouped with attribute `service`, which is parameter `name` (default: `<%=cmd%>`).

```shell
--vault=@json:'{"default":"keyring","stores":{"keyring":{"type":"secret_service","name":"<%=cmd%>"}}}'
```

#### Vault: Encrypted file

It is possible to store and use secrets encrypted in a file, with a store of type `file`:

```json
{"default":"local","stores":{"local":{"type":"file","file":"vault.bin"}}}
```

To configure the encrypted file vault as the default store, set the `vault` option in the global preset:

```shell
<%=cmd%> config preset set GLOBAL vault @json:'{"default":"local","stores":{"local":{"type":"file","file":"vault.bin"}}}'
```

The vault file is created automatically when the first secret is added - no explicit initialization is needed.
It is read when used, and again when it is modified.

> [!WARNING]
> The `vault_password` option should **not** be stored in the config file: doing so would protect secrets with a password that is itself stored in plain text, defeating the purpose of the vault.
> Use an environment variable as described above, or parameter `password` with `@file:<path>` (for example, a credential of `systemd`).

#### Vault: 1Password

Use `type: 1password` with a `source` parameter to select the backend.

##### Source: API (Connect REST API)

<https://developer.1password.com/docs/connect/>

[1Password Connect](https://developer.1password.com/docs/connect/) exposes a local REST API backed by a 1Password vault.
Deploy the Connect server with Docker, then point `<%=cmd%>` at it:

```shell
docker run -d --name op-connect \
  -p 8080:8080 \
  -v /path/to/1password-credentials.json:/home/opuser/.op/1password-credentials.json \
  1password/connect-api:latest
```

```shell
--vault=@json:'{"default":"op","stores":{"op":{"type":"1password","source":"api","url":"http://localhost:8080","vault_id":"<%=ph :vault_id%>"}}}' \
--vault-password=<%=ph :connect_token%>
```

> [!TIP]
> The `vault_id` is the alphanumeric ID shown in the 1Password web app under **Vault Settings**.
> The `vault_password` holds the Connect bearer token generated when creating the Connect server credentials.

> [!NOTE]
> The [1Password Service Accounts API](https://developer.1password.com/docs/service-accounts/) is also supported: use `url=https://api.1password.com` with a service account token as `vault_password`.
> No local server is required in that case.

##### Source: Cli (`op` CLI)

<https://developer.1password.com/docs/cli/>

Requires the `op` CLI to be installed and signed in.
No server to deploy: authentication is handled by the 1Password desktop app (biometric unlock) or by `op signin`.

```shell
--vault=@json:'{"default":"op","stores":{"op":{"type":"1password","source":"cli"}}}'
# or, to target a specific vault and account:
--vault=@json:'{"default":"op","stores":{"op":{"type":"1password","source":"cli","vault":"<%=ph :vault_name%>","account":"<%=ph :account_shorthand%>"}}}'
```

> [!TIP]
> Install `op` on macOS with `brew install 1password-cli`, then connect it to the desktop app:
> `op signin`

##### Referencing items

An item can be referenced by its title (label) or by its 1Password ID, in `@vault:<item>.<field>`:

```shell
--password=@vault:<%=ph(:item_id)%>.password
--password=@vault:<%=ph(:item_title)%>.password
```

> [!NOTE]
> If several items share the same title, use the item ID (or the `vault` parameter to restrict the search).

#### Vault: Keeper

<https://docs.keeper.io/keeperpam/secrets-manager/overview>

Keeper Secrets Manager (KSM) gives an application access to the records of shared folders of a Keeper vault, without the credentials of a user.
It requires the optional gem `keeper_secrets_manager`:

```shell
gem install keeper_secrets_manager
```

Create an application and a client device in Keeper (see the [Quick Start Guide](https://docs.keeper.io/keeperpam/secrets-manager/quick-start-guide)), share the folders of secrets with the application, and get the configuration of the device (base64 or JSON, for example with `ksm profile export`).
Parameter `config` is the value, or `@file:<path>`:

```shell
--vault=@json:'{"default":"keeper","stores":{"keeper":{"type":"keeper","config":"@file:<%=ph :ksm_config_file%>"}}}'
```

If `config` is not set in the default store, it is the value of option `vault_password`.

A secret is a record of the vault: its label is its title, or its UID.
The field of a reference is `password` by default: standard field of the record (`login`, `password`, `url`...), custom field by its label, or `notes`.
Field `username` is an alias of `login`.

```shell
--password=@vault:<%=ph(:record_title)%>.password
--password=@vault://keeper/<%=ph :record_title%>#<%=ph :field%>
```

To create records with `config vault create` (type `login`), set parameter `folder_uid`: UID of the shared folder where records are added.
Reading does not need it.

> [!NOTE]
> If several records share the same title, use the UID.
> Deleting a record with `config vault delete` requires that the application has edit permission.

#### Vault: Operations

Secrets of the default store can be manipulated using the `config vault` command:

- `info` : Show vault information
- `ids` : List secret labels in the vault
- `list` : List all secrets with full details
- `overview` : List labels of all secrets with their field names, without values
- `field` : List field names of a secret by label, without values
- `show` : Show a secret by label (or id)
- `create` : Add a new secret to the vault
- `delete` : Delete a secret by label (or id)
- `password` : Set a new password for the vault
- `import` : Import secrets from a JSON array (supports `--bulk`)
- `check` : Check that a [Secret Reference](#vault-secret-references) can be read, without its value

To add a new password entry in the vault for label `<%=ph :name%>`:

```shell
<%=cmd%> config vault create @: label=<%=ph :name%> password=@secret:password description='for this account'
```

#### Vault: Migration between vaults

To migrate all secrets from one vault backend to another (for example, from the encrypted file vault to 1Password), use `vault list` piped into `vault import`.

> [!NOTE]
> Use `list` (not `ids`) as the source: `ids` returns only labels, while `list` returns the full secret details needed for import.

```shell
<%=cmd%> config vault list --format=json --out.level=data --out.secrets=yes \
  --vault=@json:'{"default":"local","stores":{"local":{"type":"file","file":"<%=ph :source_vault_file%>"}}}' \
  --vault-password=<%=ph :source_password%> | \
<%=cmd%> config vault import @json:@stdin: --bulk=yes \
  --vault=@json:'{"default":"op","stores":{"op":{"type":"1password","url":"<%=ph :connect_url%>","vault_id":"<%=ph :vault_id%>"}}}' \
  --vault-password=<%=ph :connect_token%>
```

> [!TIP]
> Use `--out.level=data` on the `list` command so that only the raw JSON array is written to stdout, with no table headers or status lines, and `--out.secrets=yes` so that secrets are not replaced by a placeholder.

The `import` command accepts a JSON array where each element is a vault secret object (same schema as `create`).
`--bulk` makes each entry reported individually in the result table; omit it to get a single-line summary.
On error (for example a duplicate label), the default behavior is to stop (`--bfail=yes`).
Pass `--bfail=no` to skip failures and continue with the remaining entries.

#### Vault: Secret references

Secrets can also be read by reference, from any store of option `vault`:

```text
@vault://<store>/<path>[?<options>][#<field>]
```

- `<store>`: name of a store in `stores` of option `vault`.
- `<path>`: path of the secret in the store, and `<field>`: field of the secret. Both are percent-decoded (for example, `%20` for a space).
  For most types, the path is the label, and the field is `password` by default.
  For type `vault`, the path is `<mount>/<path>` in a KV v2 secrets engine, and the field is required.
- `<options>`: options of the store, as a URL query (for example, `version=2`).

References only read secrets: they are managed with the tools of the store (for example, `vault kv put` for HashiCorp Vault), or with `config vault` for the default store.
Compared to `@vault:<label>.<field>`, several stores can be used in the same command, and a HashiCorp Vault store reads any KV v2 mount, a given version, and limits the paths that can be read by reference (`allowed_prefixes`).
Values read by reference are kept in memory for `cache_ttl` seconds.
The configuration of stores is the same as in applications that use the library with references `secret://<store>/<path>` (for example, IBM Aspera Orchestrator).

For example, a HashiCorp Vault server with AppRole authentication, limited to secrets under `kv/aspera/`, and the encrypted file of `config vault` as default store, unlocked with option `vault_password`:

```shell
--vault=@json:'{"default":"local","stores":{"corp":{"type":"vault","url":"https://vault.example.com:8200","approle":{"role_id":"<%=ph :role_id%>","secret_id":"@file:/etc/vault/secret_id"},"allowed_prefixes":["kv/aspera/"]},"local":{"type":"file","file":"vault.bin"}}}'
```

References in a preset: to field `password` of secret `aspera/faspex` in mount `kv`, and to field `password` (default field of type `file`) of label `<%=ph :vault_label%>` in the encrypted file:

```shell
<%=cmd%> config preset set <%=ph :preset_name%> @: url=... username=... password=@val:@vault://corp/kv/aspera/faspex#password
<%=cmd%> config preset set <%=ph :preset_name%> @: url=... username=... password=@val:@vault://local/<%=ph :vault_label%>
```

To check that a reference can be read, without its value (store, version, time of update):

```shell
<%=cmd%> config vault check @vault://corp/kv/aspera/faspex#password
```

#### Configuration Finder

When a secret is needed by a sub command, the command can search for existing configurations in the configuration file by setting option `secret` to the special value `PRESET`.

The lookup is done by comparing the service URL and username (or access key).

#### Securing passwords and secrets

A password can be saved in clear in an [Option Preset](#option-preset) together with other account information (URL, username, and so on).
Example:

```shell
<%=cmd%> config preset set <%=ph :preset_name%> @: url=... username=... password=...
```

For more secure storage, first create a vault entry (see [Vault: Operations](#vault-operations)), then refer to it in the preset:

```shell
<%=cmd%> config preset set <%=ph :preset_name%> @: url=... username=... password=@val:@vault:<%=ph(:vault_label)%>.password
```

> [!NOTE]
> Use `@val:` in front of `@vault:` so that the [Extended Value](#extended-value-syntax) is not evaluated.

To migrate existing clear-text passwords from presets to the vault in one step, use the `secure` command.
The vault must already be configured (option `vault`, see [Secret Vault](#secret-vault)).

```shell
<%=cmd%> config preset secure
```

This scans all presets (or a single one if a name is provided) and, for every option whose name ends with `password` or `secret`, moves the value into the vault and replaces it with a `@vault:` reference.

```shell
<%=cmd%> config preset secure <%=ph :preset_name%>
```

When a vault is configured, the `set` and `ask` preset commands automatically move secret values (options ending with `password` or `secret`) into the vault as they are written, so no manual migration is needed.
To disable this behavior for a single command, pass `--vault=@none:`.

### Private Key

Some Aspera applications allow the user to be authenticated using [Public Key Cryptography](https://en.wikipedia.org/wiki/Public-key_cryptography):

- For SSH: Server
- For OAuth JWT: AoC, Faspex 5, faspio Gateway

It consists of using a pair of associated keys: a private key and a public key.
The same pair can be used for multiple applications.
The file containing the private key (key pair) can optionally be protected by a passphrase.
If the key is protected by a passphrase, then the passphrase is prompted when the key is used.
Some plugins support option `passphrase`.

Keys of type `ed25519` and OpenSSH encoded keys (default on modern Linux) are supported.
See section: [Private key type ed25519](#private-key-type-ed25519).
For OpenSSH encoded keys protected by a passphrase, install gem `bcrypt_pbkdf` (not available for JRuby):

```shell
gem install bcrypt_pbkdf
```

The following sample commands use the shell variable `KEY_PAIR_PATH`.
Set it to the desired safe location of the private key.
Typically, located in folder `$HOME/.ssh` or `$HOME/.aspera/<%=cmd%>`.
For example:

```shell
KEY_PAIR_PATH=~/.aspera/<%=cmd%>/<%=ph :pkey_name%>
```

Several methods can be used to generate a key pair.

The format expected for keys is [PEM](https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail).

If another format is used, such as `DER`, it can be converted to `PEM`, for example, using `openssl`.

#### <%=tool%> for key generation

The generated key is of type `RSA`, by default: **4096** bit.
For convenience, the public key is also extracted with extension `.pub`.
Files are PEM encoded.
The key is not passphrase protected.

```shell
<%=cmd%> config genkey ${KEY_PAIR_PATH} 4096
```

To display the public key of a private key:

```shell
<%=cmd%> config pubkey @file:${KEY_PAIR_PATH}
```

#### `ssh-keygen`

Both private and public keys are generated, option `-N` is for passphrase.

```shell
ssh-keygen -t rsa -b 4096 -m PEM -N '' -f ${KEY_PAIR_PATH}
```

#### `openssl`

To generate a key pair with a passphrase, the following can be used on any system:

```shell
openssl genrsa -passout pass:<%=ph :passphrase%> -out ${KEY_PAIR_PATH} 4096
openssl rsa -pubout -in ${KEY_PAIR_PATH} -out ${KEY_PAIR_PATH}.pub
```

`openssl` is sometimes compiled to support option `-nodes` (no DES, that is, no passphrase, for example, on macOS).
In that case, add option `-nodes` instead of `-passout pass:<%=ph :passphrase%>` to generate a key without passphrase.

If option `-nodes` is not available, the passphrase can be removed using this method:

```shell
openssl rsa -passin pass:<%=ph :passphrase%> -in ${KEY_PAIR_PATH} -out ${KEY_PAIR_PATH}.no_des
mv ${KEY_PAIR_PATH}.no_des ${KEY_PAIR_PATH}
```

To change (or add) the passphrase for a key:

```shell
openssl rsa -des3 -in ${KEY_PAIR_PATH} -out ${KEY_PAIR_PATH}.with_des
mv ${KEY_PAIR_PATH}.with_des ${KEY_PAIR_PATH}
```

#### Using an application to generate a key pair

Many applications are available, including on the internet, to generate key pairs.
For example: <https://cryptotools.net/rsagen>

> [!WARNING]
> Private keys are sensitive information, and shall be kept secret (like a password), so using online tools is risky.

### Web service

<%=tool%> is a command-line tool: it runs in a shell, with the credentials and presets of the user who starts it, and it assumes that only this user uses it.
It is not intended to be a public-facing web server.
When commands come from another program, for example an MCP client, see [Security Level](#security-level).

Some commands start a web server, for a specific client:

| Command | Client | Protection required when `url` is not loopback |
|---|---|---|
| `mcp server`, `http` transport | MCP client | `auth_token`, see [MCP Security](#security) |
| `faspex5 postprocessing` | Faspex 5 web hooks | `secret_token` or `allowed_ips`, see [Faspex 4-style post-processing](#faspex-5-faspex-4-style-post-processing) |
| `faspex5 gateway`, `aoc gateway` | Faspex 4 client applications | `username` and `password`, see [Faspex 4 Gateway](#faspex-5-faspex-4-gateway) |
| `node emulator` | Node API clients, for tests | `username` and `password`, see [Node emulator](#node-emulator) |

By default, the server listens on a loopback address: `localhost`, an address of `127.0.0.0/8`, or `::1`.
It can be reached only from the same host.

> [!WARNING]
> Loopback restricts the host, not the user: on a host shared with other users, they can also reach the server.
> On such a host, also set the protection of the command.

When the host of `url` is not a loopback address, for example `0.0.0.0` (all interfaces), the server can be reached from the network: the command refuses to start without its protection.
On a network, use HTTPS (`https://` in `url`) or a reverse proxy with TLS: with HTTP, passwords and tokens are sent in clear.

Other features listen on a loopback address only, to receive input from the browser of the user:

- [Web login flow](#web-login-flow): the result of the login, on `redirect_uri`.
- `@secret:`, with option `ui` set to `graphical` (see [Secret Vault](#secret-vault)), or with `mcp server` and the `stdio` transport (see [Secrets entered in a web page](#secrets-entered-in-a-web-page)): the secret entered by the user.

The server serves HTTP, or HTTPS with a certificate.
The following parameters are supported:

| Parameter         | Type     | Default                 | Description                                                      |
|-------------------|----------|-------------------------|------------------------------------------------------------------|
| `url`             | `String` | `http://localhost:8080` | Base URL on which requests are received; a path can be included. | <!-- markdownlint-disable-line -->
| `cert`            | `String` | -       | (HTTPS) Path to certificate file (with ext. `.pfx` or `.p12` for `PKCS12`).        |
| `key`             | `String` | -       | (HTTPS) Path to private key file (PEM), or passphrase for `PKCS12`.                |
| `chain`           | `String` | -       | (HTTPS) Path to certificate chain (PEM only).                                    |

Parameter `url` (base URL) defines:

- If `http` or `https` is used
- The local port number (default 443 for HTTPS, 80 for HTTP)
- The **base path**, that is, the path under which requests are received (useful for routing when a reverse proxy is used).

A web page open in a browser can send requests to a local web server, also on `localhost`.
To refuse them, the server checks each request:

- When `url` is a loopback address (`localhost`, `127.0.0.0/8`, `::1`), header `Host` shall be a loopback name or address, else HTTP 403: a host name that resolves to `127.0.0.1` is refused (DNS rebinding).
- Header `Origin`, sent by browsers, shall be the origin of the server, else HTTP 403.
- A JSON body shall have `Content-Type: application/json`, else HTTP 415: a web page cannot send it to another site without the agreement of that site.

Clients that are not browsers send no `Origin`, and the `Host` of the URL they call.
They shall send the type of a JSON body: for example, with `curl`, add `-H 'Content-Type: application/json'`.

### Image and video thumbnails

<%=tool%> can display thumbnails for images and videos in the **terminal**, using [iTerm2 inline image protocol](https://iterm2.com/documentation-images.html) or through colorized text.

This feature can be used:

- In the `thumbnail` command of `node` when using **gen4/access key** API.
- When using the `show` command of `preview` plugin.
- `coffee` and `image` commands of `config` plugin.
- Any displayed value which is a URL to image can be displayed with option `format` set to `image`

The following options can be specified in option `--out.img`:

<%=schema_to_table(Aspera::Schema::Registry::IMAGE_OPTIONS)%>

Examples:

- Display image as colorized text (requires `rmagick`)

```shell
<%=cmd%> config image https://eudemo.asperademo.com/wallpaper.jpg --ui=text --out.img.text=true
```

- Display image from byte stream as image in terminal (requires iTerm2-compatible terminal)

```shell
curl -so - https://eudemo.asperademo.com/wallpaper.jpg | <%=cmd%> config image @stdin:bin
```

- Display image from file (requires iTerm2-compatible terminal)

```shell
<%=cmd%> config image @stdin:bin < A-team.jpg
```

### Graphical Interactions: Browser and Text Editor

Some actions may require the use of a graphical tool:

- A browser for Aspera on Cloud authentication (web auth method)
- A browser to enter a secret requested with `@secret:`
- A text editor for editing the configuration file

By default, <%=tool%> assumes that a graphical environment is available on Windows and macOS; on other systems, it relies on the presence of the `DISPLAY` environment variable.
The composite option `ui` (use `--ui=help` to display this schema) selects the mode, the way a web login is received, and the browser command:

<%=schema_to_table(Aspera::Schema::Registry::UI_OPTIONS)%>

A plain value is the `mode`:

- `--ui=browser` (or `graphical`) forces a graphical environment: a browser is opened for URLs or secrets.
- `--ui=terminal` (or `text`) forces a text environment: the URL to open is displayed on terminal, and secrets are entered on terminal.
- `--ui=auto` selects the mode from the environment (default).

The browser is opened, by priority, with: `--ui.command`, or the system default.
The system default is opened with the following command:

| OS      | Command                |
|---------|------------------------|
| macOS   | `open <url>`           |
| Windows | `start explorer "<url>"` |
| Linux   | `xdg-open <url>`       |

To edit a file (for example `config open`), whatever the `mode`, the editor is, by priority: the command in the environment variable `EDITOR`, else `notepad.exe` on Windows, else the system default above (or `--ui.command` if defined).

When a command is defined, it is used to open URLs whatever the `mode`.
The command is an array: the URL is appended as last argument.
The executable is either a full path, or the name of an executable found in the `PATH`.
For example, to use Firefox:

```bash
<%=cmd%> config echo @secret: --ui=browser --ui.command=@json:'["firefox","--private-window"]'
```

### Web login flow

Authentication methods that need a user login in a browser (`--auth=web`, including for Shares) all work the same way: <%=tool%> listens on a local port, the browser is redirected to it after login.

![Web login flow: <%=tool%> listens on a loopback port and receives the result of the login from the browser](<%=link_repo('docs/login-flow.svg')%>)

1. <%=tool%> generates a random `state` and starts a local HTTP server on the loopback address of `redirect_uri` (default: `http://localhost:12345`).
2. <%=tool%> opens the login URL in the browser (see [Graphical Interactions](#graphical-interactions-browser-and-text-editor)): the authorization endpoint with `redirect_uri` and `state` for `web`, or, for Shares, the SAML login page with `RelayState`.
   If no graphical environment is available, the URL is displayed, to be opened on any browser of the same host.
3. The user logs in on the server, possibly redirected to an identity provider.
4. The server redirects the browser to `redirect_uri`, with the OAuth code (`web`), or, for Shares, the tokens, and the `state`.
5. The browser sends this request to <%=tool%>, which checks that `state` is the one it generated, and stops listening.
6. <%=tool%> requests the token to the server: exchange of the code (`web`) or, for Shares, of the refresh token, and saves it in the cache.
   For Faspex 5, the code is protected with PKCE: <%=tool%> sends a challenge with the login URL, and the matching verifier with the code.
   Next calls use the cached token, renewed if needed without a browser.

The code or tokens never go to another host than the local one: the host of `redirect_uri` shall be loopback.

#### Option `ui.web_auth`

Option `ui.web_auth` (part of the composite option `ui`, see [Graphical Interactions](#graphical-interactions-browser-and-text-editor)) selects how the result of a web login is received:

| Value            | Local port | Use when |
|------------------|------------|----------|
| `port` (default) | Yes: <%=tool%> listens on the loopback address of `redirect_uri` | The browser runs on the same system as <%=tool%>, or an SSH tunnel is possible. |
| `paste`          | No: `redirect_uri` is only used in the login URL | The browser cannot reach the system that runs <%=tool%>, and no tunnel is possible. |

With `paste`, after login the user gives the result to <%=tool%> through the terminal (it is hidden, as it contains a code or tokens: see [Hidden Input](#hidden-input)):

- the code displayed by Shares (a long text of letters, digits, `-` and `_`), or the code shown by `<%=cmd%> config web_login` on the workstation,
- or the full URL (or only the query) from the address bar of the browser, which shows a connection error on `redirect_uri`: this is expected.

In all cases the `state` is checked.
Details are in the following sections.

Example:

```shell
<%=cmd%> <%=ph :plugin%> <%=ph :command%> --ui=terminal --ui.web_auth=paste
```

#### Web login when the browser is on another system

The browser sends the result of the login to `redirect_uri`, on the loopback address of the system where the browser runs.
If <%=tool%> runs on another system than the browser (for example, <%=tool%> is installed on a server, and the user is connected with SSH from a workstation), the redirection does not reach <%=tool%>.

To solve this, forward the port of `redirect_uri` from the workstation to the server with an SSH tunnel, and open the login URL in the browser of the workstation:

1. On the workstation, open the SSH session with a tunnel (same port on both sides, default `12345`):

   ```shell
   ssh -L 127.0.0.1:12345:127.0.0.1:12345 <SERVER_USER>@<SERVER_HOST>
   ```

2. In this session, run the command with `--ui=terminal`, so that the login URL is displayed instead of opening a browser on the server (this is the default if the server has no graphical environment):

   ```shell
   <%=cmd%> <%=ph :plugin%> <%=ph :command%> --ui=terminal
   ```

3. Copy the displayed URL in the browser of the workstation, and log in.
4. The browser is redirected to `http://localhost:12345`: the tunnel sends the request to <%=tool%> on the server, and the flow continues as described above.

The tunnel only exists as long as the SSH session is open.

If no tunnel is possible (for example, a jump server between the workstation and the server), use `--ui.web_auth=paste`: <%=tool%> then opens no local port, and the result of the login is given through the terminal.
There are two ways, depending on whether <%=tool%> is also installed on the workstation.

With `--ui.web_auth=port` (default), in an SSH session with `--ui=terminal`, a warning reminds this option.

##### With <%=tool%> on the workstation

<%=tool%> on the workstation opens the login page, receives the redirection of the browser, and shows a code to paste in the terminal of the server.
Nothing else is needed on the workstation: no configuration, no preset, no access to the server of the application.
The exchange of the code for a token is done by <%=tool%> on the server: the secret of the client does not leave it.

1. In the SSH session, run the command with `--ui=terminal --ui.web_auth=paste`:

   ```shell
   <%=cmd%> <%=ph :plugin%> <%=ph :command%> --ui=terminal --ui.web_auth=paste
   ```

2. <%=tool%> displays a message that proposes the two ways to log in, with the login URL for the first one, and a command to run on the workstation for the second one: it contains a code made of letters, digits, `-` and `_`. Then <%=tool%> waits:

   ```text
   USER ACTION: To continue, choose one of these two ways:
     1. With any browser (<%=cmd%> is not needed on the workstation):
        - Open this URL in a browser and log in:
            https://...
        - The browser shows a connection error on http://localhost:12345: this is expected.
        - Copy the full URL from the address bar of the browser, and paste it in the prompt below.
     2. If <%=cmd%> is installed on the workstation that has the browser:
        - Run there:
            <%=cmd%> config web_login <%=ph :code%>
        - Log in in the page that opens.
        - Copy the code shown by the browser, and paste it in the prompt below.
   ```

   The command is displayed only if <%=tool%> does not start the browser itself (`--ui=terminal` without `--ui.command`).
   If the browser is started by <%=tool%> (`--ui=graphical`, or `--ui.command`), it is on the same host as <%=tool%>, and the redirection may be immediate (user already logged in): only the steps to log in, copy the URL from the browser and paste it are displayed.

3. On the workstation, run this command.
   The first time for a login host, <%=tool%> displays the host of the login page, and asks to trust it (`yes`): it opens a URL that comes from another system.
   Trusted hosts are saved; without a terminal, an unknown host is refused.
   <%=tool%> then opens the browser on the login page and listens on `redirect_uri`.
4. Log in. The browser shows a page "Login Complete" with the code to paste, hidden by default:
   - The button **Copy** puts the code in the clipboard.
   - The **eye** button shows or hides the code, to select it manually.
5. Paste the code in the terminal of the server ([hidden](#hidden-input): `🔑` becomes `…`). <%=tool%> on the server checks the `state`, and the flow continues as described above, from step 6.

The command on the workstation:

- accepts only a login page in `https`, and a `redirect_uri` on a loopback address; the host shown for confirmation is the one of the URL, not a label given in the code;
- is available only at security level `low`;
- ends once the browser has received the page with the code; the port of `redirect_uri` shall be free on the workstation (the URL is registered for the login and cannot be changed);
- gives to the server only the parameters it needs (the `code` and the `state`).

The codes are compressed and encrypted with a key that is not secret (derived from a constant and the current time, in slots of 15 minutes): they are hard to read and are valid for 15 to 30 minutes (the clocks of both computers must be correct), but they are **not confidential**: do not keep them, nor send them. The code shown by Shares also uses the random `state` of the login in its key.
The codes are authenticated: a code that is incomplete, mistyped or modified is detected.
Spaces and line breaks are ignored (letter case matters): a code displayed on several lines can be pasted.

##### Without <%=tool%> on the workstation

If <%=tool%> is not installed on the workstation, the URL of the error page is used:

1. In the SSH session, run the command with `--ui=terminal --ui.web_auth=paste`.
2. Copy the displayed login URL in the browser of the workstation, and log in.
3. The browser is redirected to `redirect_uri` (for example `http://localhost:12345/?code=...&state=...`) and shows a connection error: this is expected.
4. Copy the full URL from the address bar of the browser, and paste it in the terminal ([hidden](#hidden-input), as it contains a code or tokens).
   The query alone (`code=...&state=...`) is also accepted.
   The `state` is mandatory: it is checked like in the standard flow, then the flow continues from step 6.

Both ways accept, at the prompt, the code, the URL or the query.
If standard input is not a terminal, the line is read from it.
The size of a pasted line may be limited by the terminal: the code of the reply contains only what is needed.

Notes:

- For Shares with `--auth=web`, `paste` is simpler: Shares itself displays the code, so neither the tunnel, nor `<%=cmd%> config web_login`, nor the URL of the error page is used (see [Authentication of SAML users](#authentication-of-saml-users)).
- The port must be free on the workstation.
  To use another port, change it in the tunnel and in `--redirect-uri`, for example `--redirect-uri=http://localhost:23456` and `-L 127.0.0.1:23456:127.0.0.1:23456`.
  For Aspera on Cloud, this `redirect_uri` shall also be declared in the API client (see [API Client Registration](#api-client-registration)).
- The tunnel listens on `127.0.0.1`: if the browser resolves `localhost` to `::1`, use `--redirect-uri=http://127.0.0.1:12345`.
- On Windows, `ssh` is the OpenSSH client provided with the system; with PuTTY, add a local port forwarding (Connection &rarr; SSH &rarr; Tunnels) from `127.0.0.1:12345` to `127.0.0.1:12345`.
- Another solution is X11 forwarding: run an X server on the workstation (for example `VcXsrv` or X410 on Windows) and connect with `ssh -X`.
  The browser then runs on the server and is displayed on the workstation, so no tunnel is needed.
  It is heavier (X server to install, slower display), and the browser is the one of the server.
- Without interaction (automation), prefer a method that needs no browser, such as `--auth=jwt` for Aspera on Cloud.

### Logging, Debugging

The gem is equipped with traces, mainly for debugging and learning APIs.
The composite option `log` groups all logging parameters (use `--log=help` to display this schema):

<%=schema_to_table(Aspera::Schema::Registry::LOG_OPTIONS)%>

> [!TIP]
> Individual options `log_level`, `log_format`, `logger`, and `log_secrets` are also available as aliases for `log.level`, `log.format`, `log.type`, and `log.secrets` respectively.

#### `log_level` and `log_secrets`

To increase debug level, use option `log_level` (for example, using command line `--log-level=xx`, env var `<%=opt_env :log_level%>`, or an [Option Preset](#option-preset)).

> [!NOTE]
> When using the `direct` agent (`ascp`), additional transfer logs from `ascp` can be activated using `ascp` options and `ascp_args`, see [`direct`](#agent-direct).

By default, passwords and secrets are redacted from logs.
Set option `log_secrets` to `yes` to include secrets in logs.

#### `log_format`

Option `log_format` (alias for `log.format`) supports a few pre-defined formatters or a custom one using `@ruby:`.
A custom formatter is a lambda that takes 4 arguments; see [Ruby Formatter](https://github.com/ruby/logger/blob/master/lib/logger/formatter.rb): `severity`, `time`, `progname`, `msg`.
The default formatter is:

```ruby
->(s, _d, _p, m){"#{s[0..2]}#{s[-1]} #{m}\n"}
```

#### Logging examples

- Display debugging log on `stdout`:

```shell
<%=cmd%> config preset overview --log-level=debug --logger=stdout
```

Or equivalently using dot-path notation:

```shell
<%=cmd%> config preset overview --log.level=debug --log.type=stdout
```

- Log errors to `syslog`:

```shell
<%=cmd%> config preset overview --log-level=error --logger=syslog
```

Or using the composite option in a preset:

```yaml
log:
  level: error
  type: syslog
```

> [!NOTE]
> When <%=tool%> is used interactively in a shell, the shell itself will usually log executed commands in the history file (`history | grep <%=cmd%>`).

### Learning Aspera Product APIs (REST)

<%=tool%> uses mainly REST APIs to interact with Aspera applications.

To get traces of execution, with dump of API calls, use argument: `--log-level=debug`.

To display HTTP/S traffic set option `log_level` to `trace2`: `--log-level=trace2`.
It will display the exact content of HTTP requests and responses.

### HTTP socket parameters

To ignore SSL certificate for **any** address/port, use option: `insecure`, that is, `--insecure=yes`.
To ignore SSL certificate for a list of specific address/port, use option `ignore_certificate`, set to a URL or an `Array` of URLs for which the certificate is ignored (only the address and port are matched), for example, `--ignore-certificate=https://127.0.0.1:9092` or `--ignore-certificate=@list:,https://127.0.0.1:9092,https://127.0.0.1:9093`

> [!NOTE]
> Ignoring certificate also applies to `ascp` WSS.

Ignoring a certificate is **not recommended**.
It is preferable to add the certificate to the trusted store.
When certificate validation is skipped, a warning is displayed.
To disable this warning, set the option `warn_insecure` to `no`.

HTTP connection parameters (not `ascp` WSS) can be adjusted using option `http_options`:

<%=schema_to_table(Aspera::Schema::Registry::HTTP_OPTIONS)%>

Time values are durations: a number of **seconds** (`Integer` or `Float`), or a `String`, e.g. `30s`, `12h`, `1d`, `1h 30m`, `1d 02:00:00`.
Any additional key is forwarded as a setter to the `Net::HTTP` session.
For a full list, refer to the Ruby library: [`Net::HTTP`](https://github.com/ruby/net-http/blob/master/lib/net/http.rb).

Like any other option, those can be set either on command line, or in configuration file, either in a global preset or server-specific one.

Example:

```shell
<%=cmd%> aoc admin package list --http-options=@json:'{"read_timeout":10.0}'
```

With a server whose token and refresh token expire at the same time (e.g. Shares: 24 hours), `token_refresh_max_age` refreshes the token before its refresh token expires.
A command run more often than this duration (e.g. scheduled every 12 hours) keeps the session alive without a new login, provided the token stays in cache (`token_cache_max_age`):

```shell
<%=cmd%> shares files browse / --http-options=@json:'{"token_cache_max_age":"1d","token_refresh_max_age":"12h"}'
```

The option `ssl_options` corresponds to a list of options as listed in `man SSL_CTX_set_options`.
The default initial value is the default of Ruby as specified in `openssl/ssl.rb`.
Each option can be specified as a `String` with the same name as in the OpenSSL library by removing the prefix: `SSL_OP_`, or an `Integer` (for example, `0` resets to no option).
If the name appears in the list, the option is set.
If the name appears in the list prefixed with a hyphen (`-`), the option is cleared.
For example to enable option `SSL_OP_CIPHER_SERVER_PREFERENCE`, add it to the list as `CIPHER_SERVER_PREFERENCE`.
To disable option `SSL_OP_SAFARI_ECDHE_ECDSA_BUG`, add it as `-SAFARI_ECDHE_ECDSA_BUG`.

Example:

```json
{"ssl_options":["CIPHER_SERVER_PREFERENCE","-SAFARI_ECDHE_ECDSA_BUG"]}
```

### Proxy

There are several types of network connections, each of them uses a different mechanism to define a (forward) **proxy**:

- REST calls (APIs) and HTTP Gateway
- `ascp` WSS and Legacy Aspera HTTP/S Fallback
- `ascp` SSH and UDP (Aspera FASP)

See the following sections.

#### Proxy for REST and HTTP Gateway

REST API calls and transfers based on HTTP Gateway both use Ruby's `Net::HTTP` class.
See [Ruby find proxy](https://rubyapi.org/4.0/o/uri/generic#method-i-find_proxy).

When Ruby HTTP is used, there are two possibilities to define an HTTP proxy to be used.

The `http_proxy` environment variable (**lower case**) can be set to the **URL** of the proxy (with optional credentials).
Syntax is: `(http|https)://[user:password@]host:port`.
For example, `http://myproxy.org.net:3128`.

> [!NOTE]
> Ruby expects a URL and `myproxy.org.net:3128` alone is **not** valid.

Credentials for proxy are optional but can also be specified:

```shell
export http_proxy=http://<%=ph :username%>:<%=ph :password%>@proxy.example.com:3128
```

Option `http_proxy` does the same (set env var) but on command line:

```shell
<%=cmd%> --http-proxy=http://<%=ph :username%>:<%=ph :password%>@host:port ...
```

Alternatively, the `fpac` option (function for proxy auto config) can be set to a [Proxy Auto Configuration (PAC)](https://en.wikipedia.org/wiki/Proxy_auto-config) JavaScript value.

> [!NOTE]
> Proxy credentials are not supported in PAC files.

To read the script from a URL (`http:`, `https:` and `file:`), use prefix: `@uri:`.
A minimal script can be specified to define the use of a local proxy:

```shell
<%=cmd%> --fpac='function FindProxyForURL(url, host){return "PROXY localhost:3128"}' ...
```

The result of a PAC file can be tested with command: `config proxy_check`.
Example, using command line option:

```shell
<%=cmd%> config proxy_check --fpac='function FindProxyForURL(url, host) {return "PROXY proxy.example.com:3128;DIRECT";}' http://example.com
```

```text
proxy://proxy.example.com:3128
```

```shell
<%=cmd%> config proxy_check --fpac=@file:./proxy.pac http://www.example.com
```

```text
proxy://proxy.example.com:8080
```

```shell
<%=cmd%> config proxy_check --fpac=@uri:http://server/proxy.pac http://www.example.com
```

```text
proxy://proxy.example.com:8080
```

If the proxy found with the PAC requires credentials, then use option `proxy_credentials` with username and password provided as an `Array`:

```shell
<%=cmd%> --proxy-credentials=@json:'["<%=ph :username%>","<%=ph :password%>"]' ...
```

```shell
<%=cmd%> --proxy-credentials=@list::<%=ph(:username)%>:<%=ph(:password)%> ...
```

#### Proxy for Legacy Aspera HTTP/S Fallback

Only supported with the `direct` agent: To specify a proxy for legacy HTTP fallback, use `ascp` native option `-x` and `ascp_args`: `--transfer=@json:'{"ascp_args":["-x","<%=ph :proxy_url%>"]}'`.

#### FASP proxy (forward) for transfers

To specify a FASP proxy (forward), set the [**transfer-spec**](#transfer-specification) parameter: `proxy` (only supported with the `direct` agent).

For example, for an Aspera forward proxy not encrypted (HTTP) without authentication running on port 9091, the option would be:

```shell
--ts=@json:'{"proxy":"dnat://proxy.example.org:9091"}'
```

Or, alternatively, (prefer transfer spec like above, generally):

```shell
--transfer=@json:'{"ascp_args":["--proxy","dnat://proxy.example.org:9091"]}'
```

### FASP configuration

<%=tool%> uses one of the transfer agents to execute transfers.

By default, it uses the `direct` agent, which is a local `ascp`.
Nevertheless, <%=tool%> does not come with `ascp` installed.
This is the reason why it is advised to install the Aspera Transfer Daemon during installation (`<%=cmd%> transferd install`).

By default, <%=tool%> uses the `ascp` binary found in **well known locations**, that is, typical Aspera product installation paths.

The `config` plugin allows finding and specifying the location of `ascp`.
It provides the following commands for `ascp` sub-command:

- `show` : Show the path of `ascp` used
- `info` : Show information on `ascp` and its environment
- `install` : Install the Transfer SDK (deprecated, same as `transferd install`)
- `spec` : List transfer spec parameters supported by `ascp`
- `schema` : Show the JSON schema of the transfer spec
- `errors` : List known `ascp` errors and whether they are retry-able
- `products list` : List Aspera transfer products available locally

#### Selection of `ascp` location for [`direct`](#agent-direct) agent

Option: `sdk_folder` is used to specify the location of `ascp`.
By default, <%=tool%> uses `ascp` from the Transfer SDK installed in its configuration folder (see `transferd install`).

To override and use an alternate `ascp` path, use option `sdk_folder` (`--sdk-folder=`).

For a permanent change, set a global default.
For example, `<%=ph :install_dir%>` could be `~/my_install_dir` on Linux, or `C:\Users\admin\.aspera\<%=cmd%>\sdk` on Windows.

Using a POSIX shell:

```shell
<%=cmd%> config preset set GLOBAL sdk_folder <%=ph :install_dir%>
```

```text
INFO Updated: global_common_defaults: sdk_folder <- <%=ph :install_dir%>
INFO Saving config file: /home/john/.aspera/<%=cmd%>/config.yaml
```

If the path has spaces, read section: [Shell and Command line parsing](#command-line-parsing-special-characters).

A special value `product:<%=ph :product_name%>` can be used for option `sdk_folder`.
It specifies to use `ascp` from the given product name.
A special value for product name is `FIRST`, which means: use the first product found in the internal list.
In that case, other files (SSH keys, `aspera.conf`, `transferd`) are still taken from the default SDK folder.

Locally installed Aspera products can be listed with:

```shell
<%=cmd%> config ascp products list
```

```text
╭───────────────────────────────────────┬──────────────────────────────────────╮
│ name                                  │ app_root                             │
╞═══════════════════════════════════════╪══════════════════════════════════════╡
│ IBM Aspera Transfer SDK               │ /Users/laurent/.aspera/sdk           │
│ IBM Aspera for Desktop                │ /Applications/IBM Aspera.app         │
│ IBM Aspera Connect                    │ /Applications/IBM Aspera Connect.app │
│ IBM Aspera High-Speed Transfer Server │ /Library/Aspera                      │
╰───────────────────────────────────────┴──────────────────────────────────────╯
```

To permanently use the `ascp` of a product:

```shell
<%=cmd%> config preset set GLOBAL sdk_folder 'product:IBM Aspera Connect'
```

```text
INFO Updated: default: config <- global_common_defaults
INFO Updated: global_common_defaults: sdk_folder <- product:IBM Aspera Connect
INFO Saving config file: /home/john/.aspera/<%=cmd%>/config.yaml
```

To show the path of currently used `ascp`:

```shell
<%=cmd%> config ascp show
```

```text
/Users/laurent/.aspera/sdk/ascp
```

```shell
<%=cmd%> config ascp info
```

```text
╭─────────┬──────────────────────────────────────────────────╮
│ field   │ value                                            │
╞═════════╪══════════════════════════════════════════════════╡
│ ascp    │ /Users/john/.aspera/sdk/ascp                     │
...
╰─────────┴──────────────────────────────────────────────────╯
```

### Transfer Clients: Agents

Some actions on Aspera Applications lead to file transfers (upload and download) using the FASP protocol (`ascp`).
Transfers will be executed by a transfer client, here called **Transfer Agent**.

The following agents are supported and selected with option `transfer`:

| `transfer` | location | Description of agent          |
|----------|----------|-------------------------------|
| [`direct`](#agent-direct)          | local    | direct execution of `ascp`    |
| [`transferd`](#agent-transfer-daemon) | local    | Aspera Transfer Daemon        |
| [`connect`](#agent-connect-client) | local    | Aspera Connect Client (to be deprecated in 2027, use `desktop`) |
| [`desktop`](#agent-desktop-client) | local    | Aspera for Desktop            |
| [`node`](#agent-node-api)          | remote   | Aspera Transfer Node          |
| [`httpgw`](#agent-http-gateway)    | remote   | Aspera HTTP Gateway           |

The list of agents and their short identifier can be displayed with:

```shell
<%=cmd%> config agents list
```

To display the configurable parameters of a specific agent (with required fields, default values, enumerated values):

```shell
<%=cmd%> config agents parameters <agent name>
```

For example:

```shell
<%=cmd%> config agents parameters direct
<%=cmd%> config agents parameters node
```

To display the description of an agent:

```shell
<%=cmd%> config agents show <agent name>
```

> [!NOTE]
> All transfer operations are seen from the point of view of the agent.
> For example, an agent executing an **upload**, or **package send** operation will effectively push files to the related server from the system where the agent runs.

All above agents (including `direct`) receive transfer parameters as a [**transfer-spec**](#transfer-specification).
Parameters in transfer-spec can be modified with option `ts`.

**Specific** options for agents are provided with option `transfer` (as a `Hash`, optionally with an `agent` key).

> [!NOTE]
> Parameters in `transfer` are specific for each agent type and are described in the agents respective sections.

#### Dry run of a transfer

With option `dry_run` (`--dry-run=yes`), a transfer command does not start the transfer: its result is the final transfer spec, as it would be given to the agent (with option `ts` and file list applied), with secrets hidden (unless `--out.secrets=yes`).
Nothing is transferred.

```shell
<%=cmd%> server download /aspera-test-dir-large/100MB --dry-run=yes
```

Commands that change something before the transfer are refused with option `dry_run`, before any change: `aoc packages send` and `faspex5 packages send` (the package is created first), `sync` commands, and preview generation of `preview`.

#### Asynchronous Transfer Mode

Adding `asynchronous: true` to the `transfer` option makes <%=tool%> return immediately after
submitting the transfer, without waiting for completion.

The returned `job_id` can be used at any time to check progress:

```shell
# Start a download and return immediately
<%=cmd%> server download /remote/big-file.bin --to-folder=/tmp \
  '--transfer=@json:{"agent":"desktop","asynchronous":true}'

# Poll status later
<%=cmd%> config agents jobs status <job_id>

# List all pending/completed async transfers
<%=cmd%> config agents jobs list

# Remove completed/failed entries
<%=cmd%> config agents jobs cleanup
```

> [!NOTE]
> `config transfer` (`list`, `status`, `cleanup`) is deprecated after 4.28.0: use `config agents jobs`. It still works, with a warning.

All transfer agents support asynchronous mode:

| Agent       | Status source                                                                 | Persisted across restart |
| ----------- | ----------------------------------------------------------------------------- | ------------------------ |
| `desktop`   | JSON-RPC `get_transfer` (auto-discovered URL)                                 | Yes |
| `node`      | REST `ops/transfers/{id}`                                                     | Yes |
| `connect`   | REST `transfers/info/{id}` (auto-discovered URL)                              | Yes |
| `transferd` | gRPC `monitor_transfers`                                                      | Yes |
| `direct`    | In-process thread state (re-queryable while process lives, e.g. MCP mode)    | No: returns `unknown` after restart |
| `httpgw`    | In-process thread state (re-queryable while process lives, e.g. MCP mode)    | No: returns `unknown` after restart |

For `direct` and `httpgw`, the transfer runs as a Ruby thread inside the <%=tool%> process.
The `job_id` is persisted on disk but the live thread state is only available as long as the same process is running.
If the process is restarted, `config agents jobs status` returns `unknown` for those jobs.

Parameters of the agent are persisted, except secrets (e.g. `password` of agent `node`): `config agents jobs status` takes them from the current `transfer` option, if it is for the same agent (e.g. same option on command line, or in a preset).

> [!NOTE]
> **`asynchronous` and MCP** - When <%=tool%> is used as an MCP server, an AI assistant calling
> a transfer command may time out or cancel the request and retry, causing duplicate transfers.
> Using `asynchronous: true` eliminates this risk: the transfer is submitted immediately,
> the `job_id` is returned, and the AI can poll
> `config agents jobs status <job_id>` to track progress without any risk of duplication.
> This works with all agents, including `direct` and `httpgw`.

#### Agent: Direct

The `direct` agent directly executes a local `ascp` in <%=tool%>.
This is the default agent for <%=tool%> (option `--transfer=direct`).
<%=tool%> will locally search installed Aspera products, including SDK, and use `ascp` from that component.
See [FASP](#fasp-configuration).

##### Agent: Direct: `transfer`

The `transfer` option accepts the following optional parameters to control multi-session, Web Socket Session, Resume policy and add any argument to `ascp`:

<%=schema_to_table('transfer_opts:components.schemas.DirectAgentOptions')%>

In case of transfer interruption, the agent will **resume** a transfer up to `iter_max` times.
Sleep between iterations is given by the following formula where `iter_index` is the current iteration index, starting at 0:

```text
min( sleep_max, sleep_initial * sleep_factor ^ iter_index )
```

By default, the progress bar of <%=tool%> is displayed (see [Transfer progress bar](#transfer-progress-bar)): it aggregates all sessions of a multi-session transfer.

To display the native progress bar of `ascp` instead, set parameter `quiet` to `false`:

```shell
--transfer.quiet=false
```

In that case, the progress bar of <%=tool%> is not displayed, unless option `progress_bar` is set.
For multi-session transfers, each `ascp` process displays its own progress bar.

To skip usage of management port (which disables the progress bar of <%=tool%>), set option `monitor` to `false`.

By default, Ruby's root CA store is used to validate any HTTPS endpoint used by `ascp` (for example, WSS).
To use a custom certificate store, use the `trusted_certs` option of direct agent's option `transfer`.
To use `ascp`'s default, use option:

```shell
--transfer.trusted_certs=@none:
```

Some transfer errors are considered **retry-able** (for example, timeout) and others are not (for example, wrong password).
The list of known protocol errors and retry level can be listed:

```shell
<%=cmd%> config ascp errors
```

Error codes of sessions (`errcode` in `ascp` logs) are a different numbering, listed with their category and the corresponding error above:

```shell
<%=cmd%> config ascp errors session
```

Examples:

```shell
<%=cmd%> ... --transfer.wss=true --transfer.resume.iter_max=20
<%=cmd%> ... --transfer.spawn_delay_sec=2.5 --transfer.multi_incr_udp=false
```

Parameter `ascp_args` can also be used to activate logging using option `-L` of `ascp`.
For example, to activate debug level 2 for `ascp` (`DD`), and display those logs on the terminal (`-`):

```shell
--transfer=@json:'{"ascp_args":["-DDL-"]}'
```

This is useful to debug if a transfer fails.

To store `ascp` logs in file `aspera-scp-transfer.log` in a folder, use `--transfer=@json:'{"ascp_args":["-L","/path/to/folder"]}'`.

To analyze `ascp` log files (`ascp` 4.0 and later), give log files, or folders with log files, to `config ascp logs`:

```shell
<%=cmd%> config ascp logs summary /path/to/folder
<%=cmd%> config ascp logs sessions /path/to/folder/aspera-scp-transfer.log
```

| Command             | Result                                                          |
|---------------------|-----------------------------------------------------------------|
| `summary`           | Statistics of sessions, errors by category, maximum throughput, findings. |
| `health`            | Health check for monitoring in Nagios format (failed sessions and low efficiency over last N minutes). |
| `sessions`          | One row per session, with diagnostics.                          |
| `diagnostics`       | One row per diagnostic of a session: `id`, `severity` (`error`, `warning`, `info`), `message` and `recommendation` (action to take, when the diagnostic has one). |
| `multi_sessions`    | Multi-session transfers: sessions grouped by transfer, with aggregate rate. |
| `snapshots`         | Aggregate rates per period.                                     |
| `snapshot_sessions` | Rates of each session per period.                               |
| `peers`             | Sessions and errors by peer address.                            |
| `transfers`         | Transferred files.                                              |
| `licenses`          | Licenses of local and peer systems.                             |
| `overdrives`        | Sessions with loss due to overdriving of network or storage.    |
| `records`           | Log lines parsed into records: `samples`, `sessions` or `transfers` (see below). |
| `fields`            | Description of the fields of records: `samples`, `sessions` or `transfers`. |
| `find`              | `ascp` log files of this system (no argument): `path`, `size`, `modified`, `source`, most recent first. |

Command `find` lists the local files that contain `ascp` log lines, in the log folders of the installed products (including `<logging><directory>` of their `aspera.conf`), of `ascp` found in `PATH`, of IBM Aspera for Desktop, and in the default locations of `ascp` (below). Give the paths it lists to the other commands:

```shell
<%=cmd%> config ascp logs find --fields=path
<%=cmd%> config ascp logs sessions ~/Library/Logs/Aspera
```

`ascp` writes its log in the folder of option `-L`, else in `<logging><directory>` of `aspera.conf`, else in a location that depends on the OS:

| OS            | Default location of the `ascp` log |
|---------------|------------------------------------|
| Linux, Unix   | syslog, facility `local2`: `/var/log/messages` or `/var/log/syslog` by default, `/var/log/aspera.log` if syslog is configured to separate the Aspera logs. |
| macOS         | `~/Library/Logs/Aspera` (`/Library/Logs/Aspera` for `root`). |
| Windows       | `var\log` of the product if this folder exists, else the folder of `ascp`. |

For the `ascp` used by <%=tool%>, `<%=cmd%> config ascp info --fields=log` gives this location (a folder, or `syslog`).

In a folder, the file is `aspera-scp-transfer.<n>.log` (rotated, `n` from `0` to `log_count` of `aspera.conf`), and `aspera-scp-transfer.log` is a hard link to the current one. `ascp` 4 (`ascp4`) writes `ascp4.<n>.log`.

| Application            | Location of the `ascp` log |
|------------------------|----------------------------|
| <%=tool%>, agent `direct` or `transferd` | No `-L`: default location above (e.g. on Linux in syslog). With agent `direct`, `-L` can be set with `ascp_args` (see above). |
| IBM Aspera Connect     | `-L` set to its log folder (e.g. `~/Library/Logs/Aspera_Connect`). |
| IBM Aspera for Desktop | Log folder of the application, also used for its own logs and those of `transferd`: `~/Library/Logs/com.ibm.software.aspera.desktop` on macOS, `%APPDATA%\com.ibm.software.aspera.desktop\logs` on Windows, `~/.config/com.ibm.software.aspera.desktop/logs` on Linux. |
| IBM Aspera Transfer Daemon | `-L` set to `fasp_runtime.log.dir` of its configuration (or `localLog` of the transfer), else the default location above. |
| Server side of a transfer | On the server, configured by its `aspera.conf`, or by option `-R` of the client: see [`server logs`](#analyze-ascp-logs-of-the-server). |

On Linux, the syslog files are often readable only by `root`, and a container may have no syslog daemon (the log of `ascp` is then lost): use `-L`, or read the system journal, e.g. `journalctl -t ascp | <%=cmd%> config ascp logs summary -`.
For the other logs of Aspera products, see the IBM support page [Where are IBM Aspera logs located](https://www.ibm.com/support/pages/where-are-ibm-aspera-desktop-client-or-ibm-aspera-server-logs-located).

Log files compressed with gzip (e.g. rotations `aspera.log-20261101.gz`, `aspera-scp-transfer.1.log.gz`) are read directly, in a folder or given as argument; gzip is detected from the first bytes of the file, not from its name. Argument `-` reads the logs from the standard input, plain or compressed with gzip:

```shell
<%=cmd%> config ascp logs summary /var/log/aspera.log-20261101.gz
zcat /var/log/aspera.log-2026*.gz | <%=cmd%> config ascp logs summary -
```

To analyze the logs of an HSTS read over SSH, instead of files of the local machine, use command `logs` of the plugin [`server`](#analyze-ascp-logs-of-the-server).

A file must contain `ascp` log lines (`FASP` messages, or lines of process `ascp` in syslog): in a folder, other files are ignored; a file given as argument that is not an `ascp` log is refused.

When logs of both sides of a session are analyzed (client and server), each session includes the status, error and diagnostics of the other side (`peer_side`, `peer_diagnostics`).

For example, to list only errors:

```shell
<%=cmd%> config ascp logs diagnostics /path/to/folder --select=@json:'{"severity":"error"}'
```

Besides the default columns, `sessions` rows have context columns to filter sessions (show them with `--fields=ALL`, or select with `--fields=session,product_name,transport,authentication`, or filter with `--select`/`--query`); a column is absent when the log does not give it:

| Column           | Value                                                                                                              |
|------------------|--------------------------------------------------------------------------------------------------------------------|
| `product_name`   | Product that wrote the log, from the line `<product> version <version>` (e.g. `Aspera High-Speed Transfer Server`, `Aspera Transfer SDK`, `Aspera Connect`), without `IBM`. |
| `transport`      | `ssh` if `Session Start` has `tcp_port`, `wss` if it has `wss_port`.                                                |
| `authentication` | `token` if `ascp` logs that `ASPERA_AUTH_TOKEN` is set, else `node` if it logs the storage of a node access key. Never the token, the access key or the storage root. |
| `proxy`          | Address of the proxy (`proxy_ip` of `Session Params`), absent if there is none.                                     |
| `fips`           | `true` or `false` (`fips_enabled` of `Session Params`).                                                             |

Diagnostics of a session include: category of error (e.g. `udp_setup`, `storage`, `authentication`) with a hint, retry of a failed session, parameters set by the server (cipher, resume policy, virtual link), efficiency and loss of control messages, decline of the rate during the transfer (`rate_decline`: second half of the samples below 70% of the first half, not evaluated if the peer changes the rate, if another transfer session starts meanwhile, or if the session failed), and for a sender, which limit of the receiver (network, disk, virtual link) or reading from storage limits the rate. Other diagnostics: no packet received for some seconds, by the receiver (`reception_interruption`) or by the sender, which gets no feedback of the receiver (`feedback_interruption`); overflow of the retransmission timer (`rex_timer_overflow`: the retransmission RTT is very large); maximum rate of the license of `ascp` below the target rate (`license_rate_limit`); license that expires within `license_expiry_days` (default `30`) of the start of the session, or has expired (`license_expiry`); and many small files transferred (`small_files`): at least `small_files_min_count` (default 100) files with a mean size below `small_files_max_mean` (default 1 MB); path MTU measured by `ascp` below `small_mtu_max` (default 1400, `ascp` measures 1492, 1006, 508 or 296), which suggests a VPN or a tunnel (`small_mtu`). Two configuration messages, which have no effect on the transfer, are not diagnostics but only appear in `findings` of `summary`: OpenSSL modules folder not found (`ossl-modules not found`), and a schedule of virtual link capacity that could not be registered (`unable to submit change event`).

The `recommendation` of a diagnostic is only in the list `diagnostics` (not in `sessions`, where `diagnostics` is a list of messages, and not in `summary`): it tells what to check or change, with the `ascp` options and `aspera.conf` parameters concerned (e.g. UDP port and firewalls, target and minimum rate, storage write, SSH). Diagnostics without action (e.g. information, or cancelled by the user) have no `recommendation`; the diagnostic of the category of a failed session gives its hint in `message`.

Option `ascp_logs` (dot-notation) sets `period` (snapshot period in minutes, default `1`), `zero_bytes` (include sessions without transferred bytes), `mtu` (when not found in logs), `resolve` (host names of peers), `timezone`, `health_minutes` (window in minutes for health check command, default `60`), `remote_max_size` (maximum total size in bytes of the log files read from a server with [`server logs`](#analyze-ascp-logs-of-the-server), default `268435456`), and `thresholds` (diagnostic thresholds, including `rate_decline_ratio`, `rate_decline_min_samples`, `rate_decline_delay`, `rate_decline_end_fraction`, `license_expiry_days`, `small_files_min_count`, `small_files_max_mean` and `small_mtu_max`), e.g. `--ascp-logs.period=5` or `--ascp-logs.thresholds.efficiency=95`.

Times of log lines are read in the time zone of the analyst, and displayed in it. To read the log of another system without shifting it, set the time zone of the log with `timezone`: `UTC` or an offset `+HH:MM`, e.g. `--ascp-logs.timezone=+02:00`. Syslog lines (`Oct 25 00:02:20`) have no year: it is deduced from the modification date of the log file (the current date for the standard input), the log being before this date. So a log from December to January, analyzed in March, has its December lines in the previous year. Keep the modification date of the file when copying it (e.g. `cp -p`, `scp -p`).

Command `records` gives the log lines parsed into records, with the field names of the log lines, to filter them with `--out.query` (JMESPath):

| Record      | Log lines                                                                                       |
|-------------|-------------------------------------------------------------------------------------------------|
| `samples`   | `Receiver bl` or `Sender bl` line, with the `DS Qs` line that follows it in field `DS`.          |
| `sessions`  | `Session Start`, `Session Params`, `Session Stop` and `Session Statistics` lines of a session, and lines of the process about it (see below). |
| `transfers` | `Transfer Start` and `Transfer Stop` lines of a file.                                           |

A group of a log line becomes an object: for example, `rate t/m/c/n/vl/vr/r=...` becomes `rate.t`, `rate.m`, `rate.c`, etc.
Values are numbers when the log value is a number: rates in bps, durations in ms, s or µs, and percentages without `%`.
`Session Stop` and `Transfer Stop` have the fields of `Session Start` and `Transfer Start`, with their final values.
When several log files are read, field `log_file` gives the log file of each record.
Field `cookie` of `Session Params` is never output.

A session record also has the fields of these lines of the process (`ascp`), when the log has them:

| Field                                                          | Log line                                                                                              |
|----------------------------------------------------------------|-------------------------------------------------------------------------------------------------------|
| `fasp_version`, `license_max_rate`, `license_expires`          | `Initializing FASP version <version>, license expires on <date>, max rate=<N> Mbps, ...`: `license_max_rate` (bps) and `license_expires` are absent if the license is unlimited or has no expiry date. `account no.` and `license no.` are never output. |
| `pMTU`, `start_brtt`                                           | `Measured pMTU: <N> Bytes, start_brtt: <N> ms`.                                                        |
| `datagram_size`, `block_size`, `path_mtu`                      | `datagram size <N>B, block size <N>B, path MTU <N>B` (no `path_mtu` in old versions).                  |
| `peer_rate_params`                                             | List of `Peer requested rate params adopted` lines, in the order of the log: `time`, `target_rate`, `min_rate` and `transfer_policy` of each change. |

For example, samples where the calculated rate is lower than the target rate, and sessions with loss of control messages from the receiver:

```shell
<%=cmd%> config ascp logs records samples /path/to/aspera-scp-transfer.log --out.query='[?rate.c < rate.t].{time: time, session: uuid, calculated: rate.c, network: rate.n, lost: bl2.l}'
<%=cmd%> config ascp logs records sessions /path/to/folder --out.query='[?rcvr_ctl.lost_pct > `1`]'
```

Command `fields` gives the type and description (with unit) of each field of a kind of record (`samples`, `sessions` or `transfers`), with its path as used in `--out.query` (e.g. `rate.c`):

```shell
<%=cmd%> config ascp logs fields samples
<%=cmd%> config ascp logs fields sessions
<%=cmd%> config ascp logs fields transfers
```

> [!NOTE]
> When transfer agent [`direct`](#agent-direct) is used, the list of files to transfer is provided to `ascp` using either `--file-list` or `--file-pair-list` and a temp file list, unless `--file-list` or `--file-pair-list` is already provided via `transfer` parameter `ascp_args`.
> To place source paths directly on the `ascp` command line instead of using a temp file, set `file_list` to `false` in `transfer`: `--transfer.file_list=false`.

In addition to standard methods described in section [File List](#list-of-files-for-transfers), it is also possible to specify the list of files using `transfer` parameter `ascp_args`:

```shell
--sources=@ts --transfer=@json:'{"ascp_args":["--file-list","myfilelist"]}'
```

> [!NOTE]
> File lists are shown here; similar options exist for file pair lists.

> [!NOTE]
> This method avoids the creation of a copy of the file list: if the standard options `--sources=@lines:@file:... --src-type=...` are used, then the file list is read and parsed, and a new file list is created in a temporary folder.

> [!NOTE]
> This method has limitations: it applies **only** to the [`direct`](#agent-direct) transfer agent (that is, local `ascp`) and not to Aspera on Cloud.

##### Agent: Direct: Management messages

By default, <%=tool%> gets notifications from `ascp` on its management port.
This can be disabled with parameter: `monitor=false` of `transfer`.

It is also possible to send messages to `ascp` using this management port.
A typical use is to change the target rate of a running transfer.

The communication is done through a JSON file that shall be created in <%=tool%>'s config folder as displayed with:

```shell
<%=cmd%> config folder
```

The name of the file shall be: `send_<%=ph :PID%>`, where `<%=ph :PID%>` is the process ID of the running <%=tool%>.

If there is only one <%=tool%> running, one can get the PID like this:

```shell
ps -axo pid,command|grep <%=cmd%>|grep -v grep|cut -f1 -d' '
```

Example to change the target rate:

```shell
echo '{"type":"RATE","rate":300000}' > ~/.aspera/<%=cmd%>/send_67470
```

When <%=tool%> detects this file, it uses it during a transfer and then deletes it.

> [!NOTE]
> The JSON's keys use **snake case**, that is, lower case with `_` as word separator.
> The list of message `type` values can be found in `aspera/ascp/management.rb`: `OPERATIONS`.
> The list of parameters is `PARAMETERS` (native names are capitalized, keys in the JSON file are in snake case).

##### Agent: Direct: `aspera.conf`: Virtual Links

This agent supports a local configuration file, `aspera.conf`, where Virtual links can be configured.

On a server (HSTS), the following commands can be used to set a global virtual link:

```shell
asconfigurator -x 'set_trunk_data;id,1;trunk_name,in;trunk_capacity,100000;trunk_on,true'
asconfigurator -x 'set_trunk_data;id,2;trunk_name,out;trunk_capacity,100000;trunk_on,true'
asconfigurator -x 'set_node_data;transfer_in_bandwidth_aggregate_trunk_id,1'
asconfigurator -x 'set_node_data;transfer_out_bandwidth_aggregate_trunk_id,2'
```

This command is not available on clients: instead, edit the file `aspera.conf` (its location is shown by `<%=cmd%> config ascp info --fields=aspera_conf`) and modify the sections `default` and `trunks` like this for a global 100 Mbps virtual link (capacity is in kbps):

```xml
<?xml version='1.0' encoding='UTF-8'?>
<CONF version="2">
    <default>
        <transfer>
            <in>
                <bandwidth>
                    <aggregate>
                        <trunk_id>1</trunk_id>
                    </aggregate>
                </bandwidth>
            </in>
            <out>
                <bandwidth>
                    <aggregate>
                        <trunk_id>2</trunk_id>
                    </aggregate>
                </bandwidth>
            </out>
        </transfer>
    </default>
    <trunks>
        <trunk>
            <id>1</id>
            <name>in</name>
            <on>true</on>
            <capacity>
                <schedule format="ranges">100000</schedule>
            </capacity>
        </trunk>
        <trunk>
            <id>2</id>
            <name>out</name>
            <capacity>
                <schedule format="ranges">100000</schedule>
            </capacity>
            <on>true</on>
        </trunk>
    </trunks>
</CONF>
```

It is also possible to set a schedule with different time and days, for example for the value of `schedule`:

```text
start=08 end=19 days=mon,tue,wed,thu capacity=900000;1000000
```

##### Agent: Direct: `aspera.conf`: File name with special characters

By default, `ascp` replaces file system disallowed characters in transferred file names with `_`.
On Windows, it concerns: `* : | < > " ' ?`.

Replacing illegal characters in transferred file names is a built-in feature of Aspera transfers.
This behavior can be customized with the `aspera.conf` configuration file.
For example, to replace illegal character `|` with an underscore `_`:

1. First, locate the configuration file with:

```shell
<%=cmd%> config ascp info --fields=aspera_conf
```

Typically, it is located at `$HOME/.aspera/sdk/aspera.conf`

1. Edit this file, and add the following line inside the XML section `CONF.default.file_system`:

```xml
        <replace_illegal_chars>_|</replace_illegal_chars>
```

The result should look like this:

```xml
<?xml version='1.0' encoding='UTF-8'?>
<CONF version="2">
<default>
    <file_system>
        <resume_suffix>.aspera-ckpt</resume_suffix>
        <partial_file_suffix>.partial</partial_file_suffix>
        <replace_illegal_chars>_|</replace_illegal_chars>
    </file_system>
</default>
</CONF>
```

According to the [documentation](https://www.ibm.com/docs/en/ahts/4.4.x?topic=reference-user-group-default-configurations), the parameter works as follows:

- The first character in the value is the replacement character.
- All other characters listed after it are the **illegal** ones to be replaced.

So in this example: `|` will be replaced with `_`.

If the mounted target file system is **Windows** but <%=tool%> runs on Linux, there are several additional illegal characters to handle.
In that case, set the parameter as shown below. XML special characters such as `<`, `>`, `"` and `'` must be escaped properly:

```xml
<replace_illegal_chars>_*:|&lt;&gt;&quot;&apos;?</replace_illegal_chars>
```

In this example:

- `_` is the replacement character.
- The list of characters that will be replaced is: `*:|<>"'?`

So, for example:

- `report|final?.txt` becomes `report_final_.txt`
- `data*backup"2025".csv` becomes `data_backup_2025_.csv`

#### Agent: Connect Client

> **Note:** IBM Aspera Connect will be deprecated in 2027.
> Use [IBM Aspera for Desktop](#agent-desktop-client) instead: `--transfer=desktop`.
> <%=tool%> displays a warning when the `connect` agent is used.

By specifying option: `--transfer=connect`, <%=tool%> will start transfers using the locally installed **IBM Aspera Connect Client**.
There are no specific parameters for option `transfer`.

#### Agent: Desktop Client

By specifying option: `--transfer=desktop`, <%=tool%> will start transfers using the locally installed **IBM Aspera Desktop Client**.
There are no specific parameters for option `transfer`.

#### Agent: Node API

By specifying option: `--transfer=node`, <%=tool%> starts transfers in an Aspera Transfer Server using the Node API, either on a local or remote node.
This is especially useful for direct node-to-node transfers.

Parameters provided in option `transfer` are:

<%=schema_to_table('transfer_opts:components.schemas.NodeAgentOptions')%>

Like any other option, `transfer` can get its value from a pre-configured [Option Preset](#option-preset):

```shell
--transfer=@preset:<%=ph :preset_name%> --transfer.agent=node
```

It can also directly use the [Extended Value](#extended-value-syntax) syntax:

```shell
--transfer=@json:'{"agent":"node","url":"https://...","username":"<%=ph :username%>","password":"<%=ph :password%>"}'
```

If `transfer` is not specified and a default node has been configured (name in `node` for section `default`) then this node is used by default.

If the `password` value begins with `Bearer` then the `username` is expected to be an access key and the parameter `root_id` is mandatory and specifies the file ID of the top folder to use on the node using this access key.
It can be either the access key's root file ID, or any authorized file ID underneath it.

#### Agent: HTTP Gateway

The Aspera HTTP Gateway is a service that allows sending and receiving files using HTTPS.

By specifying option: `--transfer=httpgw`, <%=tool%> will start transfers using the Aspera HTTP Gateway.

Parameters provided in option `transfer` are:

<%=schema_to_table('transfer_opts:components.schemas.HttpgwAgentOptions')%>

Example:

```shell
<%=cmd%> faspex5 packages receive 323 --transfer=httpgw --transfer.url=https://asperagw.example.com:9443/aspera/http-gwy
```

> [!NOTE]
> The gateway only supports transfers authorized with a token.

If the application, for example, AoC or Faspex 5, is configured to use the HTTP Gateway, then <%=tool%> will automatically use the gateway URL if `--transfer=httpgw` is specified, so `transfer` URL becomes optional.

#### Agent: Transfer Daemon

Another possibility is to use the Transfer Daemon (`transferd`).
Set option `transfer` to `transferd`.

Options for `transfer` are:

<%=schema_to_table('transfer_opts:components.schemas.TransferdAgentOptions')%>

> [!NOTE]
> If port zero is specified in the URL, then the daemon will listen on a random available port.
> If no address is specified, then `127.0.0.1` is used.

A daemon started by <%=tool%> requires an API key, so that other users of the host cannot use it: the one of parameter `api_key`, else a random one.
A daemon left running (`stop` is `false`) never gets a random key, as the next executions could not know it: set parameter `api_key` (for all executions), else it has no authentication (a warning tells it).
Its configuration file is in the temporary folder, readable only by the user.

For example, to use an external, already running `transferd`, use option:

```shell
--transfer=@json:'{"agent":"transferd","url":":55002","start":false,"stop":false}'
```

The gem `grpc` is not part of default dependencies, as it requires compilation of a native part.
So, to use the Transfer Daemon you should install this gem:

```shell
gem install grpc
```

If the execution complains about incompatible libraries, then force recompilation of the native part:

```shell
gem uninstall grpc

gem install grpc --platform ruby
```

On Windows the compilation may fail for various reasons (3.1.1):

<!-- spellchecker: disable -->

- `cannot find -lx64-ucrt-ruby310`

   &rarr; copy the file `[Ruby main dir]\lib\libx64-ucrt-ruby310.dll.a` to (remove the `dll` extension) `[Ruby main dir]\lib\libx64-ucrt-ruby310.a`
  
- `conflicting types for 'gettimeofday'`

  &rarr; edit the file `[Ruby main dir]/include/ruby-[version]/ruby/win32.h` and change the signature of `gettimeofday` to `gettimeofday(struct timeval *, void *)`, that is, change `struct timezone` to `void`

<!-- spellchecker: enable -->

#### Transfer Daemon as a system service

The Transfer Daemon (`transferd`) can run permanently as a `systemd` service, for applications that use an existing daemon (see [Agent: Transfer Daemon](#agent-transfer-daemon), `start` set to `false`).
<%=tool%> installs the SDK, writes the configuration file of the daemon (`/etc/transferd/transferd.json`) and the `systemd` unit, then enables and starts the service.

Commands are in `transferd service` (plugin [`transferd`](#plugin-transferd-transfer-daemon)):

| Command     | Action |
|-------------|--------|
| `spec`      | Show the schema of the configuration file of the daemon (`transferd.json`). Works on any system. |
| `install`   | Install the SDK if it is missing, then do `configure`. |
| `configure` | Merge the given configuration into the existing file, validate it, write the file and the unit, reload `systemd`, enable and restart the service, and wait until the daemon listens. |
| `status`    | Show the version, the state of the service, the endpoint and whether it listens. The API key is never shown. |
| `uninstall` | Stop and remove the service. With `purge` set to `true` in `service`, also remove the configuration file and the log folder. |
| `use`       | Switch to an installed version of the SDK and restart the service (see below). |
| `versions`  | List the installed versions of the SDK (see below). |

Except `spec` and `versions`, commands take the optional **last** positional argument `CONFIG`: a `Hash` ([Extended Value](#extended-value-syntax)) with two optional sections:

- `service`: how the service is installed.
- `config`: content of `transferd.json`.

```json
{
  "service": {
    "user": "asperadaemon"
  },
  "config": {
    "address": "127.0.0.1",
    "port": 55002,
    "log_directory": "/var/log/aspera-transferd",
    "workers": {"max_concurrent": 10},
    "authentication": {"enabled": true}
  }
}
```

Parameters of section `service`:

<%=schema_to_table(Aspera::Plugins::Transferd::Service::SERVICE_OPTIONS)%>

Section `config` follows the JSON schema of the daemon, displayed with:

```shell
<%=cmd%> transferd service spec
```

<%=schema_to_table('transferd')%>

The configuration is checked before anything is written:

- Keys not given keep their value in the existing `transferd.json` (deep merge), and a key set to `null` is removed.
- An unknown key, a value of a wrong type, or an inconsistent configuration (for example `tls.enabled` without `certificate` and `key`) is refused, with the name of the key and of the file if the faulty key is in the existing file.
  The daemon itself ignores unknown keys silently.
- The section `fasp_runtime` is computed from the SDK folder, and can be overridden.
- If `authentication.enabled` is `true` and no `api_key` is given, the key of the existing file is kept, else a random one is generated.
  The file is written in clear text with mode `0640`, owner `user:group`.
  To get the key from the [vault](#secret-vault), write `{"config":{"authentication":{"api_key":"@vault:transferd.api_key@"}}}` in an [Extended Value](#extended-value-syntax) `@json:@extend:'...'`.

Requirements:

- `systemd` on Linux only.
  On other systems, or without `systemctl`, commands fail with a message (only `spec` and `--dry-run` work everywhere).
- Run as `root`, except with `--dry-run=yes` (option is a boolean), which shows the actions and the files without any change, and `spec` and `versions`.
- The account (`asperadaemon` by default) is **not** created by <%=tool%>.
  If it does not exist, the command fails and shows the command to create it:
  `useradd --system --no-create-home --shell /usr/sbin/nologin asperadaemon`.
  This is the account used by other Aspera products on the same host, so that files have the same owner.
- If the version of the SDK installed is different from the version of the schema, then a warning is displayed (it is not an error).

Example:

```shell
sudo <%=cmd%> transferd service install --sdk-folder=/opt/aspera/transferd/current @json:'{"config":{"port":55002,"authentication":{"enabled":true}}}'
```

```shell
<%=cmd%> transferd service configure --dry-run=yes @json:'{"config":{"log_level":"debug"}}'
```

```shell
sudo <%=cmd%> transferd service status
```

```shell
sudo <%=cmd%> transferd service uninstall @json:'{"service":{"purge":true}}'
```

##### Versions side by side and rollback

If the SDK folder (option `sdk_folder`) is named `current`, e.g. `--sdk-folder=/opt/aspera/transferd/current`, then <%=tool%> uses the layout `<prefix>/<version>` with a link `current` that points to the version in use:

```text
/opt/aspera/transferd/1.1.9
/opt/aspera/transferd/1.1.10
/opt/aspera/transferd/current -> 1.1.10
```

- `service install` installs the version given in `service.version` (default: version tested with this release of <%=tool%>) in `<prefix>/<version>`, and sets the link `current`.
  If the installation fails, then the link is set back to the previous version.
- The unit and `transferd.json` refer to `current`: switching the link and restarting the service is enough to change the version.
- `service versions` lists the installed versions and the one in use.
- `service use <%=ph :version%>` switches the link and restarts the service.
  If the service does not start, then the link is set back to the previous version and the service is restarted.

Any other folder name is used as is, with no link.

### Transfer Specification

Some commands lead to file transfer (upload/download).
All parameters necessary for this transfer are described in a [**transfer-spec**](#transfer-specification) (Transfer Specification), such as:

- Server address
- Transfer username
- Credentials
- File list
- And so on

<%=tool%> builds the [**transfer-spec**](#transfer-specification) internally as a `Hash`.
It is not necessary to provide additional parameters on the command line for a transfer.

It is possible to modify or add any of the supported [**transfer-spec**](#transfer-specification) parameters using the `ts` option.
The `ts` option accepts a `Hash` [Extended Value](#extended-value-syntax) containing one or several [**transfer-spec**](#transfer-specification) parameters.
Multiple `ts` options on command line are cumulative, and the `Hash` value is deeply merged.
To remove a (deep) key from transfer spec, set the value to `null`.

> [!NOTE]
> Default transfer spec values can be displayed with command:

```shell
<%=cmd%> config ascp info --fields=ts --out.flat=no
```

It is possible to specify `ascp` options when the `transfer` option is set to [`direct`](#agent-direct) using `transfer` option parameter: `ascp_args`.
Example:

```shell
--transfer=@json:'{"ascp_args":["-l","100m"]}'
```

Or an equivalent (using dotted expression):

```shell
--transfer.ascp_args=@list:' -l 100m'
```

This is especially useful for `ascp` command line parameters not supported in the transfer spec.

The use of a [**transfer-spec**](#transfer-specification) instead of `ascp` command line arguments has the following advantages:

- It is common to all [Transfer Agents](#transfer-clients-agents)
- It does not depend on command line limitations (special characters, and so on)

#### Transfer Parameters

All standard [**transfer-spec**](#transfer-specification) parameters can be specified.
A [**transfer-spec**](#transfer-specification) can also be saved/overridden in the configuration file.

References:

- [Aspera Node API Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20node%20api%22) &rarr; /opt/transfers
- [Aspera Transfer Daemon Documentation](https://developer.ibm.com/apis/catalog?search=%22aspera%20transfer%20sdk%22) &rarr; Guides &rarr; API Ref &rarr; Transfer Spec V1
- [Aspera Connect SDK](https://d3gcli72yxqn2z.cloudfront.net/connect/v4/asperaweb-4.js) &rarr; search `The parameters for starting a transfer.`

Parameters can be displayed with commands:

```shell
<%=cmd%> config ascp spec
```

An optional parameter can be specified to display only the parameters supported by a specific transfer agent, or `overview` for one column per agent indicating which agents support each parameter:

```shell
<%=cmd%> config ascp spec direct
<%=cmd%> config ascp spec overview
<%=cmd%> config ascp spec overview --fields=name,a,c,d,h,n,t
```

A JSON Schema can be generated with command:

```shell
<%=cmd%> config ascp schema --format=jsonpp
```

An optional parameter can be specified to display the schema for a specific transfer agent:

```shell
<%=cmd%> config ascp schema transferd --format=jsonpp
```

The description gives the supported agents, if not all, and the corresponding `ascp` argument or environment variable.

#### Transfer Specification Reference

<%=agent_table%>

<%=spec_to_table(Aspera::Transfer::Spec::SCHEMA, **Aspera::Transfer::Spec.doc_options)%>

#### Destination folder for transfers

The destination folder is set by <%=tool%> by default to:

- `.` for downloads
- `/` for uploads

It is specified by the [**transfer-spec**](#transfer-specification) parameter `destination_root`.
As such, it can be modified with option: `--ts=@json:'{"destination_root":"<%=ph :path%>"}'`.
The option `to_folder` provides an equivalent and convenient way to change this parameter:
`--to-folder=<%=ph :path%>`.

#### List of files for transfers

When uploading, downloading or sending files, the user must specify the list of files to transfer.

By default, the list of files to transfer is provided on the command line.

The list of (source) files to transfer is specified by ([Extended Value](#extended-value-syntax)) option `sources` (default: `@args`).
The list is either the list of source files, or a combined source/destination list (see below) depending on value of option `src_type` (default: `list`).

In <%=tool%>, all transfer parameters, including file list, are provided to the transfer agent in a [**transfer-spec**](#transfer-specification) so that execution of a transfer is independent of the transfer agent (direct, connect, node, transfer daemon...).
So, eventually, the list of files to transfer is provided to the transfer agent using the [**transfer-spec**](#transfer-specification) field: `"paths"` which is a list (array) of pairs of `"source"` (mandatory) and `"destination"` (optional).
The `sources` and `src_type` options provide convenient ways to populate the transfer spec with the source file list.

Possible values for option `sources` are:

- `@args` : (default) the list of files (or file pair) is directly provided on the command line (after commands): unused arguments (not starting with `-`) are considered as source files.

> [!IMPORTANT]
> When using `@:` to build a command parameter and `--sources=@args` (default),
> the `END` marker is required between the `@:` block and the file list.
> See [Positional Arguments with Dot-path](#positional-arguments-with-dot-path).

**Example**:

  ```shell
  <%=cmd%> server upload ~/mysample.file secondfile
  ```

  This is the same as (with default values):

  ```shell
  <%=cmd%> server upload --sources=@args --src-type=list ~/mysample.file secondfile
  ```

- An [Extended Value](#extended-value-syntax) with type **`Array` of `String`**

> [!TIP]
> An [Extended Value](#extended-value-syntax) can be tested with the command `config echo`

  Examples:

- Using [Extended Value](#extended-value-syntax)

    Create the file list:

    ```shell
    echo ~/mysample.file > myfilelist.txt
    echo secondfile >> myfilelist.txt
    ```

    Use the file list: one path per line:

    ```shell
    --sources=@lines:@file:myfilelist.txt
    ```

- Using JSON array

    ```shell
    --sources=@json:'["file1","file2"]'
    ```

- Using STDIN, one path per line

    ```shell
    --sources=@lines:@stdin:
    ```

- Using Ruby code (one path per line in file)

    ```ruby
    --sources=@ruby:'File.read("myfilelist.txt").split("\n")'
    ```

- `@ts` : the user provides the list of files directly in the `paths` field of transfer spec (option `ts`).
Examples:

  - Using transfer spec

  ```shell
  --sources=@ts --ts=@json:'{"paths":[{"source":"file1"},{"source":"file2"}]}'
  ```

The option `src_type` allows specifying if the list specified in option `sources` is a simple file list or if it is a file pair list.

> [!NOTE]
> Option `src_type` is not used if option `sources` is set to `@ts`

Supported values for `src_type` are:

- `list` : (default) the path of destination is the same as source and each entry is a source file path
- `pair` : the first element is the first source, the second element is the first destination, and so on.

Example: Source file `200KB.1` is renamed `sample1` on destination:

```shell
<%=cmd%> server upload --src-type=pair ~/Documents/Samples/200KB.1 /Upload/sample1
```

#### Source directory structure on destination

This section is not specific to <%=tool%>: it describes `ascp` behavior.

The transfer destination is normally expected to designate a destination folder.

But there is one exception: The destination specifies the new item name when the following are met:

- There is a single source item (file or folder)
- Transfer spec `create_dir` is not set to `true` (`ascp` option `-d` not provided)
- Destination is not an existing folder
- The `dirname` of destination is an existing folder

For this reason, it is recommended to set `create_dir` to `true` for consistent behavior between single and multiple item transfers; this is the default in <%=tool%>.

If a simple source file list is provided (no `destination` in `paths`, that is, no `file_pair_list` provided), the destination folder is used as destination folder for each source file, and source file folder names are not preserved.

The inner structure of source items that are folders is preserved on destination.

A leading `/` on destination is ignored (relative to docroot) unless docroot is not set (relative to home).

In the following table source folder `d3` contains 2 files: `f1` and `d4/f2`.

| Source files    | Destination | Folders on Dest.  | `create_dir` | Destination Files           |
|-----------------|-----|-----|------|-----------------------------------|
| `f1`            | `d/f`       | -                 | false        | Error: `d` does not exist.  |
| `f1`            | `d/f`       | `d`               | false        | `d/f` (renamed)             |
| `f1`            | `d/f/.`     | `d`               | false        | `d/f` (renamed)             |
| `f1`            | `d/f`       | `d/f`             | false        | `d/f/f1`                    |
| `f1` `f2`       | `d`         | `d`               | false        | `d/f1` `d/f2`               |
| `d3`            | `d`         | -                 | false        | `d/f1` `d/f2` (renamed)     |
| `f1`            | `d`         | -                 | true         | `d/f1`                      |
| `f1` `f2`       | `d`         | -                 | true         | `d/f1` `d/f2`               |
| `d1/f1` `d2/f2` | `d`         | -                 | true         | `d/f1` `d/f2`               |
| `d3`            | `d`         | -                 | true         | `d/d3/f1` `d/d3/d4/f2`      |

If a file pair list is provided, then it is possible to rename or specify a different destination folder for each source (relative to the destination).

If transfer spec has a `src_base`, it has the side effect that the simple source file list is considered as a file pair list, and so the lower structure of source folders is preserved on destination.

| Source files      | Destination | `src_base` | Destination Files           |
|-------------------|-------------|------------|-----------------------------|
| `d1/d2/f2` `d1/d3/f3` | `d`     | `d1`       | `d/d2/f2` `d/d3/f3`         |

Advanced Example: Send files `./file1` and `./folder2/files2` to server (for example, `/Upload`) and keep the original file names and folders, that is, send `file1` to `/Upload/file1` and `files2` to `/Upload/folder2/files2`.

- If files are specified as `./file1 ./folder2/files2`,

  then destination will be: `/Upload/file1 /Upload/files2`

- One possibility is to specify a file pair list: `--src-type=pair file1 file1 folder2/files2 folder2/files2`
- Another possibility is to specify a source base (transfer spec parameter `src_base`): `--ts.src_base=$PWD $PWD/file1 $PWD/folder2/files2`

  The `.` path cannot be used as a source base.

- Similarly, create a temporary soft link (Linux): `ln -s . tmp_base` and use `--ts.src_base=tmp_base tmp_base/file1 tmp_base/folder2/files2`
- One can also similarly use `--sources=@ts` and specify the list of files in the `paths` field of transfer spec with both `source` and `destination` for each file.

#### Multi-session transfer

Multi session, that is, starting a transfer of a file set using multiple sessions (one `ascp` process per session) is supported on `direct` and `node` agents, not yet on connect.

- `--transfer=node`

```shell
--ts=@json:'{"multi_session":10,"multi_session_threshold":1}'
```

Multi-session is directly supported by the node daemon.

- `--transfer=direct`

```shell
--ts=@json:'{"multi_session":5,"multi_session_threshold":1,"resume_policy":"none"}'
```

> [!NOTE]
> `resume_policy` set to `attr` may cause problems: `none` or `sparse_csum` shall be preferred.

<%=tool%> starts multiple `ascp` for Multi-session using `direct` agent.

When multi-session is used, one separate UDP port is used per session (refer to `ascp` manual page).

#### Content protection

Content protection (Client-Side Encryption at Rest, CSEAR) ensures that files remain encrypted while stored on the server.
With CSEAR, the client encrypts files during upload and decrypts files during download, using a passphrase known only to the users sharing the files.

- Upload: Files are encrypted on the client side before being sent to the server.
- Download: Files are decrypted on the client side as they are retrieved from the server.

At all times, files remain encrypted on the server; encryption and decryption occur exclusively on the client side.

Activating CSEAR consists of setting transfer spec parameters:

- `content_protection` : activate encryption (`encrypt` for upload) or decryption (`decrypt` for download)
- `content_protection_password` : the passphrase to be used.

Example: parameter to download a Faspex package and decrypt on the fly

```shell
--ts=@json:'{"content_protection":"decrypt","content_protection_password":"<%=ph :password%>"}'
```

> [!NOTE]
> Faspex 5 requires package parameter `ear_enabled` set to `true` for CSEAR.
> In that case the transfer spec parameter `content_protection` is automatically set.
> `content_protection_password` is then required in all cases.

#### Transfer Spec Examples

- Change target rate

```shell
--ts=@json:'{"target_rate_kbps":500000}'
```

- Override the FASP SSH port to a specific TCP port:

```shell
--ts=@json:'{"ssh_port":33002}'
```

- Force HTTP fallback mode:

```shell
--ts=@json:'{"http_fallback":"force"}'
```

- Activate progress when not activated by default on server

```shell
--ts=@json:'{"precalculate_job_size":true}'
```

### Transfer progress bar

File transfer operations are monitored, and a progress bar is displayed on the standard error if option `progress_bar` (`Bool`) is set to `yes` (default if the standard error is a terminal).
So, the progress bar is displayed even if the output of the command is redirected to a file.

The same progress bar is used for any type of transfer: using `ascp`, server to server, using HTTPS, and so on.

It shows the elapsed time, the percentage, the rate in megabits per second (`Mbps`, 1,000,000 bits per second, averaged over the last 5 seconds) and the estimated remaining time.
As long as the total size is not known (for example, when the job size is not pre-calculated), the transferred size is shown instead of the percentage.
For multi-session transfers, sessions are aggregated, and the number of running sessions is shown in brackets.
Files already at destination (resumed transfer) count in the progress, but not in the rate.
If the transfer fails, the progress bar stops at the reached progress, and shows `failed`.
Log lines are displayed above the progress bar.

Agent `direct` can display the native progress bar of `ascp` instead (see [`direct`](#agent-direct)).

### Scheduler

<%=tool%> does not include a built-in scheduler.
Automated execution should therefore rely on operating system facilities.

Two common execution modes are supported:

- Scheduled execution: run <%=tool%> commands periodically.

- Daemon/service mode: run <%=tool%> continuously as a server.

#### Creating a wrapping script

Before configuring scheduling or services, it is often useful to create a wrapper script that prepares the environment and optionally enforces execution limits.

This script may:

- Configure environment variables (PATH, Ruby, and so on)

- Enforce a maximum runtime

- Centralize command options

**Example** (Linux)

```shell
#!/bin/bash
# Load the Ruby environment if required
# Forward arguments to <%=cmd%> and ensure it does not exceed 30 min execution
exec timeout 30m <%=cmd%> "${@}"
```

Save as:

```shell
/home/xfer/bin/<%=cmd%>_tool
```

Then, make it executable.

#### Windows: Scheduler

Windows provides the [Task Scheduler](https://docs.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page).

Tasks can be configured using:

- [`schtasks.exe`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create)

- PowerShell module [`ScheduledTasks`](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks)

- `taskschd.msc` (UI)

By default, Windows Task Scheduler prevents overlapping executions.

#### Linux: `systemd` Timer

Most modern Linux distributions use `systemd` which provides scheduling via [`timer`](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) units.
Define a name for the job, for example: `<%=cmd%>_job` as `<%=ph :name%>` below.

1. Create the service

    `/etc/systemd/system/<%=ph :name%>.service`

    ```ini
    [Unit]
    Description=Run <%=cmd%> preview scan

    [Service]
    Type=oneshot
    ExecStart=/home/xfer/bin/<%=cmd%>_tool preview scan --logger=syslog --out.level=error
    User=xfer
    Group=xfer
    ```

1. Create the timer (same base name)

    `/etc/systemd/system/<%=ph :name%>.timer`

    ```ini
    [Unit]
    Description=Hourly execution of <%=ph :name%>

    [Timer]
    OnCalendar=hourly
    AccuracySec=1min
    Persistent=true

    [Install]
    WantedBy=timers.target
    ```

1. Enable the timer

    ```shell
    sudo systemctl daemon-reload
    sudo systemctl enable --now <%=ph :name%>.timer
    ```

Check status:

```shell
systemctl status <%=ph :name%>.timer
```

```shell
systemctl list-timers | grep <%=ph :name%>
```

Run service once to test:

```shell
sudo systemctl start <%=ph :name%>.service
```

#### Linux: `cron` Scheduler

Unix-like systems also provide [`cron`](https://www.man7.org/linux/man-pages/man5/crontab.5.html).

Example of `crontab` for user `xfer`.

```shell
crontab<<EOF
0    * * * *  /home/xfer/bin/<%=cmd%>_tool preview scan --logger=syslog --out.level=error
2-59 * * * *  /home/xfer/bin/<%=cmd%>_tool preview trevents --logger=syslog --out.level=error
EOF
```

Linux also provides `anacron` for daily or hourly jobs that must run even if the system was previously offline.

> [!NOTE]
> Logging options are specified directly in the `cron` entry so command output remains visible when running the command manually.

#### Running as system service (Daemon mode)

Some commands run continuously (for example, listening on a network port).
In this case, it is recommended to run <%=tool%> as a system service.

On Linux this is typically done using [`systemd`](https://systemd.io/).

For example, below `<%=ph :name%>` is `<%=cmd%>_svc`.

A [wrapping script](#creating-a-wrapping-script), again, is convenient: `/usr/local/bin/start_<%=ph :name%>.sh`:

Service definition at `/etc/systemd/system/<%=ph :name%>.service`:

```ini
[Unit]
Description=My <%=cmd%> daemon
After=network.target

[Service]
ExecStart=/usr/local/bin/start_<%=ph :name%>.sh
Restart=on-failure
RestartSec=15
User=xfer
# Optional, specify a working directory
# WorkingDirectory=/path/to/working/dir
# Optional, redirect output
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Enable and start:

```shell
sudo systemctl daemon-reload
sudo systemctl enable --now <%=ph :name%>.service
systemctl status <%=ph :name%>.service
journalctl -u <%=ph :name%>.service
```

#### Preventing Concurrent Execution

When running scheduled jobs, it may be necessary to ensure that only one instance of <%=tool%> runs at a time.

This avoids situations such as:

- Multiple instances accumulating and overloading the system

- Duplicate transfers

- Duplicate `preview` outputs

##### Option: `lock_port`

<%=tool%> provides a built-in locking mechanism via the `lock_port` option.

- `lock_port` prevents concurrent executions of the same command.

- If another instance is already running and holding the specified port, the new execution exits immediately.

Under the hood, this works by opening a local TCP server port.
If the port is already in use, the process fails, effectively acting as a local lock.
The lock is released automatically when the process exits.

> [!NOTE]
> When using <%=tool%> in containers, `lock_port` only works within the same container.
> Each container has its own network namespace, so the lock does not apply across containers.

Example: Test <%=tool%> locking by running this command in two separate terminals within 30 seconds:

```shell
<%=cmd%> config echo @ruby:'sleep 30' --lock-port=12345
```

- The first instance will sleep for 30 seconds.

- The second instance will exit immediately with:

```text
WARN -- : Another instance is already running (Address already in use - bind(2) for "127.0.0.1" port 12345).
```

##### OS-based concurrency protection

Operating system schedulers also provide protection against overlapping runs.

- Windows Task Scheduler prevents concurrent runs by default.
- Linux `cron` can leverage [`flock`](https://man.cx/flock%281%29) to achieve the same effect:

```shell
/usr/bin/flock -w 0 /var/cron.lock <%=cmd%> ...
```

- `systemd` avoids overlaps when scheduling a `Type=oneshot` service.

```ini
[Unit]
Description=My <%=cmd%> daemon
...

[Service]
ExecStart=/usr/local/bin/start_<%=ph :name%>.sh
Type=oneshot
RemainAfterExit=yes
...
```

> [!NOTE]
> Systemd timers can schedule this service and ensure no overlapping runs occur.

### "Proven&ccedil;al"

`ascp`, the underlying executable implementing Aspera file transfer using FASP, has a capability to not only access the local file system (using system's `open`,`read`,`write`,`close` primitives), but also to do the same operations on other data storage such as S3, Hadoop and others.
This mechanism is called **PVCL** (from **Proven&ccedil;al**, a restaurant located in Sophia Antipolis).
Several **PVCL** adapters are available, one is embedded in `ascp`, the others are provided in shared libraries and must be activated.

The list of supported **PVCL** adapters can be retrieved with command:

```shell
<%=cmd%> config ascp info --fields=@re:'^pvcl'
```

```text
process v1
shares v1
noded v1
faux v1
file v1
stdio v1
stdio-tar v1
```

The output shows the adapters: `process`, `shares`, `noded`, `faux`, `file`, `stdio`, `stdio-tar`.

Those adapters can be used wherever a file path is used in `ascp` including configuration.
They act as a **pseudo drive**.

The simplified format is:

```shell
<%=ph :adapter%>:///<%=ph :sub_file_path%>?<%=ph :arg1%>=<%=ph :val1%>&...
```

One of the adapters, used in this manual, for testing, is `faux`.
It is a pseudo file system allowing generation of file data without actual storage (on source or destination).

Other PVCL modules exist and are implemented in shared libraries.
Those libraries are available only on HSTS.
To activate a PVCL library, place the corresponding shared library in the same folder as `ascp`.

Example:

```shell
cp /opt/aspera/lib/pvcl/libpvcl_cloud.so $(<%=cmd%> config ascp info --fields=root)
```

Then check available modules as shown previously (`ascp info`).

### `faux:` for testing

This adapter can be used to simulate a file or a directory.
This is a feature of `ascp`, not <%=tool%>.
The following is an extract of the man page of `ascp`.

To discard data at the destination, the destination argument is set to `faux://`.

To send uninitialized data in place of an actual source file, the source file is replaced with an argument of the form:

```shell
faux:///filename?filesize
```

Where:

- `filename` is the name that will be assigned to the file on the destination
- `filesize` is the number of bytes that will be sent (in decimal).

> [!NOTE]
> Characters `?` and `&` are shell special characters (wildcard and background), so `faux` file specification on command line should be protected (using quotes or `\`).
> If not, the shell may give error: `no matches found` or equivalent.

For all sizes, a suffix can be added (case-insensitive) to the size: k, m, g, t, p, e (values are powers of 2, for example, 1M is 2<%=pow 20%>, that is, 1 mebibyte, not megabyte).
The maximum allowed value is 8\*2<%=pow 60%>.
Extremely large `faux` file sizes (petabyte range and above) will likely fail due to lack of destination storage unless destination is `faux://`.

To send uninitialized data in place of a source directory, the source argument is replaced with an argument of the form:

```shell
faux:///dirname?<%=ph :arg1%>=<%=ph :val1%>&...
```

Where:

- `dirname` is the folder name and can contain `/` to specify a subfolder.
- Supported arguments are:

| Name     | Type   | Description                                                    |
|----------|--------|----------------------------------------------------------------|
| count    | int    | Number of files<%=br%>Mandatory |
| file     | string | Basename for files<%=br%>Default: `file` |
| size     | int    | Size of first file.<%=br%>Default: 0 |
| inc      | int    | Increment applied to determine next file size<%=br%>Default: 0 |
| seq      | enum   | Sequence in determining next file size<%=br%>Values: `random`, `sequential`<%=br%>Default: `sequential` |
| buf_init | enum   | How source data is initialized<%=br%>Option `none` is not allowed for downloads.<%=br%>Values:`none`, `zero`, `random`<%=br%>Default:`zero` |

The sequence parameter is applied as follows:

- If `seq` is `random` then each file size is:

  - `size +/- (inc * rand())`
  - Where rand is a random number between 0 and 1
  - File size must not be negative; `inc` is set to `size` if it is greater than `size`.
  - Similarly, overall file size must be less than 8\*2<%=pow 60%>.
  If size + inc is greater, inc will be reduced to limit size + inc to 7\*2<%=pow 60%>.

- If `seq` is `sequential` then each file size is:

  - `size + ((file_index - 1) * inc)`
  - Where first file is index 1
  - So file1 is `size` bytes, file2 is `size + inc` bytes, file3 is `size + inc * 2` bytes, and so on
  - As with `random`, `inc` will be adjusted if `size + (count * inc)` is not less than 8\*2<%=pow 60%>.

Filenames generated are of the form: `<%=ph :file%>_<00000 ... count>_<%=ph :filesize%>`

Examples:

- Upload 20 gibibytes of generated data to file `myfile` in directory `/Upload`

```shell
<%=cmd%> server upload faux:///myfile\?20g --to-folder=/Upload
```

- Upload a file /tmp/sample but do not save results to disk (no docroot on destination)

```shell
<%=cmd%> server upload /tmp/sample --to-folder=faux://
```

- Upload a faux directory `mydir` containing 1 million files, sequentially with sizes ranging from 0 to 2 Mebibyte - 2 bytes, with the base name of each file being `testfile` to /Upload

```shell
<%=cmd%> server upload "faux:///mydir?file=testfile&count=1m&size=0&inc=2&seq=sequential" --to-folder=/Upload
```

- Upload a faux directory `mydir` containing 1000 files, of size 1 byte, with the base name of each file being `testfile` to /Upload

```shell
<%=cmd%> server upload "faux:///mydir?file=testfile&count=1000&size=1" --to-folder=/Upload
```

### `file:` for growing files

A growing file is a file that another program is still writing during the transfer, for example a live recording, a log file, or a stream capture.
The built-in `file` PVCL adapter of `ascp` transfers such a file: `ascp` sends the data as the file grows, and completes the transfer when the file stops changing.
This is a feature of `ascp`, not <%=tool%>.

For more information, see the [HSTS `ascp` command reference](https://www.ibm.com/docs/en/ahts/4.4.x?topic=line-ascp-command-reference).

#### Syntax of the `file:` URI

To transfer a growing file, specify the source file as a `file:` URI that contains the `grow` parameter:

```shell
file:///<%=ph :path%>?grow=<%=ph :wait_time%>[&<%=ph :parameter%>=<%=ph :value%>...]
```

The path of the file follows the prefix `file:///`:

| Path     | Example URI                        | File                             |
|----------|------------------------------------|----------------------------------|
| Relative | `file:///live.log?grow=60`         | `live.log` in the current folder |
| Absolute | `file:////var/log/app.log?grow=60` | `/var/log/app.log`               |

An absolute path starts with `/`, so the URI of an absolute path contains four slashes.

The URI supports the following parameters:

| Parameter       | Description |
|-----------------|----------------------------------------------------------------|
| `grow`          | Wait time, in seconds: the transfer completes when the file does not change during this time.<%=br%>Required.<%=br%>If the value is not a number, for example `grow=default`, the wait time is 10 seconds. |
| `wait_start`    | Start of the wait time:<%=br%>- `mtime`: the last modification time of the file.<%=br%>- `null_read`: the time when `ascp` reaches the end of the file, that is, when a read of the file returns no data.<%=br%>Default: `mtime` |
| `confirm_stop`  | If `true`, the program that writes the file confirms the end of the file. See [Confirming the end of a growing file](#confirming-the-end-of-a-growing-file).<%=br%>Ignored if `wait_start` is `null_read`.<%=br%>Default: `false` |
| `max_grow_size` | Maximum size of the file, in bytes.<%=br%>Accepts the suffixes `k`, `m`, `g`, `t`, `p`, and `e` (powers of 1024).<%=br%>Default: 2<%=pow 63%> - 1 bytes, or the maximum file size of the file system if lower. |

> [!IMPORTANT]
> The growing file must be on a native file system, that is, a file system that the operating system accesses directly.

> [!TIP]
> On the command line, enclose the URI in single quotes: the characters `?` and `&` have a special meaning for the shell.

#### Completion of the transfer

`ascp` sends the data as the program writes it.
When `ascp` has sent all the data that the file contains, it starts to count the wait time.
If the file grows during the wait time, `ascp` sends the new data and starts to count the wait time again.
When the wait time ends without a change to the file, the transfer completes.

As a result:

- The command completes after the wait time that follows the last write.
  For example, with `grow=120`, the command completes about 2 minutes after the program stops writing.
- If the program pauses for longer than the wait time, the transfer completes before the end of the file, and the destination file is incomplete.
  Set a wait time that is longer than the longest pause of the program.

To complete the transfer without waiting, use `confirm_stop`.

#### Confirming the end of a growing file

With `confirm_stop=true`, the program that writes the file signals the end of the file, so the transfer does not wait.

1. Start the transfer with `confirm_stop=true` and a wait time that is longer than the longest pause of the program:

   ```shell
   <%=cmd%> server upload live.log --ts.source_root='file:///?grow=600&confirm_stop=true' --to-folder=/Upload
   ```

2. When the program finishes writing the file, set the modification time of the file to a time earlier than the wait time.
   For example:

   ```shell
   touch -t 200001010000 live.log
   ```

   The transfer completes immediately.

> [!IMPORTANT]
> With `confirm_stop=true`, if the wait time ends before the program sets the modification time, `ascp` considers the file invalid and the transfer fails.

To report an error in the file, with or without `confirm_stop`, the program sets the modification time of the file to 0, that is, `1970-01-01 00:00:00 UTC`.
`ascp` then fails the transfer of the file.
For example:

```shell
TZ=UTC touch -t 197001010000 live.log
```

#### Uploading a growing file

`ascp` activates the growing file mode only if it finds the `grow` parameter in one of the following locations:

- The first source on its command line.
- The source prefix: `ascp` option `--source-prefix`, set by transfer spec parameter `source_root`.
- The docroot of the transfer user, on the server.

`ascp` does not look for the `grow` parameter in a file list.
By default, the [`direct`](#agent-direct) agent provides the sources to `ascp` in a file list.
As a result, if you specify a `file:` URI as a source with the default options, the transfer fails with the error `Session initiation failed, fail to set pvcl`.

Use one of the following methods.
The examples use the [`direct`](#agent-direct) agent.

- **Set the URI as source prefix** (recommended)

  Set transfer spec parameter `source_root` to a `file:` URI that contains the folder of the files and the parameters.
  Specify the sources as paths relative to this folder.
  `ascp` inserts each source path before the parameters: for example, `file:////var/log?grow=120` and `app.log` give `file:////var/log/app.log?grow=120`.
  All the files of the transfer use the same parameters.

  To upload `live.log` from the current folder:

  ```shell
  <%=cmd%> server upload live.log --ts.source_root='file:///?grow=120' --to-folder=/Upload
  ```

  To upload `/var/log/app.log`:

  ```shell
  <%=cmd%> server upload app.log --ts.source_root='file:////var/log?grow=120' --to-folder=/Upload
  ```

- **Set the URI as source on the command line**

  Set transfer parameter `file_list` to `false`, so that <%=tool%> places the source on the `ascp` command line instead of in a file list.
  Use this method for a single file.

  ```shell
  <%=cmd%> server upload 'file:///live.log?grow=120' --to-folder=/Upload --transfer.file_list=false
  ```

> [!TIP]
> To display the native progress bar of `ascp` instead of the progress bar of <%=tool%>, add `--transfer.quiet=false`.

#### Downloading a growing file

For a download, the growing file is on the server.
The transfer user on the server usually has a docroot, and the server does not resolve a `file:` URI from the client in this docroot: the transfer fails with the error `No such file or directory`.
Instead, the server administrator sets the parameters in the docroot of the transfer user.
For example, on the server:

```shell
asconfigurator -x 'set_user_data;user_name,xfer_live;absolute,file:////data/live?grow=120'
```

Then, the client downloads the file with a path relative to the docroot, as for any other file:

```shell
<%=cmd%> server download live.log --to-folder=.
```

All the transfers of this user are then growing file transfers, so use a dedicated transfer user.
This method also applies to transfers that use a token, for example with the Node API or Aspera on Cloud: for a download with a token, `ascp` does not accept a `file:` URI as source prefix.

If the transfer user has no docroot and the transfer does not use a token, you can also use the upload methods, with absolute paths on the server.

### Usage

```text
<%=cmd%> -h
<%=include_usage%>

```

### Bulk creation and deletion of resources

Bulk creation and deletion of resources are possible using option `bulk` (`yes`,`no`(default)).
In that case, the operation expects an `Array` of `Hash` instead of a simple `Hash` using the [Extended Value](#extended-value-syntax) syntax.
This option is available only for some resources: if you need it, try and see if the entities you create or delete support this option.

### Plugins

<%=tool%> uses a plugin mechanism.
The first level command (just after <%=tool%> on the command line) is the name of the concerned plugin which will execute the command.
Each plugin usually represents commands sent to a specific application.
Available plugins can be found using command:

```shell
<%=cmd%> config plugins list
```

```text
╭────────┬────────┬────────┬───────────┬─────────────────────────────────────────────────╮
│ plugin │ detect │ wizard │ status    │ path                                            │
╞════════╪════════╪════════╪═══════════╪═════════════════════════════════════════════════╡
│ shares │ ✓      │ ✓      │ available │ .../aspera-cli/lib/aspera/plugins/shares        │
│ node   │ ✓      │ ✓      │ available │ .../aspera-cli/lib/aspera/plugins/node          │
...
╰────────┴────────┴────────┴───────────┴─────────────────────────────────────────────────╯
```

Column `status` is `available`, or the reason why the plugin cannot be used (e.g. `missing gem <gem>`).
Details of one plugin (source, form, capabilities, dependencies, gems, security level):

```shell
<%=cmd%> config plugins show node
```

Most plugins will take the URL option: `url` to identify their location.

REST APIs of Aspera legacy applications (Aspera Node, Shares, Console, Orchestrator) use simple username/password authentication: HTTP Basic Authentication using options: `username` and `password`.

Aspera on Cloud and Faspex 5 rely on OAuth.

Plugins are looked up in the folder of the gem (built-in plugins), and in the folders of option `plugin_folder` (list):

- By default (`DEF`): folder `plugins` of the configuration folder (option `home`).
- Folders given replace the default, which can still be included with the special value `DEF`.
- Each use of the option appends to the list: `--plugin-folder=DEF --plugin-folder=<FOLDER>`. A plugin of a folder later in the list has priority over one of the same name.
- `--plugin-folder=@json:[]`: no folder other than the one of the gem.

The folders of option `plugin_folder`:

```shell
<%=cmd%> --show-config --fields=plugin_folder
```

You can create the skeleton of a new plugin like this:

```shell
<%=cmd%> config plugins create foo .
```

```text
Created ./foo.rb
```

```shell
<%=cmd_skip%> --plugin-folder=. foo
```

#### Writing a plugin

A plugin is, in a plugin folder (option `plugin_folder`, by default folder `plugins` of the configuration folder), either a Ruby file (this section), or a folder with a manifest, for a plugin with several files, a transfer agent or schemas (see [Writing a plugin bundle](#writing-a-plugin-bundle)).

- **Name**: the file name is the plugin name, which is the first command, e.g. file `my_app.rb` for command `my_app`.
  The file defines class `Aspera::Cli::Plugins::<Class>`, the name in CamelCase (`MyApp`), subclass of `Base` (`aspera/cli/plugins/base`).
  For common options, the class includes one of these modules (`include <Module>`):
  - `BasicAuth` (`aspera/cli/plugins/basic_auth`): options `url`, `username`, `password`, method `basic_auth_api` returns a REST client with HTTP Basic authentication.
  - `Oauth` (`aspera/cli/plugins/oauth`): options of `BasicAuth`, and `auth` (default `jwt`), `client_id`, `client_secret`, `redirect_uri`, `private_key`, `passphrase`.
- **Requires**: the plugin requires the files of the gem that it uses, e.g. `require 'aspera/cli/plugins/base'` (the `lib` folder of the gem is in the Ruby load path).
  Built-in plugins load only what they use: a class or module of the gem (for example `Plugins::Oauth`, `Rest::Client`) may not be loaded yet when the plugin is read (`NameError: uninitialized constant`).
- **Options**: `option :<name>, description: '...'` (optional: `default:`, `allowed:` a type or a list of values), value read with `options.get_option(:<name>)` (`mandatory: true` to require it).
  `use_options <Module>` adds the options of a module, e.g. `use_options OauthWebOptions` (`client_id`, `client_secret`, `redirect_uri`) for the OAuth web flow only, without the other options of `Oauth`.
  In the help, the options of `use_options` and of an included module (`BasicAuth`, `Oauth`) are listed in the order of these lines in the class.
- **Commands**: `command :<name>, description: '...'`, inside `commands_under :<name> do ... end` for sub-commands.
  Positional arguments: `arguments: [{name: :<name>, description: '...'}]` (optional: `mandatory: false`, `default:`, `type: Hash`, `multiple: true`).
  An argument that is a local path adds `complete: :file` (or `:folder`) for shell completion, and then `access:` so the path is checked against the [Security Level](#security-level): `:read` (the command reads it), `:write` (the command writes it), or `:none` (not a local path read or written by <%=tool%>, for example a remote path, or a path given to another program).
  `read_only: true` for a command that changes nothing (allowed with option `poll`).
- **Actions**: the method `action_<command path>`, e.g. `action_item_show` for `item show`, receives the arguments as keyword arguments (and `**` for others).
  It returns a result, displayed according to option `format`: `Result::SingleObject.new(<Hash>)`, `Result::ObjectList.new(<Array of Hash>)`, `Result::Status.new('<text>')`, `Result::Nothing.new`.
- **REST**: `Rest::Client.new(base_url:, auth:)` (`aspera/rest`), methods `read`, `create`, `update`, `delete` (JSON), and `call` for other cases:
  - `auth`: `{type: :basic, username:, password:}`, or `{type: :oauth2, grant_method: :web, client_id:, ...}` (see `lib/aspera/oauth/client`).
    Parameters `path_authorize` and `path_token` are paths from `base_url`, or absolute URLs, when the token is created on another host than the authorization page.
    Parameter `token_field` is the field of the token in the answer (default `access_token`), or a dot-separated path of a nested field, e.g. `authed_user.access_token` for a Slack user token.
  - Raw body, e.g. binary, sent as is: `call(operation: 'PUT', body: <String or IO>, headers: {'Content-Type' => '<MIME_TYPE>'})`.
    An `IO` (e.g. `File.open(path, 'rb')`) is streamed from its current position, without loading the file in memory.
- **Errors**: raise `Cli::BadArgument` (wrong argument or option) or `Cli::Error`.
  For any other error, the location in the plugin (file and line) is logged at level `info`.
- **Security**: a plugin is code: plugins from other folders than the gem are loaded at [Security Level](#security-level) `low` only.

Example: plugin `my_app` for a REST API with Basic authentication: `my_app info`, `my_app item list`, `my_app item show <ID>`.

```ruby
# Plugin `my_app`, file `my_app.rb` in a plugin folder, class `MyApp`
# Files of the gem used by the plugin (its `lib` folder is in the load path)
require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Cli
    module Plugins
      class MyApp < Base
        # Options `url`, `username` and `password`, method `basic_auth_api`
        include BasicAuth

        application_name 'My Application'
        option :page_size, description: 'Number of items per page', allowed: Integer, default: 100

        command :info, description: 'Show application information', read_only: true
        commands_under :item, description: 'Manage items' do
          command :list, description: 'List items', read_only: true
          command :show, description: 'Show an item', arguments: [{name: :id, description: 'Item identifier'}], read_only: true
        end

        # Command `info`
        def action_info(**) = Result::SingleObject.new(api.read('info'))

        # Command `item list`
        def action_item_list(**) = Result::ObjectList.new(api.read('items', {limit: options.get_option(:page_size)}))

        # Command `item show <ID>`, with arguments as keyword arguments
        def action_item_show(id:, **) = Result::SingleObject.new(api.read("items/#{id}"))

        private

        # REST client of the application, with Basic authentication
        def api = @api ||= basic_auth_api
      end
    end
  end
end
```

```shell
<%=cmd_skip%> --plugin-folder=<FOLDER> my_app item list --url=https://app.example.com/api --username=<USERNAME> --password=<PASSWORD> --page-size=10
```

#### Writing a plugin bundle

A bundle is a folder `<name>/` of a plugin folder, with a manifest `plugin.yaml`: the built-in plugins (`aoc`, `node`, `transferd`, ...) are bundles, in `lib/aspera/plugins/<name>/` of the gem.
A single file stays the simplest form, for a plugin that has commands only.
The manifest is data: reading it never runs code of the bundle, and `config plugins list` and `config plugins show <NAME>` show the plugin, also when it is unavailable (invalid manifest, missing dependency), with the reason.

```text
<PLUGIN_FOLDER>/my_app/
  plugin.yaml     manifest
  commands.rb     class Aspera::Plugins::MyApp::Commands: top level command `my_app`
  <other>.rb      other files, declared in the manifest if the manifest loads them
  schemas/        schemas (JSON or YAML), declared in the manifest
```

- **Names**: the name of the folder is the name of the plugin, and the field `name` of the manifest: lower case letters, digits and `_`, starting with a letter.
  A file `<file>.rb` of the bundle defines the constant `Aspera::Plugins::<Name>::<Const>`, where `<Name>` is the name in CamelCase (`MyApp`): `commands.rb` defines `Commands`, a subclass of `Cli::Plugins::Base`, as a single file, with `include Cli::Plugins::BasicAuth` or `Oauth` for the common options.
  Constants in the manifest (`class`, `module`) are relative to `Aspera::Plugins::<Name>`, file names to the folder of the bundle (no `..`, no hidden file).
- **Same name**: for a name that is both a file `<name>.rb` and a folder `<name>/` of the same plugin folder, the bundle is used, with a warning.
- **Requires**: as for a single file, the code requires the files of the gem that it uses.
  The code is loaded when the plugin is used (command, agent, service), not when it is listed.
- **Options**: as for a single file.
  `option <NAME>, before: <OTHER>` places an option before another one in the help, also an option of a module mounted on another plugin (e.g. before `smtp` of `config`).
  An option placed `before:` an unknown option, or in a cycle of `before:`, goes at the end, with a warning in the log: the other options and the commands work.

Manifest `plugin.yaml` (schema `lib/aspera/plugin.schema.yaml`: no other field than these, at each level):

| Field | Default | Content |
| --- | --- | --- |
| `name` | (mandatory) | Name of the plugin, same as the folder |
| `title` | (mandatory) | Name of the product, in the lists and in the instructions of `mcp server` |
| `mcp` | none | Section added to the instructions of `mcp server` for the AI client, about the use of the plugin (e.g. development guides). `%{<POINT>}` is replaced by the list of the entries of the extension point `<POINT>`: the field `name` of each entry, with the title of its bundle, so the schema of an extension point used this way requires `name` |
| `depends` | `[]` | Bundles that this one uses. If one is missing or unavailable, this bundle is unavailable |
| `gems` | `[]` | Optional gems required by the code, checked when the code is loaded: the error tells `gem install <GEM>` |
| `commands` | `false` | `true`: `commands.rb` defines `Commands`, the top level command `<name>` |
| `schemas` | `[]` | Schemas added to the registry: `key` (unique), `file`, `owned` (default `false`: schema of a vendor API, not used to check values), `source` (`url`, `version` of a downloaded schema, used by `rake tools:openapi`) |
| `extension_points` | `[]` | Points that other bundles extend: `name`, `schema` (file: schema of one entry) |
| `extensions` | `{}` | Entries for the extension points of other bundles, by name of point: `file` and `class` of the code, and the fields defined by the schema of the point |
| `mounts` | `[]` | Modules added to the commands of another plugin: `target` (plugin name), `file`, `module` |
| `services` | `[]` | Objects shared through the context, created on first use: `name`, `file`, `class` |

A bundle can add a transfer agent: the built-in bundle `xfer` declares the extension point `agent`. An entry has `name` (value of option `transfer`), `short` (one letter, unique), `file`, `class` (subclass of `Aspera::Agent::Base`) and `options_schema` (schema file of the parameters of the agent):

```yaml
name: my_agent
title: My transfer agent
depends:
  - xfer
extensions:
  agent:
    - name: my_agent
      short: m
      file: agent.rb
      class: Agent
      options_schema: schemas/agent_options.yaml
```

Example: bundle `my_app`, the same plugin as above, in folder `<PLUGIN_FOLDER>/my_app/`.

File `plugin.yaml`:

```yaml
name: my_app
title: My Application
commands: true
mcp: >-
  Use `my_app` to manage the items of My Application.
```

File `commands.rb`:

```ruby
# Files of the gem used by the plugin (its `lib` folder is in the load path)
require 'aspera/cli/plugins/base'
require 'aspera/cli/plugins/basic_auth'

module Aspera
  module Plugins
    module MyApp
      # Top level command `my_app`
      class Commands < Cli::Plugins::Base
        # Options `url`, `username` and `password`, method `basic_auth_api`
        include Cli::Plugins::BasicAuth

        application_name 'My Application'
        option :page_size, description: 'Number of items per page', allowed: Integer, default: 100

        command :info, description: 'Show application information', read_only: true
        commands_under :item, description: 'Manage items' do
          command :list, description: 'List items', read_only: true
          command :show, description: 'Show an item', arguments: [{name: :id, description: 'Item identifier'}], read_only: true
        end

        # Command `info`
        def action_info(**) = Cli::Result::SingleObject.new(api.read('info'))

        # Command `item list`
        def action_item_list(**) = Cli::Result::ObjectList.new(api.read('items', {limit: options.get_option(:page_size)}))

        # Command `item show <ID>`, with arguments as keyword arguments
        def action_item_show(id:, **) = Cli::Result::SingleObject.new(api.read("items/#{id}"))

        private

        # REST client of the application, with Basic authentication
        def api = @api ||= basic_auth_api
      end
    end
  end
end
```

```shell
<%=cmd_skip%> --plugin-folder=<FOLDER> config plugins show my_app
<%=cmd_skip%> --plugin-folder=<FOLDER> my_app item list --url=https://app.example.com/api --username=<USERNAME> --password=<PASSWORD> --page-size=10
```

### Plugins vs Transfer Agents

Plugins typically represent a specific remote application on which <%=tool%> can operate, while transfer agents are the underlying components that handle the actual data transfer.

A given remote application can sometimes be both a plugin and a transfer agent.
For example: `node` and `httpgw` are both plugins and transfer agents.

A plugin is invoked as the first positional argument in a command line.
A Transfer Agent is used by setting the option `transfer` (for example, `--transfer=node`).

### Command line parsing, Special Characters

<%=tool%> is typically executed in a shell, either interactively or in a script.
<%=tool%> receives its arguments on the command line.
The way arguments are parsed and provided to <%=tool%> depends on the operating system and shell.

#### Shell parsing for Unix-like systems: Linux, macOS, AIX

Linux command line parsing is well-defined:
It is fully documented in the shell's documentation.

On Unix-like environments, this is typically a POSIX-like shell (`bash`, `zsh`, `ksh`, `sh`).
A c-shell (`csh`, `tcsh`) or other shell can also be used.
In this environment, the shell parses the command line, possibly replacing variables, and so on.
See [bash shell operation](https://www.gnu.org/software/bash/manual/bash.html#Shell-Operation).
The shell builds the list of arguments and then `fork`/`exec` Ruby with that list.
Ruby receives the list of command line arguments from the shell and gives it to <%=tool%>.
Special character handling (quotes, spaces, env vars, ...) is handled by the shell for any command executed.

#### Shell parsing for Windows

On Windows, command line parsing first depends on the shell used (see next sections).
MS Windows command line parsing differs from Unix-like systems because Windows does not provide a list of arguments to the executable (Ruby): it provides the whole command line as a single string, but the shell may interpret some special characters.

So command line parsing is not handled by the shell (`cmd.exe`), not handled by the operating system, but it is handled by the executable (Ruby).
Typically, Windows executables use the [Microsoft library for this parsing](https://learn.microsoft.com/en-us/cpp/cpp/main-function-command-line-args).

As far as <%=tool%> is concerned: the executable is Ruby.
It has its own parsing algorithm, close to a Linux shell parsing.

Thankfully, <%=tool%> provides a command to check the value of an argument after parsing: `config echo`.
One can also run <%=tool%> with option `--log-level=debug` to display the command line after parsing.

It is also possible to display arguments received by Ruby using this command:

```batchfile
C:> ruby -e 'puts ARGV' "Hello World" 1 2
```

```text
Hello World
1
2
```

> [!NOTE]
> Use `pp` instead of `puts` to display as Ruby `Array`.

Once the shell has dealt with the command line "special" characters for it, the shell calls Windows' `CreateProcess` with the whole command line as a single string.
(Unlike Unix-like systems where the command line is split into arguments by the shell.)

It's up to the program to split arguments:

- [Windows: How Command Line Parameters Are Parsed](https://daviddeley.com/autohotkey/parameters/parameters.htm#RUBY)
- [Understand Quoting and Escaping of Windows Command Line Arguments](https://web.archive.org/web/20190316094059/http://www.windowsinspired.com/understanding-the-command-line-string-and-arguments-received-by-a-windows-program/)

<%=tool%> is a Ruby program, so Ruby parses the command line (received with `GetCommandLineW`) into arguments and provides them to the Ruby code (`$0` and `ARGV`).
Ruby vaguely follows the Microsoft C/C++ parameter parsing rules.
(See `w32_cmdvector` in Ruby source [`win32.c`](https://github.com/ruby/ruby/blob/master/win32/win32.c#L1766)):

- Space characters: split arguments (space, tab, newline)
- Backslash: `\` escapes a single special character
- Globbing characters: `*?[]{}` for file globbing
- Double quotes: `"`
- Single quotes: `'`

#### Shell parsing for Windows: `cmd.exe`

The following examples give the same result on Windows using `cmd.exe`:

- Single quote protects the double quote

  ```batchfile
  <%=cmd%> config echo @json:'{"url":"https://..."}'
  ```

- Triple double quotes are replaced with a single double quote

  ```batchfile
  <%=cmd%> config echo @json:{"""url""":"""https://..."""}
  ```

- Double quote is escaped with backslash within double quotes

  ```batchfile
  <%=cmd%> config echo @json:"{\"url\":\"https://...\"}"
  ```

`cmd.exe` handles some special characters: `^"<>|%&`.
It handles I/O redirection (`<>|`), shell variables (`%`), and multiple commands (`&`).
Eventually, all those special characters are removed from the command line unless escaped with `^` or `"`.
`"` are kept and given to the program.

#### Shell parsing for Windows: PowerShell

For PowerShell, the behavior depends on the version (5.1, 7.3+).

A difficulty is that PowerShell parses the command line for its own use and manages special characters, but then it passes the command line to the program (Ruby) as a single string, possibly without the special characters.
If not using PowerShell features (for example, variables), one can use the "stop-parsing" token `--%`.

Details can be found here:

- [Passing arguments with quotes](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing#passing-arguments-that-contain-quote-characters)

- [Quoting rules](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules)

##### PowerShell 5

- Check your PowerShell version:

```powershell
$psversiontable.psversion.Major
```

```text
5
```

The following examples give the same result on Windows using PowerShell 5:

```text
╭───────┬───────╮
│ field │ value │
╞═══════╪═══════╡
│ x     │ true  │
│ k     │ v     │
╰───────┴───────╯
```

- Use PowerShell argument `--%` to place PowerShell in "stop-parsing" mode.

```powershell
<%=cmd%> config echo  --% @json:'{"k":"v","x":true}'
```

- Triple double quotes are replaced with a single double quote in normal mode:

```powershell
<%=cmd%> config echo @json:'{"""k""":"""v""","""x""":true}'
```

- To insert PowerShell variables in the JSON string, one can do:

```powershell
$var="v"
<%=cmd%> config echo  $('@json:{"""k""":"""' + $var + '""","""x""":true}')
```

##### PowerShell 7

- Check your PowerShell version:

```powershell
$psversiontable.psversion.Major
```

```text
7
```

The following examples give the same result on Windows using PowerShell 7:

- Use PowerShell argument `--%` to place PowerShell in "stop-parsing" mode.

```powershell
<%=cmd%> config echo  --% @json:{"k":"v","x":true}
```

- Single quote protects double quote in normal mode:

```powershell
<%=cmd%> config echo @json:'{"k":"v","x":true}'
```

- To insert PowerShell variables in the JSON string, one can do:

```powershell
$var="v"
<%=cmd%> config echo  $('@json:{"k":"' + $var + '","x":true}')
```

- Use PowerShell structure and then convert to JSON string:

```powershell
$var="v"
<%=cmd%> config echo "@json:$(@{ k = $var; x = $true } | ConvertTo-Json -Compress)"
```

#### Extended Value (JSON, Ruby, ...)

Some values provided to <%=tool%> (options, **Command Parameters**) are expected to be [Extended Values](#extended-value-syntax), that is, not a simple `String`, but a composite structure (`Hash`, `Array`).

For small structures with a few keys, the [dot-path](#dot-path-notation) `key.subkey=value` notation (using `@:` to collect positional arguments, or `--opt.key=value` directly for options) is often the most convenient: it requires no quoting and reads naturally on the command line.
For larger or more complex structures (deep nesting, arrays of hashes, values copied from API documentation), the `@json:` modifier is typically a better fit.
`@json:` expects a [JSON](https://www.json.org/) value; note that `"` is used to enclose a `String` in JSON, which may be difficult to specify in shells: enclose the whole argument in single quotes to avoid this.

Any option or **Command Parameter** expecting a `Hash` value accepts the special value `help` to display its schema.
See [Schema Discovery with `help`](#schema-discovery-with-help).

#### Using a shell variable, parsed by shell, in an Extended Value

To be evaluated by the shell, the shell variable must not be in single quotes.
Enclose the variable in double quotes so that it results in a single argument for <%=tool%> even if its value contains spaces: `bash` splits the result of an unquoted variable expansion into several words (`zsh` does not, by default).

> [!NOTE]
> We use a simple shell variable in this example.
> It does not need to be exported as an environment variable.

```shell
MYVAR="Hello World"
<%=cmd%> config echo @json:'{"title":"'"$MYVAR"'"}' --format=json
<%=cmd%> config echo "@json:{\"title\":\"$MYVAR\"}" --format=json
```

```json
{"title":"Hello World"}
```

#### Double quote in strings in command line

Double quote is a shell special character.
Like any shell special character, it can be protected either by preceding with a backslash or by enclosing in a single quote.

```shell
<%=cmd%> config echo \"
<%=cmd%> config echo '"'
```

```text
"
```

Double quote in JSON is a little tricky because `"` is special both for the shell and JSON.
Both shell and JSON syntax allow protecting `"`, but only the shell allows protection using single quote.

```shell
<%=cmd%> config echo @json:'"\""' --format=text
<%=cmd%> config echo @json:\"\\\"\" --format=text
<%=cmd%> config echo @ruby:\'\"\' --format=text
```

```text
"
```

Here a single quote or a backslash protects the double quote to avoid shell processing, and then an additional `\` is added to protect the `"` for JSON.
But as `\` is also shell special, then it is protected by another `\`.
  
#### Shell and JSON or Ruby special characters in Extended Value

Construction of values with special characters is done like this:

- First select a syntax to represent the [Extended Value](#extended-value-syntax), for example, JSON or Ruby

- Write the expression using this syntax, for example, using JSON:

```json
{"title":"Test \" ' & \\"}
```

Or, using Ruby:

```ruby
{"title"=>"Test \" ' & \\"}
{'title'=>%q{Test " ' & \\}}
```

Both `"` and `\` are special characters for JSON and Ruby and can be protected with `\` (unless Ruby's extended single quote notation `%q` is used).
  
- Then, since the value will be evaluated by shell, any shell special characters must be protected, either using preceding `\` for each character to protect, or by enclosing in single quote:

```shell
<%=cmd%> config echo @json:{\"title\":\"Test\ \\\"\ \'\ \&\ \\\\\"} --format=json
<%=cmd%> config echo @json:'{"title":"Test \" '\'' & \\"}' --format=json
<%=cmd%> config echo @ruby:"{'title'=>%q{Test \" ' & \\\\}}" --format=json
```

```json
{"title":"Test \" ' & \\"}
```

#### Reading special characters interactively

If <%=tool%> is used interactively (a user typing on terminal), values can be entered by the user:

```shell
<%=cmd%> config echo @ruby:"{'title'=>gets.chomp}" --format=json
```

`gets` is Ruby's method of terminal input (terminated by `\n`), and `chomp` removes the trailing `\n`.

#### Command line arguments from a file

If you need to provide a list of command line arguments from lines that are in a file, on Linux you can use the `xargs` command:

```shell
xargs -a lines.txt -d \\n <%=cmd%> config echo
```

This is equivalent to execution of:

```shell
<%=cmd%> config echo [line1] [line2] [line3] ...
```

If there are spaces in the lines, those are not taken as separator, as we provide option `-d \\n` to `xargs`.

#### Extended value using special characters read from environment variables or files

Using a text editor or shell: create a file `title.txt` (and env var) that contains exactly the text required: `Test " ' & \` :

```shell
export MYTITLE='Test " '\'' & \'
echo -n $MYTITLE > title.txt
```

Using those values will not require any escaping of characters since values do not go through shell or JSON parsing.

If the value is to be assigned directly to an option of <%=cmd%>, then you can directly use the content of the file or env var using the `@file:` or `@env:` readers:

```shell
<%=cmd%> config echo @file:title.txt --format=text
<%=cmd%> config echo @env:MYTITLE --format=text
```

```text
Test " ' & \
```

If the value to be used is in a more complex structure, then the `@ruby:` modifier can be used: it allows any Ruby code in expression, including reading from file or env var.
In those cases, there is no character to protect because values are not parsed by the shell, or JSON or even Ruby.

```shell
<%=cmd%> config echo @ruby:"{'title'=>File.read('title.txt')}" --format=json
<%=cmd%> config echo @ruby:"{'title'=>ENV['MYTITLE']}" --format=json
```

```json
{"title":"Test \" ' & \\"}
```

<%=include_plugin_manual(:aoc)-%>
<%=include_plugin_manual(:ats)-%>
<%=include_plugin_manual(:server)-%>
<%=include_plugin_manual(:node)-%>
<%=include_plugin_manual(:faspex5)-%>
<%=include_plugin_manual(:shares)-%>
<%=include_plugin_manual(:console)-%>
<%=include_plugin_manual(:orchestrator)-%>
<%=include_plugin_manual(:cos)-%>
<%=include_plugin_manual(:httpgw)-%>
<%=include_plugin_manual(:transferd)-%>
<%=include_plugin_manual(:faspio)-%>
<%=include_plugin_manual(:alee)-%>
<%=include_plugin_manual(:preview)-%>
## Plugin: `mcp`: Model Context Protocol server

The `mcp` plugin starts a [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server that exposes <%=tool%> to AI assistants, LLM-based tools and agent builders such as [Langflow](#langflow).
The server registers a single tool, `execute_<%=cmd%>_command`, which executes any <%=tool%> command in-process and returns the result as text.

> [!IMPORTANT]
> The `mcp` and `rack` gems are required, see section [Installing Optional Gems](#installing-optional-gems).

Install them with the following command:

```shell
gem install mcp rack
```

### Usage

```shell
<%=cmd%> mcp server
<%=cmd%> mcp server @: instructions="Use this server to manage Aspera transfers"
<%=cmd%> mcp server @: transport=http
```

### `server` command options

The `server` command accepts an optional [Hash](#extended-value-syntax) argument with the following keys.
Keys of a transport are refused with the other transport.

#### General

| Key | Type | Default | Description |
|---|---|---|---|
| `transport`        | `string` | `stdio` | Transport to use: `stdio` or `http` |
| `description`      | `string` | - | Short description of the server shown in the AI client UI |
| `instructions`     | `string` | - | Longer hint shown to the AI client describing what the server does and how to use it |
| `protocol_version` | `string` | - | MCP protocol version to advertise, for example, `2024-11-05` |
| `validate_tool_call_arguments` | `boolean` | `true` | Whether to validate tool arguments against the input schema |
| `max_text_bytes`   | `integer` | `100000` | Maximum byte size of the JSON text content for list results. Items are appended whole until the limit is reached; the full list is always available in `structuredContent` |

#### `stdio` transport

| Key | Type | Default | Description |
|-----|-----|-----|-----|
| `max_line_bytes` | `integer` | 4194304 (4 MiB) | Maximum JSON frame size in bytes |

> [!NOTE]
> **`stdio` transport and server description** - The MCP protocol does not carry a `description` field in the `initialize` handshake.
> For `stdio` servers, AI clients (Claude Desktop, VS Code, Bob, and so on) cannot retrieve the description automatically.
> Add a `"description"` field directly in the client's `mcpServers` configuration to display it in the UI.

#### `http` transport (Streamable HTTP)

| Key | Type | Default | Description |
|-----|-----|-----|-----|
| `url` | `string` | `http://127.0.0.1:3000` | Address and port the server listens on, without path, for example, `http://0.0.0.0:3000`. Use `https://` for TLS. |
| `cert` | `string` | - | With `https://`: path to the TLS certificate file, PEM or PKCS12 (`.p12`, `.pfx`). Without `cert` and `key`, a self-signed certificate is generated. |
| `key` | `string` | - | With `https://`: path to the PEM private key file, or the PKCS12 passphrase. |
| `chain` | `string` | - | With `https://`: path to the PEM certificate chain file. |
| `public_url` | `string` | from `url` | URL of the server for clients, used in OAuth metadata and in the URL of secret pages, for example, `https://your-server:3000`. Mandatory with `oauth` when the host of `url` is `0.0.0.0` or `::`. |
| `auth_token` | `string` | - | Static Bearer token. If set, all MCP requests must carry `Authorization: Bearer <token>`, else HTTP 401. Cannot be empty. It is also the access code asked on secret pages, and on the consent page with `oauth`. Generate it with `openssl rand -hex 32`. |
| `auth_token_min_bits` | `integer` | `80` | Minimum estimated strength of `auth_token`, in bits: a weak token is refused at startup. The estimate uses the optional gem `zxcvbn` if installed, else a built-in estimate. `0` disables the check. |
| `oauth` | `boolean` | `false` | Enable OAuth 2.0 PKCE flow with dynamic client registration. When `true`, clients register automatically and users authenticate via a browser consent page. |
| `oauth_access_token_ttl` | `integer` | `3600` | OAuth access token lifetime in seconds. |
| `oauth_refresh_token_ttl` | `integer` | `2592000` | OAuth refresh token lifetime in seconds (30 days). |
| `stateless` | `boolean` | `false` | Enable stateless mode |
| `allowed_origins` | `Array<string>` | - | List of allowed origins |
| `allowed_hosts` | `Array<string>` | - | List of allowed hostnames |
| `session_idle_timeout` | `integer` | - | Idle session timeout in seconds |
| `max_sessions` | `integer` | - | Maximum number of concurrent sessions |

> [!NOTE]
> `port` and `bind` are deprecated: use `url`, for example, `url=http://0.0.0.0:8080` instead of `port=8080 bind=0.0.0.0`.

For the addresses the server listens on, and HTTPS, see [Web service](#web-service).

### Security

> [!WARNING]
> The tool executes any <%=tool%> command with the credentials and presets of the user running the server.
> When the host of `url` or `public_url` is not a loopback address, `auth_token` is **mandatory**, also with `oauth`: the server refuses to start without it.

With the `http` transport:

- With `oauth`, the consent page asks for `auth_token` as access code, else anyone reaching the server could approve its own client.
  It shows where the authorization is sent (origin of `redirect_uri`): allow only if it is the expected AI client, for example `http://127.0.0.1:<port>`.
- For local-only deployments (hosts of `url` and `public_url` are loopback, see [Web service](#web-service)), `auth_token` and `oauth` are optional but recommended: on a host shared with other users, they can also reach the server.
  Without `auth_token`, the consent page only asks to click **Allow**.
- `auth_token` and `oauth` can coexist: a request is accepted if it carries a valid static token **or** a valid OAuth access token.
- A weak `auth_token` is refused at startup (see `auth_token_min_bits`): generate it with `openssl rand -hex 32`.
- On a network, use `https://` in `url` (or a reverse proxy with TLS): with `http://`, the token is sent in clear.
- `allowed_hosts` and `allowed_origins` protect against DNS rebinding but do not authenticate clients.
  They apply to all endpoints, also OAuth and secret pages, which also accept the origin of `public_url` (for a reverse proxy that changes header `Host`).

With both transports:

- Extended value `@stdin:` is refused.
- Commands sent by the client run in the main folder of the server (option `home`, `<%=opt_env :home%>`, or the default one), and use its configuration file (option `config_file`) and its vault (options `vault` and `vault_password`, also when set in a preset of the server).
  The client cannot change them: these options are refused at levels `medium` and `high`.
  If the command line of the server sets option `security` to `medium` or `high`, the server cannot set them on its command line or in a preset either: set them in its environment, for example `<%=opt_env :vault%>` and `<%=opt_env :vault_password%>`.
- `@secret:` is entered by the user on a web page, see [Secrets entered in a web page](#secrets-entered-in-a-web-page).
- Secrets are hidden in responses, also a value shorter than 8 characters as a word in a text (for example, a short password in an error message).
- The [Security Level](#security-level) is `high` by default: `@ruby:`, `@file:` (also in the parameters of stores of option `vault`), `@uri:`, `@env:`, and `@zlib:` are refused, and a secret must be the whole value: hidden in results, it cannot be processed by another extended value.
  It applies to commands sent by the client, and to presets, because the client can modify presets.
  Commands sent by the client cannot change option `security`.
  Features that execute code, such as option `notify_template` or command `config plugins create`, plugins, and writing to a file chosen by the client (option `out.file`), are refused, see [Security Level](#security-level).
  Files can be written (for example by `config download`, or by a transfer that receives files) only in `writable_paths`, none by default: without it, the client cannot download files.
  It applies to files written on the system that runs the server: not to a transfer with agent `node` (`--transfer=node`), which writes on the node.

To use another level, set option `security` when starting the server, for example:

```shell
<%=cmd%> mcp server --security.level=medium --security.allowed_paths.0=$HOME/.aspera/<%=cmd%>/my_private_key
```

To let the client download files in a folder, keep the level `high` and give the folder:

```shell
<%=cmd%> mcp server --security.writable_paths.0=$HOME/Downloads/<%=cmd%>
```

> [!NOTE]
> A level set by option also applies to the parameters of the `server` command: for example, `auth_token=@env:MCP_TOKEN` requires level `low`.
> Without option `security`, the parameters of the `server` command are not restricted.
>
> A preset created by `aoc wizard` or `faspex5 wizard` reads the private key with `@file:`.
> With level `high`, either store the key in the preset (`<%=cmd%> config preset set <%=ph :aoc_org%> private_key @file:<%=ph :path%>`, without `@val:`), or use level `medium` with the key in `allowed_paths`.
>
> In the same way, a secret of a vault read from a file (for example, `token` of HashiCorp Vault: `@file:<path>`) requires level `medium` with the file in `allowed_paths`.

### HTTP endpoints

With the `http` transport, the server exposes the following endpoints:

| Endpoint | Description |
|---|---|
| `GET /` | Discovery: JSON object with `name`, `version`, and `description` of the server, no authentication |
| `POST`, `GET`, `DELETE` `/mcp` | MCP endpoint (Streamable HTTP), the URL to configure in the AI client. Requires `auth_token` or an OAuth access token, if configured |
| `GET`, `POST` `/secret/<id>` | Secret pages, see [Secrets entered in a web page](#secrets-entered-in-a-web-page) |
| `GET /.well-known/oauth-authorization-server` | With `oauth`: OAuth discovery metadata (RFC 8414) |
| `POST /oauth/register` | With `oauth`: Dynamic client registration (RFC 7591) — any client may register and receive a `client_id`. At most 100 clients are kept: beyond, the least recently used is removed. At most 10 `redirect_uris`, absolute and without fragment |
| `GET /oauth/authorize` | With `oauth`: Consent page shown to the user in a browser, with the `client_id` and where the code is sent (origin of `redirect_uri`) |
| `POST /oauth/authorize` | With `oauth`: Processes the user decision (allow/deny) and issues an authorization code |
| `POST /oauth/token` | With `oauth`: Exchanges the code for tokens (`authorization_code`) or renews them (`refresh_token`) |

AI clients that support the discovery endpoint (such as Bob) read the description from it and display it in their MCP server list without any manual configuration.

AI clients that support the MCP Authorization spec (such as Bob) detect the OAuth endpoints automatically via the `WWW-Authenticate` header returned on HTTP 401, register dynamically, and launch the browser-based login flow without any extra configuration.

### Secrets entered in a web page

[Extended Value](#extended-value-syntax) `@secret:[name]` asks for a secret, for example, a password.
In MCP server mode, there is no terminal: the user enters the secret on a web page of the server instead, following the [URL mode elicitation](https://modelcontextprotocol.io/specification/2026-07-28/client/elicitation) of the MCP protocol.
The secret goes from the browser to the MCP server only: it is not sent to the MCP client or the AI model, and it is hidden in the results of the command.

`@secret:` can be used in commands sent by the AI client, for example, `--password=@secret:password`, and in presets of the user running the server.

For a command that needs a secret:

1. The server replies to the tool call with the URL of a secret page.
1. The MCP client shows the URL and asks the user for consent to open it in a browser.
1. The user enters the secret on the page and submits it, or cancels.
1. The MCP client calls the tool again, and the server executes the command with the secret.

If the command needs several secrets, these steps are repeated for each secret.

The secret page is served:

- With the `http` transport: by the MCP server, at `<public_url>/secret/<id>`.
  If `auth_token` is set, the page also asks for it as access code.
  Set `public_url` if the browser does not reach the server on the address of `url`.
- With the `stdio` transport: by a local web server on `http://127.0.0.1` with a random port, started on first use.

A secret request expires after 10 minutes.
Secrets are kept in memory only, until the command completes.

> [!NOTE]
> The MCP client must support URL mode elicitation (capability `elicitation.url`), else the command fails with an error.
> Protocol `2026-07-28` (result `input_required`) and `2025-11-25` (request `elicitation/create` from the server) are supported.
> With protocol `2025-11-25`, the `http` transport must not be `stateless`.

### Examples

Start an MCP server over `stdio` (default - suitable for use as an MCP server in an IDE or AI tool):

```shell
<%=cmd%> mcp server
```

Start an MCP server over HTTP on port 8080:

```shell
<%=cmd%> mcp server @: transport=http url=http://0.0.0.0:8080 auth_token=@env:MCP_TOKEN
```

Start an MCP server over HTTPS, with a certificate:

```shell
<%=cmd%> mcp server @: transport=http url=https://0.0.0.0:8443 cert=<%=ph :path%>/cert.pem key=<%=ph :path%>/key.pem auth_token=@env:MCP_TOKEN
```

Start with custom instructions and a specific protocol version:

```shell
<%=cmd%> mcp server @: instructions="Aspera transfer automation" protocol_version=2024-11-05
```

Start an MCP server with OAuth 2.0 PKCE authentication (for AI clients such as Bob that support the MCP Authorization spec):

```shell
<%=cmd%> mcp server @: transport=http url=http://0.0.0.0:3000 public_url=http://your-server:3000 oauth=true auth_token=@env:MCP_TOKEN
```

### MCP client configuration

#### Streamable HTTP transport

##### Local server (no authentication required)

Start the server in a separate terminal first:

```shell
<%=cmd%> mcp server @: transport=http
```

Then register it in the AI client's MCP configuration file.

For [**IBM Bob**](https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob), add to `.bob/mcp.json` in your project (or `~/.bob/mcp.json` for global configuration):

```json
{
  "mcpServers": {
    "ascli": {
      "type": "streamable-http",
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

For other clients (Claude Desktop, VS Code, and so on):

```json
{
  "mcpServers": {
    "ascli": {
      "type": "http",
      "url": "http://localhost:3000/mcp"
    }
  }
}
```

##### Remote server with static token

When the server is exposed on a non-local address, `auth_token` is required.

**Option A: static Bearer token** - suitable for all MCP clients.
Set the token in the environment and start the server:

```shell
export MCP_TOKEN=$(openssl rand -hex 32)
<%=cmd%> mcp server @: transport=http url=http://0.0.0.0:3000 auth_token=@env:MCP_TOKEN
```

For [**IBM Bob**](https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob), pass the same token in the `Authorization` header:

```json
{
  "mcpServers": {
    "ascli": {
      "type": "streamable-http",
      "url": "http://your-server:3000/mcp",
      "headers": {
        "Authorization": "Bearer <%=ph :token%>"
      }
    }
  }
}
```

For other clients (Claude Desktop, VS Code, and so on):

```json
{
  "mcpServers": {
    "ascli": {
      "type": "http",
      "url": "http://your-server:3000/mcp",
      "headers": {
        "Authorization": "Bearer <%=ph :token%>"
      }
    }
  }
}
```

##### Remote server with OAuth 2.0 PKCE

**Option B: OAuth 2.0 PKCE flow** - for AI clients that support the MCP Authorization spec (such as Bob).
No token to configure in the client: the client registers dynamically and opens a browser window for user consent on first connection.
The consent page asks for the access code: the value of `auth_token`.

Start the server with OAuth enabled:

```shell
<%=cmd%> mcp server @: transport=http url=http://0.0.0.0:3000 public_url=http://your-server:3000 oauth=true auth_token=@env:MCP_TOKEN
```

For [**IBM Bob**](https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob), register the URL with no extra configuration:

```json
{
  "mcpServers": {
    "ascli": {
      "type": "streamable-http",
      "url": "http://your-server:3000/mcp"
    }
  }
}
```

Bob detects the OAuth endpoints via the `WWW-Authenticate` header on the first HTTP 401 response and triggers the browser-based login flow automatically.

> [!NOTE]
> With `http` transport, the client connects to a running server process.
> The server must be started and kept running independently before the AI client tries to connect.

#### `stdio` transport

The client launches <%=tool%> directly as a subprocess.
Add the following to the AI client's MCP configuration file.

##### IBM Bob `stdio`

For [**IBM Bob**](https://bob.ibm.com/docs/ide/configuration/mcp/mcp-in-bob), add to `.bob/mcp.json` in your project (or `~/.bob/mcp.json` for global configuration):

```json
{
  "mcpServers": {
    "ascli": {
      "type": "stdio",
      "command": "/path/to/bin/<%=cmd%>",
      "args": ["mcp", "server"],
      "description": "Aspera CLI MCP server"
    }
  }
}
```

Most other clients (Claude Desktop, Cursor, and so on) use the same `mcpServers` format, VS Code uses `servers` (see below).

##### Claude Desktop `stdio`

Find the configuration file as specified in [Claude Desktop Documentation](https://modelcontextprotocol.io/docs/2026-07-28/develop/connect-local-servers).

Place this section in `mcpServers`:

```json
{
  "mcpServers": {
    "ascli": {
      "command": "ascli",
      "args": ["mcp", "server"]
    }
  },
...
}
```

##### Claude Code `stdio`

For [**Claude Code**](https://code.claude.com/docs/en/mcp), register the server with the command line (option `--scope user` for all projects):

```shell
claude mcp add ascli -- <%=cmd%> mcp server
```

In a shell, Claude Code can also execute <%=tool%> directly: install the agent skill instead (see [Leveraging AI Assistance](#leveraging-ai-assistance)).

##### VS Code `stdio`

For **VS Code** (GitHub Copilot agent mode), add to `.vscode/mcp.json` in your workspace (or run command **MCP: Add Server**):

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

##### Cursor `stdio`

For **Cursor**, add to `.cursor/mcp.json` in your project (or `~/.cursor/mcp.json` for global configuration):

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

##### Development mode for `stdio`

If the <%=tool%> gem is not installed and you are running directly from the source tree, Ruby will not find the `lib/` directory automatically.
Add the `RUBYLIB` environment variable pointing to the `lib/` directory of the project:

```json
{
  "mcpServers": {
    "ascli": {
      "type": "stdio",
      "command": "/path/to/aspera-cli/bin/<%=cmd%>",
      "args": ["mcp", "server"],
      "env": {
        "RUBYLIB": "/path/to/aspera-cli/lib"
      }
    }
  }
}
```

#### Langflow

[Langflow](https://docs.langflow.org/) is an open-source visual builder of AI agents.
An agent built with Langflow operates IBM Aspera products with <%=tool%> through the **MCP Tools** component, an MCP client (`stdio`, and Streamable HTTP since Langflow 1.7): no code to write.

##### Register the server in Langflow

In Langflow, click the profile icon, select **Settings**, then **MCP Servers**, and click **Add MCP Server**.

With the `stdio` transport, when <%=tool%> is installed on the host of Langflow, select **STDIO**:

| Field | Value |
|-------|-------|
| **Name** | `ascli` |
| **Command** | Absolute path of <%=tool%>, given by `which <%=cmd%>` (Windows: `where <%=cmd%>`) |
| **Arguments** | `mcp`, then `server` |

With the `http` transport, for example when Langflow runs in a container (its image has no Ruby), start the server with a static token (the MCP client of Langflow does not support OAuth):

```shell
export MCP_TOKEN=$(openssl rand -hex 32)
<%=cmd%> mcp server @: transport=http url=http://0.0.0.0:3000 auth_token=@env:MCP_TOKEN
```

<%=tool%> can also run in its own container, next to Langflow: the [container image](#container) includes the gems `mcp` and `rack`.
To keep the presets and the transferred files, mount the configuration folder and a transfer folder (see [Container: Details](#container-details)), and let the agent write files in the transfer folder only (see [Security](#security)).
With the same variable `MCP_TOKEN`:

```shell
podman run --rm --name <%=cmd%> --publish 3000:3000 --env MCP_TOKEN --user root --env <%=opt_env :home%>=/home/cliuser/.aspera/<%=cmd%> --volume $HOME/.aspera/<%=cmd%>:/home/cliuser/.aspera/<%=cmd%> --volume $HOME/xferdir:/xferfiles <%=container_image%>:latest mcp server --security.writable_paths.0=/xferfiles @: transport=http url=http://0.0.0.0:3000 auth_token=@env:MCP_TOKEN
```

The agent then uploads from, and downloads to, folder `/xferfiles`.

Then, in Langflow:

1. In **Settings** > **Global Variables**, create a **Credential** variable, for example `ASCLI_MCP_TOKEN`, with value `Bearer` followed by a space and the token.
1. In **Add MCP Server**, select **HTTP/SSE**:
   - **Name**: `ascli`
   - **URL**: `http://<%=ph :host%>:3000/mcp`.
     When Langflow runs in Docker Desktop and <%=tool%> on the host (or with a published port): `http://host.docker.internal:3000/mcp`.
     When both containers are on the same network (option `--network`, or the same Docker Compose project): the name of the container (or of the service) of <%=tool%>, for example, `http://<%=cmd%>:3000/mcp`.
   - **Headers**: key `Authorization`, value `ASCLI_MCP_TOKEN` (the name of the variable: Langflow replaces it with its value)

##### Add <%=tool%> to an agent

1. From the **MCP** sidebar, drag the server `ascli` to the flow: it adds an **MCP Tools** component.
1. In field **Tool**, select `execute_<%=cmd%>_command`.
1. In the header menu of the component, enable **Tool mode**.
1. Connect the port **Toolset** of the component to the port **Tools** of the **Agent** component.

Langflow gives the model the description of the tool, but not the instructions of the server.
So that the agent uses <%=tool%> for requests about Aspera, and the presets for credentials, add this text to field **Agent Instructions** of the **Agent** component:

```text
For any request about IBM Aspera, use the tool execute_<%=cmd%>_command: file transfer (FASP), Aspera on Cloud (aoc), Faspex 5 (faspex5), Node API (node), HSTS and SSH servers (server), Shares (shares), Orchestrator (orchestrator), Console (console), IBM Cloud Object Storage (cos).
Before a command whose syntax you have not checked in this conversation, list the commands of the plugin with ["config","commands","<%=ph :plugin%>"], and get the fields of a Hash argument with "help" in its place.
Credentials are in presets: list them with ["config","preset","overview"] and use --preset=<%=ph :preset_name%>. Never ask the user for a password: if no preset fits, tell the user which preset to create.
A transfer returns immediately with a job_id: check it with ["config","agents","jobs","status","<%=ph :job_id%>"].
Filter long lists with --query, --out.select and --out.fields.
```

##### Limits of Langflow

- **Secrets**: the MCP client of Langflow does not support URL mode elicitation: `@secret:` fails (see [Secrets entered in a web page](#secrets-entered-in-a-web-page)).
  Create the presets beforehand, with secrets in the [Secret Vault](#secret-vault).
- **Results**: Langflow gives the model the text of the result only, not `structuredContent`.
  A list larger than `max_text_bytes` (100000 bytes by default) is truncated for the model: filter it (see [Filtering results](#filtering-results)), or raise `max_text_bytes`.
- **Timeout**: a tool call fails after 180 seconds by default.
  The MCP server starts transfers in [asynchronous mode](#asynchronous-transfer-mode): a transfer returns immediately.
  For other long commands, raise **Tool Execution Timeout (seconds)** in the advanced settings of the **MCP Tools** component, or the environment variable `LANGFLOW_MCP_TOOL_EXECUTION_TIMEOUT` of Langflow.

<%=include_commands_for_plugin(:mcp)%>

### End-to-end AI testing

The file [`docs/test-mcp-with-ai.md`](test-mcp-with-ai.md) contains a step-by-step test procedure for validating the MCP server with a live AI assistant (Bob, Claude Desktop, VS Code Copilot, or any MCP-capable client).
It covers tool visibility, self-discovery, Hash schema introspection, option listing, documentation retrieval, live transfer tasks, truncation handling, error handling, and credential safety.

### MCP usage patterns for AI

> [!TIP]
> This section is for AI assistants using the MCP server.
> Follow these patterns to avoid common first-call failures and unnecessary retries.

#### Session bootstrap

Always start a session with two discovery calls before doing anything else:

```json
["config", "preset", "list"]
["config", "preset", "show", "default"]
```

The second call returns the mapping from `plugin` to `preset_name` so you know which credentials are active for each plugin.

#### Command discovery

Always use `["config", "commands", "<plugin>"]` to enumerate the commands of a plugin and their syntax.
Add command words to list only the commands under that path, e.g. `["config", "commands", "aoc", "files"]`.
A line ending with `<command...>` provides the commands of another plugin, given by `(see: ...)`.
Use option `--expand-mounts=yes` to list them in place.
Omit `<plugin>` to list the commands of all plugins (much larger result).
Never guess command names from training data: names like `shared_folders` vs `shared_inboxes` are easily confused.

#### Schema introspection for Hash arguments

Whenever a command syntax shows a Hash argument (e.g. `<account:Hash>`), call `help` in its place **before** the real call:

```json
["<plugin>", "<cmd>", ..., "help"]
```

This returns a table of field names, types, and descriptions.
Never infer field names from server error messages.

#### Secrets

To use a secret the user did not provide (password, passphrase), pass `@secret:<name>` as value.
The user enters it on a web page and you never see it: prefer it to asking for the secret in the conversation.

```json
["server", "browse", "/", "--url=ssh://host:33001", "--username=user", "--password=@secret:password"]
```

#### Async transfers and cross-call status tracking

The `direct` agent keeps transfer state in-memory.
A job started in one MCP call **cannot** be monitored in a subsequent call: the in-memory agent is gone between calls.

Use the `transferd` agent when you need to check transfer status in a later call:

```json
["server", "upload", "--transfer=transferd", "--to-folder=/dst", "/local/file"]
```

The `desktop` agent is also unaffected because it runs in an external process.

#### Workspace context for AoC

`aoc files` and `aoc packages` commands require a workspace context.
If no default workspace is configured in the preset, always add `--workspace=NAME`:

```json
["aoc", "files", "ls", "/", "--workspace=MyWorkspace"]
```

List available workspaces with `["aoc", "user", "workspaces", "list"]`.

#### Admin operations and privilege checks

Before calling any `admin` sub-command, verify that the active preset has admin rights.
`access_denied` typically means the wrong preset is active, not a syntax error.
Check with:

```json
["config", "preset", "show", "<preset_name>"]
```

## Operational Utilities

This section covers the specialized modules and utilities used to integrate <%=tool%> into your broader operational infrastructure.
While the core plugins handle data movement, these tools provide the "integration layer" for enterprise environments: Aspera Sync and Hot Folder enable automated, folder-based synchronization; Nagios and SMTP modules provide health monitoring and automated email alerting for transfer status; and the `asession` tool and the Ruby module `Aspera` allow integration of transfers into other programs.
Together, these features transform the CLI from a manual tool into a fully integrated component of an automated, monitored data workflow.

### IBM Aspera Sync

An interface for the `async` utility is provided in the following plugins:

- `server sync` (SSH Auth)
- `node sync` (use gen3 token)
- `aoc files sync` (uses `node` plugin with bearer token)
- `shares files sync` (uses `node` plugin with gen3 token)

The `sync` command, available in above plugins, performs the following actions:

- Start a local Sync session by executing the `async` command with the appropriate parameters.
- Get local Sync session information by accessing the Async snap database directly.
- Get local Sync session information using the `asyncadmin` command, if available.

One advantage of using <%=tool%> over the `async` command line is the possibility to use a configuration file, using standard options of <%=tool%>.
Moreover, <%=tool%> supports sync with applications requiring token-based authorization.

Some `sync` parameters are filled by the related plugin using transfer spec parameters (for example, including token).

> [!NOTE]
> All `sync` commands require an `async` enabled license and availability of the `async` executable (and `asyncadmin`).
> The Aspera Transfer Daemon 1.3+ includes this.

#### Quick test

Below is a simple end-to-end procedure to verify synchronization using the demo server.

1. Initialize the demo server configuration:

    ```shell
    <%=cmd%> config initdemo
    ```

1. Create a local folder with a sample file to sync:

    ```shell
    mkdir foobar
    echo hello > foobar/file1
    ```

1. Create the destination folder on the remote server:

    ```shell
    <%=cmd%> server -Pdemoserver mkdir /Upload/mydest1
    ```

1. Run the sync operation:

    ```shell
    <%=cmd%> server -Pdemoserver sync push foobar --to-folder=/Upload/mydest1
    ```

The following sections provide additional details on available options and configuration.

#### Starting a sync session

To start a sync session, use one of the three sync directions, followed by a folder path.
For `push` and `bidi`, the path is a local folder.
For `pull`, the path is a remote folder.

The corresponding path on the opposite side is provided using the `to_folder` option.

**General syntax:**

```shell
<%=cmd%> ... sync <%=ph :direction%> <%=ph :path%> [--to-folder=<%=ph :path%>] [<%=ph :sync_info%>]
```

| <%=ph :direction%><%=br%>(parameter) | <%=ph :path%><%=br%>(parameter)   | `to_folder`<%=br%>(option) |
|-----------|--------|-------------|
| `push`    | Local  | Remote      |
| `bidi`    | Local  | Remote      |
| `pull`    | Remote | Local       |

An optional positional `Hash` argument (`<%=ph :sync_info%>`) may be provided.
It can be expressed in one of two formats:

- `conf` format (recommended)
- `args` format (legacy)

A single sync session must use **one format exclusively**.

- If `<%=ph :sync_info%>` is not provided, a default configuration is automatically generated in the `conf` format (details in the next section).

- If argument `<%=ph :sync_info%>` is provided, the format is inferred:

  - If the `Hash` contains either key `sessions` or `instance`, the `args` format is used.
  - Otherwise, the `conf` format is used.

##### `sync_info`: `conf` format

This is the **preferred** syntax.
It is the same payload as specified on the `async` option `--conf` or in Node API `/asyncs`.

Documentation on Async Node API can be found on [IBM Developer Portal](https://developer.ibm.com/apis/catalog?search=%22aspera%20sync%20api%22).

The following parameters are automatically filled from mandatory arguments, and are not allowed:

- `direction`
- `local.path`
- `remote.path`

Parameter `name` is set to a default value if not provided in `sync_info`.
Parameter `quiet` is set to `false` if not provided in `sync_info` and a terminal is detected.

> [!NOTE]
> The configuration is passed to `async` on its command line (`--conf64`, the base64 of the JSON), which is visible to the other users of the host (for example with `ps`).
> The remote password and token (`remote.pass`, `remote.token`) are **not** put there: they are passed in the environment variables `ASPERA_SCP_PASS` and `ASPERA_SCP_TOKEN`, which `async` reads when they are absent from the configuration.
> `async` has no environment variable for the other secrets it reads only from the configuration (the proxy password, and `local.pass`): these stay in `--conf64`. They are hidden in the logs of <%=tool%>, but a user of the host can still read them (base64) while `async` runs. Prefer token-based authentication, or run on a host where other users are trusted.

The documentation is available in the terminal with:

```shell
<%=cmd%> config sync spec
```

> [!NOTE]
> <%=tool%> accepts the following fields within the `sync_info` Hash.
> The options listed in the **Description** column correspond to the equivalent parameters used by the low-level `async` command.

<%=spec_to_table(Aspera::Sync::Operations::CONF_SCHEMA, annotate: Aspera::Transfer::CommandLineBuilder.method(:doc_lines))%>

##### `sync_info`: `args` format

This is the **legacy** syntax.
<%=tool%> defines a JSON equivalent to regular `async` options.
It is based on a JSON representation of `async` command line options.
Technically, it allows definition of multiple sync sessions in a single command, but <%=tool%> only accepts a single session for consistency with the previous syntax.

This format is selected if the `sync_info` `Hash` has either key `sessions` or `instance`.

The following parameters are automatically filled from mandatory arguments, and are not allowed:

- `direction`
- `local_dir`
- `remote_dir`

Parameter `name` is set to a default value if not provided in `sync_info`.

#### Sync management and monitoring: `admin`

The `admin` command provides subcommands to inspect the state of an Async sync session.
Most subcommands read the local snap database (`snap.db`) directly - no server connection is required.
The exception is `status`, which calls the `asyncadmin` utility available only on server products.

The snap database is opened **read-only** (even with option `sql`), so the `admin` subcommands never modify it, even while `async` is synchronizing.

These commands can also be run from the `config` plugin:

```shell
<%=cmd%> config sync admin
```

**Prerequisites:** Most `admin` subcommands require the `sqlite3` gem:

```shell
gem install sqlite3
```

**Usage:** All `admin` subcommands share the same argument structure:

```shell
<%=cmd%> ... sync admin <%=ph :command%> <%=ph :folder%> [<%=ph :sync_info%>]
```

- `<%=ph :command%>` - one of the subcommands listed below.
- `<%=ph :folder%>` - path to the local database folder (a folder containing a `.private-asp` subfolder). By default this is the local synchronized folder; if a separate database folder was configured, specify that path instead.
- `[<%=ph :sync_info%>]` - optional `Hash` to identify the session. If the folder contains only one session it is selected automatically; otherwise provide `@: name=<%=ph :session_name%>`.

The only exception is `find`, which takes a plain directory path and lists all `<%=ph :session_name%>` found inside it.

**Subcommands:**

| Command     | Uses          | Description                                                                                            |
|-------------|---------------|--------------------------------------------------------------------------------------------------------|
| `find`      | filesystem    | Search a directory for existing sync sessions and list their names and paths                           |
| `status`    | `asyncadmin`  | Retrieve the status of a running sync session (requires a server-side product)                         |
| `meta`      | `sqlite3`     | Display session metadata from `sync_snapmeta_table`                                                    |
| `counters`  | `sqlite3`     | Display synchronization counters from `sync_snap_counters_table`                                       |
| `file_info` | `sqlite3`     | List the synchronization state of each file from `sync_snapdb_table` (state, record ID, path, message) |
| `overview`  | `sqlite3`     | List all tables and their columns in the snap database                                                 |
| `query`     | `sqlite3`     | Execute an arbitrary SQL statement against the snap database and return the result rows                |

The `query` subcommand requires `--sql` with the full SQL statement to execute.
The sqlite3-based subcommands (`meta`, `counters`, `file_info`) accept `--sql` optionally to append a SQL fragment (for example, a `WHERE` or `ORDER BY` clause):

```shell
<%=cmd%> ... sync admin query <%=ph :folder%> --sql="SELECT * FROM sync_snapdb_table WHERE state=20"
<%=cmd%> ... sync admin file_info <%=ph :folder%> --sql="WHERE state=20"
<%=cmd%> ... sync admin file_info <%=ph :folder%> --sql="WHERE state=20 ORDER BY f_meta_path"
```

**Snap database schema:** The snap database (`snap.db`) contains the following tables:

**`sync_snapmeta_table`** - one row per session, written at start and updated at stop:

<%=schema_to_table('async_tables:properties.meta')%>

**`sync_snap_counters_table`** - one row, updated live during a session:

<%=schema_to_table('async_tables:properties.counters')%>

**`sync_snapdb_table`** - one row per tracked file or directory:

<%=schema_to_table('async_tables:properties.file_info')%>

#### Sync log analysis: `logs`

The `logs` command reads the `async` log files of the local host and reports only the **notable** events, skipping the bulk of the log (synchronized files, transfers, periodic statistics):

- File conflicts and errors: a `SYNC FILE STOP` line with `status=CONFLICT` or `status=ERROR` (a conflict is reported until both copies are identical).
- Unsupported file-system events (`Unsupported file system event`).
- Session lifecycle: session `start`, `stop` and `idle`.
- Any `ERR`-level line (for example a connection or algorithm error).

```shell
<%=cmd%> ... sync logs [<%=ph :paths%>...]
```

- `<%=ph :paths%>` - one or more `async` log files (`gzip` is supported), folders (only the `async*.log` files in them are read), or `-` for the standard input.
- When no path is given, the log at the default location of the local host is read: `~/Library/Logs/Aspera/async.log` on macOS, the `syslog` files on Linux and Unix (`async` logs to `syslog`); on Windows `async` logs in its own working folder, so a path must be given.

The result is a list with the fields: `time`, `level`, `session` (pair name), `kind`, `path`, `status` and `detail`. Filter it with the standard output options, for example to show only conflicts:

```shell
<%=cmd%> config sync logs --out.select=@json:'{"kind":"file conflict"}'
```

> **Note:** as for any command that reads a local path chosen by the client, the paths are checked against the security level (option `security`): reading is refused at level `high` and limited to `allowed_paths` at level `medium` (see [Security Level](#security-level)).

### Hot folder

<%=tool%> does **not** have a standalone `hotfolder` command.
Instead, you create a Hot Folder by combining the upload or download commands with specific transfer-spec parameters and an OS scheduler (like `cron` or Task Scheduler).

#### Requirements

<%=tool%> may be used as a simple hot folder engine.
A hot folder is defined as a tool that:

- Locally (or remotely) detects new files in a top folder
- Sends detected files to a remote (respectively, local) repository
- Only sends new files, and does not re-send already sent files
- Optionally: sends only files that are not still **growing**
- Optionally: after transfer of files, deletes or moves to an archive

In addition: the detection should be made **continuously** or on specific time/date.

#### Setting up a hot folder

The general idea is to rely on:

- Existing `ascp` features for detection and transfer
- <%=tool%> configuration capabilities and server-side knowledge
- The OS scheduler for reliability and continuous operation

##### `ascp` features

Useful `ascp` features are available as arguments (see the `ascp` manual):

- Sending only **new** files
  - Option `-k 1,2,3` (`resume_policy`)
- Remove or move files after transfer:
  - `--remove-after-transfer` (`remove_after_transfer`)
  - `--move-after-transfer` (`move_after_transfer`)
  - `--remove-empty-directories` (`remove_empty_directories`)
- Send only files not modified since the last X seconds:
  - `--exclude-newer-than` (`exclude_newer_than`)
  - `--exclude-older-than` (`exclude_older_than`)
- Top level folder should not be created on destination
  - `--src-base` (`src_base`)

> [!NOTE]
> <%=tool%> takes transfer parameters exclusively as a [**transfer-spec**](#transfer-specification), with `ts` option.

> [!NOTE]
> Usual native `ascp` arguments are available as standard [**transfer-spec**](#transfer-specification) parameters, but not special or advanced options.

> [!TIP]
> Only for the [`direct`](#agent-direct) transfer agent (not others, like connect or node), native `ascp` arguments can be provided with parameter `ascp_args` of option `transfer`.

##### Server side and configuration

Virtually any transfer on a **repository** on a regular basis might emulate a hot folder.

> [!NOTE]
> File detection is not based on events (`inotify`, and so on), but on a simple folder scan on source side.

> [!TIP]
> Options may be saved in an [Option Preset](#option-preset) and used with `-P`.

##### Scheduling

Once <%=tool%> command line arguments are defined, run the command using the OS native scheduler, for example, every minute or every 5 minutes.
See [Scheduler](#scheduler) (and option `lock_port`).

#### Example: Upload hot folder

```shell
<%=cmd%> server upload source_hot --to-folder=/Upload/target_hot --lock-port=12345 --ts=@json:'{"remove_after_transfer":true,"remove_empty_directories":true,"exclude_newer_than":-8,"src_base":"source_hot"}'
```

The local folder (here, relative path: `source_hot`) is sent (upload) to an Aspera server.
Source files are deleted after transfer.
Growing files will be sent only once they do not grow anymore (based on an 8-second cool-off period).
If a transfer takes more than the execution period, then the subsequent execution is skipped (`lock_port`) preventing multiple concurrent runs.

#### Example: Unidirectional synchronization (upload) to server

```shell
<%=cmd%> server upload source_sync --to-folder=/Upload/target_sync --lock-port=12345 --ts=@json:'{"resume_policy":"sparse_csum","exclude_newer_than":-8,"src_base":"source_sync"}'
```

This can also be used with other folder-based applications: Aspera on Cloud, Shares, Node.

#### Example: Unidirectional synchronization (download) from Aspera on Cloud Files

```shell
<%=cmd%> aoc files download . --to-folder=. --lock-port=12345 --progress-bar=no --out.level=data --ts=@json:'{"resume_policy":"sparse_csum","target_rate_kbps":50000,"exclude_newer_than":-8,"delete_before_transfer":true}'
```

> [!NOTE]
> Option `delete_before_transfer` will delete files locally, if they are not present on remote side.

> [!NOTE]
> Options `progress_bar` and `--out.level` limit output for headless operation (for example, a cron job).

### Health check and Nagios

Most plugins provide a `health` command that checks the health status of the application.
Example:

```shell
<%=cmd%> console health
```

```text
╭────────┬─────────────┬────────────╮
│ status │ component   │ message    │
╞════════╪═════════════╪════════════╡
│ ok     │ console api │ accessible │
╰────────┴─────────────┴────────────╯
```

Typically, the health check uses the REST API of the application, with the following exception: the `server` plugin checks health by issuing a transfer to the server (`server health transfer`).

<%=tool%> can be called by Nagios to check the health status of an Aspera server.
The output can be made compatible with Nagios with option `--format=nagios`:

```shell
<%=cmd%> server health transfer --to-folder=/Upload --format=nagios --progress-bar=no
```

```text
OK - [transfer:ok]
```

### SMTP for email notifications

<%=tool%> can send emails.
To do so, set up the SMTP configuration with option `smtp`.

The `smtp` option is a `Hash` ([Extended Value](#extended-value-syntax)) with the following fields:

<%=schema_to_table(Aspera::Schema::Registry::SMTP_OPTIONS)%>

#### Example of configuration

```shell
<%=cmd%> config preset set smtp_google server smtp.google.com
<%=cmd%> config preset set smtp_google username john@gmail.com
<%=cmd%> config preset set smtp_google password <%=ph :password%>
```

or

```shell
<%=cmd%> config preset set smtp_google @json:'{"server":"smtp.google.com","username":"john@gmail.com","password":"<%=ph :password%>"}'
```

or

```shell
<%=cmd_skip%> config preset set smtp_google @: server=smtp.google.com username=john@gmail.com password=<%=ph :password%>
```

Set this configuration as global default, for instance:

```shell
<%=cmd%> config preset set cli_default smtp @val:@preset:smtp_google
<%=cmd%> config preset set default config cli_default
```

#### Email templates

Sent emails are built using a template that uses the [`ERB`](https://www.tutorialspoint.com/ruby/eruby.htm) syntax.

The template is the full SMTP message, including headers.

The following variables are defined by default:

- `from_name`
- `from_email`
- `to`

Other variables are defined depending on context.

#### Test

Check settings with `smtp_settings` command.
Send test email with `email_test`.

```shell
<%=cmd%> config smtp_settings --smtp=@preset:smtp_google
<%=cmd%> config email_test --smtp=@preset:smtp_google --notify-to=sample.dest@example.com
```

#### Notifications for transfer status

An e-mail notification can be sent upon transfer success and failure (one email per transfer job, one job being possibly multi session, and possibly after retry).

To activate, use option `notify_to`.

A default e-mail template is used, but it can be overridden with option `notify_template`.

The environment provided contains the following additional variables:

- `subject` : a default subject including transfer status
- `status` : global status of transfer
- `ts` : the [**transfer-spec**](#transfer-specification) used for the transfer
- `from_email` : email of sender (from `smtp` configuration)
- `from_name` : name of sender (from `smtp` configuration)
- `to` : recipient of the email (from `notify_to`)

Example of template:

```text
From: <%='<'%>%=from_name%> <<%='<'%>%=from_email%>>
To: <<%='<'%>%=to%>>
Subject: <%='<'%>%=subject%>

Transfer is: <%='<'%>%=status%>
```

### Tool: `asession`

This gem comes with a second executable tool providing a simplified standardized interface to start a FASP session: `asession`.

It aims at simplifying the startup of a FASP session from a programmatic standpoint as formatting a [**transfer-spec**](#transfer-specification) is:

- Common to Aspera Node API (HTTP POST /ops/transfer)
- Common to Aspera Connect API (browser JavaScript `startTransfer`)
- Generated by using any third-party language-specific JSON library

Ideally, IBM will integrate this directly into `ascp`, making this tool redundant.

Integration with any language is possible, provided that the language can spawn a subprocess, write to its STDIN, read from STDOUT, and generate and parse JSON.

`asession` expects a single argument: a session specification that contains parameters and a [**transfer-spec**](#transfer-specification).

If no argument is provided, it assumes a value of: `@json:@stdin:`, that is, JSON on stdin.

> [!NOTE]
> If JSON is the format, specify `@json:` to tell `asession` to decode the `Hash` using JSON syntax.

During execution, it generates all low level events, one per line, in JSON format on stdout.

Top level parameters supported by `asession`:

| Parameter          | Description                                                            |
|--------------------|------------------------------------------------------------------------|
| `spec`             | The [**transfer-spec**](#transfer-specification)                       |
| `agent`            | Same parameters as `transfer` option for agent `direct`                |
| `loglevel`         | Log level of `asession`                                                |
| `file_list_folder` | The folder used to store (for garbage collection) generated file lists.<%=br%>Default: `[system tmp folder]/[username]_asession_filelists` |

#### Comparison of interfaces

| Feature/Tool | Transfer Daemon | FASPManager | `ascp` | `asession` |
|------------|-------------|-------------|-------------|-------------|
| status | Supported | Deprecated | Supported | Deprecated |
| language integration | Many | C/C++<%=br%>C#/.net<%=br%>Go<%=br%>Python<%=br%>java<%=br%> | Any | Any |
| required additional components to `ascp` | Daemon | Library<%=br%>(+headers) | - | Ruby<%=br%>Aspera gem |
| startup | Daemon | API | Command line arguments | JSON on stdin<%=br%>(standard APIs:<%=br%>JSON.generate<%=br%>Process.spawn) |
| events | Poll | Callback | Possibility to open management port<%=br%>and proprietary text syntax | JSON on stdout |
| platforms | Like `ascp` and `transferd` | Like `ascp` and lib (if compiled) | Any with `ascp` | Any with Ruby and `ascp` |

#### Simple session

Create a file `session.json` with:

```json
{"remote_host":"demo.asperasoft.com","remote_user":"asperaweb","ssh_port":33001,"remote_password":"<%=ph :password%>","direction":"receive","destination_root":"./test.dir","paths":[{"source":"/aspera-test-dir-tiny/200KB.1"}],"resume_level":"none"}
```

Then start the session:

```shell
asession < session.json
```

#### Asynchronous commands and Persistent session

`asession` also supports asynchronous commands (on the management port).
Instead of the traditional text protocol as described in `ascp` manual, the format for commands is: one single line per command, formatted in JSON, where parameters shall be **snake** style, for example: `LongParameter` &rarr; `long_parameter`

This is particularly useful for a persistent session (with the [**transfer-spec**](#transfer-specification) parameter: `"keepalive":true`)

```text
asession
{"remote_host":"demo.asperasoft.com","ssh_port":33001,"remote_user":"asperaweb","remote_password":"<%=ph :password%>","direction":"receive","destination_root":".","keepalive":true,"resume_level":"none"}
{"type":"START","source":"/aspera-test-dir-tiny/200KB.2"}
{"type":"DONE"}
```

(events from FASP are not shown in above example.
They would appear after each command)

#### Help

```shell
asession -h
<%=include_asession%>
```

### Ruby Module: `Aspera`

Main components:

- `Aspera` generic classes for REST and OAuth
- `Aspera::Plugins::Direct::Agent`: Starting and monitoring transfers using `ascp`.
- `Aspera::Plugins::<Name>`: the code of each product (bundle `lib/aspera/plugins/<name>/`): `Api` (client of the product API, e.g. `Aspera::Plugins::Node::Api`), `Agent`, `Commands`. The files other than `commands.rb` do not use the command line: `require 'aspera/plugins/<name>/api'`.
- `Aspera::Agent::Factory.instance.create(<AGENT>, <OPTIONS>)`: creates a transfer agent by its name (`direct`, `node`, ...).
- `Aspera::Cli`: <%=tool%>.

Working examples can be found in repo: <https://github.com/laurent-martin/aspera-api-examples> in Ruby examples.

## Common problems

<%=tool%> detects common problems and provides hints to solve them.

### Error: "Remote host is not who we expected"

Cause: `ascp` >= 4.x checks fingerprint of the highest server host key, including ECDSA.
`ascp` < 4.0 (3.9.6 and earlier) supports only RSA (and ignores ECDSA presented by the server).
`aspera.conf` supports a single fingerprint.

Workaround on client side: To ignore the certificate (SSH fingerprint) add option on client side (this option can also be added permanently to the configuration file):

```shell
--ts=@json:'{"sshfp":null}'
```

Workaround on server side: Either remove the fingerprint from `aspera.conf`, or keep only RSA host keys in `sshd_config`.

References: ES-1944 in the release notes of 4.1, and the [HSTS admin manual section "Configuring Transfer Server Authentication With a Host-Key Fingerprint"](https://www.ibm.com/docs/en/ahts/4.2?topic=upgrades-configuring-ssh-server).

### Error: "can't find header files for ruby"

Some Ruby gems dependencies require compilation of native parts (C).
This also requires Ruby header files.
If Ruby was installed as a Linux package, then also install the Ruby development package:
`ruby-dev` or `ruby-devel`, depending on distribution.

### Private key type: `ed25519`

Keys of type `ed25519` and keys in the OpenSSH format are supported by `net-ssh` using the Ruby `openssl` gem (>= 3.2.0): the `ed25519` gem is not needed.
Only OpenSSH private keys protected by a passphrase require the `bcrypt_pbkdf` gem, which requires compilation of native code:

```shell
gem install bcrypt_pbkdf
```

If the gem is missing, then loading such a key fails with an error mentioning `bcrypt_pbkdf`.

If the OpenSSL backend does not support Ed25519, then the following message is displayed:

```text
OpenSSH keys only supported if ED25519 is available (NotImplementedError)
net-ssh requires openssl >= 3.2.0 and a crypto backend with Ed25519 enabled for ed25519 support.
```

To ignore the `ed25519` keys of the default identities (`~/.ssh/id_ed25519`), set env var `<%=opt_env :enable_ed25519%>` to `false`.

In addition, if **JRuby** is used, host keys of type: `ecdsa-sha2` and `ecdh-sha2` are also deactivated by default.
To activate, set env var `<%=opt_env :enable_ecdsha2%>` to `true`.

### JRuby: `net-ssh`: Unsupported algorithm

JRuby may not implement all the algorithms supported by OpenSSH.

Add the following to option `ssh_options`:

```json
{"host_key":["rsa-sha2-512","rsa-sha2-256"],"kex":["curve25519-sha256","diffie-hellman-group14-sha256"],"encryption": ["aes256-ctr", "aes192-ctr", "aes128-ctr"]}
```

For example:

```shell
--ssh-options=@json:'{"host_key":["rsa-sha2-512","rsa-sha2-256"],"kex":["curve25519-sha256","diffie-hellman-group14-sha256"],"encryption": ["aes256-ctr", "aes192-ctr", "aes128-ctr"]}'
```

### Error: "SSL_read: unexpected eof while reading"

Newer OpenSSL libraries expect a clean SSL close.
To deactivate this error, enable option `IGNORE_UNEXPECTED_EOF` for `ssl_options` in option `http_options`.

```shell
--http-options=@json:'{"ssl_options":["IGNORE_UNEXPECTED_EOF"]}'
```

### Error: `ascp`: `/lib64/libc.so.6`: version `GLIBC_2.28` not found

This happens on Linux x86 if you try to install `transferd` on a Linux version too old to support a newer `ascp` executable.

Workaround: Install an older version of `transferd`:

```shell
<%=cmd%> transferd install 1.1.2
```

See [Single file executable](#single-file-executable).

### Error: Cannot rename partial file

This is an error coming from `ascp` when it is configured to use a partial file name, and at the end of the transfer, the partial file, now complete, does not exist anymore.

This often happens when two transfers start in parallel for the same file:

- Session 1 starts for file1, it creates file: file1.partial and fills it.
- Session 2 starts for file1 (same), it creates file: file1.partial and fills it.
- Session 1 finishes, and renames file1.partial to file1.
- Session 2 finishes, and tries to rename file1.partial to file1, but it fails as it does not exist anymore...

By default, <%=tool%> creates a configuration file `~/.aspera/sdk/aspera.conf` like this:

```xml
<?xml version='1.0' encoding='UTF-8'?>
<CONF version="2">
<default>
    <file_system>
        <resume_suffix>.aspera-ckpt</resume_suffix>
        <partial_file_suffix>.partial</partial_file_suffix>
    </file_system>
</default>
</CONF>
```

In container, this is located in `/ibm_aspera`.

One possibility to avoid that error is to disable partial filename suffix... But that only hides the problem.

For example, when using the container, override that file with a volume and remove the line for extension.
Another possibility is to add this option: `--transfer=@json:'{"ascp_args":["--partial-file-suffix="]}'` : this overrides the value in config file.

> [!NOTE]
> If one relies on `--lock-port` when using containers to avoid parallel transfers in a cron job, this may be the cause, as `lock_port` does not lock across containers.
> Use `flock` instead.

## Security and Trust

This section is for security and compliance reviewers who evaluate <%=tool%> before its use in an organization.
It summarizes how <%=tool%> protects credentials, communications and the system that runs it, and how the project is developed and released.
The detailed reasoning is in the [Security Assurance Case](<%=link_repo('docs/ASSURANCE_CASE.md')%>).

### Protection by area

| Area | How <%=tool%> protects it | Details |
| ---- | ------------------------ | ------- |
| Credentials | Secret values are hidden in logs, results and error messages. Secrets can be kept in a vault instead of the configuration file: encrypted file, HashiCorp Vault, Keeper, 1Password, macOS keychain, Linux Secret Service. The configuration folder is readable only by the current user. | [Secret Vault](#secret-vault) |
| Communications | API calls use HTTPS, and the certificate of the server is verified by default (disabled only with `--insecure=yes`). | [SSL CA certificate bundle](#configuring-the-ssl-ca-certificate-bundle) |
| File transfers | Transfers use the IBM Aspera transfer engine (`ascp`), with the encryption in transit and at rest defined by the server and the transfer specification. | [Transfer Specification](#transfer-specification) |
| Execution by a client that is not fully trusted (AI assistant, program that builds commands) | A security level restricts what commands can do: reading local files, executing code, writing files. The MCP server uses level `high` by default, and the client cannot change it. | [Security Level](#security-level) |
| AI assistants (MCP server) | The AI client cannot execute code, cannot write files outside the folders that the user allows, and never sees secrets. Over HTTP, a token is mandatory when the server is not on the loopback address, and OAuth 2.0 with PKCE is supported. | [MCP server security](#security) |
| Local web servers (login, MCP over HTTP) | They listen on the loopback address by default, with authentication and protection against cross-site requests. | [Web service](#web-service) |
| Usage data | <%=tool%> sends no usage data (no telemetry). It connects to the servers given in commands and presets, and to public IBM and GitHub locations only for the commands that download from them (for example `transferd install`, development guides). Every 7 days by default, it checks RubyGems for a new version (option `version_check_days`, `0` to disable). | [Configuration](#plugin-config-configuration) |

### Supply chain

- The gem is signed: its signature can be verified at installation, see [Verifying gem installation signature](#verifying-gem-installation-signature).
- Publishing the gem on RubyGems requires multi-factor authentication.
- Release packages (gem, single executable, portable packages, container image) are built by GitHub Actions from the repository.
- Dependencies are gems, updated with Renovate.
- The source code is analyzed by CodeQL and RuboCop in continuous integration, and tested by unit and integration tests, including tests of the security levels (coverage is shown in the README badge).

### Project practices

- Open source, Apache 2.0 license, developed in the [IBM GitHub organization](<%=gemspec.homepage%>).
- [OpenSSF Best Practices](https://www.bestpractices.dev/projects/5861): silver badge.
- Vulnerabilities are reported and handled as described in [SECURITY.md](<%=link_repo('SECURITY.md')%>).
- Roles, decisions and continuity of the project: [GOVERNANCE.md](<%=link_repo('GOVERNANCE.md')%>).
- Structure of the code: [ARCHITECTURE.md](<%=link_repo('docs/ARCHITECTURE.md')%>).

## About

### Hootput, the mascot

![Hootput the Owl](<%=link_repo('docs/art/mascot.svg')%>)

Hootput lives in the terminal, watching over every command with wide, unblinking eyes.
Known for concise output and sharp insight, this owl thrives where others get lost in the dark.
It doesn't chatter; it hoots: clear, precise, and always on time.

Like <%=tool%>, Hootput is built for action: launching transfers, parsing options, and navigating APIs without hesitation.
Light on feathers but heavy on wisdom, it turns complexity into simple one-liners.
When you hear Hootput's call, you know your data is already in flight.

### History

When I joined Aspera, there was only one CLI: `ascp`, the implementation of the FASP protocol, but there was no CLI to access the various existing products (Server, Faspex, Shares).
At some point, Serban (founder) provided a shell script able to create a Faspex package using the Faspex REST API.
Since all products relate to file transfers using FASP (`ascp`), I thought it would be interesting to have a unified CLI for FASP transfers.
Also, because `ascp` already existed, I conceived an extended tool: `eascp.pl`, which accepted all `ascp` options for transfers but was also able to transfer to Faspex and Shares (the destination was a kind of URI for the applications).

There were a few pitfalls:

- `eascp.pl` was written in the aging `perl` language, while most Aspera web application products (other than the Transfer Server) are written in `ruby`.
- It was only for transfers and was not able to call other product APIs.

So, it evolved into <%=tool%>:

- Portable: works on platforms supporting `ruby` (and `ascp`)
- Easy to install with the `gem` utility
- Supports transfers with multiple [Transfer Agents](#transfer-clients-agents); this is why transfer parameters moved from the `ascp` command line to the [**transfer-spec**](#transfer-specification) (more reliable, more standard)
- `ruby` is consistent with other Aspera products

Over time, a supported command-line tool `aspera` was developed in C++ and later deprecated.
It had the advantage of being relatively easy to install as a single executable (still using `ascp`), but it was too limited in scope and lacked many of the features of this CLI.

Enjoy a coffee on me:

```shell
<%=cmd%> config coffee
<%=cmd%> config coffee --ui=text
<%=cmd%> config coffee --ui=text --out.img.text=true
```

### References

Ruby gem: [<%=gemspec.metadata['rubygems_uri']%>](<%=gemspec.metadata['rubygems_uri']%>)

Ruby Doc: [<%=gemspec.metadata['documentation_uri']%>](<%=gemspec.metadata['documentation_uri']%>)

[Aspera APIs on IBM developer](https://developer.ibm.com/apis/catalog/?search=aspera)
