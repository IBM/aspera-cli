# Contributing
<!-- cspell:words passin -->
## Reporting Issues and Vulnerabilities

You can report issues at <https://github.com/IBM/aspera-cli/issues>

Before you go ahead please search existing issues for your problem.

To make sure that we can help you quickly please include and check the following information:

- Include the `ascli` version you are running in your report.
- If you are not running the latest version (please check) then update.
- Include your `ruby -e "puts RUBY_DESCRIPTION"`.

Thanks!

## Making Contributions

To fetch and test the gem for development, do:

```bash
git clone https://github.com/IBM/aspera-cli.git
cd aspera-cli
```

Then see [Running Tests](#running-tests).

If you want to contribute, please:

- Fork the project.
- Make your feature addition or bug fix.
- Add tests for it. This is important so I don't break it in a future version unintentionally.
- Run `rubocop` to comply for coding standards
- Update `CHANGELOG.md`
- Send a pull request on GitHub.

## Architecture

A list of classes are provided in <docs/uml.png>

Architecture:

![Architecture](docs/architecture.png)

The entry point is: `lib/aspera/cli/main.rb`.

Plugins are located in: `lib/aspera/cli/plugins`.

Transfer agents, in: `lib/aspera/agent`.

## Ruby version

Install Ruby using your prefered method.

To cleanup installed gems to start fresh:

```bash
make clean_gems
```

## Tool chain

TODO: document installation of tool chain.

Build system uses GNU Make.

### Environment

A few macros/envvars control some aspects:

| macro                       | description                          |
|-----------------------------|--------------------------------------|
| `ASPERA_CLI_TEST_CONF_FILE` | Path to configuration file with secrets for tests |
| `ASPERA_CLI_TEST_MACOS`     | Set to `true` if local HSTS running on macOS      |
| `ASPERA_CLI_TEST_PRIVATE`   | Path to private folder               |
| `ENABLE_COVERAGE`           | Tests with coverage analysis if set. |
| `SIGNING_KEY`               | Path to signing key to build Gem.    |
| `GEM_VERSION`               | Gem version to build container       |

Those macros can be set either in an env var, or on the `make` command line.

> **Note:** vars `ASPERA_CLI_TEST_` are typically set in user's shell profile.

To use the CLI directly from the development environment, add this to your shell profile:

```bash
dev_ascli=$HOME/github/aspera-cli
export PATH=$dev_ascli/bin:$PATH
export RUBYLIB=$dev_ascli/lib:$RUBYLIB
```

The env var `ASCLI_TRANSFER_SDK_LOCATION_URL` can be set to override the URL where the list of versions and download URLs for `transferd` can be retrieved, it can be useful to test new versions.

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

## Running Tests

First, a testing configuration file must be created.
From project top folder, execute:

```bash
mkdir ~/some_secure_folder
cp docs/test_env.conf ~/some_secure_folder/.
```

Fill `~/some_secure_folder/test_env.conf` with system URLs and credentials for tests.

Then tell where this file is located:

```bash
export ASPERA_CLI_TEST_CONF_FILE=~/some_secure_folder/test_env.conf
```

This project uses a `Makefile` for tests:

```bash
make test
```

When new commands are added to the CLI, new tests shall be added to the test suite in `tests/Makefile`.

### Special tests

Some gems are optional: `rmagick` and `grpc`, as they require compilation of native code which may cause problems.
By default, tests that use those gems are skipped.
To run them: `make optional`.
Those tests also require the optional gems to be installed: `make install_optional_gems`.

Some other tests require interactive input. To run them: `make interactive`

To run every test: `make full`

### Pre-release tests

For preparation of a release, do the following:

1. Select a ruby version to test with.
2. Remove all gems: `make clean_gems`
3. `cd tests && make full`

To test additional Ruby version, repeat the procedure with other Ruby versions.

## Coverage

A coverage report can be generated in folder `coverage` using gem `SimpleCov`.
Enable coverage monitoring using macro/envvar `ENABLE_COVERAGE`.

```bash
cd tests
make ENABLE_COVERAGE=1
```

Once tests are completed, or during test, consult the page: [coverage/index.html](coverage/index.html)

## Build

By default, the gem is built signed: `make`.
A private key is required to generate a signed Gem.
Its path must be set using macro/envvar `SIGNING_KEY`, see below.
The gem is signed with the public certificate found in `certs` and the private key (kept secret by maintainer).

```bash
make SIGNING_KEY=/path/to/vault/gem-private_key.pem
```

It is also possible to build an unsigned version for development purpose: `make unsigned_gem`.

### Gem Signature

Refer to <certs/README.md>

### gRPC stubs for transfer SDK

Update with:

```bash
make grpc
```

It downloads the latest proto file and then compiles it.

## Container image build

See [Container build](./container/README.md).

For operations, move to the folder:

```bash
cd container
```

## Single executable build

Initially, `rubyc` (gem [`ruby-packer`](https://github.com/pmq20/ruby-packer) and [here](https://github.com/you54f/ruby-packer)) was used to build a single executable.

<https://www.tebako.org/>

A modern version of this is now used: [`tebako`](https://github.com/tamatebako/tebako) for which a container is provided.

```bash
cd binary
make GEM_VERSION=4.11.0
```

## Development check list for new release

When preparing for a new release do the following:

- TODO

## Long Term Implementation and delivery improvements

- replace rest and oauth classes with ruby standard gems:
  - <https://github.com/rest-client/rest-client>
  - <https://github.com/oauth-xx/oauth2>
- use gem Thor <http://whatisthor.com/> (or other standard Ruby CLI manager)
- Package a single-file executable for various architectures with <https://github.com/pmq20/ruby-packer> (`rubyc`)
- look at <https://github.com/phusion/traveling-ruby>
