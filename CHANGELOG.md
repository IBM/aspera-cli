# Changes (Release notes)

* 4.15.0.pre

  * new: global: added resolution hints for well known issues.
  * new: global: extended value expression `@extend:` finds and replace extended values in a string (e.g. for JSON)
  * new: global: option `fields` now supports `RegExp`
  * new: global: option `ignore_certificate` to specify specific URLs instead of global option `insecure`
  * new: wizard: can detect multiple applications at the same address or url.
  * new: aoc: wizard accepts public links
  * new: orchestrator: error analysis for workflow start
  * new: httpgw: now supports pseudo file for testing: e.g. `faux:///testfile?1k`
  * new: node: added command `transfer sessions` to list all sessions of all transfers
  * new: node: generate bearer token from private key and user information
  * new: node: access node API with bearer token as credentials
  * new: agent: `direct` allows ignoring certificate for wss using http options
  * new: preview: command `show` generates a preview and displays it in terminal
  * change(break): config: commands `detect` and `wizard` takes now a mandatory argument: address or url instead of option `url`.
  * change(break): sync: plugin `sync` is removed: actions are available through `server` and `node` plugins.
  * change(break): sync: replaced option `sync_session` with optional positional parameter.
  * change(break): preview: command `scan`, `events` and `trevents` replaced option `query` with optional positional parameter for filter (like `find`).
  * change(break): removed extended value handler `incps`, as it is never used (use `extend` instead).
  * change(break): node: `find` command now takes an optional `@ruby:` extended value instead of option `query` with prefix: `exec:`
  * change(break): aoc: selection by name uses percent selector instead of option or parameter `name`
  * change(break): faspex: remote source selection now uses percent selector instead of parameter `id` or `name`
  * change(break): faspex: option `source_name` is now `remote_source`
  * change(break): orchestrator: workflow start takes arguments as optional positional extended value instead of option `param`
  * change(break): option `fields`: `+prop` is replaced with: `DEF,prop` and `-field` is replaced with: `DEF,-field`, and whole list is evaluated.

* 4.14.0

  * new: server: option `passphrase` for simpler command line (#114)
  * new: percent selector for entities identifier
  * new: faspex5: shared inbox and workgroup membership management
  * new: faspex5: invite external user to shared inbox
  * new: faspex5: package list and receive from workgroups and shared inboxes
  * new: config: Command `ascp info` shows default transfer spec.
  * new: httpgw: synchronous and asynchronous upload modes
  * new: node: command `bandwidth_average` to get average bandwidth of node, per periods
  * fix: option `ts`: deep add and remove of keys. (#117)
  * fix: faspex5: user lookup for `packages send` shall be exact match (#120)
  * fix: direct: if transfer spec contains "paths" and elements with "destination", but first element has only "source", then destinations were ignored. Now "destination" all or none is enforced.
  * change: using `aoc files` or node gen4 operations (`browse`, `delete`) on a link will follow the link only if path ends with /
  * change: shares: command `repository` is changed to `files` for consistency with aoc and upcoming faspex5, but is still available as alias
  * change: aoc: better handling of shared links
  * change: global: option `value` is deprecated. Use positional parameter for creation data and option `query` for list/delete operations.
  * change: config: remove deprecated command: `export_to_cli`
  * change: config: removed all legacy preset command, newer command `preset` shall be used now.
  * change: config: SDK is now installed in $HOME/.aspera/sdk instead of $HOME/.aspera/ascli/sdk
  * change(break): aoc/node: Simplification: gen4 operations: show modify permission thumbnail are now directly under node gen 4 command. Command `file` is suppressed. Option `path` is suppressed. The default expected argument is a path. To provide a file id, use selector syntax: %id:_file_id_
  * change(break): node: option `token_type` is removed, as starting with HSTS 4.3 basic token is only allowed with access keys, so use gen4 operations: `acc do self`

* 4.13.0

  * new: preview: option `reencode_ffmpeg` allows overriding all re-encoding options
  * new: faspex5: package delete (#107)
  * new: faspex5: package recv for inboxes and regular users (#108)
  * new: faspex5: smtp management
  * new: faspex5: use public link for authorization of package download, using option `link`
  * new: faspex5: list content of package, and allow partial download of package
  * new: faspex5: list packages support multiple pages and items limitations (`max` and `pmax`)
  * new: aoc: files operations with workspace-less user (#109)
  * new: node: async with gen3 token (#110)
  * new: node: display of preview of file in terminal for access keys
  * change: option `transfer_info` is now cumulative, setting several times merge values
  * change(deprecation): Removed support of Ruby 2.4 and 2.5 : too old, no security update since a long time. If you need older ruby version use older gem version.
  * fix: cos: do not use refresh token when not supported
  * fix: container: SDK installed in other folder than `ascli` (#106)

* 4.12.0

  * new: docker: build image from official gem version, possibility to deploy beta as well
  * new: generic: `delete` operation supports option `value` for deletion parameters
  * new: aoc: command `aoc packages recv` accepts option `query` to specify a shared inbox
  * new: faspex: (v4) user delete accepts option `value` with value `{"destroy":true}` to delete users permanently
  * new: faspex: (v4) gateway to faspex 5 for package send
  * new: faspex5: possibility to change email templates
  * new: faspex5: shared folder list and browse
  * new: faspex5: emulate faspex 4 postprocessing, plugin: `faspex5` command: `postprocessing`
  * new: faspex5: send package from remote source
  * new: shares: option `type` for command `shares admin user`
  * new: shares: full support for shares admin operations
  * change(break): shares: command `shares admin user saml_import` replaced with `shares admin user import --type=saml`
  * change(break): shares: command `shares admin user ldap_import` replaced with `shares admin user add --type=ldap`
  * change(break): shares: command `app_authorizations` now has sub commands `show` and `modify`
  * change(break): shares: similar changes for `shares admin share user show`
  * change(break): option `ascp_opts` is removed, and replaced with `transfer_info` parameter `ascp_args`

* 4.11.0

  * new: vault: secret finder, migration from config file
  * new: allow removal of transfer spec parameter by setting value to `null`
  * new: option `ascp_opts` allows to provide native `ascp` options on command line
  * new: command `sync` added to `node` (gen4) and `server` plugins, also available in `aoc`
  * fix: security: no shell interpolation
  * fix: when WSS and node agent: no localhost (certificate)
  * fix: #99 `aoc file download` for single shared folder
  * fix: due to change of API in faspex 5 for send package (paths is mandatory for any type of transfer now)
  * fix: Oauth web authentication was broken, fixed now
  * change(break): container image has entry point
  * change(break): `aoc admin res node` commands `v3` and `v4` replaced with `do` and command `v3` moved inside `do`
  * change(break): renamed options for `sync`
  * change: node gen4 operations are moved from aoc plugin to node plugin but made available where gen4 is used
  * change: if wss is enabled on server, use wss
  * lots of cleanup and refactoring

* 4.10.0

  * new: httpgw transfer agent: support api v2, support transfer through http proxy, including proxy password
  * new: faspex5: get bearer token
  * updates: for docker container version
  * break: option `secrets` is renamed to `vault`

* 4.9.0

  * new: shares: import of SAML users and LDAP users
  * new: M1 apple silicon support SDK install (uses x86 ascp)
  * new: support bulk operation more globally (create/delete), not all ops , though
  * new: added missing transfer spec parameters, e.g. `src_base`, `password`
  * new: improved documentation on faspex and aoc package send
  * fix: `node do` command fixed
  * fix: improved secret hiding from logs
  * change(break): removed rarely commands nodeadmin, configuration, userdata, ctl from plugin `server`
    as well as option `cmd_prefix`
  * change: `ascli` runs as user `cliuser` instead of `root` in container
  * change: default access right for config folder is now user only, including private keys

* 4.8.0

  * new: #76 add resource `group_membership` in `aoc`
  * new: add resource `metadata_profile` in `faspex5`
  * new: add command `user profile` in `faspex5`
  * new: add config wizard for `faspex5`
  * new: #75 gem is signed
  * change(break): removed dependency on gem `grpc` which is used only for the `trsdk` transfer agent. Users can install the gem manually if needed.
  * change(break): hash vault keys are string instead of symbol
  * change: cleanup with rubocop, all strings are immutable now by default, list constants are frozen
  * change: removed Hash.dig implementation because it is by default in Ruby >= 2.3
  * change: default is now to hide secrets on command output. Set option `show_secrets` to reveal secrets.
  * change: option `insecure` displays a warning

* 4.7.0

  * new: option to specify font used to generate image of text file in `preview`
  * new: #66 improvement for content protection (support standard transfer spec options for direct agent)
  * new: option `fpac` is now applicable to all ruby based HTTP connections, i.e. API calls
  * new: option `show_secrets` to reveal secrets in command output
  * new: added and updated commands for Faspex 5
  * new: option `cache_tokens`
  * new: Faspex4 dropbox packages can now be received by id
  * change(break): command `conf gem path` replaces `conf gem_path`
  * change(break): option `fpac` expects a value instead of URL
  * change(break): option `cipher` in transfer spec must have hyphen
  * change(break): renamed option `log_passwords` to `log_secrets`
  * change(break): removed plugin `shares2` as products is now EOL
  * fix: After AoC version update, wizard did not detect AoC properly

* 4.6.0

  * new: command `conf plugin create`
  * new: global option `plugin_folder`
  * new: global option `transpose_single`
  * new: simplified metadata passing for shared inbox package creation in AoC
  * change(break): command `aoc packages shared_inboxes list` replaces `aoc user shared_inboxes`
  * change(break): command `aoc user profile` replaces `aoc user info`
  * change(break): command `aoc user workspaces list` replaces `aoc user workspaces`
  * change(break): command `aoc user workspaces current` replaces `aoc workspace`
  * change(break): command `conf plugin list` replaces `conf plugins`
  * change(break): command `conf connect` simplified
  * fix: #60 ascli executable was not installed by default in 4.5.0
  * fix: add password hiding case in logs

* 4.5.0

  * new: support transfer agent: [Transfer SDK](README.md#agt_trsdk)
  * new: support [http socket options](README.md#http_options)
  * new: logs hide passwords and secrets, option `log_passwords` to enable logging secrets
  * new: `config vault` supports encrypted passwords, also macos keychain
  * new: `config preset` command for consistency with id
  * new: identifier can be provided using either option `id` or directly after the command, e.g. `delete 123` is the same as `delete --id=123`
  * change: when using wss, use [ruby's CA certs](README.md#certificates)
  * change: unexpected parameter makes exit code not zero
  * change(break): options `id` and `name` cannot be specified at the same time anymore, use [positional identifier or name selection](README.md#res_select)
  * change(break): `aoc admin res node` does not take workspace main node as default node if no `id` specified.
  * change(break): : `orchestrator workflow status` requires id, and supports special id `ALL`
  * fix: various smaller fixes and renaming of some internal classes (transfer agents and few other)

* 4.4.0

  * new: `aoc packages list` add possibility to add filter with option `query`
  * new: `aoc admin res xxx list` now get all items by default #50
  * new: `preset` option can specify name or hash value
  * new: `node` plugin accepts bearer token and access key as credential
  * new: `node` option `token_type` allows using basic token in addition to aspera type.
  * change: `server`: option `username` not mandatory anymore: xfer user is by default. If transfer spec token is provided, password or keys are optional, and bypass keys are used by default.
  * change(break): resource `apps_new` of `aoc` replaced with `application` (more clear)

* 4.3.0

  * new: parameter `multi_incr_udp` for option `transfer_info`: control if UDP port is incremented when multi-session is used on [`direct`](README.md#agt_direct) transfer agent.
  * new: command `aoc files node_info` to get node information for a given folder in the Files application of AoC. Allows cross-org or cross-workspace transfers.

* 4.2.2

  * new: `faspex package list` retrieves the whole list, not just first page
  * new: support web based auth to aoc and faspex 5 using HTTPS, new dependency on gem `webrick`
  * new: the error "Remote host is not who we expected" displays a special remediation message
  * new: `conf ascp spec` displays supported transfer spec
  * new: options `notif_to` and `notif_template` to send email notifications on transfer (and other events)
  * fix: space character in `faspe:` url are percent encoded if needed
  * fix: `preview scan`: if file_id is unknown, ignore and continue scan
  * change: for commands that potentially execute several transfers (`package recv --id=ALL`), if one transfer fails then ascli exits with code 1 (instead of zero=success)
  * change(break): option `notify` or `aoc` replaced with `notif_to` and `notif_template`

* 4.2.1

  * new: command `faspex package recv` supports link of type: `faspe:`
  * new: command `faspex package recv` supports option `recipient` to specify dropbox with leading `*`

* 4.2.0

  * new: command `aoc remind` to receive organization membership by email
  * new: in `preview` option `value` to filter out on file name
  * new: `initdemo` to initialize for demo server
  * new: [`direct`](README.md#agt_direct) transfer agent options: `spawn_timeout_sec` and `spawn_delay_sec`
  * fix: on Windows `conf ascp use` expects ascp.exe
  * fix: (break) multi_session_threshold is Integer, not String
  * fix: `conf ascp install` renames sdk folder if it already exists (leftover shared lib may make fail)
  * fix: removed replace_illegal_chars from default aspera.conf causing "Error creating illegal char conversion table"
  * change(break): `aoc apiinfo` is removed, use `aoc servers` to provide the list of cloud systems
  * change(break): parameters for resume in `transfer-info` for [`direct`](README.md#agt_direct) are now in sub-key `"resume"`

* 4.1.0

  * fix: remove keys from transfer spec and command line when not needed
  * fix: default to create_dir:true so that sending single file to a folder does not rename file if folder does not exist
  * new: update documentation with regard to offline and docker installation
  * new: renamed command `nagios_check` to `health`
  * new: agent `http_gw` now supports upload
  * new: added option `sdk_url` to install SDK from local file for offline install
  * new: check new gem version periodically
  * new: the --fields= option, support -_field_name_ to remove a field from default fields
  * new: Oauth tokens are discarded automatically after 30 minutes (useful for COS delegated refresh tokens)
  * new: mimemagic is now optional, needs manual install for `preview`, compatible with version 0.4.x
  * new: AoC a password can be provided for a public link
  * new: `conf doc` take an optional parameter to go to a section
  * new: initial support for Faspex 5 Beta 1

* 4.0.0

  * now available as open source (github) with general cleanup
  * changed default tool name from `mlia` to `ascli`
  * changed `aspera` command to `aoc`
  * changed gem name from `asperalm` to `aspera-cli`
  * changed module name from `Asperalm` to `Aspera`
  * removed command `folder` in `preview`, merged to `scan`
  * persistency files go to sub folder instead of main folder
  * added possibility to install SDK: `config ascp install`

* 0.11.8

  * Simplified to use `unoconv` instead of bare `libreoffice` for office conversion, as `unoconv` does not require a X server (previously using `Xvfb`)

* 0.11.7

  * rework on rest call error handling
  * use option `display` with value `data` to remove out of extraneous information
  * fixed option `lock_port` not working
  * generate special icon if preview failed
  * possibility to choose transfer progress bar type with option `progress`
  * AoC package creation now output package id

* 0.11.6

  * orchestrator : added more choice in auth type
  * preview: cleanup in generator (removed and renamed parameters)
  * preview: better documentation
  * preview: animated thumbnails for video (option: `video_png_conv=animated`)
  * preview: new event trigger: `trevents` (`events` seems broken)
  * preview: unique tmp folder to avoid clash of multiple instances
  * repo: added template for secrets used for testing

* 0.11.5

  * added option `default_ports` for AoC (see manual)
  * allow bulk delete in `aspera files` with option `bulk=yes`
  * fix getting connect versions
  * added section for Aix
  * support all ciphers for [`direct`](README.md#agt_direct) agent (including gcm, etc..)
  * added transfer spec param `apply_local_docroot` for [`direct`](README.md#agt_direct)

* 0.11.4

  * possibility to give shared inbox name when sending a package (else use id and type)

* 0.11.3

  * minor fixes on multi-session: avoid exception on progress bar

* 0.11.2

  * fixes on multi-session: progress bat and transfer spec param for "direct"

* 0.11.1

  * enhanced short_link creation commands (see examples)

* 0.11

  * add transfer spec option (agent `direct` only) to provide file list directly to ascp: `EX_file_list`.

* 0.10.18

  * new option in. `server` : `ssh_options`

* 0.10.17

  * fixed problem on `server` for option `ssh_keys`, now accepts both single value and list.
  * new modifier: `@list:<separator>val1<separator>...`

* 0.10.16

  * added list of shared inboxes in workspace (or global), use `--query=@json:'{}'`

* 0.10.15

  * in case of command line error, display the error cause first, and non-parsed argument second
  * AoC : Activity / Analytics

* 0.10.14

  * added missing bss plugin

* 0.10.13

  * added Faspex5 (use option `value` to give API arguments)

* 0.10.12

  * added support for AoC node registration keys
  * replaced option : `local_resume` with `transfer_info` for agent [`direct`](README.md#agt_direct)
  * Transfer agent is no more a Singleton instance, but only one is used in CLI
  * `@incps` : new extended value modifier
  * ATS: no more provides access keys secrets: now user must provide it
  * begin work on "aoc" transfer agent

* 0.10.11

  * minor refactor and fixes

* 0.10.10

  * fix on documentation

* 0.10.9.1

  * add total number of items for AoC resource list
  * better gem version dependency (and fixes to support Ruby 2.0.0)
  * removed aoc search_nodes

* 0.10.8

  * removed option: `fasp_proxy`, use pseudo transfer spec parameter: `EX_fasp_proxy_url`
  * removed option: `http_proxy`, use pseudo transfer spec parameter: `EX_http_proxy_url`
  * several other changes..

* 0.10.7

  * fix: ascli fails when username cannot be computed on Linux.

* 0.10.6

  * FaspManager: transfer spec `authentication` no more needed for local transfer to use Aspera public keys. public keys will be used if there is a token and no key or password is provided.
  * gem version requirements made more open

* 0.10.5

  * fix faspex package receive command not working

* 0.10.4

  * new options for AoC : `secrets`
  * `ACLI-533` temp file list folder to use file lists is set by default, and used by `asession`

* 0.10.3

  * included user name in oauth bearer token cache for AoC when JWT is used.

* 0.10.2

  * updated `search_nodes` to be more generic, so it can search not only on access key, but also other queries.
  * added doc for "cargo" like actions
  * added doc for multi-session

* 0.10.1

  * AoC and node v4 "browse" works now on non-folder items: file, link
  * initial support for AoC automation (do not use yet)

* 0.10

  * support for transfer using IBM Cloud Object Storage
  * improved `find` action using arbitrary expressions

* 0.9.36

  * added option to specify file pair lists

* 0.9.35

  * updated plugin `preview` , changed parameter names, added documentation
  * fix in `ats` plugin : instance id needed in request header

* 0.9.34

  * parser "@preset" can be used again in option "transfer_info"
  * some documentation re-organizing

* 0.9.33

  * new command to display basic token of node
  * new command to display bearer token of node in AoC
  * the --fields= option, support +_field_name_ to add a field to default fields
  * many small changes

* 0.9.32

  * all Faspex public links are now supported
  * removed faspex operation `recv_publink`
  * replaced with option `link` (consistent with AoC)

* 0.9.31

  * added more support for public link: receive and send package, to user or dropbox and files view.
  * delete expired file lists
  * changed text table gem from text-table to terminal-table because it supports multiline values

* 0.9.27

  * basic email support with SMTP
  * basic proxy auto config support

* 0.9.26

  * table display with --fields=ALL now includes all column names from all lines, not only first one
  * unprocessed argument shows error even if there is an error beforehand

* 0.9.25

  * the option `value` of command `find`, to filter on name, is not optional
  * `find` now also reports all types (file, folder, link)
  * `find` now is able to report all fields (type, size, etc...)

* 0.9.24

  * fix bug where AoC node to node transfer did not work
  * fix bug on error if ED25519 private key is defined in .ssh

* 0.9.23

  * defined REST error handlers, more error conditions detected
  * commands to select specific ascp location

* 0.9.21

  * supports simplified wizard using global client
  * only ascp binary is required, other SDK (keys) files are now generated

* 0.9.20

  * improved wizard (prepare for AoC global client id)
  * preview generator: added option : --skip-format=&lt;png,mp4&gt;
  * removed outdated pictures from this doc

* 0.9.19

  * added command aspera bearer --scope=xx

* 0.9.18

  * enhanced aspera admin events to support query

* 0.9.16

  * AoC transfers are now reported in activity app
  * new interface for Rest class authentication (keep backward compatibility)

* 0.9.15

  * new feature: "find" command in aspera files
  * sample code for transfer API

* 0.9.12

  * add nagios commands
  * support of ATS for IBM Cloud, removed old version based on aspera id

* 0.9.11

  * change(break): @stdin is now @stdin:
  * support of ATS for IBM Cloud, removed old version based on aspera id

* 0.9.10

  * change(break): parameter transfer-node becomes more generic: transfer-info
  * Display SaaS storage usage with command: aspera admin res node --id=nn info
  * cleaner way of specifying source file list for transfers
  * change(break): replaced download_mode option with http_download action

* 0.9.9

  * change(break): "aspera package send" parameter deprecated, use the --value option instead with "recipients" value. See example.
  * Now supports "cargo" for Aspera on Cloud (automatic package download)

* 0.9.8

  * Faspex: use option once_only set to yes to enable cargo like function. id=NEW deprecated.
  * AoC: share to share transfer with command "transfer"

* 0.9.7

  * homogeneous transfer spec for `node` and [`direct`](README.md#agt_direct) transfer agents
  * preview persistency goes to unique file by default
  * catch mxf extension in preview as video
  * Faspex: possibility to download all packages by specifying id=ALL
  * Faspex: to come: cargo-like function to download only new packages with id=NEW

* 0.9.6

  * change(break): `@param:`is now `@preset:` and is generic
  * AoC: added command to display current workspace information

* 0.9.5

  * new parameter: new_user_option used to choose between public_link and invite of external users.
  * fixed bug in wizard, and wizard uses now product detection

* 0.9.4

  * change(break): onCloud file list follow --source convention as well (plus specific case for download when first path is source folder, and other are source file names).
  * AoC Package send supports external users
  * new command to export AoC config to Aspera CLI config

* 0.9.3

  * REST error message show host and code
  * option for quiet display
  * modified transfer interface and allow token re-generation on error
  * async add admin command
  * async add db parameters
  * change(break): new option "sources" to specify files to transfer

* 0.9.2

  * change(break): changed AoC package creation to match API, see AoC section

* 0.9.1

  * change(break): changed faspex package creation to match API, see Faspex section

* 0.9

  * Renamed the CLI from aslmcli to ascli
  * Automatic rename and conversion of former config folder from aslmcli to ascli

* 0.7.6

  * add "sync" plugin

* 0.7

  * change(break): AoC package recv take option if for package instead of argument.
  * change(break): Rest class and Oauth class changed init parameters
  * AoC: receive package from public link
  * select by col value on output
  * added rename (AoC, node)

* 0.6.19

  * change(break): ats server list provisioned &rarr; ats cluster list
  * change(break): ats server list clouds &rarr; ats cluster clouds
  * change(break): ats server list instance --cloud=x --region=y &rarr; ats cluster show --cloud=x --region=y
  * change(break): ats server id xxx &rarr; ats cluster show --id=xxx
  * change(break): ats subscriptions &rarr; ats credential subscriptions
  * change(break): ats api_key repository list &rarr; ats credential cache list
  * change(break): ats api_key list &rarr; ats credential list
  * change(break): ats access_key id xxx &rarr; ats access_key --id=xxx

* 0.6.18

  * some commands take now --id option instead of id command.

* 0.6.15

  * change(break): "files" application renamed to "aspera" (for "Aspera on Cloud"). "repository" renamed to "files". Default is automatically reset, e.g. in config files and change key "files" to "aspera" in preset "default".
