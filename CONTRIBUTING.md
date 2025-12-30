# Contributing
<!-- cspell:words passin -->
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
rake -T
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
rake tools:clean_gems
```

> [!TIP]
> This is especially useful before testing across different Ruby versions or preparing for a release.

## Tool chain

TODO: document installation of tool chain.

Build system uses Ruby's `rake`.

### Environment

A few macros/env vars control some aspects:

| Environment variable        | Description                          |
|-----------------------------|--------------------------------------|
| `ASPERA_CLI_TEST_CONF_FILE` | Path to configuration file with secrets for tests.      |
| `ASPERA_CLI_TEST_PRIVATE`   | Path to private folder with makefile for beta delivery. |
| `ASPERA_CLI_DOC_CHECK_LINKS`| Check links still exist during doc generation.          |
| `LOG_LEVEL`                 | Change log level in `rake` tasks.    |
| `ENABLE_COVERAGE`           | Tests with coverage analysis if set. |
| `SIGNING_KEY`               | Path to signing key to build Gem.    |
| `GEM_VERSION`               | Override gem version for builds.     |

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

The test envornment is composed with a YAML configuration file with server addresses and secrets and a YAML file describing tests, including the command line to run.

Previously it was based on Makefile, but this has been replaced for better portability to the Windows OS.

### Preparation of environment

First, a testing configuration file must be created (once).
From project top folder, execute:

```bash
mkdir ~/some_secure_folder
cp docs/test_env.conf ~/some_secure_folder/.
```

Fill `~/some_secure_folder/test_env.conf` with system URLs and credentials for tests.

Then, tell where this file is located (e.g. in your shell profile):

```bash
export ASPERA_CLI_TEST_CONF_FILE=~/some_secure_folder/test_env.conf
```

### Test descriptions

When new commands are added to the CLI, new tests shall be added to the test suite in `tests/tests.yml`.

### Running Tests

This project uses a `Rakefile` for tests.
`rake` can be executed in any folder (it will look for the `Rakefile` in one of the parent folders).
To lists test tasks:

```bash
rake -T test:
```

To force run all tests:

```bash
rake test:reset
rake test:run
```

### Special tests

Some gems are optional: `rmagick` and `grpc`, as they require compilation of native code which may cause problems.
By default, tests that use those gems are skipped.
To run them: `make optional`.
Those tests also require the optional gems to be installed: `make install_optional_gems`.

Some other tests require interactive input. To run them: `make interactive`

To run every test: `make full`

### Pre-release tests

For preparation of a release, do the following:

1. Select a Ruby version to test with.
2. Remove all gems: `rake tools:clean_gems`
3. Install gems: `bundle install`
4. `rake test:run`

To test additional Ruby version, repeat the procedure with other Ruby versions.

## Coverage

A coverage report can be generated in folder `coverage` using gem `SimpleCov`.
Enable coverage monitoring using macro/envvar `ENABLE_COVERAGE`.

```bash
rake test:run ENABLE_COVERAGE=1
```

Once tests are completed, or during test, consult the page: [coverage/index.html](coverage/index.html)

## Build

By default, the gem is built signed: `rake build`.
A private key is required to generate a signed Gem.
Its path must be set using macro/envvar `SIGNING_KEY`, see below.
The gem is signed with the public certificate found in `certs` and the private key pointed by `SIGNING_KEY` (kept secret by maintainer).

```bash
rake build SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

It is also possible to build an unsigned version for development purpose: `make unsigned_gem`.

### Gem Signature

Refer to <certs/README.md>

### gRPC stubs for transfer SDK

Update with:

```bash
rake tools:grpc
```

It downloads the latest proto file and then compiles it.

## Container image build

See [Container build](./container/README.md).

For operations, move to the folder:

```bash
cd container
```

## Single executable build

See [Executable build](build/binary/README.md).

To list operations:

```bash
rake -T ^binary:
```

## Development check list for new release

When preparing for a new release do the following:

- TODO

## Long Term Implementation and delivery improvements

- replace Rest and OAuth classes with ruby standard gems:
  - <https://github.com/rest-client/rest-client>
  - <https://github.com/oauth-xx/oauth2>
- use gem Thor <http://whatisthor.com/> (or other standard Ruby CLI manager)
- look at <https://github.com/phusion/traveling-ruby>
