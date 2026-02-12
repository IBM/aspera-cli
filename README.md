# Aspera CLI

[![Gem Version](https://badge.fury.io/rb/aspera-cli.svg)](https://badge.fury.io/rb/aspera-cli)
[![unit tests](https://github.com/IBM/aspera-cli/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/IBM/aspera-cli/actions)
[![CII Best Practices](https://bestpractices.coreinfrastructure.org/projects/5861/badge)](https://bestpractices.coreinfrastructure.org/projects/5861)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**`ascli`** is the command-line interface for IBM Aspera products.
Use it from the terminal or in scripts to:

- Drive **Aspera on Cloud**, **Faspex**, **Shares**, **Node**, **Console**, **Orchestrator**, and **High-Speed Transfer Server**
- Call REST APIs and run high-speed transfers (**FASP**)
- Automate workflows with config, presets, and scripting

## Documentation

Choose what best suits you:

| Resource | Link |
|----------|------|
| **Online manual** | [docs/README.md](docs/README.md) |
| **PDF manual** | In [releases](https://github.com/IBM/aspera-cli/releases) |
| **RubyGems** | [rubygems.org/gems/aspera-cli](https://rubygems.org/gems/aspera-cli) |
| **RubyDoc** | [rubydoc.info/gems/aspera-cli](https://www.rubydoc.info/gems/aspera-cli) |
| **Docsify** | [online](https://docsify-this.net/?basePath=https://raw.githubusercontent.com/IBM/aspera-cli/main/docs&homepage=README.md&sidebar=true&browser-tab-title=Aspera%20CLI%20Manual&hide-credits=true&maxLevel=4&externalLinkTarget=_blank&image-captions=true&dark-mode=auto) |

## Install

Install **Ruby** ≥ 3.1

```bash
gem install aspera-cli
ascli config transferd install
```

The second command installs the **FASP** transfer engine (`ascp`).
For other install methods (single executable, Docker, Chocolatey, Homebrew), see the [user manual](docs/README.md#installation).

**Quick check:**

```bash
ascli -v
```

## Contributing

- **Bugs & features:** [BUGS.md](BUGS.md)
- **How to contribute:** [CONTRIBUTING.md](CONTRIBUTING.md)
- **Release notes:** [CHANGELOG.md](CHANGELOG.md)

Commands map to Aspera REST APIs; see the manual for options.
For debugging, use `--log-level=debug`.

## License

[Apache-2.0](LICENSE)
