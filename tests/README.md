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

### Secrets

No secret value is stored in checked-in files, not even a test value: secrets are generated in `pre`, and used with `$(secret :<name>)`:

```yaml
node_emulator_start:
  pre: generated_secret(:emulator)
  args:
    - '@json:{"username":"sim","password":"$(secret :emulator)",...}'
```

`generated_secret(:<name>, value: nil)` creates file `tmp/secrets/<name>` (readable by the user only), unless it already exists, with `value`, or by default 20 random alphanumeric characters.
So the value is the same in all test runs: e.g. tests that depend on `node_emulator_start` use `$(secret :emulator)` without generating it.
`secret(:<name>)` reads the value in Ruby code, and fails if it was not generated.
In documentation, `$(secret :<name>)` is shown as `<PASSWORD>`.

In manual mode (`TEST_INTERACTIVE=manual`), the value to enter in the browser is in `tmp/secrets/<name>`: create this file beforehand to choose the value.

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

### Interactive Tests and Browser Automation

Tests tagged `interactive` involve prompts (terminal stdin), macOS Keychain, or web browser interactions (secret requests, OAuth consent):

* **Terminal input**: Injected automatically via test definition `stdin:`.
* **macOS Keychain**: Managed and unlocked automatically via a dedicated test keychain (`ascli`).
* **Web pages (`--ui=graphical`, `@secret:`)**: Handled by Google Chrome (via `ferrum`) or HTTP fallback.

The following environment variables control interactive test behavior:

| Variable | Values / Default | Description |
|---|---|---|
| `TEST_INTERACTIVE` | `auto` (default), `manual` | In `auto` mode, all interactions are handled without human intervention. In `manual` mode, the real system browser opens and waits for user input. |
| `TEST_HEADLESS` | `false` (default), `true` | When `false`, Chrome opens visibly on screen. Set to `true` for headless execution (ideal for CI/CD). |
| `TEST_DELAY` | `0.5` (default), float | Delay in seconds between actions (typing, clicking) in visible mode. Set to `0` for maximum speed. |
| `ASCLI_UI` | `ui` option value | Set by the test runner before each test (browser command `ruby tests/auto_browser.rb`, option `ui.command`). Not to be set manually. |

#### Login credentials for web pages

When a web login page is displayed (e.g. OAuth login for `--auth=web`), `tests/auto_browser.rb` fills the user name and password automatically.
Credentials differ by application, so each test selects the preset of the test configuration file that holds them (options `username` and `password`), using `select_browser` in `pre`.
It adds `--login-preset=<preset>` to the browser command, set with sub-option `command` of option `ui` (env var `ASCLI_UI`), which `ascli` runs with the URL to open:

```yaml
aoc_webauth_profile:
  tags:
    - interactive
  pre: "select_browser(login_preset: 'aoc_user')"
  args: ...
```

A test that does not call `select_browser` gets no automatic login.
Likewise, `select_browser(secret: :<name>)` and `select_browser(access_code: :<name>)` select the [generated secrets](#secrets) entered on secret pages (`@secret:`) and as access code on consent pages: the browser command gets only their names (`--secret=<name>`, `--access-code=<name>`).
The selection (`ASCLI_UI`) is cleared before each test.

The value is not read directly from the YAML file: it is evaluated by `ascli` itself (`ascli config echo @preset:<preset>.<option>`, using the home folder of the tests).
So any [Extended Value](../docs/README.md#extended-value-syntax) is supported: `@vault:`, `@file:`, `@extend:`, `@preset:`...

For example, to keep the password in a vault, declare the vault in the default preset (`cli_default`) of the test configuration file, and reference the secret in the preset:

```yaml
cli_default:
  vault:
    type: 1password
    source: cli
aoc_web:
  username: my_user@example.com
  password: "@vault:<item title or id>.password"
```

Any other vault type works the same way (e.g. `type: file` with `vault_password`).

> [!NOTE]
> With `1password` and `source: cli`, the `op` command must be signed in before running the tests.

Examples:

```bash
# Run interactive tests with Chrome visible (default settings)
bundle exec rake "test:run[tag interactive]"

# Run in headless mode (silent background execution for CI)
TEST_HEADLESS=true bundle exec rake "test:run[tag interactive]"

# Slow down web automation to observe each step (1.5s delay)
TEST_DELAY=1.5 bundle exec rake "test:run[tag interactive]"

# Manual mode (opens default system browser for user interaction)
TEST_INTERACTIVE=manual bundle exec rake "test:run[conf_echo_secret_web]"
```

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
