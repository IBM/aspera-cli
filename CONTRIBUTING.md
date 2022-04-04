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

```bash
ENABLE_COVERAGE=1 make test
```
