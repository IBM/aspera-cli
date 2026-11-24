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

### Dedicated SSH Server for Local Node Tests (macOS)

Some local node and transfer tests (e.g. `preview_ak`, `nd_ak_bearer_*`) require an active local SSH server for the `xfer` user.
On enterprise-managed macOS machines, the system Remote Login service (`sudo systemsetup -setremotelogin on`) is often automatically disabled by security policies.

To run these tests without requiring `sudo` or relying on macOS Remote Login, set up a dedicated `sshd` instance listening only on `127.0.0.1:33001`.

#### 1. Create the `xfer` user and authorized keys

```bash
# Create user if it does not exist
sudo /usr/sbin/sysadminctl -addUser xfer

# Setup docroot and SSH keys (using Aspera token auth public key)
sudo mkdir -p /Users/xfer/.ssh /Users/xfer/docroot/previews
sudo cp /Library/Aspera/var/aspera_tokenauth_id_rsa.pub /Users/xfer/.ssh/authorized_keys
sudo chown -R xfer: /Users/xfer/docroot /Users/xfer/.ssh
sudo chmod 700 /Users/xfer/.ssh
sudo chmod 600 /Users/xfer/.ssh/authorized_keys
sudo /bin/chmod -R +a "$(whoami) allow write" /Users/xfer/docroot
```

#### 2. Create the dedicated `sshd` configuration

Create `/Library/Aspera/etc/sshd_aspera_config` (owned by `root:wheel`, permissions `0600`):

```text
Port 33001
ListenAddress 127.0.0.1
Protocol 2

SyslogFacility AUTH
LogLevel INFO

# Authentication
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

# Ciphers and algorithms (enable ssh-rsa for Aspera client compatibility)
HostkeyAlgorithms +ssh-rsa
PubkeyAcceptedAlgorithms +ssh-rsa

# Security & limits
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PrintMotd no
PrintLastLog no
TCPKeepAlive yes
ClientAliveInterval 20
ClientAliveCountMax 3

# Restrict to transfer user
AllowUsers xfer

Match User xfer
    PubkeyAuthentication yes
    PubkeyAcceptedAlgorithms +ssh-rsa
    AuthorizedKeysFile /Users/xfer/.ssh/authorized_keys
```

#### 3. Create the LaunchDaemon

Create `/Library/LaunchDaemons/com.aspera.sshd.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aspera.sshd</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/sbin/sshd</string>
        <string>-D</string>
        <string>-f</string>
        <string>/Library/Aspera/etc/sshd_aspera_config</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/Library/Logs/Aspera/sshd_aspera.log</string>
</dict>
</plist>
```

Load the service:

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.aspera.sshd.plist
```

#### 4. Configure Aspera Node

Configure `asconfigurator` to use port `33001`:

```bash
sudo asconfigurator -x 'server;server_name,my_local_server;ssh_port,33001;enable_http,true;enable_https,true;listen,"127.0.0.1:9091,127.0.0.1:9092s";wss_enabled,false'
```

In `docs/test_env.conf` (and your private test configuration file), set `preview_ak.ts.ssh_port: 33001`.

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
| `priority`    | `Integer`| Run earlier: 1 is the highest (see below).       |
| `command`     | `String` | Executable name (default: `ascli`).              |
| `args`        | `Array`  | Command-line arguments.                          |
| `harness`     | `Hash`   | Options for the test only, not in the manual.    |
| `env`         | `Hash`   | Environment variables for this test.             |
| `vars`        | `Hash`   | Ruby variables for `$(...)`, `pre` and `post`.   |
| `pre`         | `String` | Ruby code to run before the test.                |
| `post`        | `String` | Ruby code to run after the test.                 |
| `stdin`       | `String` | Standard input to the command.                   |
| `expect`      | `String` | Expected stdout (or stderr for must_fail).       |
| `template`    | `String` | Member of this template (see below).             |
| `instantiate` | `String` | Instance of this template (see below).           |

The commands of the tests (`args`) are shown as examples in the manual, except for tests tagged `no_doc`.
Options needed only by the test procedure go in `harness`: they are added after `args` when the test runs, and are not shown in the manual.
Each key gives an option `--<key>=<value>`: a `Hash` or `Array` value is given as `@json:`, other values as is.
For example, a test that waits for an item created by a previous test:

```yaml
  args:
    - node
    - service
    - list
  harness:
    poll:
      interval: 5
      max: 60
      until: "contains([].id,'service1')"
      show: last
```

Tests are executed and listed in this order:

1. A test comes after the tests in its `depends_on`.
2. `priority`: 1 is the highest; a test without `priority` comes after all tests with one.
3. Position in `tests.yml`.

For example, give a priority to tests that need a human (`interactive`, password entry), so that they run at the start, followed by unattended tests.
A test with a priority brings its dependencies forward with it.
Test names given on the command line run in the given order.

Some tags have special meaning (active tags, listed below); others are only for grouping (e.g. to skip or select tests).
A grouping tag shall be used by at least 2 tests (the tests of the plugin with that name count): a tag used by a single test is rejected, as it is probably a typo. Active tags are valid even for a single test. Tags `tty` and `background` cannot be combined.

| Tag           | Description                                                       |
|---------------|-------------------------------------------------------------------|
| `no_doc`      | Do not include in generated documentation.                        |
| `must_fail`   | Test is expected to fail (non-zero exit); `expect` matches stderr.|
| `cleanup`     | If it fails, ignore it (used for cleanup steps).                  |
| `flaky`       | Known unstable test; failure is tolerated.                        |
| `save_output` | Save command output to a file named after the test case.          |
| `tmp_conf`    | Use a temporary config file (config may be modified).             |
| `background`  | Do not wait for completion; save PID for later stop.              |
| `tty`         | Run the command in a pseudo-terminal (see below).                 |
| `interactive` | A human would have to act (see below).                            |

A test that waits for a value (e.g. a package received, a folder created) repeats its command with option `poll` in `harness` (see above), instead of a `sleep` in `post` of the previous test.
When the previous test is a deletion done asynchronously by the server (e.g. `node service delete`) and the next one creates the same item again, a read test tagged `no_doc` polls between them until the item is gone (e.g. `nd_service_clean_wait`).

A `background` test is started when its process has written its PID file (at most `BACKGROUND_START_TIMEOUT` seconds).
Its process is usually stopped by the `post` of the test that uses it, but its state stays `passed`.
So `test:reset` resets the tests that depend on the selected ones, and also the `background` tests that the selected ones depend on (directly or not) and whose process has ended (no PID file), with their own dependents: e.g. `rake "test:reset[conf_web_login]"` also resets `f5_mock_idp_https_start`, so that the mock IdP is started again.

In `pre`/`post` Ruby code, `t.saved_output(name)` reads output saved by a test with `save_output`; `t.stop_process(name)` stops a process started with `background`.
`wait_listening(port, tls: false)` waits until a server accepts connections (`tls: true` for an HTTPS server: completes the TLS handshake), e.g. in `post` of a `background` test that starts a server, or before the first request to it.

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
So, as for other tests, the position in `tests.yml` gives the execution order (after dependencies and `priority`).

For each generated test:

- `args`: the instance's `args` are placed before the member's `args`.
- `tags`: the instance name and the instance's `tags` are added to the member's `tags`.
- `vars`: the instance's `vars` are merged into the member's `vars` (the instance's value wins).
- `priority`: the instance's `priority`, if any, replaces the member's.
- `depends_on`: names of sibling members are replaced with `<instance>.<member>`, other names are unchanged.
- `t`: the same rule applies to names given to `t` methods, e.g. in instance `aoc_user_suite`, `t.saved_output(:awa_bearer)` reads the output of `aoc_user_suite.awa_bearer`.

An instance entry accepts only `instantiate`, `args`, `tags`, `vars`, `priority`, `description` and `$comment`.
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

# clean (also run by clobber) stops the background processes left by tests, see tmp/states/*.pid
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
- **Pseudo-terminal**: With `stdin:`, the command reads a file, so `$stdin.tty?` is false: the masked input of secrets (`getpass`) and the questions asked only on a terminal (e.g. trusting the host of `config web_login`) are not run. A test with the tag `tty` runs the command in a pseudo-terminal (`PTY.spawn`) instead: each line of `stdin:` is typed when the command displays a prompt (output ending with `> `), the typed characters are not displayed when the command hides them. The text displayed on the terminal is saved in `tmp/states/<test>.tty` (e.g. for a `post` that checks that a secret is not displayed). The output of the command goes to the terminal, so `expect` and `save_output` work with `--out.file` only (set by `save_output`); `stderr` is not separated. The timeout applies as for other `interactive` tests. The tag `tty` cannot be combined with `background`, and a test with it does not capture `must_fail` messages in a file.
- **`--interactive=yes`**: the test configuration sets `interactive` to `no` (preset `cli_default`), so a test of the interactive input of missing arguments gives `--interactive=yes` on the command line. Test `conf_echo_interactive` runs `config echo` without argument: the value is asked (`argument: value>`) and read on `stdin:`.
- **Wizard**: tests of `config wizard` run with `ASCLI_WIZ_TEST=yes`, which skips the steps that wait for the user (`Enter` after the public key, mandatory client id and secret of Faspex 5 and of an organization specific client of AoC). A test that covers those steps sets `ASCLI_WIZ_TEST: ~` in `env:` (the value of the test is not overwritten) and gives the answers in `stdin:`.
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
- Tests tagged `gui` start a graphical client application (IBM Aspera Connect, IBM Aspera for Desktop) with its URL handler (`fasp://`, `aspera://`): they need a logged-in desktop session and the client installed. `auto_browser.rb` gives such URLs to the system (`open`, `xdg-open`), so no click is needed. Skip them on a headless system: `bundle exec rake test:skip'[tag gui]'`.
- These tests are run by hand, on a workstation (Chrome, macOS Keychain, test configuration file with credentials): they are not run in a CI environment.
- The mock IdP covers the authorization code flow of Faspex 5 only (not Shares, not AoC).
- With tag `tty`, `stdout` and `stderr` are mixed on the terminal.

#### Local mock IdP for `--auth=web`

`tests/mock_idp.rb` is a local server (no real account, no MFA) that mocks a Faspex 5: authorization page (`/aspera/faspex/auth/authorize`), token endpoint (authorization code and refresh), a ping, and the list of packages.
Test `f5_mock_idp_start` (`background`) starts it on `127.0.0.1:13783`, with an access code generated by `generated_secret(:mock_idp_auth)`; test `f5_mock_webauth` runs `faspex5 package list --auth=web` against it, depends on the first, and stops the server in `post`.
The authorization page is handled by `tests/auto_browser.rb` (Chrome, or HTTP fallback if `ferrum` is not installed): it enters the access code, allows, and the redirection reaches the callback server of `ascli`.

Two more tests use the same server, to cover `--ui.web_auth=paste` (the browser cannot reach the loopback address of the host that runs `ascli`):

- `f5_mock_webauth_paste` (tag `tty`, server started by its own test `f5_mock_idp_paste_start`: a rake task runs once and the server is stopped by `post` of the test that uses it) runs `faspex5 package list --auth=web --ui.web_auth=paste`. `ascli` displays the URL of the login page and waits at the `Code or URL>` prompt. The line of `stdin:` is evaluated when it is typed: `mock_idp_paste_reply(screen, :mock_idp_auth)` (in `test_helpers.rb`) reads the URL in the text displayed so far (`screen`), allows the access on the mock IdP like a user, and returns the URL of the redirection (with `code` and `state`), as copied from the address bar of the browser. `ASCLI_UI` is unset: no browser is started.
- `conf_web_login` (tag `tty`) runs `config web_login <code>`, for the workstation that has the browser. The code is made in the arguments with `web_login_code(...)` (`SealedHash`, type login). The login page shall be `https`, so test `f5_mock_idp_https_start` starts the mock IdP with `--https` (self-signed certificate; `auto_browser.rb` accepts it for loopback addresses only). The host is not known: `pre` deletes the persisted list of trusted hosts, the question `Open it, and trust this host for next logins? (yes/no)>` is answered `yes` on the terminal, and `post` checks that the question was displayed and that the host is persisted. Then the mock IdP page is opened by `auto_browser.rb`, and the redirection is received by `config web_login`.

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

With the 1Password desktop app integration, an `op` authorization is valid for the terminal session that approved it, expires after 10 minutes without any `op` call, and lasts at most 12 hours.
These durations are fixed: neither `op` nor the app can change them.
Locking the app (auto-lock timeout, sleep, screensaver) also ends the authorization.
A long test run can therefore ask again for authorization when no test reads a secret for more than 10 minutes.

To avoid this, either:

- Keep the authorization alive in the same terminal during the run:

  ```zsh
  op whoami >/dev/null || op signin
  ( while sleep 300; do op whoami >/dev/null 2>&1; done ) &
  keepalive=$!
  bundle exec rake "test:run[...]"
  kill $keepalive
  ```

  Also set the **Auto-lock** delay of the app (Settings → Security) longer than the run, and prevent sleep with `caffeinate -i bundle exec rake ...`.

- Or use a [1Password service account](https://developer.1password.com/docs/service-accounts/) with read access to the test vault: when `OP_SERVICE_ACCOUNT_TOKEN` is set, `op` uses it instead of the desktop app, with no prompt and no timeout.
  The vault must then be specified in the store parameters (`vault`).

  ```zsh
  export OP_SERVICE_ACCOUNT_TOKEN=<TOKEN>
  ```

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

Each tested process stores only its own result in `tmp/coverage/parts`.
The report is generated at the end of `test:run`, also when a test fails.
To generate it during a run, or after `rake spec`:

```bash
bundle exec rake test:coverage
```

Open [tmp/coverage/index.html](tmp/coverage/index.html) to view the report: line and branch coverage.
Results older than one day are removed: coverage accumulates over several runs (e.g. `"test:run[next 10]"`) within that delay.

When all test cases are completed (passed or skipped), the coverage badge file [docs/coverage.json](../docs/coverage.json) is also updated.
Commit it: the coverage badge of the top [README.md](../README.md) reads it through [shields.io](https://shields.io/badges/endpoint-badge).
It is not updated after a partial run, to avoid publishing a lower coverage.

## Durations

The duration of each test is saved in `tmp/durations.yml` (last execution of the test, passed or failed).
At the end of `test:run`, the duration of the run and its slowest tests are logged.

To show the total duration of all tests, also when they were run in several runs, and the slowest tests (default: 20):

```bash
bundle exec rake test:durations
bundle exec rake 'test:durations[50]'
```
