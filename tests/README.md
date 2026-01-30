# Testing Environment

The test environment uses two YAML files: a configuration file (server addresses and secrets) and a test definition file that describes each test case and the command line to run.

Previously the suite was Makefile-based; it was replaced for better portability (including Windows).

## Preparation of environment

First, a testing configuration file must be created (once).
From project top folder, execute:

```bash
mkdir ~/some_secure_folder
cp docs/test_env.conf ~/some_secure_folder/.
```

Fill `~/some_secure_folder/test_env.conf` with system URLs and credentials for tests.

Then, tell where this file is located (e.g. in your shell profile):

```bash
export ASPERA_CLI_TEST_CONF_URL=~/some_secure_folder/test_env.conf
```

## Test descriptions

When new commands are added to the CLI, add corresponding tests to `tests/tests.yml`.
Standard YAML formatting rules apply.
The executable is given by `command` (default: main CLI); the arguments are given by the `args` array.
Commands are run via the system `exec` call, not a shell, so no shell quoting or escaping is applied.
Test cases can be grouped and controlled with tags.

The following keys are supported in each test entry:

| Field         | Type     | Description                                      |
|---------------|----------|--------------------------------------------------|
| `description` | `String` | Human-readable description.                      |
| `$comment`    | `String` | Internal comment (e.g. for maintainers).         |
| `tags`        | `Array`  | Group tests or enable special behavior.          |
| `depends_on`  | `Array`  | Test case names that must run before this one.   |
| `command`     | `String` | Executable name (default: `ascli`).              |
| `args`        | `Array`  | Command-line arguments.                          |
| `env`         | `Hash`   | Environment variables for this test.             |
| `pre`         | `String` | Ruby code to run before the test.                |
| `post`        | `String` | Ruby code to run after the test.                 |
| `stdin`       | `String` | Standard input to the command.                   |
| `expect`      | `String` | Expected stdout (or stderr for must_fail).       |

Some tags have special meaning; others are only for grouping (e.g. to skip or select tests).

| Tag           | Description                                                       |
|---------------|-------------------------------------------------------------------|
| `nodoc`       | Do not include in generated documentation.                        |
| `must_fail`   | Test is expected to fail (non-zero exit); `expect` matches stderr.|
| `pre_cleanup` | If it fails, ignore it (used for cleanup steps).                  |
| `flaky`       | Known unstable test; failure is tolerated.                        |
| `save_output` | Save command output to a file named after the test case.          |
| `wait_value`  | Re-run until a value is produced (requires `save_output`).        |
| `tmp_conf`    | Use a temporary config file (config may be modified).             |
| `noblock`     | Do not wait for completion; save PID for later stop.              |

In `pre`/`post` Ruby code, `read_value_from(name)` reads output saved by a test with `save_output`; `stop_process(name)` stops a process started with `noblock`.

Values inside `$(...)` in YAML strings are evaluated as Ruby expressions.
Constants and helpers are defined in `rakelib/test.rake` and are available in `pre`/`post` and in `$(...)`.

## Running Tests

This project uses a `Rakefile` for tests.
You can run `rake` from any folder (it will find the `Rakefile` in a parent directory).
To list test tasks:

```bash
bundle exec rake -T ^test:
```

To run all tests (but a few), in a given order:

```shell
# Cleanup installed gems:
ls $(gem env gemdir)/gems/|sed -e 's/-[^-]*$//'|sort -u|xargs -n 1 gem uninstall -axI

# clean Gemfile.lock
rm -f Gemfile.lock
killall ascli

# re-install Gems
gem install bundler
bundle install

bundle exec rake clobber

# skip some tests
bundle exec rake test:skip'[nd_xfer_lst_once1 nd_xfer_lst_once2]'
bundle exec rake test:skip'[tag faspex]'

# run some tests first
bundle exec rake test:run'[tag interactive]'

# run remaining tests
bundle exec rake test:run
```

> [!NOTE]
> The `test:` rake tasks take an optional argument in `[]`.
> Use `tag &lt;name&gt;` to filter by tag; otherwise the argument is a list of test case names.
> Omit the argument to apply the task to all test cases.

## Pre-release tests

For preparation of a release, do the following:

1. Select a Ruby version to test with.
2. Run tests as in previous section.

To test additional Ruby version, repeat the procedure with other Ruby versions.

## Coverage

A coverage report is written to `tmp/coverage` when using the `SimpleCov` gem.
Enable it with the environment variable `ENABLE_COVERAGE`:

```bash
bundle exec rake test:run ENABLE_COVERAGE=1
```

Open [tmp/coverage/index.html](tmp/coverage/index.html) to view the report (during or after the run).
