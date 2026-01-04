# Contributing

## Reporting Issues and Vulnerabilities

If you encounter a problem or vulnerability, please report it at [GitHub Issues](https://github.com/IBM/aspera-cli/issues).

Before submitting a new issue:

- Search existing issues to see if your problem has already been reported or resolved.

To help us assist you efficiently, include the following in your report:

- The version of `ascli` you are using:

  ```bash
  ascli version
  ```

- Confirmation that you're using the latest version (update if not).
- The output of your Ruby environment:

  ```bash
  ruby -v
  ```

## Making Contributions

We welcome contributions to improve the `aspera-cli` project!

### Getting Started

Clone the repository and navigate to the project's main folder:

```bash
git clone https://github.com/IBM/aspera-cli.git
cd aspera-cli
bundle install
bundle exec rake -T
```

For testing instructions, refer to [Running Tests](#running-tests).

### How to Contribute

To submit a contribution:

1. **Fork** the repository on GitHub.

1. **Create a feature branch** for your changes.

1. **Implement** your feature or bug fix.

1. **Write tests** to ensure your changes are robust and won’t break future versions.

1. Run `rubocop` to ensure your code follows the Ruby style guide.

1. Update `CHANGELOG.md` with a summary of your changes.

1. Submit a **pull request** with a clear description of your contribution.

> [!TIP]
> Make sure your pull request is focused and includes only relevant changes.

## Architecture

The overall architecture of `aspera-cli` is modular and extensible.

![Architecture](docs/architecture.png)

Structure Highlights:

- Entry Point:

  `lib/aspera/cli/main.rb` - This is where the CLI execution begins.

- Plugins:

  Located in `lib/aspera/cli/plugins`, plugins extend CLI functionality and encapsulate specific features.

- Transfer Agents:

  Found in `lib/aspera/agent`, these handle data transfers operations.

A list of classes are provided in <docs/uml.png>

## Ruby version

`aspera-cli` is built with Ruby.
You can install Ruby using any method you prefer (e.g., `rbenv`, `rvm`, system package manager).

To start with a clean state and remove all installed gems:

```bash
bundle exec rake tools:clean_gems
```

> [!TIP]
> This is especially useful before testing across different Ruby versions or preparing for a release.

## Tool chain

TODO: document installation of tool chain.

Build system uses Ruby's `rake`.

### Environment

A few macros/env vars control some aspects:

| Environment variable        | Description                                        |
|-----------------------------|----------------------------------------------------|
| `ASPERA_CLI_TEST_CONF_FILE` | Path to configuration file with secrets for tests. |
| `ASPERA_CLI_DOC_CHECK_LINKS`| Check links still exist during doc generation.     |
| `LOG_LEVEL`                 | Change log level in `rake` tasks.                  |
| `ENABLE_COVERAGE`           | Tests with coverage analysis if set.               |
| `SIGNING_KEY`               | Path to signing key to build Gem.                  |
| `GEM_VERSION`               | Override gem version for builds.                   |

Those macros can be set either in an env var, or on the `rake` command line.

> [!NOTE]
> Env vars `ASPERA_CLI_*` are typically set in user's shell profile for development.
> Others are more for "one shot" use (on command line).

To use the CLI directly from the development environment, add this to your shell profile (adapt the real path):

```bash
dev_ascli=$HOME/github/aspera-cli
export PATH=$dev_ascli/bin:$PATH
export RUBYLIB=$dev_ascli/lib:$RUBYLIB
```

### Documentation

Documentation is generated with `pandoc` and `LaTeX`.

IBM font `Plex` is used, for installation see [IBM Plex](https://www.ibm.com/plex/).

On macOS to install `lualatex` and all packages:

```bash
brew install texlive
```

If `lualatex` is installed using another method, ensure that the following packages are installed:

```bash
tlmgr update --self
tlmgr install fvextra selnolig lualatex-math
```

To check URL during doc generation, set env var: `ASPERA_CLI_DOC_CHECK_LINKS=1`.

To debug doc generation, set env var: `ASPERA_CLI_DOC_DEBUG=debug`.

## Test Environment

Refer to <tests/README.md>.

## Build

The gem is built with:

```bash
bundle install
bundle exec rake build
```

If you don't want to install optional gems:

```bash
bundle config set without optional
```

Build beta version:

```bash
export GEM_VERSION=$(env -u GEM_VERSION rake tools:version).$(date +%Y%m%d%H%M)
```

### Signed gem

A private key is required to generate a signed Gem.
Its path must be set using envvar `SIGNING_KEY`.
The gem is signed with the public certificate found in `certs` and the private key pointed by `SIGNING_KEY` (kept secret by maintainer).

```bash
bundle exec rake build SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

Refer to <certs/README.md>.

### gRPC stubs for transfer SDK

Update with:

```bash
bundle exec rake tools:grpc
```

It downloads the latest proto file and then compiles it.

## Container image build

See [Container build](./container/README.md).

## Single executable build

See [Executable build](build/binary/README.md).

To list operations:

```bash
bundle exec rake -T ^binary:
```

## Development check list for new release

When preparing for a new release do the following:

- Run test suite:

```bash
bundle exec rake test:run
```

- Set beta version:

```bash
export GEM_VERSION=$(env -u GEM_VERSION rake tools:version).$(date +%Y%m%d%H%M)
```

- Check that container builds (using beta):

```bash
bundle exec rake container:build
bundle exec rake container:test
```

## Long Term Implementation and delivery improvements

- replace Rest and OAuth classes with ruby standard gems:
  - <https://github.com/rest-client/rest-client>
  - <https://github.com/oauth-xx/oauth2>
- use gem Thor <http://whatisthor.com/> (or other standard Ruby CLI manager)
- look at <https://github.com/phusion/traveling-ruby>
