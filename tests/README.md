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
| `vars`        | `Hash`   | Ruby variables for `$(...)`, `pre` and `post`.   |
| `pre`         | `String` | Ruby code to run before the test.                |
| `post`        | `String` | Ruby code to run after the test.                 |
| `stdin`       | `String` | Standard input to the command.                   |
| `expect`      | `String` | Expected stdout (or stderr for must_fail).       |
| `template`    | `String` | Member of this template (see below).             |
| `instantiate` | `String` | Instance of this template (see below).           |

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

In `pre`/`post` Ruby code, `t.saved_output(name)` reads output saved by a test with `save_output`; `t.stop_process(name)` stops a process started with `noblock`.

Values inside `$(...)` in YAML strings are evaluated as Ruby expressions.
Constants and helpers are defined in `rakelib/test.rake` and are available in `pre`/`post` and in `$(...)`.

A `t` variable (a `TestEnv::Context` instance) is always available in `pre`/`post` and `$(...)` expressions.
Its methods take an optional test case name (default: current test): `saved_output`, `stop_process`, `check_process`, `out_file`, `err_file`, `pid_file`, `resolve`.

### Test templates

Templates run the same set of tests on several systems (e.g. AoC and AoC for Enterprise).

An entry with `template: <template name>` is a member of that template.
It is not executed by itself.
An entry with `instantiate: <template name>` is an instance of that template.
It is replaced, at its position in `tests.yml`, by one test named `<instance>.<member>` per member of the template.
So, as for other tests, the execution order is the order in `tests.yml`.

For each generated test:

- `args`: the instance's `args` are placed before the member's `args`.
- `tags`: the instance name and the instance's `tags` are added to the member's `tags`.
- `vars`: the instance's `vars` are merged into the member's `vars` (the instance's value wins).
- `depends_on`: names of sibling members are replaced with `<instance>.<member>`, other names are unchanged.
- `t`: the same rule applies to names given to `t` methods, e.g. in instance `aoc_user_suite`, `t.saved_output(:awa_bearer)` reads the output of `aoc_user_suite.awa_bearer`.

An instance entry accepts only `instantiate`, `args`, `tags`, `vars`, `description` and `$comment`.
A template that is never instantiated, or an unknown template, is an error.

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
d="$(gem env gemdir)/gems"
ls "$d"|sed -e 's/-[^-]*$//'|sort -u|xargs -n 1 gem uninstall -axI
ls "$d"|while read e;do rm -fr $d/$e;done

# clean Gemfile.lock
rm -f Gemfile.lock

# re-install Gems
gem install bundler
bundle install

killall ascli;sleep 2
bundle exec rake clobber

# skip some tests
bundle exec rake test:skip'[tag fxgateway]'

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
