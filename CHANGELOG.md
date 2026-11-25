# Changes (Release notes)

## 4.30.0.pre

Released: [Place date of release here]

### New Features

* Option `plugin_folder`: `--show-config` lists all the folders given (it showed only the last one), and `DEF` (the default) is the folder `plugins` of the configuration folder. `--plugin-folder=@json:[]` uses no plugin folder other than the one of the gem.
* Development version of the gem: built from `main` every day it changes, not signed, and attached as `aspera-cli-nightly.gem` to the GitHub pre-release `nightly`. Its version is the version in development followed by the number of commits of `main`, e.g. `4.30.0.pre.5592`. See the manual, section "Installing the development version of the gem".
* Options `node_api`, `ssh_options` (`server`) and `service_credentials` (`cos`) have a schema: `help` as value shows their parameters (e.g. `--node-api=help`), and a value is checked when the option is set. `--transfer=help` shows the parameter `asynchronous`, common to all agents.
* Plugin bundles: a plugin of a plugin folder (option `plugin_folder`) can be a folder `<name>/` with a manifest `plugin.yaml` (data only, validated by `lib/aspera/plugin.schema.yaml`), in addition to a single file `<name>.rb`. A bundle has its commands (`commands.rb`), and can add a transfer agent (value of option `transfer`, with the schema of its parameters), schemas, commands to another plugin (`config`), shared services, and can depend on other bundles. A bundle that cannot be used (invalid manifest, missing dependency) is listed with its reason, and the other plugins work. The built-in plugins and transfer agents (`aoc`, `faspex5`, `node`, `server`, `direct`, `transferd`, ...) are bundles of the gem, in `lib/aspera/plugins/<name>/`, with their specs and tests. See the manual, section "Writing a plugin".
* `config plugins list`: shows the folder of a bundle as `path`, has a column `status` (`available`, or the reason why the plugin is unavailable), and lists the unavailable plugins. New command `config plugins show <NAME>`: title, source, form, path, security level, status, commands, agents, schemas, mounts, services, extension points, dependencies and missing gems of a plugin, without loading its code.
* `ascli <NAME>` for an unavailable plugin gives the reason, and a transfer agent of an unavailable plugin gives `plugin <NAME> is unavailable: <REASON>`. The error of an invalid value of option `transfer` lists the agents provided by the bundles: `connect`, `desktop`, `direct`, `httpgw`, `node`, `transferd`.
* `mcp server`: the instructions for the AI client are built from the manifests of the plugins (title and section `mcp`).
* Every transfer agent accepts every base option of the transfer (e.g. `trusted_certs` with agent `node`).
* A hint for the product of an error is shown only when the plugin of that product is loaded. `INFO Location:` of an error raised in a bundle points to the file of the bundle.
* New command `sync logs` (also `server sync logs`, `node sync logs`): it reads the `async` (IBM Aspera Sync) log files of the local host and reports only the notable events, so a drift between two folders is easy to find: file conflicts and errors (`SYNC FILE STOP` with `status=CONFLICT` or `ERROR`), unsupported file-system events, session start/stop/idle, and `ERR`-level lines. With no argument it reads the log at the default location (`~/Library/Logs/Aspera/async.log` on macOS, `syslog` on Linux and Unix); a path, a folder, a `gzip` file, or `-` (standard input) can be given. The paths are checked against the security level, like `@file:`.

### Issues Fixed

* Agent `transferd`: the daemon started by `ascli` had no authentication: during the transfer, another user of the host could call its API on the local port. It now requires an API key: the one of parameter `api_key`, else a random one, sent by `ascli` in each call. Its configuration file, in the temporary folder, is readable only by the user (it was readable by all). A daemon left running (`stop` is `false`) gets the key of parameter `api_key`, else it has no authentication, with a warning.
* `server ls`, `du`, `md5sum`, `rm`, `mv`, `cp`, `mkdir` with several paths: only the result of the last path was shown, e.g. `server du <PATH_A> <PATH_B>` showed the size of `<PATH_B>`, and `server ls <FILE> <FOLDER>` did not list the folder. When a path failed and another one succeeded, the error was `unexpected value: 2` (the other paths were processed), and when several failed, only the last one was reported. All results are now shown, and each failed path is reported with its error, after all paths are processed.
* `server` commands executed by `ascmd` (`ls`, `rm`...): a path with newlines was sent as several command lines, and the lines between the first and the last one were executed as commands of `ascmd` (e.g. `as_rm`), for example with a file name made for that. A newline or NUL character in a path is now refused, as is a command longer than what `ascmd` reads (4094 bytes, it stopped with `Internal server error`). An error of `ascmd` itself (e.g. usage) showed errno `4294967295` instead of `-1`, and a date before 1970 was wrong.
* `aoc` with `--auth=web` and no `client_id`: the global client was used, and AoC refused the login in the browser (_Add the redirect URI for your API client..._). `ascli` now stops before opening the browser, with an error that tells to set `client_id` and `client_secret` of an API client of the organization. The manual stated that the default of `auth` is `web` and the one of `redirect_uri` is `http://localhost:12345`: the default of `auth` is `jwt`, and `redirect_uri` has no default.
* Errors caused by a value given by the user were reported as a bug of `ascli`: `Other(Aspera::AssertError): assertion failed: ...`, exit code 1, with the location in the code. For example: an element that is not a string in a list option (`--plugin-folder=@json:'[1]'`), parameters of `sync_info`, of `transfer_info` or of the transfer spec (`paths` without `source`), of `smtp`, a `--query` that is a list, package ids, the configuration file. They are now reported as `Argument` (exit code 2), and a shared folder not found (`aoc`, `faspex5`) as `Identifier` (exit code 4). Errors of parameters found by the library of the gem, and not converted by the command, were also reported as `Other` (e.g. `Missing mandatory option: private_key` of `aoc` with `--auth=jwt`): they are now reported as `Argument`. A component missing on the system is reported as `Environment`: no `ascp` or SDK installed, font of `magick`, H.264 encoder of `ffmpeg`, tool used for previews.
* Other errors that are not a bug were also reported as `Other(<class>)`, with the location in the code. They are now reported without location: errors of secret references and of option `vault` as `Vault`; a secret not found, or several secrets with the same label, in all stores, as `Identifier` (exit code 4), as is a lookup by name (`%name:`) that matches several entities; a wrong password of the vault file, and a passcode or public link refused by Faspex 5, as `Authentication` (exit code 3); parameters of `sync` (`local_db_dir`), metadata of an `aoc` package (`missing mandatory field: ...`), the URL of `httpgw` and a `faux:` path (it was `Transfer`, exit code 5) as `Argument` (exit code 2); a graphical environment required (agents `connect` and `desktop`) and the requirements of the service of `transferd` (Linux with systemd, root) as `Environment`; a remote command that failed as `SSH`; other failures of a remote service as `Error`.
* Agent `node` with a bearer token and no `root_id`: the error said `root_id not allowed for access key`, it is required.
* Agent `transferd`: a `url` without port is refused, with the expected format (the daemon was started, and the connection to it failed).
* Options `log`, `out` and `node_api`: an unknown key was reported as a bug (`Other(Aspera::InternalError)` or `assertion failed`). It is now refused with its path, like for the other options with a schema, e.g. ``object property at `/levl` is a disallowed additional property``, as is a value of `node_api` that is not a boolean.
* Option `smtp`: an unknown key, or a value of a wrong type, was refused only when an email was sent: it is now refused when the option is set. The manual stated that the default of `domain` is the domain part of `server`: it is the one of `from_email`.
* Option `transfer`: an unknown parameter, or a parameter of another agent (e.g. `wss` with agent `node`), was refused only when the transfer started, with the Ruby error `unknown keyword`: it is now refused when the option is set. Same for parameter `resume` of agent `direct`, and for option `image` (`out.img`), refused only when an image was displayed.
* Manual: option `node_api` has no parameter `per_page`: it is a parameter of option `query`.
* `--transfer=node` without `url` and without default `node` configuration: the message `No default node configured. Please specify --transfer.url or --transfer` was a Ruby error (`NameError`, reported as a bug of `ascli`). It is now the `Argument` error with that message.
* Plugin of a single file `<name>.rb` with `_` in its name (e.g. `my_app.rb`): help and `poll` messages showed the name of the class in lower case (`myapp`), they now show the name of the file.
* `mcp server`: the commands sent by the client ran in the default home (`~/.aspera/ascli`, or env `ASCLI_HOME`) instead of the main folder of the server (option `home`). They now run in the main folder of the server; the client still cannot change it at security levels `medium` and `high`.
* `mcp server`: the commands sent by the client could choose the configuration file with option `config_file`, and so read, create, modify or rename a file of the server, also outside `writable_paths`. The option is now refused at security levels `medium` and `high`, and the commands of the client use the configuration file of the server.
* `mcp server`: the commands sent by the client could choose the vault with option `vault` (and its password with `vault_password`), and so create a vault file outside `writable_paths`, or make the server connect to a host of their choice (HashiCorp Vault, Keeper, ...). The options are now refused at security levels `medium` and `high`, and the commands of the client use the vault of the server, also when it is set in a preset of its configuration file.
* `mcp server`: the commands sent by the client could start a transfer with an agent that runs on the local host (`direct`, a local `transferd` daemon, `connect`, `desktop`, `httpgw`), which reads and writes local files and runs local programs. At security level `high` (the default in MCP server mode), a transfer now uses an agent that the user controls on a remote host (`node`, or `transferd` attached to a remote daemon): an agent that runs on the local host is refused, with a message that tells to select a remote agent. In addition, the parameters that pass raw arguments to `ascp` or `ssh` (`ascp_args` of agent `direct`, `ssh_args` of the transfer spec) can start a local program (for example an `ssh` `ProxyCommand`): they are now refused at security levels `medium` and `high` (they execute code, allowed at level `low` only).
* `mcp server`: a command sent by the client could redirect the saved credentials of the server to a host it chose, by combining a preset that holds a secret with its own `url` (the `url` of the command line overrode the one of the preset, but the secret stayed from the preset, and was sent to the host of the client). At levels `medium` and `high`, a secret from the configuration of the server (a preset, or the environment: options `password`, `client_secret`, `private_key`, `passphrase`) is now refused when the `url` is given on the command line: the secret and its `url` must come from the same place.
* `mcp server`: the commands sent by the client could disable or redirect the validation of a server certificate, or route through a proxy, and so intercept the connections of the server and its credentials (man-in-the-middle): options `insecure`, `ignore_certificate`, `cert_stores`, `http_proxy`, and the keys `ca_file`, `verify_mode` and `ssl_options` of option `http_options`. They now require security level `low`: refused at levels `medium` and `high`.
* `mcp server`: the commands sent by the client could start a local server that listens on the network and serves a folder of the host or accepts transfers: `node emulator` (`simulator`), `aoc gateway`, `faspex5 gateway`. These commands, like `faspex5 postprocessing`, now require security level `low`: they are refused, and not listed by `config commands`, at levels `medium` and `high`.
* `mcp server`: several commands read or wrote a local path chosen by the client without the security check, so at level `high` the client could read a file, enumerate a folder (following symbolic links), write or replace a file, or run a local program on a local file: `config ascp logs`, `config sync admin` (and `server`/`node sync admin`), `preview test` and `show`, `orchestrator workflows import` and `check_import` (read); `config genkey` and `config plugins create` (write); `config image` with a `file:` URL (read). These paths are now checked against the security level, like `@file:`: refused at level `high`, and limited to `allowed_paths` (read) or `writable_paths` (write) at level `medium`, where a missing path and one outside the allowed paths give the same error (no path-existence oracle). The `sync` transfer commands (`push`, `pull`, `bidi`) run the local `async` program and are refused at level `high`. Raw SQL (option `sql` of `sync admin`) can write a file (for example `VACUUM INTO`), and options `sdk_folder` (the folder `ascp` is run from) and `temp.folder` (`temp_folder`, where temporary files are written) let the client choose a local path: they are refused at levels `medium` and `high`.
* `config web_login`: about 1 code in 64 started with `-`, and `ascli config web_login <code>` then read the code as an option (`Missing argument: code`). A code no longer starts with `-`. For Shares, install the updated patch `docs/shares/zz_saml_cli_relay_state.rb`, which makes the codes on the server.
* `sync push|pull|bidi` with `sync_info` in `conf` format: the remote password and token were in the command line of `async` (`--conf64`, base64 of the configuration), visible to the other users of the host (`ps`), and shown in the debug log (`--log-level=debug`). They are now given in environment variables `ASPERA_SCP_PASS` and `ASPERA_SCP_TOKEN`, hidden in logs, and the value of `--conf64` is hidden in logs.
* `sync push|pull|bidi` in continuous mode (`"mode":"continuous"`): `ascli` stopped `async` about 10 seconds after the end of the first activity, when `async` closes its management port (it reports each activity period as a session). `ascli` now waits for the end of `async` (e.g. Ctrl-C, or `asyncadmin --terminate`).
* `--transfer=transferd` without the optional gem `grpc`: `ascli` stopped with a Ruby error and a stack trace (`cannot load such file -- grpc (LoadError)`). It now tells to install the gem: `agent transferd requires gem grpc: gem install grpc`.

### Breaking Changes

* Option `plugin_folder`: the folders given replace the folder `plugins` of the configuration folder (they were added to it). To use both, add `DEF`, e.g. `--plugin-folder=DEF --plugin-folder=<FOLDER>`. A warning tells when that folder has plugins and is not used.
* `server du` and `server md5sum`: the result is a list with one row per path, with column `path` (it was a single object, of the last path only).
* `server df`: the column of the type of file system is `type` (it was `is_a`).
* An unknown key in options `smtp`, `transfer` and `image` (`out.img`) is refused when the option is set: a preset with such a key makes every command fail, also one that does not send an email, transfer or display an image. An unknown key is refused (it was ignored) in option `package_folder` (`aoc`), in the parameters of `node telemetry`, and in the plugin set of `orchestrator plugins reload_set` (it was sent to Orchestrator).
* Security level `high` (the default in MCP server mode) now refuses a transfer agent that runs on the local host (`direct`, a local `transferd` daemon, `connect`, `desktop`, `httpgw`): a transfer uses a remote agent that the user controls (`node`, or `transferd` with a `url` to a remote daemon). The default agent is `direct` (local): on the command line, a transfer at level `high` without an agent is refused with a message that tells to select a remote agent (level `high` is not the default on the command line). The parameters that pass raw arguments to `ascp` or `ssh` (`ascp_args` of agent `direct`, `ssh_args` of the transfer spec) are refused at levels `medium` and `high`: they can start a local program, so they are allowed at level `low` only.
* Security levels `medium` and `high`: a secret from a preset (or the environment) is not sent to a `url` given on the command line (the secret and its `url` must come from the same place), so option `url` on the command line combined with a preset that carries a secret (`password`, `client_secret`, `private_key`, `passphrase`) is refused. The command line default level `low` is unaffected.
* Security levels `medium` and `high` refuse the options that disable or redirect the validation of a server certificate, or route through a proxy (available at level `low` only): `insecure`, `ignore_certificate`, `cert_stores`, `http_proxy`, and the keys `ca_file`, `verify_mode` and `ssl_options` of option `http_options`.
* Security levels `medium` and `high` refuse the commands that start a local server (they are available at level `low` only, as `faspex5 postprocessing`): `node emulator` (`simulator`), `aoc gateway`, `faspex5 gateway`.
* Security levels `medium` and `high`: a command that reads or writes a local path chosen by the client checks it like `@file:`, refused at `high` and limited to `allowed_paths`/`writable_paths` at `medium` (it was not checked): `config ascp logs`, `config`/`server`/`node sync admin`, `preview test` and `show`, `config genkey`, `config plugins create`, `orchestrator workflows import` and `check_import`, and `config image` with a `file:` URL. `orchestrator workflows import` was not restricted before (it is read like any local file, since `ascli` reads it, even though it is then sent to Orchestrator). The `sync` transfer commands (`push`, `pull`, `bidi`) run the local `async` program and are refused at level `high`. Option `sql` of `sync admin`, and options `sdk_folder` and `temp.folder` (`temp_folder`), are refused at levels `medium` and `high`. Library and plugin authors: a command argument that completes to a local file or folder (`complete: :file` or `:folder`) must now declare `access:` (`:read`, `:write`, or `:none` when it is not a local path read or written by `ascli`).
* Ruby library use, `ascli` command line unchanged: the code of each product is in a bundle `lib/aspera/plugins/<name>/`, with files moved and classes renamed, with no alias and no file left at the old path. Require the new path and use the new name, for example: `Aspera::Api::Node` (`aspera/api/node`) is `Aspera::Plugins::Node::Api` (`aspera/plugins/node/api`), `Aspera::Agent::Direct` is `Aspera::Plugins::Direct::Agent`, `Aspera::Agent::Transferd` is `Aspera::Plugins::Transferd::Agent`, `Aspera::Cli::Plugins::Aoc` is `Aspera::Plugins::Aoc::Commands`, `Aspera::AsCmd` is `Aspera::Plugins::Server::AsCmd`, `Aspera::NodeEmulator` is `Aspera::Plugins::Node::Emulator`, `Aspera::Cli::TransferAgent` is `Aspera::Plugins::Xfer::TransferAgent`. Same for the other products (`alee`, `ats`, `console`, `cos`, `faspex5`, `faspio`, `httpgw`, `orchestrator`, `preview`, `shares`). `Aspera::CommandLineBuilder` and `Aspera::CommandLineConverter` are in `Aspera::Transfer`, `Aspera::DataRepository` is `Aspera::Ascp::DataRepository`. The constants of `Aspera::Schema::Registry` for the schemas of a product (`AOC`, `NODE`, `SHARES`, `TRANSFERD_AGENT_OPTIONS`, ...) are removed: the schemas are declared in the manifest of the bundle.
* `docs/openapi_sources.yaml` is removed: the origin of each downloaded schema is the field `source` of its manifest `plugin.yaml`, used by `rake tools:openapi`.
* Plugins of a plugin folder: `BasicAuth` and `Oauth` are modules (they were classes). A plugin that subclasses `Cli::Plugins::BasicAuth` or `Cli::Plugins::Oauth` fails with `superclass must be a Class`: subclass `Cli::Plugins::Base` and write `include Cli::Plugins::BasicAuth` (or `Oauth`). In the help, the options of the module come where the `include` is, relative to `use_options`.
* Plugins of a plugin folder: the declarations of the command line moved, with no alias: `Cli::Type::*` is `Cli::Option::Type::*`, `Cli::OptionDeclarator` is `Cli::Option::Declarator`, `Cli::CommandSpec` is `Cli::Command`, `Cli::ArgumentSpec` is `Cli::Argument`, `Cli::OptionSpec` is `Cli::Option`, `Cli::MountSpec` is `Cli::Command::Mount`, `Cli::CommandRegistry` is `Cli::Command::Registry`, `Cli::OptionValue` is `Cli::Option::Value`, `Cli::OptionRegistry` is `Cli::Option::Registry`, `Cli::OptionSource` is `Cli::Option::Source`, `Cli::EVALUATIONS` is `Cli::Argument::EVALUATIONS`, `Cli::READ_ONLY_IDS` is `Cli::Command::READ_ONLY_IDS`, and the tokens of the command line `Cli::Option` and `Cli::Argument` are `Cli::CommandLine::Option` and `Cli::CommandLine::Argument`. Require paths: `aspera/cli/option_types`, `option_value`, `option_registry`, `option_declarator`, `command_spec`, `command_registry` are `aspera/cli/option/type`, `option/value`, `option/registry`, `option/declarator`, `command` (or `argument`), `command/registry`.
* Ruby library use: `Aspera::Preview::Terminal` is `Aspera::Cli::TerminalImage` (`aspera/cli/terminal_image`), and `Aspera::Preview::Backend::*` are `Aspera::Cli::TerminalImage::Backend::*`. `Aspera::Products::Other` is removed: `Products.find` and `Products::INFO_META_FILE` are in `aspera/products`, and `Other::CLI_V3`, `HSTS`, `DRIVE` are the classes `Products::CliV3`, `Products::Hsts`, `Products::Drive`, each with `APP_NAME` and `.locations` (was `LOCATION_ON_THIS_OS`).

## 4.29.1

Released: 2026-11-20

### New Features

* New option `poll`: repeats a read-only command and displays its result (each time it changes, each time, or the last one), until a JMESPath condition on the result is true, or a number of runs or a time is reached, e.g. ``orchestrator workorders status <ID> --poll=@json:'{"interval":10,"max":30,"until":"status == `Complete`"}'``. Parameters `interval`, `max`, `timeout`, `until`, `show`, `errors` (`fail` or `retry`). Refused on a command that is not marked read-only (e.g. `faspex5 packages send`), with options `once_only` and `notify_to`, and in MCP server mode. Read-only: commands named `list`, `show`, `status`, `info`, `health`, `ls`, `browse` and `find` (except `preview show`: it generates a preview file), and others, e.g. `orchestrator workflows workorders`, `server du`, `node ssync state`.
* `config`: new command `skill`: displays the agent skill (same content as `llms.txt`), for an AI that does not install skills, in a shell or through `mcp server`.
* `mcp server`: the default instructions tell the AI to read the Aspera on Cloud Automation Development Guide before writing a workflow (sections to start with, for example `package-transfer` for action "Send a package"), and point to `config skill` for general guidance. The agent skill and `llms.txt` give the same starting sections.
* Chocolatey package `aspera-cli`: installs the Windows portable package (Ruby, gems and `ascp` included, checked with its SHA-256) instead of Ruby and the gem, and adds only `ascli` to the `PATH`. It is built, tested and published by the release workflow.
* Hidden input (passwords, code or URL pasted after a web login): a mark shows the state, without revealing the length: `🔑` while the input is empty, `…` once something is typed or pasted (`***` and `...` without Unicode). Ctrl-U erases the input, e.g. to paste again. `--ui.hidden_silent=yes` reads without mark (no feedback, as before). A terminal without raw mode (error `Inappropriate ioctl for device`) reads the line as is. An input that is checked while typed or pasted (the code displayed by Shares for `--auth=web` with `--ui.web_auth=paste`) shows `✓` (green) if valid, else `✗` (red) (`valid` and `invalid` without Unicode), and is asked again if `Enter` is pressed while it is not valid.
* Web login without local port (`--ui.web_auth=paste`): the page that shows the code after `config web_login` tells how long it is valid (15 minutes). Same for the page of the Shares patch for `--auth=web` (`docs/shares`), which also tells how long the session token is valid (24 hours, from the constant of Shares).

* OAuth: new key `token_refresh_max_age` of option `http_options`: a cached token obtained since more than this duration (seconds) is refreshed before use (default: `0`, no limit). With an `ascli` command run more often than the lifetime of the refresh token (e.g. every 12 hours), it keeps a session alive without new login, e.g. with Shares whose token and refresh token both expire after 24 hours: `--http-options=@json:'{"token_cache_max_age":"1d","token_refresh_max_age":"12h"}'`.
* `http_options`: durations (timeouts, `retry_sleep`, `token_*`, `jwt_*`) accept a string, e.g. `30s`, `12h`, `1d`, `1h 30m`, in addition to a number of seconds. Keys `jwt_accepted_offset_sec` and `jwt_expiry_offset_sec` are documented.
* Plugins: the manual has a section "Writing a plugin" for a plugin loaded with option `plugin_folder`: file and class names, files of the gem to require, options, commands, actions, results, REST client, with an example.
* Plugins: an unexpected error in a plugin (e.g. `Other(NoMethodError)`) also logs its location in the plugin (file and line) at level `info`.
* Plugins: modules `OauthWebOptions` (`client_id`, `client_secret`, `redirect_uri`) and `OauthJwtOptions` (`private_key`, `passphrase`) give the options of `Oauth`: a plugin of the OAuth web flow only adds them with `use_options OauthWebOptions`. Options of the existing plugins do not change.
* OAuth: parameter `token_field` accepts a dot-separated path of a nested field of the token answer, e.g. `authed_user.access_token` (user token of Slack OAuth v2). A plain field name is read as before.
* OAuth: parameters `path_authorize` and `path_token` accept an absolute URL (`http` or `https`), used as is, e.g. a token created on another host than the authorization page. The token cache still depends on `base_url` only: no new login for existing configurations.
* `transferd install`, `transferd list`: the request for the list of SDK archives (option `locations_url`) includes the version of `ascli` in the HTTP header `Referer`.
* `transferd install`: the list of SDK archives is no longer read when the requested version is already installed, and is read once per installation instead of twice.
* REST: a raw body is sent as is when no `content_type` is given: a `String` (e.g. binary data), or an `IO` (e.g. a file) streamed from its current position, without loading it in memory, and sent again from the same position on retry. Its type is in `headers` (`Content-Type`). It was ignored, so a binary body needed `content_type: Mime::TEXT` and a `Content-Type` header.

### Issues Fixed

* Linux single executable, Linux and Windows portable packages, container image: Ruby 4.0.10 instead of 4.0.9, which has vulnerabilities in `Regexp` and `String` ([Ruby security release of 2026-11-18](https://www.ruby-lang.org/en/news/2026/11/18/multiple-vulnerabilities-in-regexp-and-string/)). With the gem, `ascli` runs on the Ruby of the system: update it to 4.0.10, 3.4.13 or 3.3.14.
* Option `security`, `mcp server`: extended value `@zlib:` was accepted at levels `medium` and `high`: a client could send a small value that decompresses to gigabytes (e.g. `@zlib:@zlib:<DATA>`), and exhaust the memory of the system. It is now refused at these levels, as `@ruby:`, `@uri:` and `@env:`. It is not limited at level `low`. Reported by visionx7.
* `orchestrator workflows import` and `check_import`: a workflow package (`.wkf`) was decompressed in memory without limit for the local check, so a small package could exhaust the memory (e.g. 1 MB for 1 GiB). A package whose files exceed 256 MiB once decompressed is now reported (issue `package.too_large`) and not decompressed: the size is read in the archive before each file.
* Node API bearer token (e.g. option `password` of plugin `node`, or a token in cache): it was decompressed without limit, so a small token could exhaust the memory. The decoded token is now limited to 64 KiB, checked while decompressing.
* Option `security`, `mcp server`: `orchestrator workflows check_import` read any local file at levels `medium` and `high`, and its issues show parts of the content. It now reads the file as `@file:`: only in `allowed_paths` at level `medium`, refused at level `high`. `workflows import` sends the file, as a transfer: not restricted.
* `config ascp info`: key `log` was always `-` (`ascp` is run with `-L-` to read its paths). It is now where `ascp` logs without option `-L`: `<logging><directory>` of `aspera.conf`, else `~/Library/Logs/Aspera` on macOS, `var\log` of the product (or the folder of `ascp`) on Windows, `syslog` on Linux and Unix.
* Logs (`--log-level=trace1`, `trace2`): the value of a secret option given on command line (e.g. `--password=<PASSWORD>`, `--vault.password=<PASSWORD>`) was shown in clear in the logs of the command line, of unprocessed options, and of the evaluation of the option. It is now declared as a secret when the command line is read, by option name, as is a structured value with a secret key (e.g. `--vault=@json:'{"password":"<PASSWORD>"}'`), and a short value (less than 8 characters) is hidden too in these logs.
* Option `dry_run` was ignored by all commands except `transferd service`, e.g. `server download` transferred files. A transfer command now does not transfer, and its result is the final transfer spec (secrets hidden). Commands that change something before the transfer (`aoc packages send`, `faspex5 packages send`: the package is created first), `sync` commands and `preview` generation are refused with option `dry_run`, before any change.
* Option `show_config`: after the configuration, the error `unprocessed values` was displayed (exit code 2) when the command had arguments, e.g. `server browse / --show-config`. Arguments of the command, not executed, are not reported anymore, unknown options still are.
* Logs (`--log-level=debug`): the value of a secret option given in an environment variable (e.g. `ASCLI_PASSWORD`, `ASCLI_VAULT_PASSWORD`) was shown in clear in the dump of environment values, and that of a secret option given on command line to `config preset update` (e.g. `--password=<PASSWORD>`) in the log of the option. Values of options from environment, presets and command line that are not declared yet are now hidden, by option name, as those of declared options.
* OAuth: an opaque token (not a JWT, e.g. Shares) was used until rejected by the server: its refresh token, if it expires at the same time, could no longer be used. The expiration given at creation (`expires_in`) is now kept in cache (`expires_at`), and the token is refreshed before it expires (`token_refresh_threshold`).
* `orchestrator workflows find_constraints`: the optional workflow ID was required ("Missing argument: add_as_revision"): an optional argument of type identifier was always mandatory. `orchestrator workflows import_with_constraints`: `add_as_revision` accepts `null` (new workflow).
* Extended value `@extend:` followed by a single extended value, e.g. `@json:@extend:@file:<PATH>`: the text on the right was taken as is (`unexpected character: '@file:...'`) instead of being decoded first, as other decoders. It is now decoded, then its embedded values (e.g. `"@vault:<LABEL>.<FIELD>@"` in a JSON file) are evaluated. With a closing `@` (`@extend:@file:<PATH>@`) the content is still inserted as is, not evaluated again.
* `mcp server`: when the optional gem `mcp` is not installed, the error was `uninitialized constant Cli` instead of the message telling to install it.
* Vault 1Password (`op`): creating a secret (e.g. `config vault create`, `config preset secure`) failed with `invalid JSON in piped input`, because `op item create` reads an item template on its standard input when it is not a terminal. The fields are now given to `op` in a JSON template on its standard input, so the secret is no longer on its command line.
* Wizard: an existing default preset for the plugin was replaced without error when `override=yes` was not given: the check (`A default configuration already exists`) never applied.
* Display of an image as text in a terminal that does not report its size (0 x 0, e.g. a pseudo-terminal) or without console: the image was scaled to nothing or failed (`Cannot decode picture.`). The default size 24 x 80 is now used.
* Display of an image as text without the optional gem `rmagick`: an image that ChunkyPNG does not decode (e.g. JPEG) failed with `cannot load such file -- rmagick`, instead of being displayed with the iTerm2 inline image protocol (if supported by the terminal) or failing with `Cannot decode picture.`.

### Breaking Changes

### Server Versions

Tested with Ruby 4.0.9 on osx-arm64.

| Plugin | Product | Version |
| ------------ | ------------------------------------------------ | ---------------- |
| `aoc` | IBM Aspera on Cloud | SaaS |
| `console` | IBM Aspera Console | 3.4.11 |
| `faspex5` | IBM Aspera Faspex | 5.0.19 |
| `faspio` | IBM Aspera faspio Gateway | 1.3.7 |
| `httpgw` | IBM Aspera HTTP Gateway | 2.3.4 |
| `node` | IBM Aspera High-Speed Transfer Server (Node API) | 4.4.9.3472 |
| `orchestrator` | IBM Aspera Orchestrator | 4.1.6.2036-00000 |
| `server` | IBM Aspera High-Speed Transfer Server (SSH) | 4.4.9.3472 |
| `shares` | IBM Aspera Shares | 1.11.5 |

### Transfer Agent Versions

| Agent | Product | Version |
| --------- | ------------------------------------------------ | ---------- |
| `connect` | IBM Aspera Connect | 4.2.16 |
| `desktop` | IBM Aspera for Desktop | 1.1.2 |
| `direct` | IBM Aspera ascp | 4.4.8.2592 |
| `httpgw` | IBM Aspera HTTP Gateway | 2.3.4 |
| `node` | IBM Aspera High-Speed Transfer Server (Node API) | 4.4.9.3472 |
| `transferd` | IBM Aspera Transfer Daemon | 1.1.9 |

## 4.29.0

Released: 2026-11-17

Highlights:

* `ascli` as a tool for AI assistants: `mcp server` is hardened (the AI client can neither execute code nor write files where it chooses) and no longer experimental; commands describe themselves (schema of structured arguments with `help`, development guides of Orchestrator and Aspera on Cloud Automation read by section); new file `llms.txt` (also as an agent skill) that tells an AI how to drive IBM Aspera products with `ascli`.
* Analysis of `ascp` logs, local (`config ascp logs`) or on a server (`server logs`): statistics, sessions, diagnostics with recommendations.
* Named secret stores for `vault`, new types `keeper` and `secret_service`, HashiCorp AppRole and token file, secrets inspected without their value.
* Web login without local port (`--ui.web_auth=paste`), SAML web authentication for `shares` (`--auth=web`).
* New plugin `transferd`: Transfer Daemon as a service. Export and import of Aspera on Cloud Automation workflows. Many new `orchestrator` commands. Improved shell completion.
* Project: OpenSSF Best Practices silver badge, test coverage 96.6%.

**This version has several breaking changes**: read the **Breaking Changes** section below before upgrading and validate production workflows before deployment. In particular: Ruby 3.3 or later is required, `config wizard`, `config detect` and `config preset lookup` take their arguments as a `Hash` (`@: url=...`), and some `orchestrator` commands are renamed.

### New Features

* `ascli`:
  * New file `llms.txt` (in the gem and in the repository): what `ascli` does with IBM Aspera products, and how to discover commands, arguments and options, on the command line or through `mcp server`. Same content as an agent skill in folder `skills/ascli`. The repository is also a Claude Code plugin marketplace: `/plugin marketplace add IBM/aspera-cli`, then `/plugin install ascli@aspera-cli`.
  * Web authentication (`--auth=web`): new key `web_auth` of option `ui`. With `--ui.web_auth=paste`, no local port is opened: after login, the user pastes in the terminal the URL the browser was redirected to. It allows SSO when the browser cannot reach the host that runs `ascli` (e.g. jump server). If `ascli` is also installed on the workstation, it displays a command `ascli config web_login <code>` to run there instead. Default: `port` (unchanged).
  * Improved shell completion: structures, extended values, local files and folders, presets (with their `_comment`), transfer jobs and `--query`.
  * SSH keys of type `ed25519` are supported without additional gem. Gem `bcrypt_pbkdf` is only needed for OpenSSH keys protected by a passphrase.
* `config`:
  * New command `ascp logs`: analysis of `ascp` log files (`ascp` 4.0 and later), of client and server (joined by session). Sub-commands: statistics, `sessions` (with context columns: product, transport, authentication, proxy, FIPS), `diagnostics` (severity, category, hint and recommended `ascp` options or `aspera.conf` parameters), `health` (Nagios format), multi-session transfers, rates per period, errors by peer, files, licenses, and parsed `records` for `--out.query`. Accepts gzip files, folders and the standard input (`-`). Command `find` lists the `ascp` log files of the local system: log folders of installed products and of `ascp` in `PATH` (and `<logging><directory>` of their `aspera.conf`), of IBM Aspera for Desktop, of the transferd service, and default locations of `ascp` for the OS (syslog files on Linux). New option `ascp_logs`: thresholds of diagnostics, `timezone`, `health_minutes`.
  * `ascp errors`: optional argument `session` lists error codes found in logs, with category and the corresponding error of the management port.
  * `vault`: option `vault` declares several named stores: `{"default":"<name>","cache_ttl":60,"stores":{"<name>":{"type":...}}}`. A secret can be read from any store with `@vault://<store>/<path>[?<options>][#<field>]`; `@vault:<label>.<field>` uses the default store. New commands `vault stores`, `check`, `overview` and `field <label>`: they inspect stores and secrets without showing values. The former single-store form of option `vault` is deprecated, and converted when the configuration file is loaded (a backup is saved). `@file:` in options `vault` and `vault_password` is restricted by option `security` (refused by default in `mcp server`).
  * `vault` type `file`: parameter `password` (value, or `@file:<path>`) replaces option `vault_password`.
  * `vault` type HashiCorp: `token` accepts `@file:<path>` (read again when modified, e.g. by Vault Agent). New parameters `approle`, `namespace` and `ca_file`.
  * `vault`: new types `keeper` (Keeper Secrets Manager, optional gem `keeper_secrets_manager`) and `secret_service` (Linux Secret Service: GNOME Keyring, KWallet, KeePassXC, with `secret-tool`).
  * `wizard` adds `_comment: "wizard: <application>"` to the preset it creates.
  * Asynchronous transfer jobs (`list`, `status`, `cleanup`) are managed by `agents jobs`. `config transfer` is deprecated.
  * `transferd` (`install`, `list`) and `ascp install` are deprecated, use the new plugin `transferd`.
  * `preset set` merges into the configuration at three levels (see Breaking Changes below). `preset update`, `initialize` and `unset` are deprecated, and show the command to use.
* `transferd`: new plugin for the Transfer Daemon.
  * `install [version]` and `list`. `install` does nothing if the version is already installed.
  * `info` and `transfers show|cancel <transfer_id>` for a running daemon (options `--url`, `--api-key`, `--ca-file`; requires gem `grpc`).
  * `service` (`spec`, `install`, `configure`, `status`, `uninstall`, `use`, `versions`): run `transferd` as a `systemd` service, with its configuration validated, and SDK versions side by side (`use` for rollback). New global option `--dry-run` shows the actions without change.
* `server`: new command `logs`: same analysis as `config ascp logs`, on the log files of the server, read over SSH (size limited by key `remote_max_size` of option `ascp_logs`, default 256 MB).
* `aoc`:
  * `automation` is no longer beta. New commands `automation workflows details`, `export`, `import` and `duplicate`.
  * New command `automation guide` (`toc`, `full`, `section <anchor>`): the Aspera on Cloud Automation Development Guide.
* `faspex5`: web authentication (`--auth=web`) uses PKCE (`S256`), checked by Faspex 5.0.16 and later. Nothing to change in the configuration.
* `shares`: new option `--auth=web`: SAML authentication with the web browser, with `--ui.web_auth=port` (default) or `paste`. It requires a patch of Shares, provided in `docs/shares` until it is part of a Shares release (see manual).
* `node`: `asperabrowser` opens the new Aspera Browser web application (option `asperabrowserurl`), as the former one is no longer available. The node credentials are given in the fragment of the URL, which the browser does not send to the web server.
* `orchestrator`:
  * New commands: `tasks`, `alerts list`, `queues`, `pools`, `plugins` (`reload`, `enable`, `import`), `workflows` (`parents`, `steps`, `test_step`, `test_status`), `portlets`, `users create`, `workorders delete`, `workorders worksteps`, `worksteps reset`, `monitors activate|deactivate`, statistics (`stats` of `workorders`, `worksteps` and `queues`), and `control` (engine, monitor and workers).
  * `workflows check_import` detects more problems that make a workflow unusable (steps that never start, loops, invalid links or lookups).
  * `workflows development` and `plugins spec` are read by section (`toc`, `full`, `section <anchor>`), so that an AI assistant reads only what it needs.
* `connect`: IBM Aspera Connect will be deprecated in 2027: the transfer agent `connect` displays a warning that recommends IBM Aspera for Desktop (`--transfer=desktop`).
* `mcp`: no longer experimental: the plugin follows the same compatibility rules as other plugins.
* **library**:
  * New class `Aspera::Secret::Resolver`: references `secret://<store>/<path>[?<options>][#<field>]` to secrets of named stores, read when used, with a cache. It can also write secrets (`writable: true`) and inspect stores and references without reading values.
  * `Aspera::Log#logger=` sends logs to the logger of the application.
  * `Aspera::SealedHash.seal` and `unseal`: new parameters `encrypt:` and `reverse:`.
  * New token creator `Aspera::OAuth::SharesWeb` (`grant_method: :shares_web`).
  * Transfer agents: new optional method `transfer_cancel`. Agent `transferd`: parameters `api_key` and `ca_file` for an existing daemon, methods `info` and `create_client`, new fields in `transfer_status`, reader `transfer_id`.
* **project**:
  * OpenSSF Best Practices: silver badge (<https://www.bestpractices.dev/projects/5861>).
  * Test coverage: 96.6% of lines (was 85%), badge in `README.md`. Branch coverage is also measured.
  * New `GOVERNANCE.md` and `docs/ASSURANCE_CASE.md` (security requirements, threat model). Code review requirements in `CONTRIBUTING.md`.
  * Each source file has an SPDX copyright and license header.

### Issues Fixed

* Security:
  * `mcp server` (security level `high`): a client could execute code, or write a file where it chooses, through some options (`notify_template`, `fpac`, `ui` key `command`, `out` key `file`, `output`, `pid_file`, `home`, `plugin_folder`, `sdk_url`, `locations_url`), the folder `plugins` of the configuration folder, `config plugins create` and `faspex5 postprocessing`. They are now available only at level `low`, on the command line and in presets. At levels `medium` and `high`, `config preset set` refuses them, `config commands` does not list refused commands, and local files are written only in the new key `writable_paths` of option `security` (none by default).
  * `config transferd install`, `config ascp install`: a file or a link of the SDK archive cannot be written outside of the installation folder. Reported by [@thesmartshadow](https://github.com/thesmartshadow).
  * `config plugins create` refuses a plugin name that is not made of lowercase letters, digits and underscores.
* `ascli`:
  * `--out.select` with a dot-path key (e.g. `directory_user.type`) selected no item with formats `json`, `jsonpp`, `yaml` and `ruby`. Matching no item displayed a table with headings only, instead of `<empty>`.
  * An argument without `=` collected by `@:` is reported as a bad argument, instead of an assertion failure. Errors of extended values name their modifier (e.g. `@file:`).
  * `@extend:` no longer evaluates again the values it inserts (e.g. read by `@env:` or `@file:`).
  * An unknown key of a `Hash` option in dot notation (e.g. `--ui.foo=1`) gave an extra `unprocessed values` error.
  * When the renewal of an expired OAuth token fails, the error of the renewal is reported, instead of the original authorization error.
  * In debug logs, a command argument that contains a single quote was quoted wrongly.
  * Gem dependency: excludes `regexp_parser` 2.13.2, with which `json_schemer` fails to load.
* `config`:
  * `preset update` saved all the options of the command line in the preset, also those placed before `update` (e.g. `--home`, `--log-level`, `--format`).
  * `preset set`: the value is evaluated once: `@val:@file:<path>` stores `@file:<path>`, as documented, not the content of the file. The result of an evaluation is no longer evaluated again.
  * `initdemo`: the demo server preset allows the SSH host key `ssh-rsa`, the only one offered by the demo server, so that `server browse` and other file operations work. To fix a preset created by an earlier version: recreate it, or add `--ssh-options=@json:'{"host_key":["ssh-rsa"]}'`.
  * `vault` type `file`: the vault keeps its owner, group and mode when it is changed by another user, e.g. root.
  * `vault` type HashiCorp: responses of Vault failed with `wrong number of arguments` with gem `json` 3.
* `aoc`:
  * `automation instances show` did not return. It now accepts the numeric identifier or the UUID.
  * `packages receive` with option `package_folder`: two fields (e.g. `{"fld":["name","id"]}`) gave `<name>.id` instead of `<name>.<id>`, and with `seq` or `opt` the existence of the folder was checked in the current folder instead of `to_folder`.
* `faspex5`: web authentication (`--auth=web`) failed when HTTP basic authentication is enabled on the API client: option `client_secret` is now sent.
* `orchestrator`: authentication with option `apikey` was rejected (HTTP 401): the API requires `username` with the API key. Option `username` is now required with `apikey`.
* `node`:
  * Browsing a folder with `--query.per_page` or `--query.page` failed when API v4 is not used.
  * `telemetry`: an integer value of key `interval` (e.g. `0`, as documented) was refused. Same for keys `spawn_timeout_sec` and `spawn_delay_sec` of `transfer_info` (agent `direct`), and `font_ratio` of option `out` (key `img`).
  * `access_keys do <id> show` and `thumbnail` ask the node not to use its cache.
* `preview`:
  * `events` generated no preview: it now generates previews of new and modified files (option `filter` applies), and deletes the previews of deleted files.
  * Option `skip_format` failed with `FrozenError`.
  * An existing preview is also detected with the preview of the file (`files/<id>/preview`), when the information of the file has no `preview`.
* **library**: agent `transferd`:
  * `transfer_status` no longer blocks on an ended transfer. When the daemon cannot be reached, does not answer in time, or does not know the transfer, the status is `unknown` instead of `running`. Calls have a timeout: key `timeout` of `agent_params`, default 10 seconds.
  * A process that attaches to an external daemon for each transfer (e.g. Orchestrator) accumulated `at_exit` handlers.

### Breaking Changes

* Ruby 3.3 or later is required (3.2 reached end of life in March 2026). Future minimum is 3.4. Policy: a Ruby version is supported until 6 months after its end of official support. Gem dependencies: `net-ssh` 8, `marcel` 2.
* `orchestrator`:
  * Command `workstep` is renamed `worksteps` (e.g. `worksteps status`), consistent with `workorders`.
  * `workflows development`: document `authoring` is replaced by `guide` (the Aspera Orchestrator Development Guide, which includes the Workflow Authoring Guide): `workflows development authoring toc` is now `workflows development guide toc`, and `workflows development templates customruby` is now `workflows development templates section customruby`.
  * `plugins spec` is now `plugins spec toc`, and `plugins spec <plugin> [section]` is now `plugins spec show <plugin> [section]`.
* `config`: arguments given in a fixed order are replaced by a `Hash`, usually given with `@:` (items `key=value` in any order):
  * `detect <url> [<plugin>]` is now `detect @: url=<url> plugin=<plugin>`. `url` is still asked if not given.
  * `wizard <url> [<plugin> [<preset>]]` is now `wizard @: url=<url> plugin=<plugin> preset=<preset>`. `url` is still asked if not given. Options `--override` and `--default` are replaced by keys `override` and `default` of the `Hash`. Options of the plugin (`--username`, `--password`, `--private-key`, `--client-id`, `--use-generic-client`...) are unchanged. Option `--key-path` is removed: give the key itself with `--private-key=@file:<path>`. The wizard still uses the default key, or generates one, if `--private-key` is empty.
  * `preset lookup --url=<url> --username=<user>` is now `preset lookup @: url=<url> username=<user>`. Options `--url` and `--username` are no longer used by this command.
  * `preset set` merges into the configuration (JSON Merge Patch: deep merge, `@none:` removes a key) at one of three levels: `set <Hash>` (presets by name, e.g. `set @: p1.url=https://example.com default.server=p1`, `set @: p1=@none:` deletes preset `p1`), `set <name> <Hash>` (parameters of a preset, e.g. `set p1 @: url=https://example.com username=bob`), or `set <name> <param> <value>` (unchanged). Options of the command line are not saved in the preset. Commands `update`, `initialize` and `unset` are deprecated, and show the command to use: `update <name> --url=...` is `set <name> @: url=...` (it now saves only the options placed after `update`), `initialize <name> <Hash>` is `delete <name>` then `set <name> <Hash>`, `unset <name> <param>` is `set <name> <param> @none:`.
* `config completion`: completion scripts saved in a file must be saved again (see manual). Keys of an option are proposed with a trailing `=` or `.`.
* **library**: Modules about secrets are in `Aspera::Secret`: `SecretHider` is now `Secret::Hider`, `SecretStrength` is now `Secret::Strength`, `Keychain` is now `Secret::Store`. `Secret::Store::Factory.create` takes only the parameters of the store, and `Factory::LIST` is replaced by `Factory.types`.

### Server Versions

Tested with Ruby 4.0.9 on osx-arm64.

| Plugin | Product | Version |
| ------------ | ------------------------------------------------ | ---------------- |
| `aoc` | IBM Aspera on Cloud | SaaS |
| `console` | IBM Aspera Console | 3.4.11 |
| `faspex5` | IBM Aspera Faspex | 5.0.19 |
| `faspio` | IBM Aspera faspio Gateway | 1.3.7 |
| `httpgw` | IBM Aspera HTTP Gateway | 2.3.4 |
| `node` | IBM Aspera High-Speed Transfer Server (Node API) | 4.4.9.3472 |
| `orchestrator` | IBM Aspera Orchestrator | 4.1.6.2036-00000 |
| `server` | IBM Aspera High-Speed Transfer Server (SSH) | 4.4.9.3472 |
| `shares` | IBM Aspera Shares | 1.11.5 |

### Transfer Agent Versions

| Agent | Product | Version |
| --------- | ------------------------------------------------ | ---------- |
| `connect` | IBM Aspera Connect | 4.2.16 |
| `desktop` | IBM Aspera for Desktop | 1.1.2 |
| `direct` | IBM Aspera ascp | 4.4.8.2592 |
| `httpgw` | IBM Aspera HTTP Gateway | 2.3.4 |
| `node` | IBM Aspera High-Speed Transfer Server (Node API) | 4.4.9.3472 |
| `transferd` | IBM Aspera Transfer Daemon | 1.1.9 |

## 4.28.0

Released: 2026-10-22

Highlights: security hardening of local web servers (authentication, minimum secret strength, cross-site requests refused), new option `security`, `mcp server` over HTTPS with token or OAuth authentication, JMESPath queries (`--out.query`), exit code by category of error, context-aware shell completion (also PowerShell), tables fitted to the terminal width. Ruby 3.2 or later is required.

### New Features

* `ascli`:
  * Local web servers refuse a weak secret at startup (`auth_token` of `mcp server`, `secret_token` of `faspex5 postprocessing`, `password` of `node emulator` and gateways): minimum strength set by parameter `*_min_bits` (default `80`, `0` disables), estimated with gem `zxcvbn` if installed.
  * New option `security`: level `medium` or `high` restricts extended values `@ruby:`, `@uri:`, `@env:` and `@file:` (see manual).
  * `@secret:` asks for the secret on a local web page in the browser when option `ui` is `graphical`.
  * Local web pages (authentication, secret request, OAuth consent) follow the light or dark theme of the system or browser.
  * Option `ui` is extended (still compatible: `--ui=text|graphical`): sub-option `mode` (`auto`, `terminal`, `browser`) and `command` (array: browser command, URL appended). It replaces the environment variables `ASPERA_BROWSER` and `BROWSER`, which are no longer used.
  * New option `--out.query`: [JMESPath](https://jmespath.org) expression (or `@ruby:` lambda) to filter and reshape results, as `--query` of the AWS and Azure CLIs. New gem dependency: `jmespath`.
  * The exit code indicates the category of error (e.g. `3` authentication, `4` not found, `5` transfer, `6` network): see `ascli -h` or the manual.
  * Tables fit the terminal width: text columns are wrapped. Parameter `width` of `--out.table` sets the maximum width.
  * Schema tables (value `help` of an option or argument, `config ascp spec`, `config sync spec`, `config agents parameters`, manual) indicate required fields.
  * Shell completion follows the context: options of plugin and command, values and types of options and arguments, keys of structures, aliases and abbreviations, local files for uploads, with descriptions in Zsh, Fish and PowerShell.
  * New composite option `--temp` with sub-options `folder`, `clean` and `expiry`: age of `ascp` file lists left by interrupted commands, deleted when a command starts (a duration, e.g. `30d`, default `5d`, `false`: never, `0`: all). Options `--temp-folder` and `--clean-temp` are deprecated.
* `config`:
  * New command `completion powershell` displays the completion script of PowerShell (see manual).
  * `ascp spec`: Optional argument: name of agent, to display only the parameters it supports (as `config ascp schema`), or `overview`, for one column per agent.
* `mcp`:
  * `server`: Authentication of transport `http` with a static token (`auth_token`) or OAuth 2.0 (`oauth`), new option `public_url`.
  * `server`: HTTPS for transport `http` with options `url`, `cert`, `key` and `chain`. Options `bind` and `port` are deprecated: use `url`.
  * `server`: `@secret:` asks the user on a web page (MCP URL mode elicitation): the secret is not sent to the AI model.
* `faspex5`:
  * `postprocessing`: New parameters `secret_token` (`?token=` in URL) and `allowed_ips` (addresses or CIDR) restrict callers.
  * `postprocessing`: Parameter `lambda` of the URL query evaluates a Ruby script returning a lambda, called with the webhook values (was ignored).
  * `gateway` (and `aoc gateway`): New parameters `username` and `password` (HTTP Basic, as Faspex 4).
* `orchestrator`:
  * New command `workflows development` displays the Workflow Authoring Guide, the Action Template Reference and the Plugin Manual (from GitHub), also used by AI assistants through `mcp server`: whole document, one section, or table of contents up to a level (default per document, or optional argument).
  * `workflows export` with option `dependencies` saves a package (`.wkf`) with sub-workflows and remote nodes.
  * `workflows import` takes an optional argument with options `folder_id`, `publish` and `link_to_subworkflows`. `workflows list` displays `folder_id`.
  * New commands `monitors list` (monitors of a type: remote node monitors give the names of remote nodes), `queues list`, `pools status` and `journal files` (files recorded in a journal book). `--query=help` displays the query parameters of each API call, from the OpenAPI description of Orchestrator (corrected from the source code of Orchestrator 4.1.6, OpenAPI 3.1).
  * New command `workflows check_import` checks a workflow file (`.yml` or `.wkf`) locally before import, and reports problems with a severity, a code and a location (as the web UI import does). `workflows import` logs these problems as warnings.
  * New command `plugins spec` displays the specifications of action plugins (from GitHub, option `plugin_specs`): template attributes with their allowed values, inputs and outputs with the template settings they depend on. Used by AI assistants through `mcp server`, and by `workflows check_import` to check action templates and the inputs of steps (attributes and values, required inputs not mapped, inputs and outputs the plugin does not have).
  * New command `workflows find_constraints` lists the conflicts and missing plugins found by Orchestrator for a file already on the server. `workflows import_with_constraints` refuses an import that Orchestrator would handle incorrectly (plugins not enabled, partial resolution of conflicts).
* `shares`:
  * New commands `share list`, `share event create`, `admin directory`, `admin user|group search`, `admin group local users`, `admin authenticate`, and `admin user|group all transfer_settings delete` (reset to global settings).
  * `health` uses the `/health_check` endpoint: status of each license and node.
  * Help of `admin share user_permissions|group_permissions create|modify` shows the request body.
* `sync`:
  * `target_rate` in `sync_info` accepts suffixes `k`, `m` and `g` (e.g. `100m`).

### Issues Fixed

* `ascli`:
  * Tokens displayed by `bearer_token`, `bearer_token_node` (`aoc`, `faspex5`, `node`), `aoc admin node bearer_token` and `node basic_token` were returned to the AI client by `mcp server`. They are now hidden.
  * Secrets are also hidden by value, wherever they appear in logs, results and `mcp server` responses (e.g. in an error message, or as a key name): values of secret options (e.g. `password`) and of presets (e.g. read alone with `@preset:<name>.password`), of `@secret:` and `@vault:`, OAuth tokens, generated bearer and basic tokens, secrets of transfer specs. In `mcp server` responses, a value shorter than 8 characters is also hidden as a word in a text.
  * With option `security` level `medium` or `high` (default of `mcp server`), a secret read by `@secret:`, `@vault:` or `@preset:` cannot be processed by another extended value (e.g. `@list:`, `@json:`, or in a text with `@extend:`), nor be a parameter name of `config preset set`: the result could reveal it to the AI client.
  * Secret values of URL query parameters (e.g. `token`, `client_secret`) are hidden in logs.
  * Logs: secrets in a Ruby `Struct` or object (`password="..."`) were shown. Secrets of a dumped structure are now hidden by field name before it is rendered, whatever `log.format`.
  * Local web servers (`faspex5 postprocessing`, `faspex5 gateway`, `aoc gateway`, `node emulator`, `mcp server`, `--auth=web`):
    * Requests that a web page in the browser can send are refused: `Host` not loopback on a loopback server (DNS rebinding), `Origin` of another site.
    * A `url` with an IPv6 address, or parameter `chain`, failed at startup.
    * WEBrick messages are logged at debug level.
  * `--auth=web`:
    * Login could wait forever when the browser called back early, or when `redirect_uri` has a path (HTTP 404).
    * A `redirect_uri` on loopback other than `127.0.0.1` (e.g. `[::1]`) was refused.
    * Ctrl-C ended with an internal error instead of stopping the command.
    * The page after login, whose URL contains the authorization code, could be cached, framed, or sent as referrer.
  * Error messages of servers in Ruby (e.g. Orchestrator) included the backtrace of the exception: it is in the debug log only.
  * Network errors and resources not found by name were reported as `Other(<exception class>)`.
  * Terminal output:
    * Unicode (`--out.utf8`): detection follows the precedence of locale variables (`LC_ALL=C` disables it), and supports Windows Terminal, VS Code, Git Bash, ConEmu and terminals setting `TERM`.
    * Colors (`--out.colors`): `NO_COLOR`, `CLICOLOR` and `CLICOLOR_FORCE` follow conventions, and results written with `--out.file` no longer contain ANSI codes.
    * Without Unicode, symbols are replaced with ASCII (e.g. hidden secret `🔑` becomes `***`).
  * A boolean or decimal result (e.g. `config echo @json:true`) failed with an internal error.
  * `--out.select` refused a Ruby lambda (`@ruby:`).
  * Help and manual: a parameter with alternatives (`oneOf`) had no type (which broke the PDF manual), and alternatives had no title.
  * Value `help` of an option or argument displays the schema as `config sync spec`: with fields of alternatives (`oneOf`), deprecations and examples, and for `--ts=help` the supported agents and `ascp` options. `config agents parameters` displays allowed values and defaults.
  * Removed gem dependencies `blankslate` and `word_wrap`: descriptions in schema tables are wrapped to the terminal width instead of cut at 120 characters.
  * Transfer spec parameter `target_rate` is in bps as documented (without suffix or with `k` it was taken as kbps, an integer was rejected), and `sync` ignored it (and `target_rate_kbps` with format `args`).
  * An asynchronous transfer with agent `direct` (default of `mcp server`) failed with `failed to open input file list`: the file list was deleted at the end of the command. Temporary files of `ascp` are now deleted when the transfer ends.
  * `--clean-temp=no` also kept the old `ascp` file lists left by interrupted commands, and two commands starting at the same time could fail when deleting the same old file list.
* `config`:
  * `preset get`: The value of a secret option (e.g. `password`) was displayed, and returned to the AI client by `mcp server`. It is now hidden, unless `--out.secrets=yes` (command line only, never in `mcp server`).
  * `preset`: A secret made of digits only (e.g. `password`, set with `config preset set`, or not quoted in the YAML file) was a number, shown in results and `mcp server` responses: it is now a `String`, hidden.
  * `vault`:
    * `system` (macOS): the password and `username` were not returned, and special characters were stored escaped.
    * `file`: `password` did not migrate a vault of version 4.26.0 or earlier to PBKDF2. The file is loaded with YAML safe loading.
    * `vault` (HashiCorp): `list` failed after a secret was deleted.
    * `1password`: `url` is read from the website of the item.
    * `preset secure` failed on a missing secret (`system`, `1password`), and `@vault:` on a label containing dots.
  * `completion words`: Extended values on the command line were evaluated at each `Tab` (e.g. `@ruby:` code executed, `@stdin:` waiting for input).
  * `completion`: Bash: words containing `=` or `:` (e.g. a URL) broke completion of the next words, and each `Tab` checked for a newer gem version on the network.
  * `documentation`: In `toc`, lines of code blocks (e.g. shell comments) were taken as headings, and they ended the extracted section. `--select` did not apply to `toc` (keys were symbols).
  * `transfer status`: For agent `direct`, `bytes_transferred` (sum of `TransferBytes` of the sessions) and `ended_at` were not set.
  * `sync translate`: Options `-C`, `--ws-connect`, `-D`, `--scan-interval` and `--remote-scan-interval` were translated incorrectly.
* `mcp`:
  * REST error messages were repeated once more at each tool call.
  * `server`: Option `--out.query` was ignored.
* `faspex5`:
  * `postprocessing`, `gateway` (and `aoc gateway`): Invalid requests return HTTP 400, 403 or 404 instead of 500, without stack trace or path of the script.
  * `packages send` (and `aoc packages send`): In asynchronous mode, the job id of the transfer was not returned: it is in field `transfer` of the result.
* `node`:
  * `emulator`: A symbolic link in the `docroot` leading out of it was followed by transfers.
  * `emulator`: A `POST` with an empty body returned HTTP 500 instead of 400.
* `orchestrator`:
  * `workflows import_with_constraints` failed with an internal error of Orchestrator (plugins not enabled), or silently imported copies (partial resolution of conflicts). The OpenAPI description of `find_constraints` and `import_with_constraints` was wrong.
  * `workflows import`, `import_with_constraints` and `publish` sent requests rejected by Orchestrator, `import` did not report workflows not imported, and `start` with `synchronous` failed to display the work order.
  * `workstep status` displayed fields that are YAML dumps of Orchestrator objects (`prerequisites`, `work_outputs`...): they are removed, inputs and outputs are in `inputs` and `outputs`.
* `shares`:
  * The manual and the description of `admin user|group all share_permissions` (read-only) did not tell that permissions are granted with `admin share user_permissions|group_permissions`: AI assistants concluded that it was not possible. The argument of `show` is named `share_id`.

### Breaking Changes

* `ascli`:
  * Secrets are hidden in results, whatever the output level or format (`--out.level=data`, `--format=json`...), unless `--out.secrets=yes`: before, `--out.level=data` (default with `--format=json`, `csv`...) showed them. This includes tokens displayed by `bearer_token`, `bearer_token_node`, `basic_token` and `config preset get <secret>`. Add `--out.secrets=yes` to scripts that use them (e.g. `$(ascli aoc bearer_token --out.secrets=yes)`).
  * Ruby 3.2 or later is required (3.1 reached end of life in March 2025). Future minimum is 3.3. Policy: a Ruby version is supported until 18 months after its end of official support.
  * The exit code on error indicates its category instead of always `1`: scripts shall test for a non-zero code. With `--format=nagios`, a failed command exits with `3` (UNKNOWN). Value `help` of a structured value exits with `0`.
  * Local web servers on an address that is not loopback require authentication: `auth_token` for `mcp server`, `secret_token` or `allowed_ips` for `faspex5 postprocessing`, `username` and `password` for `node emulator`, `faspex5 gateway` and `aoc gateway`.
  * Local web servers: a JSON body requires header `Content-Type: application/json`, else HTTP 415.
  * `@secret:` asks in the browser by default on Windows and macOS (option `ui` is `graphical`): use `--ui=text` for the terminal.
* `config`:
  * `completion`: Completion scripts saved in a folder shall be saved again (they call new command `config completion candidates`).
  * `vault`: `create` fails if the label exists (`vault`, `1password`), `delete` fails if the secret does not exist (`file`). `1password`: `url` is stored as website of the item.
  * `ascp spec`, `sync spec`, `agents parameters`, value `help` of an option or argument: Columns are `name`, `type` and `description` (no `required`), and `description` is a list of lines (formats `json`, `yaml`), absent when empty.
  * `ascp spec`: Columns per agent are displayed with argument `overview`. By default, the description lists the supported agents, if not all (e.g. `(A, N)`).
  * `agents show`: Displays only the agent description: parameters are displayed by `config agents parameters`.
* `mcp`:
  * `server`: Option `security` is `high` by default and cannot be changed by the client, and `@stdin:` is refused: a preset reading a private key with `@file:` requires level `medium` or `low`.
  * `server`: Keys of transport `http` are refused with `stdio` (the default), and `max_line_bytes` with `http`: they were ignored.
* `faspex5`:
  * `postprocessing`, `gateway` (and `aoc gateway`): Parameters are validated at startup: unknown keys are refused instead of ignored, and a missing `script_folder` is reported.
  * `postprocessing`: Only webhook values whose key starts with `faspex_` are passed to the script as environment variables, and a structured value as JSON.
* `orchestrator`:
  * `workflows import` takes a file created by `workflows export`, and `workflows import_with_constraints` takes keys `filename`, `add_as_revision`, `subwf_constraints`, ... (see help).
  * `monitors` is now `monitors snapshot`, with an optional type of monitors.
  * `workorders output` displays values of variables as plain values instead of single-element arrays, and an empty value as `null`.

### Server Versions

| Plugin | Product | Version |
| -------------- | -------------------- | ------------------ |
| `aoc` | Aspera on Cloud | SaaS |
| `console` | IBM Aspera Console | 3.4.11 |
| `faspex5` | Faspex v5 | F5.0.17 |
| `httpgw` | HTTP Gateway | 2.3.4 |
| `node` | HSTS Node API | 4.4.8.2596 |
| `orchestrator` | Orchestrator | 4.1.6.2036-00000 |
| `shares` | IBM Aspera Shares | 1.11.5 |

### Transfer Agent Versions

| Agent | Product | Version |
| ----------- | -------------------------------- | --------- |
| `connect` | IBM Aspera Connect Client | 4.2.14 |
| `desktop` | IBM Aspera Desktop Client | 4.4.3 |
| `direct` | IBM Aspera Transfer SDK (ascp) | 1.1.9 |
| `httpgw` | IBM Aspera HTTP Gateway Agent | 1.3.0 |
| `node` | IBM Aspera Node API Agent | 4.4.3 |
| `transferd` | IBM Aspera transferd daemon | 1.1.9 |

## 4.27.5

Released: 2026-10-06

### New Features

### Issues Fixed

* `node`, `aoc`: Fixed #268: Resolution of a remote path could match an entry in the wrong folder: after a path element matched, the next element could be matched by a sibling in the same folder instead of a child (e.g. `browse /a/b/c` listed `/a/c` if `/a/b/c` did not exist): such a path now fails with `Entry not found`. Affects all commands taking a remote path (`browse`, `upload`, `download`, `sync`, `delete`, `mkdir`, `rename`, ...), also in `aoc files` and `preview`.

### Breaking Changes

### Server Versions

| Plugin | Product | Version |
| -------------- | -------------------- | ------------------ |
| `aoc` | Aspera on Cloud | SaaS |
| `console` | IBM Aspera Console | 3.4.4 |
| `faspex5` | Faspex v5 | F5.0.17 |
| `httpgw` | HTTP Gateway | 2.3.4 |
| `node` | HSTS Node API | 4.4.8.2596 |
| `orchestrator` | Orchestrator | 4.1.6.2036-00000 |
| `shares` | IBM Aspera Shares | 1.9.14 |

### Transfer Agent Versions

| Agent | Product | Version |
| ----------- | -------------------------------- | --------- |
| `connect` | IBM Aspera Connect Client | 4.2.14 |
| `desktop` | IBM Aspera Desktop Client | 4.4.3 |
| `direct` | IBM Aspera Transfer SDK (ascp) | 1.1.9 |
| `httpgw` | IBM Aspera HTTP Gateway Agent | 1.3.0 |
| `node` | IBM Aspera Node API Agent | 4.4.3 |
| `transferd` | IBM Aspera transferd daemon | 1.1.9 |

## 4.27.4

Released: 2026-10-05

### New Features

* `orchestrator`: Add JWT-based bearer token authentication (default) and API key support via options `--auth_style` (`token`, `basic`, `query`) and `--apikey`.
* `aoc`: `short_link list` supports `--query=help`, help of `short_link create|modify` shows the request body.
* `node`: `emulator` executes transfers with `transferd`, and supports more of the Node API. See the manual.
* **general**: Linux portable package `aspera-cli-<version>-linux-x86_64-glibc<version>-portable.tgz`: Ruby, gems and Transfer SDK, extract and run, like the Windows portable package.
* `shares`: `admin share user_permissions|group_permissions` support `create`, `modify` and `delete` (identified by user or group id, e.g. `%username:john@example.com`).
* `config`: `commands` accepts aliases in the command path (e.g. `config commands server browse`).

### Issues Fixed

* `preview`: Generator options with a numeric value given on command line (e.g. `--thumb-vid-fraction=0.3`, `--blend-pauseframes=2`) were failing.
* `aoc`: `short_link show` always failed with `not found`.
* `faspex5`: `packages receive` with a public link now works with a list of files, and `ALL`.
* `faspex5`: `packages send` now returns the package information (like `aoc`).
* `config`: `commands` failed with `no such command` when the command path included positional arguments (e.g. `faspex5 packages receive ALL`): arguments are now skipped, and an unknown command shows the list of sub-commands.
* `aoc`: `files short_link public modify` with `access_levels` set full access (`edit`) instead of the given levels.
* `aoc`: `packages shared_inboxes short_link public` commands were failing (wrong short link purpose, parameters of shared folder links). Link type `private` is removed: AoC supports it only for shared folders.
* **general**: Agent `node` was failing when the transfer was canceled or paused on the node.
* **general**: When the default CA certificate locations of Ruby's OpenSSL do not exist (e.g. single executable built on another Linux distribution), the system CA bundle is used.
* **general**: Windows portable package displayed `Ignoring bigdecimal-... because its extensions are not built` at each start.
* **general**: Fixed #265 #266: Linux single executable of 4.27.3 ran every command as `config commands <command>`: e.g. `config transferd install` only displayed its syntax, and `faspex5 packages receive ALL` failed with `no such command`.
* `config`: `transferd install` with `--sdk-url=file:///...tar.gz` (local SDK archive, Linux) failed with `not in gzip format`.
* **general**: Linux single executable: commands could fail with `cannot load such file` (e.g. `config transferd install`: `rubygems/package`): it now includes the whole Ruby standard library and all files of gems.
* **general**: **Progress bar**: stayed at 0% when the total size was not known (the transferred size is now shown), rate was underestimated (it included connection time: now averaged over the last 5 seconds, in decimal `Mbps` like `ascp`), a resumed session doubled the total size or failed the transfer, a second HTTP download accumulated the first one, multi-session state was shared between sessions in agent `direct`. Errors in the progress bar no longer fail the transfer.
* **general**: **Progress bar**: a failed transfer was displayed as completed (the bar now stops at the reached progress, with `failed`), log lines were mixed with the progress bar (they are now displayed above it), files already at destination (whole or partially, when resumed) were not counted in progress, multi-session progress exceeded the total size (agent `direct`), agent `httpgw` did not terminate the progress bar.
* **general**: Agent `direct`: when `ascp` ended without final status (e.g. killed), `ascli` failed with `wrong number of arguments`: the transfer is now resumed.
* `shares`: Help of `admin share create|modify` showed fields `path` and `description`, rejected by Shares (error 500): fields are `directory` and `create_directory`. Same for `description` in `admin group local create|modify`.
* `aoc`: `admin user preferences|notifications show|modify` failed with `undefined method 'setup_admin_user_instance'`.
* **general**: With `--bulk=yes`, commands under a node with an identifier (e.g. `node access_keys do <id> delete`, `faspex5 admin nodes shared_folders <id> delete`, `shares admin share user_permissions <id> delete`) failed with `Missing argument: command`: only arguments supporting bulk operations are read as a list.
* `server`: Aliases `browse`, `delete` and `rename` executed `ls`, `rm` and `mv` even when `ascmd` is not available.
* `config`: `wizard` displayed a test command that does not exist for `faspio`, `orchestrator`, `console` and `server`.
* `faspex5`: With a public link to a package, the first argument of `packages browse`, `status` and `receive` was ignored (e.g. the folder of `browse`, the first file of `receive`).
* **general**: A multi-line value was evaluated as an extended value when any of its lines, not only the first one, started with a decoder (e.g. `@ruby:`): such a value is now taken as is.
* **general**: `@stdin:chomp` was failing.
* **general**: A configuration file with an error to fix (e.g. duplicate keys) was renamed `*.manual_conversion_needed`, and a new empty configuration file was created on next execution: the file is now left untouched, and the error is displayed.
* **general**: `--out.level` was overridden by `--format` given after it, or in the same `--out` value: e.g. `--out.level=info --format=json` displayed secrets.
* **general**: Integers with a leading zero were rejected in options (e.g. `--version-check-days=08`) and arguments, or read as octal in dotted values (e.g. `--query.page=010`). An invalid number in an option now gives the name of the option.
* `faspex5`: `admin shared_inboxes|workgroups saml_groups modify|delete` with a percent selector (e.g. `%name:my_group`) failed with `assertion failed`.
* `faspex5`: Lists were read endlessly if the server returned an empty page before the total count, and failed without total count.
* `config`: `vault` of type `file` without `name` failed with `no implicit conversion of nil into String` (default name: `vault.bin`).
* **general**: Interactive prompts were displayed on `stdout`, mixed with results (e.g. when redirected to a file): they are now displayed on `stderr`.
* **general**: Security: the encrypted vault file was readable by other users, and files with secrets (configuration, persistency, generated private key) were readable by other users until access was restricted, just after creation: they are now created with restricted access.
* **general**: Security: secrets of transfer agent parameters (e.g. `password` of agent `node`) were saved in clear with asynchronous transfers: `config transfer status` now takes them from the current `transfer` option.

### Breaking Changes

* **general**: With `--format=json`, `jsonpp`, `yaml` or `ruby`, the output is always valid in this format: a status is a string (e.g. `"complete"`), an empty list is `[]`, and no result is `null` (were displayed as plain text, e.g. `complete`, `empty`, `nothing`).
* `node`: `emulator` requires `transferd` and the gem `grpc`, instead of `ascp`.
* `node`: `simulator` is not renamed and is an alias of `emulator`.
* `node`: `emulator` parameter `browse_root` is renamed `docroot`.
* **general**: Release archives are named `aspera-cli-<version>-<os>-<cpu>...`: single executable `aspera-cli-<version>-linux-x86_64-glibc<version>-ocran.tgz` (was `ascli-...`), Windows portable `aspera-cli-<version>-windows-x86_64-portable.zip` (was `windows-amd64`).
* `orchestrator`: Command `plugins` is now `plugins list`.
* `orchestrator`: Default authentication is now JWT token.
* **general**: The progress bar is displayed on standard error (was standard output), by default if standard error is a terminal: it is displayed even if the output of the command is redirected to a file. Agent `direct`: if `transfer` parameter `quiet` is `false` (native progress bar of `ascp`), the progress bar of `ascli` is not displayed, unless option `progress_bar` is set.

### Server Versions

| Plugin | Product | Version |
| -------------- | -------------------- | ------------------ |
| `aoc` | Aspera on Cloud | SaaS |
| `console` | IBM Aspera Console | 3.4.4 |
| `faspex5` | Faspex v5 | F5.0.17 |
| `httpgw` | HTTP Gateway | 2.3.4 |
| `node` | HSTS Node API | 4.4.8.2596 |
| `orchestrator` | Orchestrator | 4.1.6.2036-00000 |
| `shares` | IBM Aspera Shares | 1.9.14 |

### Transfer Agent Versions

| Agent | Product | Version |
| ----------- | -------------------------------- | --------- |
| `connect` | IBM Aspera Connect Client | 4.2.14 |
| `desktop` | IBM Aspera Desktop Client | 4.4.3 |
| `direct` | IBM Aspera Transfer SDK (ascp) | 1.1.9 |
| `httpgw` | IBM Aspera HTTP Gateway Agent | 1.3.0 |
| `node` | IBM Aspera Node API Agent | 4.4.3 |
| `transferd` | IBM Aspera transferd daemon | 1.1.9 |

## 4.27.3

Released: 2026-09-25

### New Features

* **general**: Help and `config commands` show all positional arguments with meaningful names and their type when not plain text, e.g. `<account:Hash>`, `<account_id>`, `<path>`, `<source> <destination>`.
* **general**: Values of options and arguments with a schema owned by `ascli` (e.g. `ts`, `transfer`, `out`, `http_options`) are validated: the error shows the path of the invalid element and the reason. New gem dependency: `json_schemer`.
* **general**: Deprecation warnings, help and `config options` show the last version supporting a deprecated option and its replacement, e.g. `deprecated after 4.27.0: use --out.level`.
* **general**: New Windows portable package `aspera-cli-<version>-windows-amd64-portable.zip` in GitHub releases: includes Ruby, gems and `ascp`, no installation nor administrator rights needed.
* **general**: New options `--out.colors` and `--out.utf8` to enable or disable ANSI colors and Unicode characters in terminal output, instead of auto-detection.
* `config`: `completion bash|zsh|fish` displays the completion script of the shell, included in the gem: activate with `eval "$(ascli config completion bash)"` (see manual).
* `config`: `options` shows in column `allowed` the expected type of options without a list of values when not plain text, e.g. `Hash`, `Integer`, `Hash|String`.
* `config`: `commands` accepts an optional plugin name and command path, and shows sub-trees provided by another plugin (e.g. `aoc files`) as a reference unless option `expand_mounts` is `yes`.
* `aoc`: `automation` covers the whole Automation API: new `workflows update_state|cancel_instances|delete_instances|permissions`, `instances cancel`, `steps`, `actions`.
* `console`: New commands `transfer current submit`, `transfer smart pause`, `transfer queue <queue_id> list|move_forwards|move_back`, `endpoint list`, `ssh_key list`, `admin email_server_update|nodeapi_credentials_update`. `health` also checks `health/up`. Help shows request body schemas.
* `orchestrator`: `workflows start <workflow_id> [<parameters>] [<execution>]` takes an optional `Hash` argument `execution` (`synchronous`, `step`, `variable`).

### Issues Fixed

* `aoc`, `ats`, `cos`, `node`, `faspex5`, `shares`: Help, shell completion and `config commands` now show all positional arguments and all sub-commands of commands executed on a node (e.g. `aoc files permission <path> list`).
* `aoc`: `automation` commands were failing or misbehaving (`workflows list`, `workflows action`, `instances`).
* `aoc`: `admin node do <id> transfer` and `admin workspace shared_folder <id> node <id> transfer` were always failing: they now take the same arguments as `files transfer`.
* `aoc`: `user contacts show|create|modify|delete` were failing.
* `aoc`: `short_link create|modify` were ignoring the provided `password` and `access_levels`.
* `faspex5`: `admin account show` was failing, `admin file_processing next` was not available.
* `shares`: `files spec|transport` and `admin user|group all|local show|modify|delete <id>` were failing.
* `mcp`: Secrets (e.g. from `config preset show`) are now hidden in tool results.
* `node`: `telemetry` with `interval` `0` was rejected instead of sending a single measure.
* `config`: Option `sdk_folder` with value `product:<name>` was taken as a folder path.
* `config`: `transferd install` was failing when the download server sends a `Content-Disposition` header.
* `config`: On a new configuration, `preset update|set|ask` with a password, and `preset show|get|unset|delete GLOBAL`, declared a global preset without creating it: all following commands were failing. `preset delete` also removes default declarations referring to the deleted preset.
* `config`: `options` returned empty rows with option `fields` or `select`.
* **general**: Temporary files (e.g. `ascp` file list) could be deleted before use, causing random transfer failures: `failed to open input file list` (since 4.27.1).
* **general**: Option `cert_stores` was adding to the system default locations instead of replacing them, as documented (use `DEF` to include the default).
* **general**: Dot-path options: `--log.secrets=yes` was failing, indexes on an `Array` option were duplicating values, `--show-config` was showing internal values for some options.
* **general**: Help was failing when a schema enum contains `null`, `--query=help` was missing parameters defined by `$ref`.
* **general**: Log format `caller` showed `???` with Ruby < 3.4.
* **general**: The error for a missing default preset now suggests `config preset initialize` instead of obsolete commands.

### Breaking Changes

* **general**: In dot-path values (e.g. `--ts.x=yes`, `config preset set`), `yes` and `no` are converted to `Boolean`: use `@json:"yes"` to get a `String`. In a structured value, `out.table.pivot` is `false`, `true` or `single`.
* `preview`: Renamed option `mimemagic` to `detect_mime`.
* `server`: `ls|rm|mkdir|du|md5sum|mv|cp` require at least one path, `df|info` take no argument. `mv|cp` take `<source> <destination>` pairs, or only sources with option `to_folder`.
* `console`: `transfer current change_rate|change_policy` require a `<data>` argument instead of option `query`. `transfer current move_forwards|move_back` moved to `transfer queue <queue_id> move_forwards|move_back <transfer_id>`.
* `aoc`: `automation workflows action show` replaced by `automation actions show`, `automation instances modify` replaced by `automation instances cancel`.
* `orchestrator`: Options `synchronous` and `result` are deprecated, use argument `execution` of `workflows start`.
* `config`: `completion bash <words>` renamed `completion words <words>`: `completion bash` now displays the completion script. Scripts previously downloaded from folder `etc/` shall be replaced (see manual).

## 4.27.2

Released: 2026-09-18

### New Features

* `aoc`: Added `admin node update_status` to tell AoC to scan the node and get a new status.
* **Windows**: Zip installer supports per-user or global installation.
* **general**: Harden single file executable generation with `ocran`.

### Issues Fixed

* `direct`: Fixed #263: Boolean transfer spec parameter `preserve_times` was incorrectly generating ascp option: `-p true`. Leading to error message: `no remote host specified`. Now it correctly generates `-p`.

### Breaking Changes

## 4.27.1

Released: 2026-09-16

### New Features

* **global**: `browse` is now accepted as an alias for `ls` in `node access_key do`, `aoc files`, `aoc admin node do`, and `aoc admin ats access_key node`.
* `config`: Vault: added support for 1Password as a secret store.
* `config`: Preset secrets (passwords, keys) are now automatically moved to the vault when a preset is saved and a vault is used.
* `httpgw`: Added asynchronous transfer mode — `last_job_id` is now exposed so a transfer can be submitted and its status queried later.
* `direct`: Added asynchronous transfer mode — `last_job_id` is now exposed so a transfer can be submitted and its status queried later.
* `preview`: `scan` now accepts an optional path or `%id:<file_id>` selector, allowing preview generation for one file or a subtree. Added the `--filter` option, supporting glob strings, regular expressions, and `@ruby:` Proc expressions.
* `config`: Preset keys starting with `_` (e.g. `_comment`) are now ignored when a preset is applied as CLI options, allowing inline annotations in `config.yaml`.
* **global**: New composite option `--out` groups all output rendering options with dot-notation sub-keys: `format`, `level`, `file`, `fields`, `select`, `table[.pivot]`, `flat`, `secrets`, `img`. Individual options preserved with deprecation warnings.
* `config`: `preset set` now supports dot-notation keys with deep-merge and automatic type coercion.

### Issues Fixed

* `faspex5`: Wizard was incorrectly nesting `client_id` and `client_secret` under a `params:` sub-key in the generated preset, instead of placing them at the top level.
* **global**: Assigning `@none:` to a `Hash`-typed option now correctly resets it to `nil` instead of being stored as a literal value.
* `config`: Vault: removed `symmetric-encryption` gem dependency, replaced with `openssl`. Existing encrypted data may not be compatible — export your vault contents first, then re-import after upgrading.
* `config`: Vault: fixed macOS Keychain API compatibility.
* **global**: Option type `Hash` is now automatically inferred when the option schema uses `oneOf`/`anyOf` with all-object branches; no need to specify `allowed: Hash` explicitly.

### Breaking Changes

* `preview`: Options `--scan-id` and `--scan-path` are deprecated; use the optional `scan [path]` argument instead.
* `faspex`: **Plugin removed** - Faspex v4 is end of support since September 30th, 2024. Use `ascli` version 4.19.0 or earlier if still needed.

## 4.27.0

Released: 2026-09-03

> [!IMPORTANT]
> This release includes a **major internal rework** of the command dispatch layer.
> Plugin commands are now declared via a Ruby DSL (`command`, `commands_under`, `option`, `root_setup` on `Plugins::Base`), backed by `CommandRegistry` / `CommandSpec`, replacing the previous per-plugin `case`/`when` dispatch.
> Help output is now generated directly, removing the dependency on `OptParse` and enabling proper multi-level help.
> This change has been thoroughly tested, but if you encounter any unexpected behavior, please [open an issue](https://github.com/IBM/aspera-cli/issues) and consider reverting to the previous release.

### New Features

* `config`: `ascp install` / `transferd install`: Default version is now the SDK version tested with this release (`1.1.9`) instead of latest. Pass `LATEST` to install the latest available version.
* `config`: New command commands `agents` with `list`, `show <name>` and `parameters <name>` to discover available transfer agents, their short identifier and their configurable parameters.
* `mcp`: New plugin - starts a [Model Context Protocol](https://modelcontextprotocol.io/) server exposing `execute_ascli_command`. Supports `stdio` (default) and `http` (Streamable HTTP) transports.
* **global**: Documentation for growing files using the `file` PVCL adapter (`file:///path?grow=<seconds>`).
* **global**: New composite option `log` with sub-properties `level`, `type`, `format`.
* **global**: Option `transfer` is now composite (`Hash`). `transfer` also accepts a `String` (`agent` shorthand) for backward compatibility.
* `direct`: New `transfer` parameter `file_list` (default: `true`). Setting to `false` will pass source paths directly on the `ascp` command line instead of a temp file list.
* **global**: New pseudo transfer-spec parameter `target_rate` (bps). It translates to `target_rate_kbps` with optional unit suffix (`k`/`K`, `m`/`M`, `g`/`G`). Example: `--ts.target_rate=100m`.
* `config`: Bash completion (`config completion bash`) is now multi-level: pressing `Tab` after a plugin name or sub-command completes the next level of sub-commands (previously only first-level plugin names were completed).
* **global**: Use `--query=help` on any `list` command to display the available filter parameters and their types, as documented in the embedded OpenAPI spec. Supported for `faspex5 admin` resources and `aoc admin` resources.

### Breaking Changes

* **global**: Option `--transfer-info` is deprecated in favor of `--transfer`.
* **global**: Options `--log-level`, `--logger`, `--log-format` are deprecated in favor of option `--log`. Individual options preserved for backward compatibility.

## 4.26.2

Released: 2026-07-17

### New Features

* `faspex5`: New commands `admin file_processing` and `packages file_processing`.
* `aoc`: Command `user settings` now support `create`, `delete`, `list`, `show`, `modify`.
* `aoc`: New command `network_policy` and `configuration_policy` in `admin`.
* `sync` : New command `admin query` to execute an arbitrary SQL command on the snap DB.
* `sync` : Option `sql` to add arbitrary SQL suffixes to sync actions with snapshot DB.

### Issues Fixed

* `aoc`: Fixed `admin application membership create`.

### Breaking Changes

**global**: Replaced option `--bash-comp` with `config completion bash`.

## 4.26.1

Released: 2026-06-11

### New Features

* `aoc`: Added new command `admin workspace shared_folder <workspace ID> node <shared folder ID>` to provide direct access to node operations from shared folders.
* **global**: Schema for Extended Value for option or command argument can now be retrieved using the special value `help` (e.g., `--ts=help` or `package send help`). Those are generated from JSON schema descriptions.
* **doc**: Some tables in documentation are now generated from JSON schema descriptions.

### Issues Fixed

* **global**: Resolved issue where supported enumerated values were not properly listed when no value was provided (e.g., for command parameters).

## 4.26.0

Released: 2026-05-28

### New Features

* `preview`: New option `root_url` (replaces `file_access`), to override how to access files on storage.
* `node`: (also `aoc files`) Operation `modify` added to `permissions`.
* `node`: (also `aoc files`) Operation `list` now uses paging.
* `aoc`: When creating a shared inbox, the value of option `workspace` is now used as default value to set field `workspace_id`.
* `aoc`: Support additional operations on `admin application`, like activate/deactivate app in workspace.
* `aoc`: Support additional operations on `admin user` and `user`: `preferences` and `notifications`.
* `aoc`: Support selection of workspace using percent selectors: `%name:` and `%id:`.
* **global**: Added download URLs for `transferd` 1.1.8.
* **global**: New Extended Value modifier: `s` converts to `String`.
* **global**: Parameter `str_lst_sep` of option `table_style` allows setting separator for list of strings.

### Issues Fixed

* `format`: In `table` format with option `flat_hash=yes`, fixed that some parameters were not shown. Moreover, (Node API: /info), if an array of hash with name/value keys is returned with one extra key, still apply simplification.
* **global**: Fixed #254: Security for SDK installation.

### Breaking Changes

* `preview`: Removed option `file_access`, replaced with option `root_url`.
* `aoc`: Command `resource` in `admin`is now removed. It was deprecated since 4.18. Use the same command without `resource`. Place the resource name directly after `admin`.

## 4.25.6

Released: 2026-04-08

### Issues Fixed

* `node`: #253 fix `node transfer list` infinite loop with `once_only`.

## 4.25.5

Released: 2026-03-25

### New Features

* `faspex5`: When sending a package, recipients specified in fields `private_recipients`, `notified_on_upload`, `notified_on_download` and `notified_on_receipt` are now also expanded like field `recipients`.

### Issues Fixed

* `config`: Fixed `preset update` with dot-path options.
* `sync`: #251 in `admin` command: Fixed database path on Windows: Use `~private-asp` instead of `.private-asp`.
* `httpgw`: #252 HTTPGW transfer showed success even when error code `403` was returned. Now raises error with message.

## 4.25.4

Released: 2026-03-04

### New Features

* **global**: If `@:` is used, then marker `END` optionally marks the end of collected arguments.
* `format`: `display` defaults to `info` only if `format` is set to `table`, else defaults to `data`.
* `node`: Parameter `accept_v4` of option `node_api` (boolean, defaults to `true`) allows using gen4 browsing with `Accept-Version: 4.0` for best performance when there are thousands of files.

### Issues Fixed

* `faspex5`: Listing content, or receiving a package requires API parameter: `recipient_user_id` or `recipient_workgroup_id`, else error `Not authorized` is returned.

### Breaking Changes

* `node`: Options `node_cache` and `default_ports` are replaced with option: `node_api` (`Hash`) with boolean parameters (keys): `cache` and `standard_ports` with default value `true`.

## 4.25.3

Released: 2026-02-18

### New Features

* `faspex5`: Package browsing now available for all inbox types.

### Issues Fixed

* `aoc`: Public short links can now be modified.

### Breaking Changes

* `config`: Deprecated and removed action `ascp connect`.
* **global**: Deprecated and removed option `property` made redundant with `@:` and dotted values. Instead of `--property=foo bar`, use `@: foo=bar`.
* `faspex5`: Default value for option `box` is now `inbox_all` to match web UI, previously: `inbox`.

## 4.25.2

Released: 2026-02-03

### New Features

* `aoc`: Public short links can now be created with an explicit access level.

### Issues Fixed

* Fixed container builds and Windows archive generation.

### Breaking Changes

Main documentation has moved to `docs/README.md`.

* `config`: Removed option `ascp_path`, replaced by `sdk_folder`.
* `config`: Removed command `ascp use`. Use instead:

  ```shell
  ascli conf preset set GLOBAL sdk_folder <path>
  ```

* `config`: Removed command `ascp products use`. Use instead:

  ```shell
  ascli conf preset set GLOBAL sdk_folder product:<path>
  ```

* `config`: Default `log_level` is now `info` (was `warn`). To restore the previous behavior:

  ```shell
  ascli config preset set GLOBAL log_level warn
  ```

## 4.25.1

Released: 2026-01-21

### Issues Fixed

* `build`: Fixed deploy workflow to use global rake instead of bundle exec.
* `build`: Made `rspec` require conditional in `test.rake` for deploy environment.

## 4.25.0

Released: 2026-01-21

### New Features

* **global**: All `Hash` and `Array` options are now cumulative (merged). Value `@none:` resets to empty value.
* **global**: Improved error diagnostic during evaluation of extended value.
* **global**: New extended value modifier: `@:` (empty modifier) to evaluate remaining arguments as `Hash` or `Array`.
* **global**: New extended value modifier: `@stdin:chomp` reads stdin and removes `\n`.
* `config`: New option: `parser` allows definition of default parser for extended values when expecting a `Hash` or `Array` type.
* `orchestrator`: Commands now takes option `query`.
* `aoc`: The admin command for `node` now support nodes owned by admin, so that secret is no more necessary.

### Issues Fixed

* `aoc`: Restored command `admin workspace shared_folder :id list` which was since 4.11.0.
* `direct`: When using `ascp4`, do not set env var: `ASPERA_TEST_REDIS_DISABLE`, else it fails with: `Failed to initialize application`.
* `shares`: Properly detect using `/node_api/ping` endpoint instead of `/app`.

### Breaking Changes

* `aoc`: Option `package_folder` is now a Hash instead of formatted String.
* `aoc`: Deprecated option `scope`. It is selected from the command directly. For `bearer_token --scope=admin:all`, now use: `admin bearer_token`.
* `server`: By default, SSH option `use_agent` is now `false`.
* `config`: Removed option `use_product`, replaced with prefix `product:` of option `ascp_path`.
* `config`: Secret lookup is no more automatic, activate setting option `secret` to `PRESET`.
* `faspex5`: Removed deprecated (4.18) command in `admin`: `resource`, use resource name as command directly in `admin`.
* `preview`: Replaced gem `mimemagic` with `marcel`.
* **global**: Extended value modifier `@stdbin:` is replaced with `@stdin:bin`.
* Build system uses now `rake` instead of `make` for easier portability on Windows.
* PDF manual removed from repo, it is now generated for [releases](https://github.com/IBM/aspera-cli/releases) only.
* HTML manual is not generated anymore.

## 4.24.2

Released: 2025-10-24

### New Features

* `direct`: Capability to send management messages to `ascp` on running sessions. e.g. change target rate.
* `config`: Added command: `sync spec` to get sync parameters' documentation. Also added to manual.

### Issues Fixed

* `faspex5`: Fix public link auth for Faspex 5.0.13.
* `aoc`: Fix some admin operations requiring a user's home for Files.
* `node`: Fix `transfer` operations: `modify` and `cancel`.
* `config`: #230 Fix problem when installing and detecting SDK on Windows.

### Breaking Changes

* `ats`: Removed option `params`. Use positional parameter for creation, and `query` for list.

## 4.24.1

Released: 2025-10-02

### Issues Fixed

* `wizard`: Our wizard was missing its wand; we’ve returned it. Magic restored.

## 4.24.0

Released: 2025-09-30

### New Features

* `aoc`: Option `package_folder` allows specification of secondary field.
* `config`: New option `invalid_characters` ensures generated file names are valid.
* `config`: Added support for **dot-separated** option names, allowing nested hash structures to be specified directly on the command line.
* `console`: Added support for extended filters in transfer queries.
* `http_options`: New field `ssl_options` allows setting SSL Context options.
* `format`: `csv` format now supports option `table_style` for customizable output.
* `logger`: New option: `log_format` to control log formatting.
* `sync`: New command: `db` for operations on sync database.
* `sync`: Sync operations now use options `ts` and `to_folder`.

### Issues Fixed

* JRuby: Modified tests and documentation for special SSH options.
* `transferd`: Fixed discrepancies in transfer spec resume policies.
* `desktop`: Fixed discrepancies in transfer spec resume policies.
* `format`: Value of type `list` now properly display column headers.
* `select`: Filter is now done on values before enhanced display in table mode.
* `aoc`: #221 Fixed package encryption at rest (CSEAR) status.

### Breaking Changes

* `config`: Option `silent_insecure` renamed `warn_insecure`. `yes` shows warning (default).
* `ts` : Default transfer spec includes `resume_policy=sparse_csum`.
* `ssh_options` : Now additive option, like `ts`.
* `vault`: When creating an entry, the `label` field is now part of the creation Hash.
* `console`: Removed options `filter_from` and `filter_to`. Use standard option `query` instead.
* `sync`: Removed option `sync_info`. Replaced with positional parameters. Streamlined command line interface. Applies to all plugins with `sync` command.
* `async`: Removed option `sync_name`. Replaced with percent selector `%name:`.
* `aoc`: `files download` using gen4 API no longer requires providing the containing folder in first position, and then only file names. Now, directly provide the path to all files.
* `logger`: Log is simplified, date is removed by default. Use `--log_format=standard` to revert to standard Ruby logger. See option `log_format` for details.

## 4.23.0

Released: 2025-08-11

### New Features

* `aoc`: #201: Added `package_folder` option to place each received package in its own subfolder named after a package attribute. Default is `@none:` which means no subfolder will be created.
* `config`: Added `transferd` version 1.1.6.

### Issues Fixed

* `server`: #209: a missing home folder for the transfer user shall not cause an error.
* `direct`: #205: `kill` blocks `cmd` on Windows.

### Breaking Changes

* `config`: In `ascp info`: `openssldir` &rarr; `ascp_openssl_dir`, `openssl_version` &rarr; `ascp_openssl_version`, `sdk_ascp_version` &rarr; `ascp_version`.

## 4.22.0

Released: 2025-06-23

### New Features

* `faspex5`: Support paging for Faspex5 browsing.
* `aoc`: #196 Command `packages list` now also supports option `once_only`.
* `vault`: Support for IBM HashiCorp Vault to store secrets.
* `wizard`: Preset name can now be specified as optional positional parameter.
* `config`: New command `ascp schema` displays JSON schema for transfer spec for all, or just one agent.
* `node`: #198 By default do not allow creation of folder if a link exists with the same name. Use option `query` with parameter `check` set to `false` to disable.
* `node`: In gen4 operations, also used in `aoc files`, new commands: `mklink`, `mkfile`.

### Issues Fixed

* `aoc`: #195 `package receive ALL` for shared inbox without workspace now works.

### Breaking Changes

* `faspex5`, `aoc`: `gateway` now takes argument as `Hash` with `url` instead of only `String`.
* `faspex5 postprocessing`: Now takes a flat `Hash`, instead of multi-level `Hash`.
* HTTP: More retry parameters.
* `node`: renamed command `http_node_download` to `cat`, and it directly displays the content of the file in the terminal unless option `--output` is specified.

## 4.21.2

Released: 2025-04-11

### New Features

* **container**: Updated Ruby to `3.4.2`.

### Issues Fixed

* **global**: #185 `@val:` shall stop processing extended values.
* **global**: #186 Removed dependency on OpenSSL 3.3 gem to avoid `MSYS2` dep on Windows.
* `echo`: Display of list (Array) was showing only first element of it.
* `transferd`: Support for version 1.1.5+.

### Breaking Changes

* `preview`: Updated Image Magick to v7+.
* `aoc`: `admin subscription` split into `admin subscription account` and `admin subscription usage`.
* **agent**: `alpha` renamed to `desktop`.

## 4.21.1

Released: 2025-03-15

### New Features

* `config`: New command: `transferd` to list and install specific version of `asperatransferd` and `ascp`.
* `config`: New command: `tokens` with `list`, `show`, `flush` (replace `flush_tokens`).
* `faspex5`: New command: `admin contact reset_password`.
* `aoc`: #178 packages can be browsed, and individual files can be downloaded now.

### Issues Fixed

* `config`: #175 `ascli config preset set GLOBAL version_check_days 0` causes a bad `config.yaml` to be written.
* `config`: #180 Problem in `ascp install`.
* `config`: Soft links in transfer SDK archive are correctly extracted.
* `aoc`: #184 token cache shall be different per AoC org.
* `aoc`: Fix `packages delete` not working.
* `direct` agent: #174 Race condition fix with `ascp`: timeout waiting management port connect (select not readable).
* `preview`: #177 fix bug that prevents preview generation to work.

### Breaking Changes

* `transferd`: Use of Aspera Transfer Daemon requires minimum version 1.1.4. Agent `trsdk` renamed `transferd`.
* `ascp`: Default SDK version is now 1.1.4. Removes support for ascp4.
* `node`: Removed deprecated command prefix `exec:`, use `@ruby:` instead.
* **global**: Now uses OpenSSL 3.
* **global**: Ruby minimum versions is now 3.1 (mainly due to switch to OpenSSL 3). Future minimum is 3.2. Recommended is 3.4. That removes macOS default Ruby support. Newer Ruby version shall be installed on macOS with `brew`.
* **global**: Options `transpose_single` and `multi_table` replaced with single option `multi_single` and values: `no`, `yes`, `single`.
* **global**: Column name for single object is now `field` instead of `key`.

## 4.20.0

Released: 2025-01-21

> [!CAUTION]
> [Faspex version 4 is now end of support](https://www.ibm.com/support/pages/lifecycle/search?q=faspex): The `faspex` plugin will be deprecated.
> Servers shall be upgraded to Faspex 5, and users use plugin `faspex5`.

### New Features

* `aoc`: Improved usability for creation of Admin shared folders.
* `node`: New option `node_cache` (boolean) for gen4 operations.
* `node`: Option `root_id` now always works for node gen4, as well as `%id:` for file selection in addition to path.
* `node`: `transfer list` now uses the `iteration_token` to retrieve all values. Option `once_only` is now supported.
* **global**: Option `http_options` now include retry options.

### Issues Fixed

* `aoc`: Fixed `find` command not working (undefined variable).
* `aoc`: #165 AoC `mkdir` now follows the last link of containing folder.

### Breaking Changes

* Internal: Basic REST calls now return data directly. (no more `data` key). For advanced calls, use `call`.
* Internal: Transfer SDK download is now a 2-step procedure: First get the YAML file from GitHub with URLs for the various platforms and versions, and then download the archive from the official IBM repository.
* **global**: Option `format=multi` is replaced with option `multi_table=yes`.
* `faspex5`: Removed deprecated option `value` replaced with positional parameter.
  
## 4.19.0

Released: 2024-10-02

### New Features

* `server`: Add support for `async` (Aspera Sync) from Transfer SDK.
* **global**: #156 support sending folders with `httpgw`.
* **global**: New value for option `format`: `multi`.

### Issues Fixed

* `aoc`: #157 fix problem with `files browse` on a link.
* `sync`: Better documentation and handling of options.

### Breaking Changes

* **global**: Default value for direct agent option `transfer_info.multi_incr_udp` is `true` on Windows, and now `false` on other platforms.
* **global**: Token based transfers now use the RSA key only. Direct agent option `transfer_info.client_ssh_key` allows changing this behavior.
  
## 4.18.1

Released: 2024-08-21

### Issues Fixed

* **global**: #146 (@junkimu) Fix problem on Windows WRT terminal detection.
* **global**: Node gen4 (`aoc`) browsing through link now follows the link correctly.
* `shares`: #147 Fix problem for `shares files mkdir`.

### Breaking Changes

* **global**: Removed option `id`, deprecated since `4.14.0`.

## 4.18.0

Released: 2024-07-10
  
### New Features

* `faspex5`: Added command `admin configuration` for global parameters.
* `faspex5`: Added command `admin clean_deleted`.
* `faspex5`: Added resource `distribution_list`.
* `node`: "gen3" browse now returns all elements using pages, and supports option `query` with parameter `recursive`, `max`, `self`.
* `httpgw`: New plugin, detect the GW.
* `faspio`: New plugin, configure bridges.
* `config`: `ascp info` also shows the version of the OpenSSL library used by `ascp`.
* `node`: New action: `transport` to display transfer address and ports.
* **global**: Added option `http_proxy`, as an alias to env var `http_proxy`.
* **global**: Possibility to filter fields when using formats like `json` or `yaml`.

### Issues Fixed

* `faspex5`: Fixed support for percent selector for metadata profiles.

### Breaking Changes

* `aoc` : `admin resource` is deprecated, use just `admin`.
* `faspex5` : `admin resource` is deprecated, use just `admin`.
* **global**: Option `value` is deprecated and replaced with option `query` when used in generic commands: `delete` and `list`, as well as node access_key browse, node stream and watch folder list. (#142).
* **global**: Option `warnings` (and short `w`) is removed. To get Ruby warnings invoke with `ruby -w .../ascli ...`. See `Makefile` in `test`.
* **global**: Option `table_style` now expects a Hash, not String.
* **bss**: Removed unused plugin.

## 4.17.0

Released: 2024-07-13

### New Features

* `faspex5`: Automatic detection of HTTPGW.
* `faspex5`: Support public and private invitations.
* `faspex5`: Public links: Auto-fill recipient.
* `faspex5`: Recursive content of package.
* `faspex5`: Folder browsing now uses paging, requires >= 5.0.8.
* `aoc`: Automatic detection of HTTPGW.
* `shares`: Added group membership management.

### Issues Fixed

* `aoc`: `exclude_dropbox_packages` query option can be overridden (#135).
* **global**: Removed gem dependency on `bigdecimal` (not used and requires compilation).
* **global**: Tested with JRuby 9.4.6.0 (use `ServerSocket` instead of `Socket`).
* **global**: Update version for gem `terminal-table` to `3.0.2`.

### Breaking Changes

* `config`: Command `remote_certificate` now takes a command.
* **global**: Moved a few internal classes in new/renamed modules.
* **global**: Deprecated pseudo transfer specification parameters starting with `EX_`:
  * `EX_ssh_key_paths`: Use spec `ssh_private_key` or option `transfer_info={"ascp_args":["-i","..."]}`
  * `EX_http_proxy_url`: Use option `transfer_info={"ascp_args":["-x","..."]}`
  * `EX_http_transfer_jpeg`: Use option `transfer_info={"ascp_args":["-j","1"]}`
  * `EX_no_read`: Use option `transfer_info={"ascp_args":["--no-read"]}`
  * `EX_no_write`: Use option `transfer_info={"ascp_args":["--no-write"]}`
  * `EX_file_list`: Use `ascli` file list feature or option `transfer_info={"ascp_args":["--file-list","..."]}`
  * `EX_file_pair_list`: Use `ascli` file list feature or option `transfer_info={"ascp_args":["--file-pair-list","..."]}`
  * `EX_ascp_args`: Use option `transfer_info={"ascp_args":[...]}`
  * `EX_at_rest_password`: Use spec parameter `content_protection_password`
  * `EX_proxy_password`: Set password in spec parameter `proxy` or use env var `ASPERA_PROXY_PASS`.
  * `EX_license_text`: Use env var `ASPERA_SCP_LICENSE`.

## 4.16.0

Released: 2024-02-15

### New Features

* **global**: Option `output` to redirect result to a file instead of `stdout`.
* **global**: New option `silent_insecure`.
* `config`: Keys added to `config ascp info`.
* `config`: Added command `pubkey` to extract public key from private key.
* `config`: New command `vault info`.
* `faspex5`: Added `shared_folders` management.
* `faspex5`: If package has content protection, ask passphrase interactively, unless `content_protection=null` in `ts`.
* `faspex`: Added `INIT` for `once_only`.
* `aoc`: Added `INIT` for `once_only`.
* `aoc`: More list commands honor option `query`.

### Issues Fixed

* `config`: Wizard was failing due to `require` of optional gem.
* `aoc`: Use paging to list entities, instead of just one page(e.g. retrieve all packages).
* `faspex5`: When receiving ALL packages, only get those with status `completed`.
* `direct`: Better support for WSS.

### Breaking Changes

* `shares`: Option `type` for users and groups is replaced with mandatory positional argument with same value. E.g. `user list --type=local` becomes: `user local list`.
* `aoc`, `faspex`: Package `recv` command changed to `receive`, for consistency with faspex5 (`recv` is now an alias command).

## 4.15.0

Released: 2023-11-18

General: Removed many redundant options, more consistency between plugins, see below in "break".

### New Features

* **global**: Added resolution hints for well known issues.
* **global**: Extended value expression `@extend:` finds and replace extended values in a string (e.g. for JSON).
* **global**: Option `fields` now supports `RegExp`.
* **global**: Option `home` to set the main folder for configuration and cache.
* **global**: Option `ignore_certificate` to specify specific URLs instead of global option `insecure`.
* **global**: Option `cert_stores` to specify alternate certificate stores.
* **global**: Uniform progress bar for any type of transfer.
* **global**: Add extended value types: `re` and `yaml`.
* **global**: Option `pid_file` to write tool's PID during execution, deleted on exit.
* `config`: Command `remote_certificate` to retrieve a remote certificate.
* `config`: Added logger level `trace1` and `trace2`.
* `config`: `wizard` can detect multiple applications at the same address or URL.
* `aoc`: Wizard accepts public links.
* `aoc`: Support private links, and possibility to list shared folder with workspace `@json:null`.
* `orchestrator`: Error analysis for workflow start.
* `httpgw`: Now supports pseudo file for testing: e.g. `faux:///testfile?1k`.
* `node`: Added command `transfer sessions` to list all sessions of all transfers.
* `node`: Generate bearer token from private key and user information.
* `node`: Access node API with bearer token as credentials.
* **global**: Agent `direct` allows ignoring certificate for WSS using HTTP options.
* `preview`: Command `show` generates a preview and displays it in terminal.

### Issues Fixed

* Ruby warning: `net/protocol.rb:68: warning: already initialized constant Net::ProtocRetryError` solved by removing dependency on `net-smtp` from gem spec (already in base Ruby).

### Breaking Changes

* **global**: Commands `detect` and `wizard` takes now a mandatory argument: address or URL instead of option `url`.
* **global**: Renamed option `pkeypath` to `key_path`.
* **global**: Renamed option `notif_to` to `notify_to` and `notif_template` to `notify_template`.
* **global**: Removed extended value handler `incps`, as it is never used (use `extend` instead).
* **global**: Option `fields`: `+prop` is replaced with: `DEF,prop` and `-field` is replaced with: `DEF,-field`, and whole list is evaluated.
* **global**: Replaced option `progress` with option `progressbar` (boolean).
* **global**: Removed option `rest_debug` and `-r`, replaced with `--log-level=trace2`.
* **global**: The default file name for private key when using wizard is change from `aspera_aoc_key` to `my_private_key.pem`.
* `faspex5`: Removed option and `auth` type `link`: simply provide the public link as `url`.
* `faspex`: Remote source selection now uses percent selector instead of parameter `id` or `name`.
* `faspex`: Option `source_name` is now `remote_source`.
* `aoc`: Selection by name uses percent selector instead of option or parameter `name`.
* `aoc`: Removed option `link`: use `url` instead.
* `aoc`: In command `short_link`, place type before command, e.g. `short_link private create /blah`.
* `aoc`: Replaced option `operation` with mandatory positional parameter for command `files transfer`.
* `aoc`: Replaced option `from_folder` with mandatory positional parameter for command `files transfer`.
* `orchestrator`: Workflow start takes arguments as optional positional extended value instead of option `param`.
* `node`: `find` command now takes an optional `@ruby:` extended value instead of option `query` with prefix: `exec:`.
* `sync`: Plugin `sync` is removed: actions are available through `server` and `node` plugins.
* `sync`: Replaced option `sync_session` with optional positional parameter.
* `preview`: Command `scan`, `events` and `trevents` replaced option `query` with optional positional parameter for filter (like `find`).
* **global**: Agent `trsdk` parameters `host` and `port` in option `transfer_info` are replaced with parameter `url`, like `grpc://host:port`.

## 4.14.0

Released: 2023-09-22

### New Features

* `server`: Option `passphrase` for simpler command line (#114).
* Percent selector for entities identifier.
* `faspex5`: Shared inbox and workgroup membership management.
* `faspex5`: Invite external user to shared inbox.
* `faspex5`: Package list and receive from workgroup and shared inbox.
* `config`: Command `ascp info` shows default transfer spec.
* **global**: Agent `httpgw` synchronous and asynchronous upload modes.
* `node`: Command `bandwidth_average` to get average bandwidth of node, per periods.

### Issues Fixed

* Option `ts`: Deep add and remove of keys. (#117).
* `faspex5`: User lookup for `packages send` shall be exact match (#120).
* **global**: Agent `direct` if transfer spec contains "paths" and elements with "destination", but first element has only "source", then destinations were ignored. Now "destination" all or none is enforced.

### Breaking Changes

* Using `aoc files` or node gen4 operations (`browse`, `delete`) on a link will follow the link only if path ends with /.
* `shares`: Command `repository` is changed to `files` for consistency with `aoc` and upcoming `faspex5`, but is still available as alias.
* `aoc`: Better handling of shared links.
* **global**: Option `value` is deprecated. Use positional parameter for creation data and option `query` for list/delete operations.
* `config`: Remove deprecated command: `export_to_cli`.
* `config`: Removed all legacy preset command, newer command `preset` shall be used now.
* `config`: SDK is now installed in `$HOME/.aspera/sdk` instead of `$HOME/.aspera/ascli/sdk`.
* `aoc`, `node`: Simplification: gen4 operations: show modify permission thumbnail are now directly under node gen 4 command. Command `file` is suppressed. Option `path` is suppressed. The default expected argument is a path. To provide a file ID, use selector syntax: `%id:_file_id_`.
* `node`: Option `token_type` is removed, as starting with HSTS 4.3 basic token is only allowed with access keys, so use gen4 operations: `acc do self`.

## 4.13.0

Released: 2023-06-29

### New Features

* `preview`: Option `reencode_ffmpeg` allows overriding all re-encoding options.
* `faspex5`: `package delete` (#107).
* `faspex5`: `package recv` for inboxes and regular users (#108).
* `faspex5`: SMTP management.
* `faspex5`: Use public link for authorization of package download, using option `link`.
* `faspex5`: List content of package, and allow partial download of package.
* `faspex5`: List packages support multiple pages and items limitations (`max` and `pmax`).
* `aoc`: Files operations with workspace-less user (#109).
* `node`: `async` with gen3 token (#110).
* `node`: Display of preview of file in terminal for access keys.

### Issues Fixed

* `cos`: Do not use refresh token when not supported.
* **container**: SDK installed in other folder than `ascli` (#106).

### Breaking Changes

* Option `transfer_info` is now cumulative, setting several times merge values.
* Change(deprecation): Removed support of Ruby 2.4 and 2.5 : Too old, no security update since a long time. If you need older Ruby version use older gem version.

## 4.12.0

Released: 2023-03-20

### New Features

* **container**: Build image from official gem version, possibility to deploy beta as well.
* **global**: `delete` operation supports option `value` for deletion parameters.
* `aoc`: Command `aoc packages recv` accepts option `query` to specify a shared inbox.
* `faspex`: (v4) user delete accepts option `value` with value `{"destroy":true}` to delete users permanently.
* `faspex`: (v4) gateway to Faspex 5 for package send.
* `faspex5`: Possibility to change email templates.
* `faspex5`: Shared folder list and browse.
* `faspex5`: Emulate Faspex 4 post-processing, plugin: `faspex5` command: `postprocessing`.
* `faspex5`: Send package from remote source.
* `shares`: Option `type` for command `shares admin user`.
* `shares`: Full support for shares admin operations.

### Breaking Changes

* `shares`: Command `shares admin user saml_import` replaced with `shares admin user import --type=saml`.
* `shares`: Command `shares admin user ldap_import` replaced with `shares admin user add --type=ldap`.
* `shares`: Command `app_authorizations` now has sub commands `show` and `modify`.
* `shares`: Similar changes for `shares admin share user show`.
* Option `ascp_opts` is removed, and replaced with `transfer_info` parameter `ascp_args`.

## 4.11.0

Released: 2023-01-26

### New Features

* **global**: `vault`: Secret finder, migration from config file.
* **global**: Allow removal of transfer spec parameter by setting value to `null`.
* **global**: Option `ascp_opts` allows providing native `ascp` options on command line.
* `node`, `server`: Command `sync` added to `node` (gen4) and `server` plugins, also available in `aoc`.

### Issues Fixed

* **global**: Security: no shell interpolation.
* **global**: Agent `node`: when WSS is used: no localhost (certificate).
* `aoc`: #99 `file download` for single shared folder.
* `faspex5`: Change of API in Faspex 5 for send package (paths is mandatory for any type of transfer now).
* **global**: OAuth web authentication was broken, fixed now.

### Breaking Changes

* **container**: Image has entry point.
* `aoc`: `admin res node` commands `v3` and `v4` replaced with `do` and command `v3` moved inside `do`.
* Renamed options for `sync`.
* Node gen4 operations are moved from `aoc` plugin to node plugin but made available where gen4 is used.
* If WSS is enabled on server, use WSS.
* Lots of cleanup and refactoring.

## 4.10.0

Released: 2022-12-02

### New Features

* `httpgw`: Transfer agent support API v2, support transfer through HTTP proxy, including proxy password.
* `faspex5`: Get bearer token.

### Issues Fixed

* **container**: Container version.

### Breaking Changes

* `config`: Option `secrets` is renamed to `vault`.

## 4.9.0

Released: 2022-09-15

### New Features

* `shares`: Import of SAML users and LDAP users.
* M1 Apple Silicon support SDK install (uses x86 `ascp`).
* Support bulk operation more globally (create/delete), not all ops, though.
* Added missing transfer spec parameters, e.g. `src_base`, `password`.
* Improved documentation on `faspex` and `aoc` `package send`.

### Issues Fixed

* `node do` command fixed.
* Improved secret hiding from logs.

### Breaking Changes

* Removed rarely commands `nodeadmin`, `configuration`, `userdata`, `ctl` from plugin `server` as well as option `cmd_prefix`.
* `ascli` runs as user `cliuser` instead of `root` in container.
* Default access right for config folder is now user only, including private keys.

## 4.8.0

Released: 2022-06-16

### New Features

* #76 add resource `group_membership` in `aoc`.
* New resource `metadata_profile` in `faspex5`.
* New command `user profile` in `faspex5`.
* Config wizard for `faspex5`.
* #75 gem is signed.

### Breaking Changes

* Removed dependency on gem `grpc` which is used only for the `trsdk` transfer agent. Users can install the gem manually if needed.
* Hash vault keys are string instead of symbol.
* Cleanup with `rubocop`, all strings are immutable now by default, list constants are frozen.
* Removed `Hash.dig` implementation because it is by default in Ruby >= 2.3.
* Default is now to hide secrets on command output. Set option `show_secrets` to reveal secrets.
* Option `insecure` displays a warning.

## 4.7.0

Released: 2022-03-23

### New Features

* Option to specify font used to generate image of text file in `preview`.
* #66 improvement for content protection (support standard transfer spec options for direct agent).
* Option `fpac` is now applicable to all Ruby based HTTP connections, i.e. API calls.
* Option `show_secrets` to reveal secrets in command output.
* Added and updated commands for Faspex 5.
* Option `cache_tokens`.
* Faspex4 dropbox packages can now be received by ID.

### Issues Fixed

* After AoC version update, wizard did not detect AoC properly.

### Breaking Changes

* Command `conf gem path` replaces `conf gem_path`.
* Option `fpac` expects a value instead of URL.
* Option `cipher` in transfer spec must be hyphened.
* Renamed option `log_passwords` to `log_secrets`.
* Removed plugin `shares2` as products is now EOL.

## 4.6.0

Released: 2022-02-04

### New Features

* Command `conf plugin create`.
* Global option `plugin_folder`.
* Global option `transpose_single`.
* Simplified metadata passing for shared inbox package creation in AoC.

### Issues Fixed

* #60 `ascli` executable was not installed by default in 4.5.0.
* Add password hiding case in logs.

### Breaking Changes

* `aoc`: `packages shared_inboxes list` replaces `aoc user shared_inboxes`.
* `aoc`: `user profile` replaces `aoc user info`.
* `aoc`: `user workspaces list` replaces `aoc user workspaces`.
* `aoc`: `user workspaces current` replaces `aoc workspace`.
* `config`: `plugin list` replaces `conf plugins`.
* `config`: `connect` simplified.

## 4.5.0

Released: 2021-12-27

### New Features

* Support transfer agent: [Transfer SDK](README.md#agt_trsdk).
* Support [HTTP socket options](README.md#http_options).
* Logs hide passwords and secrets, option `log_passwords` to enable logging secrets.
* `config vault` supports encrypted passwords, also macOS keychain.
* `config preset` command for consistency with macOS.
* Identifier can be provided using either option `id` or directly after the command, e.g. `delete 123` is the same as `delete --id=123`.

### Issues Fixed

* Various smaller fixes and renaming of some internal classes (transfer agents and few others).

### Breaking Changes

* When using WSS, use [Ruby's CA certs](README.md#certificates).
* Unexpected parameter makes exit code not zero.
* Options `id` and `name` cannot be specified at the same time anymore, use [positional identifier or name selection](README.md#res_select).
* `aoc`: `admin res node` does not take workspace main node as default node if no `id` specified.
* `orchestrator`: `workflow status` requires IS, and supports special IS `ALL`.

## 4.4.0

Released: 2021-11-13

### New Features

* `aoc packages list` add possibility to add filter with option `query`.
* `aoc admin res xxx list` now get all items by default #50.
* `preset` option can specify name or hash value.
* `node` plugin accepts bearer token and access key as credential.
* `node` option `token_type` allows using basic token in addition to Aspera type.

### Breaking Changes

* `server`: Option `username` not mandatory anymore: `xfer` user is by default. If transfer spec token is provided, password or keys are optional, and bypass keys are used by default.
* Resource `apps_new` of `aoc` replaced with `application` (more clear).

## 4.3.0

Released: 2021-10-19

### New Features

* Parameter `multi_incr_udp` for option `transfer_info`: control if UDP port is incremented when multi-session is used on [`direct`](README.md#agt_direct) transfer agent.
* Command `aoc files node_info` to get node information for a given folder in the Files application of AoC. Allows cross-org or cross-workspace transfers.

## 4.2.2

Released: 2021-09-23

### New Features

* `faspex package list` retrieves the whole list, not just first page.
* Support web based auth to `aoc` and `faspex5` using HTTPS, new dependency on gem `webrick`.
* The error "Remote host is not who we expected" displays a special remediation message.
* `conf ascp spec` displays supported transfer spec.
* Options `notif_to` and `notif_template` to send email notifications on transfer (and other events).

### Issues Fixed

* Space character in `faspe:` URL are percent encoded if needed.
* `preview scan`: If file_id is unknown, ignore and continue scan.

### Breaking Changes

* For commands that potentially execute several transfers (`package recv --id=ALL`), if one transfer fails then `ascli` exits with code 1 (instead of zero=success).
* Option `notify` or `aoc` replaced with `notif_to` and `notif_template`.

## 4.2.1

Released: 2021-09-01

### New Features

* Command `faspex package recv` supports link of type: `faspe:`.
* Command `faspex package recv` supports option `recipient` to specify dropbox with leading `*`.

## 4.2.0

Released: 2021-08-24

### New Features

* Command `aoc remind` to receive organization membership by email.
* In `preview` option `value` to filter out on file name.
* `initdemo` to initialize for demo server.
* [`direct`](README.md#agt_direct) transfer agent options: `spawn_timeout_sec` and `spawn_delay_sec`.

### Issues Fixed

* On Windows `conf ascp use` expects ascp.exe.
* (break) multi_session_threshold is Integer, not String.
* `conf ascp install` renames `sdk` folder if it already exists (leftover shared lib may make fail).
* Removed `replace_illegal_chars` from default `aspera.conf` causing "Error creating illegal char conversion table".

### Breaking Changes

* `aoc apiinfo` is removed, use `aoc servers` to provide the list of cloud systems.
* Parameters for resume in `transfer-info` for [`direct`](README.md#agt_direct) are now in sub-key `"resume"`.

## 4.1.0

Released: 2021-06-23

### New Features

* Update documentation with regard to offline and docker installation.
* Renamed command `nagios_check` to `health`.
* Agent `http_gw` now supports upload.
* Added option `sdk_url` to install SDK from local file for offline install.
* Check new gem version periodically.
* The --fields= option, support -_field_name_ to remove a field from default fields.
* OAuth's tokens are discarded automatically after 30 minutes (useful for COS delegated refresh tokens).
* `mimemagic` is now optional, needs manual installation for `preview`, compatible with version 0.4.x.
* AoC a password can be provided for a public link.
* `conf doc` take an optional parameter to go to a section.
* Initial support for Faspex 5 Beta 1.

### Issues Fixed

* Remove keys from transfer spec and command line when not needed.
* Default to `create_dir`:`true` so that sending single file to a folder does not rename file if folder does not exist.

## 4.0.0

Released: 2021-02-03

### New Features

* Now available as open source (GitHub) with general cleanup.
* Added possibility to install SDK: `config ascp install`.

### Breaking Changes

* Changed default tool name from `mlia` to `ascli`.
* Renamed `aspera` command to `aoc`.
* Changed gem name from `asperalm` to `aspera-cli`.
* Changed module name from `Asperalm` to `Aspera`.
* Removed command `folder` in `preview`, merged to `scan`.
* Persistency files go to sub folder instead of main folder.

## 0.11.8

Released: 2020-11-30

### New Features

* Simplified to use `unoconv` instead of bare `libreoffice` for office conversion, as `unoconv` does not require an X server (previously using `Xvfb`).

## 0.11.7

Released: 2020-11-27

### New Features

* Use option `display` with value `data` to remove out of extraneous information.
* Generate special icon if preview failed.
* Possibility to choose transfer progress bar type with option `progress`.
* AoC package creation now output package ID.

### Issues Fixed

* Rework on rest call error handling.
* Fixed option `lock_port` not working.

## 0.11.6

Released: 2020-11-19

### New Features

* `orchestrator`: Added more choice in auth type.
* `preview`: Cleanup in generator (removed and renamed parameters).
* `preview`: Better documentation.
* `preview`: Animated thumbnails for video (option: `video_png_conv=animated`).
* `preview`: New event trigger: `trevents` (`events` seems broken).
* `preview`: Unique tmp folder to avoid clash of multiple instances.
* Added template for secrets used for testing.

## 0.11.5

Released: 2020-11-16

### New Features

* Added option `default_ports` for AoC (see manual).
* Allow bulk delete in `aspera files` with option `bulk=yes`.
* Added section for AIX.
* Support all ciphers for [`direct`](README.md#agt_direct) agent (including GCM, etc.).
* Added transfer spec parameter `apply_local_docroot` for [`direct`](README.md#agt_direct).

### Issues Fixed

* Fix getting connect versions.

## 0.11.4

Released: 2020-10-16

### New Features

* Possibility to give shared inbox name when sending a package (else use ID and type).

## 0.11.3

Released: 2020-10-12

### Issues Fixed

* Minor fixes on multi-session: Avoid exception on progress bar.

## 0.11.2

Released: 2020-10-09

### Issues Fixed

* Fixes on multi-session: Progress bar and transfer spec parameter for `direct`.

## 0.11.1

Released: 2020-10-01

### New Features

* Enhanced short_link creation commands (see examples).

## 0.11

Released: 2020-09-23

### New Features

* Add transfer spec option (agent `direct` only) to provide file list directly to `ascp`: `EX_file_list`.

## 0.10.18

Released: 2020-09-15

### New Features

* New option in `server`: `ssh_options`.

## 0.10.17

Released: 2020-09-01

### New Features

* New modifier: `@list:<separator>val1<separator>...`.

### Issues Fixed

* Fixed problem on `server` for option `ssh_keys`, now accepts both single value and list.

## 0.10.16

Released: 2020-08-21

### New Features

* Added list of shared inboxes in workspace (or global), use `--query=@json:'{}'`.

## 0.10.15

Released: 2020-07-23

### New Features

* `aoc`: Activity / Analytics.

### Issues Fixed

* In case of command line error, display the error cause first, and non-parsed argument second.

## 0.10.14

Released: 2020-06-17

### New Features

* Added missing `bss` plugin.

## 0.10.13

Released: 2020-06-12

### New Features

* Added Faspex5 (use option `value` to give API arguments).

## 0.10.12

Released: 2020-05-15

### New Features

* Added support for AoC node registration keys.
* Transfer agent is no more a Singleton instance, but only one is used in CLI.
* `@incps`: New extended value modifier.
* Begin work on `aoc` transfer agent.

### Breaking Changes

* Replaced option `local_resume` with `transfer_info` for agent [`direct`](README.md#agt_direct).
* `ats`: No more provides access keys secrets: now user must provide it.

## 0.10.11

Released: 2020-04-29

### Issues Fixed

* Minor refactor and fixes.

## 0.10.10

Released: 2020-04-10

### Issues Fixed

* Fix on documentation.

## 0.10.9.1

Released: 2020-03-31

### New Features

* Add total number of items for AoC resource list.

### Issues Fixed

* Better gem version dependency (and fixes to support Ruby 2.0.0).

### Breaking Changes

* Removed `aoc search_nodes`.

## 0.10.8

Released: 2020-02-13

### Breaking Changes

* Removed option `fasp_proxy`, use pseudo transfer spec parameter: `EX_fasp_proxy_url`.
* Removed option `http_proxy`, use pseudo transfer spec parameter: `EX_http_proxy_url`.

## 0.10.7

Released: 2020-01-03

### Issues Fixed

* Fix: `ascli` fails when username cannot be computed on Linux.

## 0.10.6

Released: 2019-12-11

### New Features

* FaspManager: Transfer spec `authentication` is no longer needed for local transfer to use Aspera public keys. Public keys will be used if there is a token and no key or password is provided.
* Gem version requirements made more open.

## 0.10.5

Released: 2019-12-11

### Issues Fixed

* Fix Faspex package receive command not working.

## 0.10.4

Released: 2019-12-04

### New Features

* New options for AoC: `secrets`.
* `ACLI-533` temp file list folder to use file lists is set by default, and used by `asession`.

## 0.10.3

Released: 2019-12-02

### New Features

* Included username in OAuth bearer token cache for AoC when JWT is used.

## 0.10.2

Released: 2019-11-25

### New Features

* Updated `search_nodes` to be more generic, so it can search not only on access key, but also other queries.
* Added doc for "cargo" like actions.
* Added doc for multi-session.

## 0.10.1

Released: 2019-11-11

### New Features

* AoC and node v4 "browse" works now on non-folder items: file, link.
* Initial support for AoC automation (do not use yet).

## 0.10

Released: 2019-10-19

### New Features

* Support for transfer using IBM Cloud Object Storage.
* Improved `find` action using arbitrary expressions.

## 0.9.36

Released: 2019-10-16

### New Features

* Added option to specify file pair lists.

## 0.9.35

Released: 2019-10-11

### New Features

* `preview`: Changed parameter names, added documentation.

### Issues Fixed

* `ats`: Fix: instance ID needed in request header.

## 0.9.34

Released: 2019-10-03

### Issues Fixed

* Parser `@preset` can be used again in option `transfer_info`.
* Some documentation re-organizing.

## 0.9.33

Released: 2019-08-28

### New Features

* New command to display basic token of node.
* New command to display bearer token of node in AoC.
* The `--fields=` option, support `+_field_name_` to add a field to default fields.

## 0.9.32

Released: 2019-06-13

### New Features

* All Faspex public links are now supported.

### Breaking Changes

* Removed Faspex operation `recv_publink`. Replaced with option `link` (consistent with AoC).

## 0.9.31

Released: 2019-06-12

### New Features

* Added more support for public link: receive and send package, to user or dropbox and files view.
* Changed text table gem from text-table to terminal-table because it supports multiline values.

### Issues Fixed

* Delete expired file lists.

## 0.9.27

Released: 2019-03-27

### New Features

* Basic email support with SMTP.
* Basic proxy auto config support.

## 0.9.26

Released: 2019-03-13

### New Features

* Table display with `--fields=ALL` now includes all column names from all lines, not only first one.
* Unprocessed argument shows error even if there is an error beforehand.

## 0.9.25

Released: 2019-03-11

### New Features

* `find` now also reports all types (file, folder, link).
* `find` now is able to report all fields (type, size, etc...).

### Breaking Changes

* The option `value` of command `find` to filter on name is mandatory.

## 0.9.24

Released: 2019-03-05

### Issues Fixed

* Fix bug where AoC node to node transfer did not work.
* Fix bug on error if ED25519 private key is defined in .ssh.

## 0.9.23

Released: 2019-03-04

### New Features

* Defined REST error handlers, more error conditions detected.
* Commands to select specific `ascp` location.

## 0.9.21

Released: 2019-02-09

### New Features

* Supports simplified wizard using global client.
* Only `ascp` binary is required, other SDK (keys) files are now generated.

## 0.9.20

Released: 2019-01-22

### New Features

* Improved wizard (prepare for AoC global client ID).
* Preview generator: Added option: `skip_format` with values `png`, `mp4`.

## 0.9.19

Released: 2019-01-15

### New Features

* Added command `aspera bearer --scope=xx`.

## 0.9.18

Released: 2019-01-12

### New Features

* Enhanced Aspera admin events to support query.

## 0.9.16

Released: 2019-01-11

### New Features

* AoC transfers are now reported in activity app.
* New interface for Rest class authentication (keep backward compatibility).

## 0.9.15

Released: 2018-12-20

### New Features

* New feature: `find` command in Aspera Files.
* Sample code for transfer API.

## 0.9.12

Released: 2018-12-13

### New Features

* Add `nagios` commands.
* Support of ATS for IBM Cloud.

### Breaking Changes

* Removed old ATS implementation based on Aspera ID.

## 0.9.11

Released: 2018-11-29

### New Features

* Support of ATS for IBM Cloud.

### Breaking Changes

* Removed old ATS implementation based on Aspera ID.
* **global**: `@stdin` is now `@stdin:`.

## 0.9.10

Released: 2018-11-20

### New Features

* Display SaaS storage usage with command: `aspera admin res node --id=nn info`.
* Cleaner way of specifying source file list for transfers.

### Breaking Changes

* **global**: Parameter transfer-node becomes more generic: `transfer-info`.
* **global**: Replaced `download_mode` option with `http_download` action.

## 0.9.9

Released: 2018-11-14

### New Features

* Now supports "cargo" for Aspera on Cloud (automatic package download).

### Breaking Changes

* **global**: `aspera package send` parameter deprecated, use the --value option instead with "recipients" value. See example.

## 0.9.8

Released: 2018-11-13

### New Features

* `faspex`: Use option `once_only` set to `yes` to enable cargo like function. `id=NEW` deprecated.
* `aoc`: Share to share transfer with command `transfer`.

## 0.9.7

Released: 2018-11-08

### New Features

* Homogeneous transfer spec for `node` and [`direct`](README.md#agt_direct) transfer agents.
* Preview persistency goes to unique file by default.
* Catch `mxf` extension in preview as video.
* Faspex: Possibility to download all packages by specifying `id=ALL`.
* Faspex: To come: Cargo-like function to download only new packages with id=NEW.

## 0.9.6

Released: 2018-10-30

### New Features

* AoC: Added command to display current workspace information.

### Breaking Changes

* **global**: `@param:`is now `@preset:` and is generic.

## 0.9.5

Released: 2018-10-22

### New Features

* New parameter: `new_user_option` used to choose between public_link and invite of external users.

### Issues Fixed

* Fixed bug in wizard, and wizard uses now product detection.

## 0.9.4

Released: 2018-10-19

### New Features

* AoC Package send supports external users.
* New command to export AoC config to Aspera CLI config.

### Breaking Changes

* `oncloud`: `oncloud file list` follow `--source` convention as well (plus specific case for download when first path is source folder, and others are source file names).

## 0.9.3

Released: 2018-10-18

### New Features

* REST error message show host and code.
* Option for quiet display.
* Modified transfer interface and allow token re-generation on error.
* `async` add `admin` command.
* `async` add db parameters.

### Breaking Changes

* **global**: New option `sources` to specify files to transfer.

## 0.9.2

Released: 2018-10-11

### Breaking Changes

* `aoc`: Changed AoC package creation to match API, see AoC section.

## 0.9.1

Released: 2018-10-08

### Breaking Changes

* `faspex`: Changed Faspex package creation to match API, see Faspex section.

## 0.9

Released: 2018-10-04

### New Features

* Automatic rename and conversion of former config folder from `aslmcli` to `ascli`.

### Breaking Changes

* Renamed the CLI from `aslmcli` to `ascli`.

## 0.7.6

Released: 2018-08-30

### New Features

* Add `sync` plugin.

## 0.7

Released: 2018-05-31

### New Features

* AoC: Receive package from public link.
* Select by col value on output.
* Added rename (AoC, node).

### Breaking Changes

* `aoc`: AoC `package recv` take option if for package instead of argument.
* **global**: Rest class and OAuth class changed initialization parameters.

## 0.6.19

Released: 2018-04-27

### Breaking Changes

* `ats`: `ats server list provisioned` &rarr; `ats cluster list`.
* `ats`: `ats server list clouds` &rarr; `ats cluster clouds`.
* `ats`: `ats server list instance --cloud=x --region=y` &rarr; `ats cluster show --cloud=x --region=y`.
* `ats`: `ats server id xxx` &rarr; `ats cluster show --id=xxx`.
* `ats`: `ats subscriptions` &rarr; `ats credential subscriptions`.
* `ats`: `ats api_key repository list` &rarr; `ats credential cache list`.
* `ats`: `ats api_key list` &rarr; `ats credential list`.
* `ats`: `ats access_key id xxx` &rarr; `ats access_key --id=xxx`.

## 0.6.18

Released: 2018-04-19

### New Features

* Some commands take now `--id` option instead of `id` command.

## 0.6.15

Released: 2018-04-16

### Breaking Changes

* `aspera`: `files` application renamed to `aspera` (for "Aspera on Cloud"). `repository` renamed to `files`. Default is automatically reset, e.g. in config files and change key `files` to `aspera` in preset `default`.
