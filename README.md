# IBM Aspera CLI

**The automation interface for IBM Aspera. From command line to AI agents.**

[![Gem Version](https://badge.fury.io/rb/aspera-cli.svg)](https://badge.fury.io/rb/aspera-cli)
[![unit tests](https://github.com/IBM/aspera-cli/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/IBM/aspera-cli/actions)
[![coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/IBM/aspera-cli/main/docs/coverage.json)](tests/README.md#coverage)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/5861/badge)](https://bestpractices.coreinfrastructure.org/projects/5861)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

![Hootput the Owl](docs/art/mascot.svg)

**`ascli`** is an open-source toolkit to automate, integrate and operate IBM Aspera products.
Administrators, developers, integration engineers and AI agents use the same consistent interface to the whole Aspera ecosystem.

## What can you do with `ascli`?

- **Transfer**: run high-speed **FASP** transfers, with the transfer agent of your choice (`ascp`, Transfer Daemon, IBM Aspera for Desktop, HTTP Gateway, Node API).
- **Automate**: script transfers, packages, file management, administration and operational workflows.
- **Integrate**: call Aspera REST APIs as commands, with JSON, YAML, CSV or table output, filtered with JMESPath.
- **Operate**: Aspera on Cloud, Faspex, Shares, Node API, High-Speed Transfer Server, Console, Orchestrator, Cloud Object Storage.
- **Configure**: reusable presets per environment, secrets in a vault, never in scripts.
- **Diagnose**: analyze `ascp` logs to find why a transfer failed or is slow.
- **Use AI**: let AI assistants and agents operate Aspera, in a shell or through the MCP server, without seeing secrets.

One interface, several ways to use it:

| Interface | Usage |
| --------- | ----- |
| Command line | Interactive administration and operations |
| Shell scripts, schedulers, CI/CD | Repeatable automation and batch processing |
| Structured output | Integration with applications, monitoring and pipelines |
| MCP server, agent skill | AI assistants and AI agents |

## Get started

Install **Ruby** ≥ 3.3, then:

```bash
gem install aspera-cli
ascli transferd install
ascli -v
```

The second command installs the **FASP** transfer engine (`ascp`).
No Ruby? Use the single executable, the Linux or Windows portable package, Chocolatey or the container image: see [Installation](https://github.com/IBM/aspera-cli/blob/main/docs/README.md#installation).

## Try it in 60 seconds

No account needed: the public Aspera demo server is configured for you.

```bash
ascli config initdemo
ascli server browse /
ascli server download /aspera-test-dir-small/10MB.1
```

Watch it first: [IBM Aspera in 60 seconds](https://youtu.be/TBf1W1mmX0A) (video, 1 min 23 s), more demos on the [Aspera CLI YouTube channel](https://www.youtube.com/@AsperaCLI).

## Examples

```bash
# Upload 1 GB of generated data (no local file needed), at 500 Mbps maximum
ascli server upload 'faux:///test1g?1g' --to-folder=/Upload --ts.target_rate=500m

# Browse files in Aspera on Cloud
ascli aoc files browse /

# List packages in Faspex 5, as JSON for a script
ascli faspex5 packages list --format=json

# Diagnose transfers from ascp log files
ascli config ascp logs diagnostics /var/log/aspera.log

# Let an AI assistant operate Aspera
ascli mcp server
```

Each product has its own plugin (`aoc`, `faspex5`, `shares`, `node`, `server`, `console`, `orchestrator`, `cos`...).
`ascli <plugin> -h` lists its commands.

## Use with AI assistants

`ascli` lets AI assistants and AI agents (LLM) operate IBM Aspera products for you, with the same commands, presets and secrets as you:

- **In a shell** (coding agents): nothing to set up. Give the agent [`llms.txt`](https://github.com/IBM/aspera-cli/blob/main/llms.txt), or install the agent skill [`skills/ascli`](https://github.com/IBM/aspera-cli/tree/main/skills/ascli) (with Claude Code: `/plugin marketplace add IBM/aspera-cli`, then `/plugin install ascli@aspera-cli`): the agent then discovers commands, arguments and options by itself.
- **MCP server** (Model Context Protocol): `ascli mcp server` exposes all commands to any MCP client (IBM Bob, Claude, VS Code...), locally or over HTTPS with token or OAuth authentication.

MCP server setup: install the optional gem `mcp` with `ascli` (and `rack` for HTTPS), then declare the server in the MCP client (local, `stdio`):

```bash
gem install aspera-cli mcp
```

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

Safe by default: in the MCP server, the AI can neither execute code nor write files where it chooses, and never sees secrets.
See [Leveraging AI Assistance](https://github.com/IBM/aspera-cli/blob/main/docs/README.md#leveraging-ai-assistance) in the manual.

## Supported products

| Product | Plugin | What you can do |
| ------- | ------ | --------------- |
| IBM Aspera on Cloud | `aoc` | Files, packages, administration, Automation workflows |
| IBM Aspera Faspex 5 | `faspex5` | Packages, shared inboxes, administration |
| IBM Aspera Shares | `shares` | Files, administration |
| IBM Aspera High-Speed Transfer Server | `server`, `node` | Transfers over SSH, Node API, access keys, `ascp` logs |
| IBM Aspera Console | `console` | Transfers, administration |
| IBM Aspera Orchestrator | `orchestrator` | Workflows, work orders, plugins |
| IBM Cloud Object Storage | `cos` | Transfers to buckets |
| IBM Aspera HTTP Gateway | `httpgw` | Transfer agent, health |
| IBM Aspera faspio Gateway | `faspio` | Bridges, health, metrics |
| IBM Aspera Transfer Daemon | `transferd` | Install, run as a service, manage transfers |

## Documentation

| Resource | Link |
| -------- | ---- |
| **Documentation site** | [ibm.github.io/aspera-cli](https://ibm.github.io/aspera-cli/) (one page per section, [llms.txt](https://ibm.github.io/aspera-cli/llms.txt) for AI assistants) |
| **Online manual** | [GitHub docs/README.md](https://github.com/IBM/aspera-cli/blob/main/docs/README.md) |
| **PDF manual** | In [GitHub Releases](https://github.com/IBM/aspera-cli/releases) |
| **RubyGems** | [rubygems.org/gems/aspera-cli](https://rubygems.org/gems/aspera-cli) |
| **RubyDoc** | [rubydoc.info/gems/aspera-cli](https://www.rubydoc.info/gems/aspera-cli) |
| **Docsify** | [online](https://docsify-this.net/?basePath=https://raw.githubusercontent.com/IBM/aspera-cli/main/docs&homepage=README.md&sidebar=true&browser-tab-title=Aspera%20CLI%20Manual&hide-credits=true&maxLevel=4&externalLinkTarget=_blank&image-captions=true&dark-mode=auto) |

For debugging, use `--log-level=debug`.

## Trust

`ascli` is used to operate production systems, so the project follows strict practices: [OpenSSF Best Practices](https://www.bestpractices.dev/projects/5861) silver badge, high test coverage, a [security assurance case](https://github.com/IBM/aspera-cli/blob/main/docs/ASSURANCE_CASE.md), and secrets kept out of commands and AI clients.
For security and compliance reviews, see [Security and Trust](https://github.com/IBM/aspera-cli/blob/main/docs/README.md#security-and-trust) in the manual.

## Contributing

- **Questions, ideas, show and tell:** [GitHub Discussions](https://github.com/IBM/aspera-cli/discussions)
- **Bugs & features:** [BUGS.md](https://github.com/IBM/aspera-cli/blob/main/BUGS.md)
- **Security vulnerabilities:** [SECURITY.md](https://github.com/IBM/aspera-cli/blob/main/SECURITY.md)
- **How to contribute:** [CONTRIBUTING.md](https://github.com/IBM/aspera-cli/blob/main/CONTRIBUTING.md)
- **Code of conduct:** [CODE_OF_CONDUCT.md](https://github.com/IBM/aspera-cli/blob/main/CODE_OF_CONDUCT.md)
- **Governance:** [GOVERNANCE.md](https://github.com/IBM/aspera-cli/blob/main/GOVERNANCE.md)
- **Release notes:** [CHANGELOG.md](https://github.com/IBM/aspera-cli/blob/main/CHANGELOG.md)

## License

Open source, [Apache-2.0](https://github.com/IBM/aspera-cli/blob/main/LICENSE), by IBM.
