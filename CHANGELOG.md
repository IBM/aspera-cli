# Changes (Release notes)

* 4.17.0

  * New Features:
    * `faspex5`: Support public and private invitations.
  * Issues Fixed:
    * `aoc`: #135 `exclude_dropbox_packages` query option can be overridden
  * Breaking Changes:
    * `config`: command `remote_certificate` now takes a subcommand.

* 4.16.0

  * New Features:
    * **global**: option `output` to redirect result to a file instead of `stdout`
    * **global**: new option `silent_insecure`
    * `config`: keys added to `config ascp info`
    * `config`: added command `pubkey` to extract public key from private key
    * `config`: new command `vault info`
    * `faspex5`: added `shared_folders` management
    * `faspex5`: if package has content protection, ask passphrase interactively, unless `content_protection=null` in `ts`
    * `faspex`: added `INIT` for `once_only`
    * `aoc`: added `INIT` for `once_only`
    * `aoc`: more list commands honor option `query`
  * Issues Fixed:
    * `config`: wizard was failing due to `require` of optional gem.
    * `aoc`: use paging to list entities, instead of just one page(e.g. retrieve all packages)
    * `faspex5`: When receiving ALL packages, only get those with status `completed`.
    * `direct` agent: better support for WSS
  * Breaking Changes:
    * `shares`: option `type` for users and groups is replaced with mandatory positional argument with same value.
    * `aoc`, `faspex`: package `recv` command changed to `receive`, for consistency with faspex5 (`recv` is now an alias command)

* 4.15.0

  * General: removed many redundant options, more consistency between plugins, see below in "break".
  * New Features:
    * **global**: added resolution hints for well known issues.
    * **global**: extended value expression `@extend:` finds and replace extended values in a string (e.g. for JSON)
    * **global**: option `fields` now supports `RegExp`
    * **global**: option `home` to set the main folder for configuration and cache
    * **global**: option `ignore_certificate` to specify specific URLs instead of global option `insecure`
    * **global**: option `cert_stores` to specify alternate certificate stores
    * **global**: uniform progress bar for any type of transfer.
    * **global**: add extended value types: `re` and `yaml`
    * **global**: option `pid_file` to write tool's PID during execution, deleted on exit
    * `config`: command `remote_certificate` to retrieve a remote certificate
    * `config`: added logger level `trace1` and `trace2`
    * `config`: `wizard` can detect multiple applications at the same address or url.
    * `aoc`: wizard accepts public links
    * `aoc`: support private links, and possibility to list shared folder with workspace `@json:null`
    * `orchestrator`: error analysis for workflow start
    * `httpgw`: now supports pseudo file for testing: e.g. `faux:///testfile?1k`
    * `node`: added command `transfer sessions` to list all sessions of all transfers
    * `node`: generate bearer token from private key and user information
    * `node`: access node API with bearer token as credentials
    * **global**: agent `direct` allows ignoring certificate for wss using http options
    * `preview`: command `show` generates a preview and displays it in terminal
  * Issues Fixed:
    * Ruby warning: `net/protocol.rb:68: warning: already initialized constant Net::ProtocRetryError` solved by removing dependency on `net-smtp` from gem spec (already in base ruby).
  * Breaking Changes:
    * **global**: commands `detect` and `wizard` takes now a mandatory argument: address or url instead of option `url`.
    * **global**: renamed option `pkeypath` to `key_path`
    * **global**: renamed option `notif_to` to `notify_to` and `notif_template` to `notify_template`
    * **global**: removed extended value handler `incps`, as it is never used (use `extend` instead).
    * **global**: option `fields`: `+prop` is replaced with: `DEF,prop` and `-field` is replaced with: `DEF,-field`, and whole list is evaluated.
    * **global**: replaced option `progress` with option `progressbar` (bool)
    * **global**: removed option `rest_debug` and `-r`, replaced with `--log-level=trace2`
    * **global**: the default file name for private key when using wizard is change from `aspera_aoc_key` to `my_private_key.pem`
    * `faspex5`: removed option and `auth` type `link`: simply provide the public link as `url`
    * `faspex`: remote source selection now uses percent selector instead of parameter `id` or `name`
    * `faspex`: option `source_name` is now `remote_source`
    * `aoc`: selection by name uses percent selector instead of option or parameter `name`
    * `aoc`: removed option `link`: use `url` instead
    * `aoc`: in command `short_link`, place type before command, e.g. `short_link private create /blah`
    * `aoc`: replaced option `operation` with mandatory positional parameter for command `files transfer`
    * `aoc`: replaced option `from_folder` with mandatory positional parameter for command `files transfer`
    * `orchestrator`: workflow start takes arguments as optional positional extended value instead of option `param`
    * `node`: `find` command now takes an optional `@ruby:` extended value instead of option `query` with prefix: `exec:`
    * `sync`: plugin `sync` is removed: actions are available through `server` and `node` plugins.
    * `sync`: replaced option `sync_session` with optional positional parameter.
    * `preview`: command `scan`, `events` and `trevents` replaced option `query` with optional positional parameter for filter (like `find`).
    * **global**: agent `trsdk` parameters `host` and `port` in option `transfer_info` are replaced with parameter `url`, like `grpc://host:port`

* 4.14.0

  * New Features:
    * `server`: option `passphrase` for simpler command line (#114)
    * percent selector for entities identifier
    * `faspex5`: shared inbox and workgroup membership management
    * `faspex5`: invite external user to shared inbox
    * `faspex5`: package list and receive from workgroup and shared inbox
    * `config`: Command `ascp info` shows default transfer spec.
    * **global**: agent `httpgw` synchronous and asynchronous upload modes
    * `node`: command `bandwidth_average` to get average bandwidth of node, per periods
  * Issues Fixed:
    * option `ts`: deep add and remove of keys. (#117)
    * `faspex5`: user lookup for `packages send` shall be exact match (#120)
    * **global**: agent `direct` if transfer spec contains "paths" and elements with "destination", but first element has only "source", then destinations were ignored. Now "destination" all or none is enforced.
  * Breaking Changes:
    * using `aoc files` or node gen4 operations (`browse`, `delete`) on a link will follow the link only if path ends with /
    * `shares`: command `repository` is changed to `files` for consistency with aoc and upcoming faspex5, but is still available as alias
    * `aoc`: better handling of shared links
    * **global**: option `value` is deprecated. Use positional parameter for creation data and option `query` for list/delete operations.
    * `config`: remove deprecated command: `export_to_cli`
    * `config`: removed all legacy preset command, newer command `preset` shall be used now.
    * `config`: SDK is now installed in $HOME/.aspera/sdk instead of $HOME/.aspera/ascli/sdk
    * `aoc`, `node`: Simplification: gen4 operations: show modify permission thumbnail are now directly under node gen 4 command. Command `file` is suppressed. Option `path` is suppressed. The default expected argument is a path. To provide a file id, use selector syntax: %id:_file_id_
    * `node`: option `token_type` is removed, as starting with HSTS 4.3 basic token is only allowed with access keys, so use gen4 operations: `acc do self`

* 4.13.0

  * New Features:
    * `preview`: option `reencode_ffmpeg` allows overriding all re-encoding options
    * `faspex5`: package delete (#107)
    * `faspex5`: package recv for inboxes and regular users (#108)
    * `faspex5`: smtp management
    * `faspex5`: use public link for authorization of package download, using option `link`
    * `faspex5`: list content of package, and allow partial download of package
    * `faspex5`: list packages support multiple pages and items limitations (`max` and `pmax`)
    * `aoc`: files operations with workspace-less user (#109)
    * `node`: async with gen3 token (#110)
    * `node`: display of preview of file in terminal for access keys
  * Issues Fixed:
    * `cos`: do not use refresh token when not supported
    * **container**: SDK installed in other folder than `ascli` (#106)
  * Breaking Changes:
    * option `transfer_info` is now cumulative, setting several times merge values
    * change(deprecation): Removed support of Ruby 2.4 and 2.5 : too old, no security update since a long time. If you need older ruby version use older gem version.

* 4.12.0

  * New Features:
    * **container**: build image from official gem version, possibility to deploy beta as well
    * **global**: `delete` operation supports option `value` for deletion parameters
    * `aoc`: command `aoc packages recv` accepts option `query` to specify a shared inbox
    * `faspex`: (v4) user delete accepts option `value` with value `{"destroy":true}` to delete users permanently
    * `faspex`: (v4) gateway to faspex 5 for package send
    * `faspex5`: possibility to change email templates
    * `faspex5`: shared folder list and browse
    * `faspex5`: emulate faspex 4 postprocessing, plugin: `faspex5` command: `postprocessing`
    * `faspex5`: send package from remote source
    * `shares`: option `type` for command `shares admin user`
    * `shares`: full support for shares admin operations
  * Breaking Changes:
    * `shares`: command `shares admin user saml_import` replaced with `shares admin user import --type=saml`
    * `shares`: command `shares admin user ldap_import` replaced with `shares admin user add --type=ldap`
    * `shares`: command `app_authorizations` now has sub commands `show` and `modify`
    * `shares`: similar changes for `shares admin share user show`
    * option `ascp_opts` is removed, and replaced with `transfer_info` parameter `ascp_args`

* 4.11.0

  * New Features:
    * **global**: `vault`: secret finder, migration from config file
    * **global**: allow removal of transfer spec parameter by setting value to `null`
    * **global**: option `ascp_opts` allows to provide native `ascp` options on command line
    * `node`, `server`: command `sync` added to `node` (gen4) and `server` plugins, also available in `aoc`
  * Issues Fixed:
    * **global**: security: no shell interpolation
    * **global**: agent `node`: when WSS is used: no localhost (certificate)
    * `aoc`: #99 `file download` for single shared folder
    * `faspex5`: change of API in faspex 5 for send package (paths is mandatory for any type of transfer now)
    * **global**: Oauth web authentication was broken, fixed now
  * Breaking Changes:
    * **container**: image has entry point
    * `aoc`: `admin res node` commands `v3` and `v4` replaced with `do` and command `v3` moved inside `do`
    * renamed options for `sync`
    * node gen4 operations are moved from aoc plugin to node plugin but made available where gen4 is used
    * if wss is enabled on server, use wss
    * lots of cleanup and refactoring

* 4.10.0

  * New Features:
    * httpgw transfer agent: support api v2, support transfer through http proxy, including proxy password
    * `faspex5`: get bearer token
  * Issues Fixed:
    * **container**: container version
  * Breaking Changes:
    * `config`: option `secrets` is renamed to `vault`

* 4.9.0

  * New Features:
    * `shares`: import of SAML users and LDAP users
    * M1 apple silicon support SDK install (uses x86 ascp)
    * support bulk operation more globally (create/delete), not all ops , though
    * added missing transfer spec parameters, e.g. `src_base`, `password`
    * improved documentation on faspex and aoc package send
  * Issues Fixed:
    * `node do` command fixed
    * improved secret hiding from logs
  * Breaking Changes:
    * removed rarely commands `nodeadmin`, `configuration`, `userdata`, `ctl` from plugin `server`
      as well as option `cmd_prefix`
    * `ascli` runs as user `cliuser` instead of `root` in container
    * default access right for config folder is now user only, including private keys

* 4.8.0

  * New Features:
    * #76 add resource `group_membership` in `aoc`
    * add resource `metadata_profile` in `faspex5`
    * add command `user profile` in `faspex5`
    * add config wizard for `faspex5`
    * #75 gem is signed
  * Breaking Changes:
    * removed dependency on gem `grpc` which is used only for the `trsdk` transfer agent. Users can install the gem manually if needed.
    * hash vault keys are string instead of symbol
    * cleanup with rubocop, all strings are immutable now by default, list constants are frozen
    * removed Hash.dig implementation because it is by default in Ruby >= 2.3
    * default is now to hide secrets on command output. Set option `show_secrets` to reveal secrets.
    * option `insecure` displays a warning

* 4.7.0

  * New Features:
    * option to specify font used to generate image of text file in `preview`
    * #66 improvement for content protection (support standard transfer spec options for direct agent)
    * option `fpac` is now applicable to all ruby based HTTP connections, i.e. API calls
    * option `show_secrets` to reveal secrets in command output
    * added and updated commands for Faspex 5
    * option `cache_tokens`
    * Faspex4 dropbox packages can now be received by id
  * Issues Fixed:
    * After AoC version update, wizard did not detect AoC properly
  * Breaking Changes:
    * command `conf gem path` replaces `conf gem_path`
    * option `fpac` expects a value instead of URL
    * option `cipher` in transfer spec must have hyphen
    * renamed option `log_passwords` to `log_secrets`
    * removed plugin `shares2` as products is now EOL

* 4.6.0

  * New Features:
    * command `conf plugin create`
    * global option `plugin_folder`
    * global option `transpose_single`
    * simplified metadata passing for shared inbox package creation in AoC
  * Issues Fixed:
    * #60 ascli executable was not installed by default in 4.5.0
    * add password hiding case in logs
  * Breaking Changes:
    * command `aoc packages shared_inboxes list` replaces `aoc user shared_inboxes`
    * command `aoc user profile` replaces `aoc user info`
    * command `aoc user workspaces list` replaces `aoc user workspaces`
    * command `aoc user workspaces current` replaces `aoc workspace`
    * command `conf plugin list` replaces `conf plugins`
    * command `conf connect` simplified

* 4.5.0

  * New Features:
    * support transfer agent: [Transfer SDK](README.md#agt_trsdk)
    * support [http socket options](README.md#http_options)
    * logs hide passwords and secrets, option `log_passwords` to enable logging secrets
    * `config vault` supports encrypted passwords, also macos keychain
    * `config preset` command for consistency with id
    * identifier can be provided using either option `id` or directly after the command, e.g. `delete 123` is the same as `delete --id=123`
  * Issues Fixed:
    * various smaller fixes and renaming of some internal classes (transfer agents and few other)
  * Breaking Changes:
    * when using wss, use [ruby's CA certs](README.md#certificates)
    * unexpected parameter makes exit code not zero
    * options `id` and `name` cannot be specified at the same time anymore, use [positional identifier or name selection](README.md#res_select)
    * `aoc admin res node` does not take workspace main node as default node if no `id` specified.
    * : `orchestrator workflow status` requires id, and supports special id `ALL`

* 4.4.0

  * New Features:
    * `aoc packages list` add possibility to add filter with option `query`
    * `aoc admin res xxx list` now get all items by default #50
    * `preset` option can specify name or hash value
    * `node` plugin accepts bearer token and access key as credential
    * `node` option `token_type` allows using basic token in addition to aspera type.
  * Breaking Changes:
    * `server`: option `username` not mandatory anymore: xfer user is by default. If transfer spec token is provided, password or keys are optional, and bypass keys are used by default.
    * resource `apps_new` of `aoc` replaced with `application` (more clear)

* 4.3.0

  * New Features:
    * parameter `multi_incr_udp` for option `transfer_info`: control if UDP port is incremented when multi-session is used on [`direct`](README.md#agt_direct) transfer agent.
    * command `aoc files node_info` to get node information for a given folder in the Files application of AoC. Allows cross-org or cross-workspace transfers.

* 4.2.2

  * New Features:
    * `faspex package list` retrieves the whole list, not just first page
    * support web based auth to aoc and faspex 5 using HTTPS, new dependency on gem `webrick`
    * the error "Remote host is not who we expected" displays a special remediation message
    * `conf ascp spec` displays supported transfer spec
    * options `notif_to` and `notif_template` to send email notifications on transfer (and other events)
  * Issues Fixed:
    * space character in `faspe:` url are percent encoded if needed
    * `preview scan`: if file_id is unknown, ignore and continue scan
  * Breaking Changes:
    * for commands that potentially execute several transfers (`package recv --id=ALL`), if one transfer fails then ascli exits with code 1 (instead of zero=success)
    * option `notify` or `aoc` replaced with `notif_to` and `notif_template`

* 4.2.1

  * New Features:
    * command `faspex package recv` supports link of type: `faspe:`
    * command `faspex package recv` supports option `recipient` to specify dropbox with leading `*`

* 4.2.0

  * New Features:
    * command `aoc remind` to receive organization membership by email
    * in `preview` option `value` to filter out on file name
    * `initdemo` to initialize for demo server
    * [`direct`](README.md#agt_direct) transfer agent options: `spawn_timeout_sec` and `spawn_delay_sec`
  * Issues Fixed:
    * on Windows `conf ascp use` expects ascp.exe
    * (break) multi_session_threshold is Integer, not String
    * `conf ascp install` renames sdk folder if it already exists (leftover shared lib may make fail)
    * removed replace_illegal_chars from default aspera.conf causing "Error creating illegal char conversion table"
  * Breaking Changes:
    * `aoc apiinfo` is removed, use `aoc servers` to provide the list of cloud systems
    * parameters for resume in `transfer-info` for [`direct`](README.md#agt_direct) are now in sub-key `"resume"`

* 4.1.0

  * New Features:
    * update documentation with regard to offline and docker installation
    * renamed command `nagios_check` to `health`
    * agent `http_gw` now supports upload
    * added option `sdk_url` to install SDK from local file for offline install
    * check new gem version periodically
    * the --fields= option, support -_field_name_ to remove a field from default fields
    * Oauth tokens are discarded automatically after 30 minutes (useful for COS delegated refresh tokens)
    * `mimemagic` is now optional, needs manual install for `preview`, compatible with version 0.4.x
    * AoC a password can be provided for a public link
    * `conf doc` take an optional parameter to go to a section
    * initial support for Faspex 5 Beta 1
  * Issues Fixed:
    * remove keys from transfer spec and command line when not needed
    * default to create_dir:true so that sending single file to a folder does not rename file if folder does not exist

* 4.0.0

  * New Features:
    * now available as open source (github) with general cleanup
    * added possibility to install SDK: `config ascp install`
  * Breaking Changes:
    * changed default tool name from `mlia` to `ascli`
    * changed `aspera` command to `aoc`
    * changed gem name from `asperalm` to `aspera-cli`
    * changed module name from `Asperalm` to `Aspera`
    * removed command `folder` in `preview`, merged to `scan`
    * persistency files go to sub folder instead of main folder

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

  * `orchestrator`: added more choice in auth type
  * `preview`: cleanup in generator (removed and renamed parameters)
  * `preview`: better documentation
  * `preview`: animated thumbnails for video (option: `video_png_conv=animated`)
  * `preview`: new event trigger: `trevents` (`events` seems broken)
  * `preview`: unique tmp folder to avoid clash of multiple instances
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
