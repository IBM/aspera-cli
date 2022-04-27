# Contributing

## Reporting Issues and Vulnerabilities

You can report issues at <https://github.com/IBM/aspera-cli/issues>

Before you go ahead please search existing issues for your problem.

To make sure that we can help you quickly please include and check the following information:

* Include the ascli version you are running in your report.
* If you are not running the latest version (please check), update.
* Include your `ruby -e "puts RUBY_DESCRIPTION"`.

Thanks!

## Making Contributions

To fetch & test the gem for development, do:

```bash
git clone https://github.com/IBM/aspera-cli.git
cd aspera-cli
bundle install
make test
```

If you want to contribute, please:

* Fork the project.
* Make your feature addition or bug fix.
* Add tests for it. This is important so I don't break it in a future version unintentionally.
* **Bonus Points** go out to anyone who also updates `CHANGELOG.md` :)
* Send a pull request on GitHub.

## Running Individual Tests

First, a testing environment must be created:

```bash
mkdir local
cp docs/test_env.conf local/.
```

Fill `local/test_env.conf` with system URLs and credentials for tests.

This project uses a Makefile for tests:

```bash
cd tests
make
```

When new commands are added to the CLI, new tests shall be added to the test suite.

## Coverage

A coverage report can be generated in folder `coverage` using gem `SimpleCov`. Enable coverage monitoring using env var `ENABLE_COVERAGE`.

```bash
ENABLE_COVERAGE=1 make test
```

## Build

By default the gem is built signed: `make`.
The appropriate signing key is required, and its path must be set to env var `SIGNING_KEY`.
It is possible to build a non-signed version for development purpose: `make unsigned_gem`.

### Gem Signature

Refer to: <https://guides.rubygems.org/security/>

The gem is signed with the public certificate found in `certs` and a secret key (kept secret by maintainer).

To build the signed gem:

```bash
SIGNING_KEY=/path/to/signing_key.pem make
```

The user can activate gem signature verification on installation:

* Add the certificate to gem trusted certificates:

```bash
curl https://raw.githubusercontent.com/IBM/aspera-cli/main/certs/aspera-cli-public-cert.pem -so aspera-cli-certificate.pem
gem cert --add aspera-cli-certificate.pem
rm aspera-cli-certificate.pem
```

* Install the gem with `HighSecurity` or `MediumSecurity`: this will succeed only of the gem is trusted.

```bash
gem install -P HighSecurity aspera-cli
```
