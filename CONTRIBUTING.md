# Contributing

## Reporting Issues

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

This project uses a Makefile for tests:

```bash
cd tests
make
```
