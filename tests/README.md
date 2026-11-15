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
| `tty`         | `Boolean`| Run the command in a pseudo-terminal (see below).|
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
`select_browser` displays it on terminal, and test `conf_echo_secret_web` also shows it on the web page, in the prompt of `@secret:`.

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
bundle exec rake test:skip'[tag fx_gateway]'

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

Tests tagged `interactive` are those where, without automation, a human would have to act: answer a prompt on the terminal, use a web page, unlock the macOS Keychain, or give a `sudo` password.
Data given on `stdin:` to a command that reads its input (e.g. `@stdin:`, MCP over stdio) is not an interaction: such tests are not tagged.

In `auto` mode, a test tagged `interactive` is stopped after `TEST_TIMEOUT` seconds (default 300, `0` for no limit), because it probably waits for a human.
There is no limit in `manual` mode.
The limit applies to the command of the test, not to the `pre` and `post` code.

- **Terminal input**: Injected automatically via test definition `stdin:`.
- **Pseudo-terminal**: With `stdin:`, the command reads a file, so `$stdin.tty?` is false: the masked input of secrets (`getpass`) and the questions asked only on a terminal (e.g. trusting the host of `config web_login`) are not run. A test with `tty: true` runs the command in a pseudo-terminal (`PTY.spawn`) instead: each line of `stdin:` is typed when the command displays a prompt (output ending with `> `), the typed characters are not displayed when the command hides them. The text displayed on the terminal is saved in `tmp/states/<test>.tty` (e.g. for a `post` that checks that a secret is not displayed). The output of the command goes to the terminal, so `expect` and `save_output` work with `--out.file` only (set by `save_output`); `stderr` is not separated. The timeout applies as for other `interactive` tests. `tty: true` cannot be combined with `noblock`, and does not capture `must_fail` messages in a file.
- **`--interactive=yes`**: the test configuration sets `interactive` to `no` (preset `cli_default`), so a test of the interactive input of missing arguments gives `--interactive=yes` on the command line. Test `conf_echo_interactive` runs `config echo` without argument: the value is asked (`argument: value>`) and read on `stdin:`.
- **Wizard**: tests of `config wizard` run with `ASCLI_WIZ_TEST=yes`, which skips the steps that wait for the user (`Enter` after the public key, mandatory client id and secret of Faspex 5). A test that covers those steps sets `ASCLI_WIZ_TEST: ~` in `env:` (the value of the test is not overwritten) and gives the answers in `stdin:`.
- **macOS Keychain**: Managed and unlocked automatically via a dedicated test keychain (`ascli`).
- **Web pages (`--ui=graphical`, `@secret:`)**: Handled by Google Chrome (via `ferrum`) or HTTP fallback.

The following environment variables control interactive test behavior:

| Variable | Values / Default | Description |
| --- | --- | --- |
| `TEST_INTERACTIVE` | `auto` (default), `manual` | In `auto` mode, all interactions are handled without human intervention. In `manual` mode, the real system browser opens and waits for user input. |
| `TEST_HEADLESS` | `false` (default), `true` | When `false`, Chrome opens visibly on screen. Set to `true` for headless execution (no visible window). |
| `TEST_TIMEOUT` | `300` (default), seconds | Maximum duration of the command of a test tagged `interactive`, in `auto` mode only. `0` removes the limit. |
| `TEST_LOGIN_TIMEOUT` | `120` (default), seconds | Maximum wait of `tests/auto_browser.rb` for the end of a login on an external page. Keep it lower than `TEST_TIMEOUT`, so that its message is the one reported. |
| `TEST_DELAY` | `0.5` (default), float | Delay in seconds between actions (typing, clicking) in visible mode. Set to `0` for maximum speed. |
| `ASCLI_UI` | `ui` option value | Set by the test runner before each test (browser command `ruby tests/auto_browser.rb`, option `ui.command`). Not to be set manually. |

#### Failures that need a human

In `auto` mode, a test fails quickly, with a message that says which human action would have been needed, instead of waiting:

- the command does not end within `TEST_TIMEOUT` seconds: it is stopped, with its child processes (e.g. the browser);
- `tests/auto_browser.rb` exits with an error if the login does not end within `TEST_LOGIN_TIMEOUT` seconds, if the login page asks for a second factor (one-time code) or a captcha, or if `ferrum` is not installed for an external login page (use `TEST_INTERACTIVE=manual`);
- if a preset selected by `select_browser(login_preset: ...)` has no `username` or no `password`, the test fails before the command is run.

#### Limits

- The login tests on real services (`aoc_webauth_profile`, `aoc_webauth_profile_refresh`, `f5_webauth`) need a test account **without MFA** (no second factor, no captcha): MFA and TOTP are not supported.
- Tests that use IBM Aspera Connect or IBM Aspera Desktop (`aoc_files_download_connect`, `aoc_files_download_desktop`) are not automated.
- These tests are run by hand, on a workstation (Chrome, macOS Keychain, test configuration file with credentials): they are not run in a CI environment.
- The mock IdP covers the authorization code flow of Faspex 5 only (not Shares, not AoC).
- With `tty: true`, `stdout` and `stderr` are mixed on the terminal.

#### Local mock IdP for `--auth=web`

`tests/mock_idp.rb` is a local server (no real account, no MFA) that mocks a Faspex 5: authorization page (`/aspera/faspex/auth/authorize`), token endpoint (authorization code and refresh), a ping, and the list of packages.
Test `f5_mock_idp_start` (`noblock`) starts it on `127.0.0.1:13783`, with an access code generated by `generated_secret(:mock_idp_auth)`; test `f5_mock_webauth` runs `faspex5 package list --auth=web` against it, depends on the first, and stops the server in `post`.
The authorization page is handled by `tests/auto_browser.rb` (Chrome, or HTTP fallback if `ferrum` is not installed): it enters the access code, allows, and the redirection reaches the callback server of `ascli`.

Two more tests use the same server, to cover `--ui.web_auth=paste` (the browser cannot reach the loopback address of the host that runs `ascli`):

- `f5_mock_webauth_paste` (`tty: true`, server started by its own test `f5_mock_idp_paste_start`: a rake task runs once and the server is stopped by `post` of the test that uses it) runs `faspex5 package list --auth=web --ui.web_auth=paste`. `ascli` displays the URL of the login page and waits at the `Code or URL>` prompt. The line of `stdin:` is evaluated when it is typed: `mock_idp_paste_reply(screen, :mock_idp_auth)` (in `test_helpers.rb`) reads the URL in the text displayed so far (`screen`), allows the access on the mock IdP like a user, and returns the URL of the redirection (with `code` and `state`), as copied from the address bar of the browser. `ASCLI_UI` is unset: no browser is started.
- `conf_web_login` (`tty: true`) runs `config web_login <code>`, for the workstation that has the browser. The code is made in the arguments with `web_login_code(...)` (`SealedHash`, type login). The login page shall be `https`, so test `f5_mock_idp_https_start` starts the mock IdP with `--https` (self-signed certificate; `auto_browser.rb` accepts it for loopback addresses only). The host is not known: `pre` deletes the persisted list of trusted hosts, the question `Open it, and trust this host for next logins? (yes/no)>` is answered `yes` on the terminal, and `post` checks that the question was displayed and that the host is persisted. Then the mock IdP page is opened by `auto_browser.rb`, and the redirection is received by `config web_login`.

#### Login credentials for web pages

When a web login page is displayed (e.g. OAuth login for `--auth=web`), `tests/auto_browser.rb` fills the user name and password automatically.
Credentials differ by application, so each test selects the preset of the test configuration file that holds them (options `username` and `password`), using `select_browser` in `pre`: `aoc_user_web` for Aspera on Cloud and `f5_user_web` for Faspex 5 (see `docs/test_env.conf`, without secret value).
It adds `--login-preset=<preset>` to the browser command, set with sub-option `command` of option `ui` (env var `ASCLI_UI`), which `ascli` runs with the URL to open:

```yaml
aoc_webauth_profile:
  tags:
    - interactive
  pre: "select_browser(login_preset: 'aoc_user_web')"
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
