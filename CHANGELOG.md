# Changes (Release notes)

<!-- markdownlint-configure-file { "no-duplicate-heading": { "siblings_only": true } } -->

## 4.25.0.pre

### New Features

* **global**: All `Hash` and `Array` options are now cumulative (merged). Value `@none:` resets to empty value.

### Issues Fixed

* `aoc`: Restored command `admin workspace shared_folder :id list` which was since 4.11.0.

### Breaking Changes

* `server`: By default, SSH option `use_agent` is now `false`.
* `config`: Removed option `use_product`, replaced with prefix `product:` of option `ascp_path`.

## 4.24.2

Released: 2025-10-24

### New Features

* `direct`: Capability to send management messages to `ascp` on running sessions. e.g. change target rate.
* `config`: Added command: `sync spec` to get sync parameters documentation. Also added to manual.

### Issues Fixed

* `faspex5`: Fix public link auth for Faspex 5.0.13.
* `aoc`: Fix some admin operations requiring a user's home for Files.
* `node`: Fix `transfer` operations: `modify` and `cancel`.
* `config`: #230 Fix problem when installing and detecting SDK on Windows

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
* `aoc`: `files download` using gen4 API do not require anymore to provide the containing folder in first position, and then only file names. Now, directly provide the path to all files.
* `logger`: Log is simplified, date is removed by default. Use `--log_format=standard` to revert to standard Ruby logger. See option `log_format` for details.

## 4.23.0

Released: 2025-08-11

### New Features

* `aoc`: #201: Added `package_folder` option to place each received package in its own subfolder named after a package attribute. Default is `@none:` which means no subfolder will be created.
* `config`: Added `transferd` version 1.1.6.

### Issues Fixed

* `server`: #209: missing home folder for transfer user shall not cause an error.
* `direct`: #205: `kill` blocks `cmd` on Windows.

### Breaking Changes

* `config`: In `ascp info`: `openssldir` &rarr; `ascp_openssl_dir`, `openssl_version` &rarr; `ascp_openssl_version`, `sdk_ascp_version` &rarr; `ascp_version`

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

* **container**: Updated Ruby to 3.4.2

### Issues Fixed

* **global**: #185 `@val:` shall stop processing extended values
* **global**: #186 Removed dependency on OpenSSL 3.3 gem to avoid `MSYS2` dep on Windows.
* `echo`: Display of list (Array) was showing only first element of it.
* `transferd`: Support for version 1.1.5+

### Breaking Changes

* `preview`: Updated Image Magick to v7+
* `aoc`: `admin subscription` split into `admin subscription account` and `admin subscription usage`
* **agent**: `alpha` renamed to `desktop`

## 4.21.1

Released: 2025-03-15

### New Features

* `config`: New command: `transferd` to list and install specific version of `asperatransferd` and `ascp`
* `config`: New command: `tokens` with `list`, `show`, `flush` (replace `flush_tokens`)
* `faspex5`: New command: `admin contact reset_password`
* `aoc`: #178 packages can be browsed, and individual files can be downloaded now.

### Issues Fixed

* `config`: #175 `ascli config preset set GLOBAL version_check_days 0` causes a bad `config.yaml` to be written
* `config`: #180 problem in `ascp install`
* `config`: Soft links in transfer SDK archive are correctly extracted
* `aoc`: #184 token cache shall be different per AoC org.
* `aoc`: Fix `packages delete` not working.
* `direct` agent: #174 Race condition fix with `ascp`: timeout waiting management port connect (select not readable)
* `preview`: #177 fix bug that prevents preview generation to work.

### Breaking Changes

* `transferd`: Use of Aspera Transfer Daemon requires minimum version 1.1.4. Agent `trsdk` renamed `transferd`.
* `ascp`: Default SDK version is now 1.1.4. Removes support for ascp4.
* `node`: Removed deprecated command prefix `exec:`, use `@ruby:` instead.
* **global**: Now uses OpenSSL 3.
* **global**: Ruby minimum versions is now 3.1 (mainly due to switch to OpenSSL 3). Future minimum is 3.2. Recommended is 3.4. (that removes macOS default ruby support. Newer Ruby version shall be installed on macOS with `brew`)
* **global**: Options `transpose_single` and `multi_table` replaced with single option `multi_single` and values: `no`, `yes`, `single`.
* **global**: Column name for single object is now `field` instead of `key`.

## 4.20.0

Released: 2025-01-21

  ATTENTION: [Faspex version 4 is now end of support](https://www.ibm.com/support/pages/lifecycle/search?q=faspex): The `faspex` plugin will be deprecated. Servers shall be upgraded to Faspex 5, and users use plugin `faspex5`.

### New Features

* `aoc`: Improved usability for creation of Admin shared folders.
* `node`: New option `node_cache` (bool) for gen4 operations.
* `node`: Option `root_id` now always works for node gen4, as well as `%id:` for file selection in addition to path.
* `node`: `transfer list` now uses the `iteration_token` to retrieve all values. Option `once_only` is now supported.
* **global**: Option `http_options` now include retry options.

### Issues Fixed

* `aoc`: Fixed `find` command not working. (undefined variable)
* `aoc`: #165 AoC `mkdir` now follows the last link of containing folder

### Breaking Changes

* Internal: Basic REST calls now return data directly. (no more `data` key). For advanced calls, use `call`.
* Internal: Transfer SDK download is now a 2-step procedure: First get the YAML file from GitHub with URLs for the various platforms and versions, and then download the archive from the official IBM repository.
    **global**: Option `format=multi` is replaced with option `multi_table=yes`
* `faspex5`: Removed deprecated option `value` replaced with positional parameter.
  
## 4.19.0

Released: 2024-10-02

### New Features

* `server`: Add support for `async` (Aspera Sync) from Transfer SDK
* **global**: #156 support sending folders with `httpgw`
* **global**: New value for option `format`: `multi`

### Issues Fixed

* `aoc`: #157 fix problem with `files browse` on a link
* `sync`: Better documentation and handling of options.

### Breaking Changes

* **global**: Default value for direct agent option `transfer_info.multi_incr_udp` is `true` on Windows, and now `false` on other platforms.
* **global**: Token based transfers now use the RSA key only. Direct agent option `transfer_info.client_ssh_key` allows changing this behavior.
  
## 4.18.1

Released: 2024-08-21

### New Features

* None

### Issues Fixed

* **global**: #146 (@junkimu) Fix problem on Windows WRT terminal detection
* **global**: Node gen4 (`aoc`) browsing through link now follows the link correctly
* `shares`: #147 Fix problem for `shares files mkdir`

### Breaking Changes

* **global**: Removed option `id`, deprecated since 4.14.0

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
* `node`: New action: `transport` to display transfer address and ports
* **global**: Added option `http_proxy`, as an alias to env var `http_proxy`.
* **global**: Possibility to filter fields when using formats like `json` or `yaml`.

### Issues Fixed

* `faspex5`: Fixed support for percent selector for metadata profiles.

### Breaking Changes

* `aoc` : `admin resource` is deprecated, use just `admin`.
* `faspex5` : `admin resource` is deprecated, use just `admin`.
* **global**: Option `value` is deprecated and replaced with option `query` when used in generic commands: `delete` and `list`, as well as node access_key browse, node stream and watch folder list. (#142)
* **global**: Option `warnings` (and short `w`) is removed. To get ruby warnings invoke with `ruby -w .../ascli ...`. See `Makefile` in `test`
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

* `aoc`: `exclude_dropbox_packages` query option can be overridden (#135)
* **global**: Removed gem dependency on `bigdecimal` (not used and requires compilation)
* **global**: Tested with JRuby 9.4.6.0 (use `ServerSocket` instead of `Socket`)
* **global**: Update version for gem `terminal-table` to 3.0.2

### Breaking Changes

* `config`: Command `remote_certificate` now takes a subcommand.
* **global**: Moved a few internal classes in new/renamed modules
* **global**: Deprecated pseudo transfer specification parameters starting with `EX_`:
  * `EX_ssh_key_paths`. Use spec `ssh_private_key` or option `transfer_info={"ascp_args":["-i","..."]}`
  * `EX_http_proxy_url`. Use option `transfer_info={"ascp_args":["-x","..."]}`
  * `EX_http_transfer_jpeg`. Use option `transfer_info={"ascp_args":["-j","1"]}`
  * `EX_no_read`. Use option `transfer_info={"ascp_args":["--no-read"]}`
  * `EX_no_write`. Use option `transfer_info={"ascp_args":["--no-write"]}`
  * `EX_file_list`. Use `ascli` file list feature or option `transfer_info={"ascp_args":["--file-list","..."]}`
  * `EX_file_pair_list`. Use `ascli` file list feature or option `transfer_info={"ascp_args":["--file-pair-list","..."]}`
  * `EX_ascp_args`. Use option `transfer_info={"ascp_args":[...]}`
  * `EX_at_rest_password`. Use spec parameter `content_protection_password`
  * `EX_proxy_password`. Set password in spec parameter `proxy` or use env var `ASPERA_PROXY_PASS`.
  * `EX_license_text`. Use env var `ASPERA_SCP_LICENSE`.

## 4.16.0

Released: 2024-02-15

### New Features

* **global**: Option `output` to redirect result to a file instead of `stdout`
* **global**: New option `silent_insecure`
* `config`: Keys added to `config ascp info`
* `config`: Added command `pubkey` to extract public key from private key
* `config`: New command `vault info`
* `faspex5`: Added `shared_folders` management
* `faspex5`: If package has content protection, ask passphrase interactively, unless `content_protection=null` in `ts`
* `faspex`: Added `INIT` for `once_only`
* `aoc`: Added `INIT` for `once_only`
* `aoc`: More list commands honor option `query`

### Issues Fixed

* `config`: Wizard was failing due to `require` of optional gem.
* `aoc`: Use paging to list entities, instead of just one page(e.g. retrieve all packages)
* `faspex5`: When receiving ALL packages, only get those with status `completed`.
* `direct` agent: Better support for WSS

### Breaking Changes

* `shares`: Option `type` for users and groups is replaced with mandatory positional argument with same value. E.g. `user list --type=local` becomes: `user local list`.
* `aoc`, `faspex`: Package `recv` command changed to `receive`, for consistency with faspex5 (`recv` is now an alias command)

## 4.15.0

Released: 2023-11-18

### General: Removed many redundant options, more consistency between plugins, see below in "break"

### New Features

* **global**: Added resolution hints for well known issues.
* **global**: Extended value expression `@extend:` finds and replace extended values in a string (e.g. for JSON)
* **global**: Option `fields` now supports `RegExp`
* **global**: Option `home` to set the main folder for configuration and cache
* **global**: Option `ignore_certificate` to specify specific URLs instead of global option `insecure`
* **global**: Option `cert_stores` to specify alternate certificate stores
* **global**: Uniform progress bar for any type of transfer.
* **global**: Add extended value types: `re` and `yaml`
* **global**: Option `pid_file` to write tool's PID during execution, deleted on exit
* `config`: Command `remote_certificate` to retrieve a remote certificate
* `config`: Added logger level `trace1` and `trace2`
* `config`: `wizard` can detect multiple applications at the same address or URL.
* `aoc`: Wizard accepts public links
* `aoc`: Support private links, and possibility to list shared folder with workspace `@json:null`
* `orchestrator`: Error analysis for workflow start
* `httpgw`: Now supports pseudo file for testing: e.g. `faux:///testfile?1k`
* `node`: Added command `transfer sessions` to list all sessions of all transfers
* `node`: Generate bearer token from private key and user information
* `node`: Access node API with bearer token as credentials
* **global**: Agent `direct` allows ignoring certificate for WSS using HTTP options
* `preview`: Command `show` generates a preview and displays it in terminal

### Issues Fixed

* Ruby warning: `net/protocol.rb:68: warning: already initialized constant Net::ProtocRetryError` solved by removing dependency on `net-smtp` from gem spec (already in base ruby).

### Breaking Changes

* **global**: Commands `detect` and `wizard` takes now a mandatory argument: address or URL instead of option `url`.
* **global**: Renamed option `pkeypath` to `key_path`
* **global**: Renamed option `notif_to` to `notify_to` and `notif_template` to `notify_template`
* **global**: Removed extended value handler `incps`, as it is never used (use `extend` instead).
* **global**: Option `fields`: `+prop` is replaced with: `DEF,prop` and `-field` is replaced with: `DEF,-field`, and whole list is evaluated.
* **global**: Replaced option `progress` with option `progressbar` (bool)
* **global**: Removed option `rest_debug` and `-r`, replaced with `--log-level=trace2`
* **global**: The default file name for private key when using wizard is change from `aspera_aoc_key` to `my_private_key.pem`
* `faspex5`: Removed option and `auth` type `link`: simply provide the public link as `url`
* `faspex`: Remote source selection now uses percent selector instead of parameter `id` or `name`
* `faspex`: Option `source_name` is now `remote_source`
* `aoc`: Selection by name uses percent selector instead of option or parameter `name`
* `aoc`: Removed option `link`: use `url` instead
* `aoc`: In command `short_link`, place type before command, e.g. `short_link private create /blah`
* `aoc`: Replaced option `operation` with mandatory positional parameter for command `files transfer`
* `aoc`: Replaced option `from_folder` with mandatory positional parameter for command `files transfer`
* `orchestrator`: Workflow start takes arguments as optional positional extended value instead of option `param`
* `node`: `find` command now takes an optional `@ruby:` extended value instead of option `query` with prefix: `exec:`
* `sync`: Plugin `sync` is removed: actions are available through `server` and `node` plugins.
* `sync`: Replaced option `sync_session` with optional positional parameter.
* `preview`: Command `scan`, `events` and `trevents` replaced option `query` with optional positional parameter for filter (like `find`).
* **global**: Agent `trsdk` parameters `host` and `port` in option `transfer_info` are replaced with parameter `url`, like `grpc://host:port`

## 4.14.0

Released: 2023-09-22

### New Features

* `server`: Option `passphrase` for simpler command line (#114)
* Percent selector for entities identifier
* `faspex5`: Shared inbox and workgroup membership management
* `faspex5`: Invite external user to shared inbox
* `faspex5`: Package list and receive from workgroup and shared inbox
* `config`: Command `ascp info` shows default transfer spec.
* **global**: Agent `httpgw` synchronous and asynchronous upload modes
* `node`: Command `bandwidth_average` to get average bandwidth of node, per periods

### Issues Fixed

* Option `ts`: Deep add and remove of keys. (#117)
* `faspex5`: User lookup for `packages send` shall be exact match (#120)
* **global**: Agent `direct` if transfer spec contains "paths" and elements with "destination", but first element has only "source", then destinations were ignored. Now "destination" all or none is enforced.

### Breaking Changes

* Using `aoc files` or node gen4 operations (`browse`, `delete`) on a link will follow the link only if path ends with /
* `shares`: Command `repository` is changed to `files` for consistency with aoc and upcoming faspex5, but is still available as alias
* `aoc`: Better handling of shared links
* **global**: Option `value` is deprecated. Use positional parameter for creation data and option `query` for list/delete operations.
* `config`: Remove deprecated command: `export_to_cli`
* `config`: Removed all legacy preset command, newer command `preset` shall be used now.
* `config`: SDK is now installed in `$HOME/.aspera/sdk` instead of `$HOME/.aspera/ascli/sdk`
* `aoc`, `node`: Simplification: gen4 operations: show modify permission thumbnail are now directly under node gen 4 command. Command `file` is suppressed. Option `path` is suppressed. The default expected argument is a path. To provide a file ID, use selector syntax: `%id:_file_id_`
* `node`: Option `token_type` is removed, as starting with HSTS 4.3 basic token is only allowed with access keys, so use gen4 operations: `acc do self`

## 4.13.0

Released: 2023-06-29

### New Features

* `preview`: Option `reencode_ffmpeg` allows overriding all re-encoding options
* `faspex5`: `package delete` (#107)
* `faspex5`: `package recv` for inboxes and regular users (#108)
* `faspex5`: SMTP management
* `faspex5`: Use public link for authorization of package download, using option `link`
* `faspex5`: List content of package, and allow partial download of package
* `faspex5`: List packages support multiple pages and items limitations (`max` and `pmax`)
* `aoc`: Files operations with workspace-less user (#109)
* `node`: `async` with gen3 token (#110)
* `node`: Display of preview of file in terminal for access keys

### Issues Fixed

* `cos`: Do not use refresh token when not supported
* **container**: SDK installed in other folder than `ascli` (#106)

### Breaking Changes

* Option `transfer_info` is now cumulative, setting several times merge values
* Change(deprecation): Removed support of Ruby 2.4 and 2.5 : Too old, no security update since a long time. If you need older ruby version use older gem version.

## 4.12.0

Released: 2023-03-20

### New Features

* **container**: Build image from official gem version, possibility to deploy beta as well
* **global**: `delete` operation supports option `value` for deletion parameters
* `aoc`: Command `aoc packages recv` accepts option `query` to specify a shared inbox
* `faspex`: (v4) user delete accepts option `value` with value `{"destroy":true}` to delete users permanently
* `faspex`: (v4) gateway to Faspex 5 for package send
* `faspex5`: Possibility to change email templates
* `faspex5`: Shared folder list and browse
* `faspex5`: Emulate Faspex 4 post-processing, plugin: `faspex5` command: `postprocessing`
* `faspex5`: Send package from remote source
* `shares`: Option `type` for command `shares admin user`
* `shares`: Full support for shares admin operations

### Breaking Changes

* `shares`: Command `shares admin user saml_import` replaced with `shares admin user import --type=saml`
* `shares`: Command `shares admin user ldap_import` replaced with `shares admin user add --type=ldap`
* `shares`: Command `app_authorizations` now has sub commands `show` and `modify`
* `shares`: Similar changes for `shares admin share user show`
* Option `ascp_opts` is removed, and replaced with `transfer_info` parameter `ascp_args`

## 4.11.0

Released: 2023-01-26

### New Features

* **global**: `vault`: Secret finder, migration from config file
* **global**: Allow removal of transfer spec parameter by setting value to `null`
* **global**: Option `ascp_opts` allows providing native `ascp` options on command line
* `node`, `server`: Command `sync` added to `node` (gen4) and `server` plugins, also available in `aoc`

### Issues Fixed

* **global**: Security: no shell interpolation
* **global**: Agent `node`: when WSS is used: no localhost (certificate)
* `aoc`: #99 `file download` for single shared folder
* `faspex5`: Change of API in Faspex 5 for send package (paths is mandatory for any type of transfer now)
* **global**: OAuth web authentication was broken, fixed now

### Breaking Changes

* **container**: Image has entry point
* `aoc`: `admin res node` commands `v3` and `v4` replaced with `do` and command `v3` moved inside `do`
* Renamed options for `sync`
* Node gen4 operations are moved from aoc plugin to node plugin but made available where gen4 is used
* If wss is enabled on server, use wss
* Lots of cleanup and refactoring

## 4.10.0

Released: 2022-12-02

### New Features

* `httpgw`: Transfer agent support API v2, support transfer through HTTP proxy, including proxy password
* `faspex5`: Get bearer token

### Issues Fixed

* **container**: Container version

### Breaking Changes

* `config`: Option `secrets` is renamed to `vault`

## 4.9.0

Released: 2022-09-15

### New Features

* `shares`: Import of SAML users and LDAP users
* M1 apple silicon support SDK install (uses x86 ascp)
* Support bulk operation more globally (create/delete), not all ops , though
* Added missing transfer spec parameters, e.g. `src_base`, `password`
* Improved documentation on faspex and aoc package send

### Issues Fixed

* `node do` command fixed
* Improved secret hiding from logs

### Breaking Changes

* Removed rarely commands `nodeadmin`, `configuration`, `userdata`, `ctl` from plugin `server`
      as well as option `cmd_prefix`
* `ascli` runs as user `cliuser` instead of `root` in container
* Default access right for config folder is now user only, including private keys

## 4.8.0

Released: 2022-06-16

### New Features

* #76 add resource `group_membership` in `aoc`
* Add resource `metadata_profile` in `faspex5`
* Add command `user profile` in `faspex5`
* Add config wizard for `faspex5`
* #75 gem is signed

### Breaking Changes

* Removed dependency on gem `grpc` which is used only for the `trsdk` transfer agent. Users can install the gem manually if needed.
* Hash vault keys are string instead of symbol
* Cleanup with rubocop, all strings are immutable now by default, list constants are frozen
* Removed Hash.dig implementation because it is by default in Ruby >= 2.3
* Default is now to hide secrets on command output. Set option `show_secrets` to reveal secrets.
* Option `insecure` displays a warning

## 4.7.0

Released: 2022-03-23

### New Features

* Option to specify font used to generate image of text file in `preview`
* #66 improvement for content protection (support standard transfer spec options for direct agent)
* Option `fpac` is now applicable to all ruby based HTTP connections, i.e. API calls
* Option `show_secrets` to reveal secrets in command output
* Added and updated commands for Faspex 5
* Option `cache_tokens`
* Faspex4 dropbox packages can now be received by id

### Issues Fixed

* After AoC version update, wizard did not detect AoC properly

### Breaking Changes

* Command `conf gem path` replaces `conf gem_path`
* Option `fpac` expects a value instead of URL
* Option `cipher` in transfer spec must have hyphen
* Renamed option `log_passwords` to `log_secrets`
* Removed plugin `shares2` as products is now EOL

## 4.6.0

Released: 2022-02-04

### New Features

* Command `conf plugin create`
* Global option `plugin_folder`
* Global option `transpose_single`
* Simplified metadata passing for shared inbox package creation in AoC

### Issues Fixed

* #60 ascli executable was not installed by default in 4.5.0
* Add password hiding case in logs

### Breaking Changes

* Command `aoc packages shared_inboxes list` replaces `aoc user shared_inboxes`
* Command `aoc user profile` replaces `aoc user info`
* Command `aoc user workspaces list` replaces `aoc user workspaces`
* Command `aoc user workspaces current` replaces `aoc workspace`
* Command `conf plugin list` replaces `conf plugins`
* Command `conf connect` simplified

## 4.5.0

Released: 2021-12-27

### New Features

* Support transfer agent: [Transfer SDK](README.md#agt_trsdk)
* Support [http socket options](README.md#http_options)
* Logs hide passwords and secrets, option `log_passwords` to enable logging secrets
* `config vault` supports encrypted passwords, also macos keychain
* `config preset` command for consistency with id
* Identifier can be provided using either option `id` or directly after the command, e.g. `delete 123` is the same as `delete --id=123`

### Issues Fixed

* Various smaller fixes and renaming of some internal classes (transfer agents and few other)

### Breaking Changes

* When using wss, use [ruby's CA certs](README.md#certificates)
* Unexpected parameter makes exit code not zero
* Options `id` and `name` cannot be specified at the same time anymore, use [positional identifier or name selection](README.md#res_select)
* `aoc admin res node` does not take workspace main node as default node if no `id` specified.
* : `orchestrator workflow status` requires id, and supports special id `ALL`

## 4.4.0

Released: 2021-11-13

### New Features

* `aoc packages list` add possibility to add filter with option `query`
* `aoc admin res xxx list` now get all items by default #50
* `preset` option can specify name or hash value
* `node` plugin accepts bearer token and access key as credential
* `node` option `token_type` allows using basic token in addition to aspera type.

### Breaking Changes

* `server`: Option `username` not mandatory anymore: `xfer` user is by default. If transfer spec token is provided, password or keys are optional, and bypass keys are used by default.
* Resource `apps_new` of `aoc` replaced with `application` (more clear)

## 4.3.0

Released: 2021-10-19

### New Features

* Parameter `multi_incr_udp` for option `transfer_info`: control if UDP port is incremented when multi-session is used on [`direct`](README.md#agt_direct) transfer agent.
* Command `aoc files node_info` to get node information for a given folder in the Files application of AoC. Allows cross-org or cross-workspace transfers.

## 4.2.2

Released: 2021-09-23

### New Features

* `faspex package list` retrieves the whole list, not just first page
* Support web based auth to aoc and faspex 5 using HTTPS, new dependency on gem `webrick`
* The error "Remote host is not who we expected" displays a special remediation message
* `conf ascp spec` displays supported transfer spec
* Options `notif_to` and `notif_template` to send email notifications on transfer (and other events)

### Issues Fixed

* Space character in `faspe:` url are percent encoded if needed
* `preview scan`: If file_id is unknown, ignore and continue scan

### Breaking Changes

* For commands that potentially execute several transfers (`package recv --id=ALL`), if one transfer fails then ascli exits with code 1 (instead of zero=success)
* Option `notify` or `aoc` replaced with `notif_to` and `notif_template`

## 4.2.1

Released: 2021-09-01

### New Features

* Command `faspex package recv` supports link of type: `faspe:`
* Command `faspex package recv` supports option `recipient` to specify dropbox with leading `*`

## 4.2.0

Released: 2021-08-24

### New Features

* Command `aoc remind` to receive organization membership by email
* In `preview` option `value` to filter out on file name
* `initdemo` to initialize for demo server
* [`direct`](README.md#agt_direct) transfer agent options: `spawn_timeout_sec` and `spawn_delay_sec`

### Issues Fixed

* On Windows `conf ascp use` expects ascp.exe
* (break) multi_session_threshold is Integer, not String
* `conf ascp install` renames sdk folder if it already exists (leftover shared lib may make fail)
* Removed `replace_illegal_chars` from default `aspera.conf` causing "Error creating illegal char conversion table"

### Breaking Changes

* `aoc apiinfo` is removed, use `aoc servers` to provide the list of cloud systems
* Parameters for resume in `transfer-info` for [`direct`](README.md#agt_direct) are now in sub-key `"resume"`

## 4.1.0

Released: 2021-06-23

### New Features

* Update documentation with regard to offline and docker installation
* Renamed command `nagios_check` to `health`
* Agent `http_gw` now supports upload
* Added option `sdk_url` to install SDK from local file for offline install
* Check new gem version periodically
* The --fields= option, support -_field_name_ to remove a field from default fields
* Oauth tokens are discarded automatically after 30 minutes (useful for COS delegated refresh tokens)
* `mimemagic` is now optional, needs manual install for `preview`, compatible with version 0.4.x
* AoC a password can be provided for a public link
* `conf doc` take an optional parameter to go to a section
* Initial support for Faspex 5 Beta 1

### Issues Fixed

* Remove keys from transfer spec and command line when not needed
* Default to `create_dir`:`true` so that sending single file to a folder does not rename file if folder does not exist

## 4.0.0

Released: 2021-02-03

### New Features

* Now available as open source (GitHub) with general cleanup
* Added possibility to install SDK: `config ascp install`

### Breaking Changes

* Changed default tool name from `mlia` to `ascli`
* Changed `aspera` command to `aoc`
* Changed gem name from `asperalm` to `aspera-cli`
* Changed module name from `Asperalm` to `Aspera`
* Removed command `folder` in `preview`, merged to `scan`
* Persistency files go to sub folder instead of main folder

## 0.11.8

### Simplified to use `unoconv` instead of bare `libreoffice` for office conversion, as `unoconv` does not require a X server (previously using `Xvfb`)

## 0.11.7

### Rework on rest call error handling

### Use option `display` with value `data` to remove out of extraneous information

### Fixed option `lock_port` not working

### Generate special icon if preview failed

### Possibility to choose transfer progress bar type with option `progress`

### AoC package creation now output package id

## 0.11.6

### `orchestrator`: Added more choice in auth type

### `preview`: Cleanup in generator (removed and renamed parameters)

### `preview`: Better documentation

### `preview`: Animated thumbnails for video (option: `video_png_conv=animated`)

### `preview`: New event trigger: `trevents` (`events` seems broken)

### `preview`: Unique tmp folder to avoid clash of multiple instances

### Repo: Added template for secrets used for testing

## 0.11.5

### Added option `default_ports` for AoC (see manual)

### Allow bulk delete in `aspera files` with option `bulk=yes`

### Fix getting connect versions

### Added section for Aix

### Support all ciphers for [`direct`](README.md#agt_direct) agent (including gcm, etc..)

### Added transfer spec param `apply_local_docroot` for [`direct`](README.md#agt_direct)

## 0.11.4

### Possibility to give shared inbox name when sending a package (else use id and type)

## 0.11.3

### Minor fixes on multi-session: Avoid exception on progress bar

## 0.11.2

### Fixes on multi-session: Progress bat and transfer spec param for "direct"

## 0.11.1

### Enhanced short_link creation commands (see examples)

## 0.11

### Add transfer spec option (agent `direct` only) to provide file list directly to ascp: `EX_file_list`

## 0.10.18

### New option in. `server` : `ssh_options`

## 0.10.17

### Fixed problem on `server` for option `ssh_keys`, now accepts both single value and list

### New modifier: `@list:<separator>val1<separator>...`

## 0.10.16

### Added list of shared inboxes in workspace (or global), use `--query=@json:'{}'`

## 0.10.15

### In case of command line error, display the error cause first, and non-parsed argument second

### AoC : Activity / Analytics

## 0.10.14

### Added missing bss plugin

## 0.10.13

### Added Faspex5 (use option `value` to give API arguments)

## 0.10.12

### Added support for AoC node registration keys

### Replaced option : `local_resume` with `transfer_info` for agent [`direct`](README.md#agt_direct)

### Transfer agent is no more a Singleton instance, but only one is used in CLI

### `@incps` : New extended value modifier

### ATS: No more provides access keys secrets: now user must provide it

### Begin work on "aoc" transfer agent

## 0.10.11

### Minor refactor and fixes

## 0.10.10

### Fix on documentation

## 0.10.9.1

### Add total number of items for AoC resource list

### Better gem version dependency (and fixes to support Ruby 2.0.0)

### Removed aoc search_nodes

## 0.10.8

### Removed option: `fasp_proxy`, use pseudo transfer spec parameter: `EX_fasp_proxy_url`

### Removed option: `http_proxy`, use pseudo transfer spec parameter: `EX_http_proxy_url`

### Several other changes

## 0.10.7

### Fix: `ascli` fails when username cannot be computed on Linux

## 0.10.6

### FaspManager: Transfer spec `authentication` no more needed for local transfer to use Aspera public keys. public keys will be used if there is a token and no key or password is provided

### Gem version requirements made more open

## 0.10.5

### Fix faspex package receive command not working

## 0.10.4

### New options for AoC : `secrets`

### `ACLI-533` temp file list folder to use file lists is set by default, and used by `asession`

## 0.10.3

### Included user name in oauth bearer token cache for AoC when JWT is used

## 0.10.2

### Updated `search_nodes` to be more generic, so it can search not only on access key, but also other queries

### Added doc for "cargo" like actions

### Added doc for multi-session

## 0.10.1

### AoC and node v4 "browse" works now on non-folder items: file, link

### Initial support for AoC automation (do not use yet)

## 0.10

### Support for transfer using IBM Cloud Object Storage

### Improved `find` action using arbitrary expressions

## 0.9.36

### Added option to specify file pair lists

## 0.9.35

### `preview`: Changed parameter names, added documentation

### `ats`: Fix: instance ID needed in request header

## 0.9.34

### Parser "@preset" can be used again in option "transfer_info"

### Some documentation re-organizing

## 0.9.33

### New command to display basic token of node

### New command to display bearer token of node in AoC

### The --fields= option, support +_field_name_ to add a field to default fields

### Many small changes

## 0.9.32

### All Faspex public links are now supported

### Removed faspex operation `recv_publink`

### Replaced with option `link` (consistent with AoC)

## 0.9.31

### Added more support for public link: receive and send package, to user or dropbox and files view

### Delete expired file lists

### Changed text table gem from text-table to terminal-table because it supports multiline values

## 0.9.27

### Basic email support with SMTP

### Basic proxy auto config support

## 0.9.26

### Table display with --fields=ALL now includes all column names from all lines, not only first one

### Unprocessed argument shows error even if there is an error beforehand

## 0.9.25

### The option `value` of command `find`, to filter on name, is not optional

### `find` now also reports all types (file, folder, link)

### `find` now is able to report all fields (type, size, etc...)

## 0.9.24

### Fix bug where AoC node to node transfer did not work

### Fix bug on error if ED25519 private key is defined in .ssh

## 0.9.23

### Defined REST error handlers, more error conditions detected

### Commands to select specific ascp location

## 0.9.21

### Supports simplified wizard using global client

### Only ascp binary is required, other SDK (keys) files are now generated

## 0.9.20

### Improved wizard (prepare for AoC global client id)

### Preview generator: Added option : --skip-format=&lt;png,mp4&gt;

### Removed outdated pictures from this doc

## 0.9.19

### Added command aspera bearer --scope=xx

## 0.9.18

### Enhanced aspera admin events to support query

## 0.9.16

### AoC transfers are now reported in activity app

### New interface for Rest class authentication (keep backward compatibility)

## 0.9.15

### New feature: "find" command in aspera files

### Sample code for transfer API

## 0.9.12

### Add nagios commands

### Support of ATS for IBM Cloud, removed old version based on aspera id

## 0.9.11

### Change(break): @stdin is now @stdin

### Support of ATS for IBM Cloud, removed old version based on aspera id

## 0.9.10

### Change(break): Parameter transfer-node becomes more generic: `transfer-info`

### Display SaaS storage usage with command: `aspera admin res node --id=nn info`

### Cleaner way of specifying source file list for transfers

### Change(break): Replaced download_mode option with http_download action

## 0.9.9

### Change(break): "aspera package send" parameter deprecated, use the --value option instead with "recipients" value. See example

### Now supports "cargo" for Aspera on Cloud (automatic package download)

## 0.9.8

### Faspex: Use option once_only set to yes to enable cargo like function. id=NEW deprecated

### AoC: Share to share transfer with command "transfer"

## 0.9.7

### Homogeneous transfer spec for `node` and [`direct`](README.md#agt_direct) transfer agents

### Preview persistency goes to unique file by default

### Catch mxf extension in preview as video

### Faspex: Possibility to download all packages by specifying id=ALL

### Faspex: To come: Cargo-like function to download only new packages with id=NEW

## 0.9.6

### Change(break): `@param:`is now `@preset:` and is generic

### AoC: Added command to display current workspace information

## 0.9.5

### New parameter: `new_user_option` used to choose between public_link and invite of external users

### Fixed bug in wizard, and wizard uses now product detection

## 0.9.4

### Change(break): `oncloud file list` follow --source convention as well (plus specific case for download when first path is source folder, and other are source file names)

### AoC Package send supports external users

### New command to export AoC config to Aspera CLI config

## 0.9.3

### REST error message show host and code

### Option for quiet display

### Modified transfer interface and allow token re-generation on error

### `async` add `admin` command

### `async` add db parameters

### Change(break): New option "sources" to specify files to transfer

## 0.9.2

### Change(break): Changed AoC package creation to match API, see AoC section

## 0.9.1

### Change(break): Changed faspex package creation to match API, see Faspex section

## 0.9

### Renamed the CLI from aslmcli to ascli

### Automatic rename and conversion of former config folder from aslmcli to ascli

## 0.7.6

### Add `sync` plugin

## 0.7

### Change(break): AoC `package recv` take option if for package instead of argument

### Change(break): Rest class and Oauth class changed init parameters

### AoC: Receive package from public link

### Select by col value on output

### Added rename (AoC, node)

## 0.6.19

### Change(break): `ats server list provisioned` &rarr; `ats cluster list`

### Change(break): `ats server list clouds` &rarr; `ats cluster clouds`

### Change(break): `ats server list instance --cloud=x --region=y` &rarr; `ats cluster show --cloud=x --region=y`

### Change(break): `ats server id xxx` &rarr; `ats cluster show --id=xxx`

### Change(break): `ats subscriptions` &rarr; `ats credential subscriptions`

### Change(break): `ats api_key repository list` &rarr; `ats credential cache list`

### Change(break): `ats api_key list` &rarr; `ats credential list`

### Change(break): `ats access_key id xxx` &rarr; `ats access_key --id=xxx`

## 0.6.18

### Some commands take now `--id` option instead of `id` command

## 0.6.15

### Change(break): `files` application renamed to `aspera` (for "Aspera on Cloud"). `repository` renamed to `files`. Default is automatically reset, e.g. in config files and change key `files` to `aspera` in preset `default`
