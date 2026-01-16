# Contributing

## Reporting Issues and Vulnerabilities

If you encounter a problem or a security vulnerability, please report it on [GitHub Issues](https://github.com/IBM/aspera-cli/issues).

Before submitting a new issue:

- Search existing issues to see if your problem has already been reported or resolved.

To help us assist you efficiently, include the following in your report:

- The version of `ascli` you are using:

  ```bash
  ascli version
  ```

- Confirmation that you are using the latest version (update it if needed).
- Your Ruby version information:

  ```bash
  ruby -v
  ```

## Making Contributions

We welcome contributions to improve the `aspera-cli` project!

### Getting Started

Clone the repository and navigate to the project's root directory:

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

1. **Write tests** to ensure your changes are robust and prevent regressions.

1. Run `rubocop` to ensure your code follows the Ruby style guide.

1. Update `CHANGELOG.md` with a summary of your changes.

1. Submit a **pull request** with a clear description of your contribution.

> [!TIP]
> Make sure your pull request is focused and includes only relevant changes.

## Architecture

The overall architecture of `aspera-cli` is modular and extensible.

![Architecture](docs/architecture.png)

### Structure Highlights

- Entry Point:

  `lib/aspera/cli/main.rb`, CLI startup logic.

- Plugins:

  Located in `lib/aspera/cli/plugins`; plugins extend CLI functionality and encapsulate specific features.

- Transfer Agents:

  Found in `lib/aspera/agent`, these handle data transfer operations.

Class diagrams are provided in <docs/uml.png>

## Ruby Environment

`aspera-cli` is written in Ruby.
You can install Ruby using any method you prefer (e.g., `rbenv`, `rvm`, system package manager).

To start with a clean state and remove all installed gems:

```bash
bundle exec rake tools:clean_gems
```

> [!TIP]
> This is especially useful before testing across different Ruby versions or preparing for a release.

## Toolchain

The build system uses Ruby's `rake`.

### Environment

A few macros and environment variables control certain aspects of the build:

| Environment variable        | Description                                         |
|-----------------------------|-----------------------------------------------------|
| `ASPERA_CLI_TEST_CONF_URL`  | URL for configuration file with secrets for tests.  |
| `ASPERA_CLI_DOC_CHECK_LINKS`| Check links still exist during doc generation.      |
| `LOG_LEVEL`                 | Change log level in `rake` tasks.                   |
| `ENABLE_COVERAGE`           | Enable test coverage analysis when set.             |
| `SIGNING_KEY`               | Path to the signing key used to build the gem file. |
| `GEM_VERSION`               | Override gem version for builds.                    |

These can be set either as environment variables or directly on the `rake` command line.

> [!NOTE]
> Environment variables `ASPERA_CLI_*` are typically set in the user’s shell profile for development.
> Others are intended for use on the command line.

To use the CLI directly from the development environment, add this to your shell profile (adapt the real path):

```bash
dev_ascli=$HOME/github/aspera-cli
export PATH=$dev_ascli/bin:$PATH
export RUBYLIB=$dev_ascli/lib:$RUBYLIB
```

### Documentation

Documentation is generated with `pandoc` and `LaTeX`.

The IBM `Plex` font is used; for installation instructions, see [IBM Plex](https://www.ibm.com/plex/).

On macOS, to install `lualatex` and all packages:

```bash
brew install texlive
```

If `lualatex` is installed using another method, ensure that the following packages are installed:

```bash
tlmgr update --self
tlmgr install fvextra selnolig lualatex-math
```

To check URLs during documentation generation, set the environment variable: `ASPERA_CLI_DOC_CHECK_LINKS=1`.

To debug documentation generation, set the environment variable: `ASPERA_CLI_DOC_DEBUG=debug`.

## Test Environment

Refer to <tests/README.md>.

## Build

The unsigned gem is built with:

```bash
bundle install
bundle exec rake unsigned
```

If you don't want to install optional gems:

```bash
bundle config set without optional
```

To build a beta version:

```bash
export GEM_VERSION=$(env -u GEM_VERSION rake tools:version).$(date +%Y%m%d%H%M)
```

### Signed gem

A private key is required to generate a signed gem.
Its path must be set using environment variable `SIGNING_KEY`.
The gem is signed with the public certificate found in `certs` and the private key specified by `SIGNING_KEY` (kept secret by the maintainer).

```bash
bundle exec rake SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

Refer to <certs/README.md>.

### gRPC stubs for transfer SDK

Update with:

```bash
bundle exec rake tools:grpc
```

It downloads the latest `proto` file and then compiles it.

## Container image build

See [Container build](./container/README.md).

## Single executable build

See [Executable build](build/binary/README.md).

To list operations:

```bash
bundle exec rake -T ^binary:
```

## Release

### Checklist before a new release

When preparing for a new release, do the following:

- Run the test suite:

```bash
bundle exec rake test:run
```

- Verify that the container builds successfully (using the beta version):

```bash
export GEM_VERSION=$(env -u GEM_VERSION rake tools:version).$(date +%Y%m%d%H%M)
bundle exec rake container:build
bundle exec rake container:test
```

### Version Release Process

Once the development branch is ready for release:

- Merge branch `develop` into `main` branch

- Update the version in `lib/aspera/cli/version.rb` and check-in.

- Build the PDF manual in `pkg`:

```shell
bundle exec rake doc:build
```

- Build the signed `.gem` in `pkg`:

```shell
bundle exec rake SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

- Create the release version tag and push it to GitHub. This will trigger the action `.github/workflows/deploy.yml`, which builds the gem file and pushes it to [rubygems.org](https://rubygems.org/gems/aspera-cli).

```shell
bundle exec rake release_tag
```

- Include generated artifacts from `pkg/` in GitHub release:

  - The signed `.gem`
  - The PDF Manual

## Long‑Term Implementation and Delivery Improvements

- Replace custom REST and OAuth classes with standard Ruby gems:
  - <https://github.com/rest-client/rest-client>
  - <https://github.com/oauth-xx/oauth2>
- Use the `thor` gem <http://whatisthor.com/> (or other standard Ruby CLI manager)
- Look at <https://github.com/phusion/traveling-ruby>
