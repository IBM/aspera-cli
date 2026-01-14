# Testing Environment

The test environment is composed with a YAML configuration file with server addresses and secrets and a YAML file describing tests, including the command line to run.

Previously it was based on Makefile, but this has been replaced for better portability to the Windows OS.

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

When new commands are added to the CLI, corresponding tests shall be added to the test suite in `tests/tests.yml`.
YAML formatting rules apply.
The command to execute is described by an array: `command`.
It does not include any shell special character protection because it is actually not executed by a shell: it's executed by the system's `exec` call.
Test cases are assigned some tags.

The following keys are supported in test description:

| Field         | Type     | Description                            |
|---------------|----------|----------------------------------------|
| `description` | `String` | Description.                           |
| `$comment`    | `String` | Internal comment.                      |
| `tags`        | `Array`  | Group test cases, or special handling. |
| `depends_on`  | `Array`  | Dependency.                            |
| `command`     | `Array`  | Command line arguments.                |
| `env`         | `Hash`   | Environment variables to set.          |
| `pre`         | `String` | Ruby code to execute before test.      |
| `post`        | `String` | Ruby code to execute after test.       |
| `stdin`       | `String` | Input to command.                      |
| `expect`      | `String` | Expected output.                       |

Some tags have special meaning while other tags are only a way to group test cases together (for example to skip them).

| Tag           | Description                                            |
|---------------|--------------------------------------------------------|
| `nodoc`       | Do not include in documentation.                       |
| `ignore_fail` | If it fails, ignore it, it's a cleanup.                |
| `must_fail`   | Must fail case.                                        |
| `hide_fail`   | Do not show failure. Test should work but it does not. |
| `save_output` | Output is saved in a file with same name as test case. |
| `wait_value`  | Run test until output get a value (requires `save_output`). |
| `tmp_conf`    | Use temporary config file (config is modified).        |
| `noblock`     | Do not wait completion, save PID.                      |

Function `read_value_from` reads a value previously saved with `save_output`.
Function `stop_process` reads the PID value previously saved with `noblock`.

Values inside `$(...)` are evaluated as Ruby expressions.
Some constants are defined in `test.rake` and can be used.

## Running Tests

This project uses a `Rakefile` for tests.
`rake` can be executed in any folder (it will look for the `Rakefile` in one of the parent folders).
To lists test tasks:

```bash
bundle exec rake -T ^test:
```

To force run all tests:

```bash
bundle exec rake test:reset
bundle exec rake test:run
```

To skip some tests by tags:

```bash
bundle exec rake test:skip'[tag faspex tag2]'
```

> [!NOTE]
> The first parameter: `tag` tells that the next parameters are tags, else it's a test case name.
> No parameter: apply to all test cases.

## Pre-release tests

For preparation of a release, do the following:

1. Select a Ruby version to test with.
2. Remove all gems: `bundle exec rake tools:clean_gems`
3. Install gems: `bundle install`
4. `bundle exec rake test:run`

To test additional Ruby version, repeat the procedure with other Ruby versions.

## Coverage

A coverage report can be generated in folder `coverage` using gem `SimpleCov`.
Enable coverage monitoring using environment variable `ENABLE_COVERAGE`.

```bash
bundle exec rake test:run ENABLE_COVERAGE=1
```

Once tests are completed, or during test, consult the page: [tmp/coverage/index.html](tmp/coverage/index.html)
