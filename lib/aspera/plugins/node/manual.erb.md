## Plugin: `node`: IBM Aspera High Speed Transfer Server Node

This plugin gives access to capabilities provided by the HSTS Node API.

Authentication uses either a Node API username and password, or an access key and secret, provided with options `username` and `password`.

> [!NOTE]
> Capabilities of this plugin are used in other plugins that access the Node API, such as `aoc`, `ats`, `shares`.

> [!NOTE]
> This plugin can be used with any type of **Aspera Node**, either on-premises or ATS, provided that you have Node API credentials.
> Those credentials can be either Node API user or Access Key (for example, on ATS).

### File Operations

It is possible to do **gen3/node user** operations:

- `browse`
- Transfer (`upload` / `download` / `sync`)
- `delete`
- ...

When using an access key, the so-called **gen4/access key** API is also supported through subcommands using `access_keys do self`.

Example:

- `<%=cmd%> node browse /` : list files with **gen3/node user** API
- `<%=cmd%> node access_keys do self browse /` : list files with **gen4/access key** API

#### Browse

##### Gen3

This is when executing `browse` in `node` plugin or `v3`.

Native API parameters can be placed in option `query`.

Special parameters can be placed in option `query` for "gen3" browse:

| Parameter   | Description                        |
|-------------|------------------------------------|
| `recursive` | Recursively list files.            |
| `max`       | Maximum number of files to list.   |
| `self`      | Show folder metadata, not content. |
| `skip`      | Single API call.                   |

##### Gen4

This is when executing `browse` in `aoc files` or in `node access_keys do`.

Option `node_api` controls the use of the Node API, with the following parameters:

<%=schema_to_table('node_opts:components.schemas.NodeApiOptions')%>

The number of items requested per API call is the parameter `per_page` of option `query`.
Set to `nil` (`@none:`) to deactivate paging.
Default: `1000` when `accept_v4` is `true`.

### Operation `find` on **gen4/access key**

The command `find <%=ph :folder%> [filter_expr]` is available for **gen4/access key**, under `access_keys do self`.

The argument `<%=ph :folder%>` is mandatory and is the root from which the search is performed.
The argument `[filter_expr]` is optional and represents the matching criteria.

It recursively scans storage to find files and folders matching the criteria and returns a list of matching entries.

`[filter_expr]` is either:

- Optional (default): All files and folders are selected
- Type `String`: The expression is similar to shell globbing; refer to **Ruby** function: [`File.fnmatch`](https://ruby-doc.org/3.2.2/File.html#method-c-fnmatch)
- Type `Proc` : The expression is a Ruby lambda that takes one argument: a `Hash` that contains the current folder entry to test. See the following examples.

Examples of expressions:

- Find all files and folders under `/`

  ```shell
  <%=cmd%> node access_keys do self find /
  ```

- Find all text files in `/Documents`

  ```shell
  <%=cmd%> node access_keys do self find /Documents '*.txt'
  ```

The following examples show Ruby lambda code you can use in the template command below:

```shell
 <%=cmd%> node access_keys do self find / @ruby:'->(f){[code here]}'
```

> [!TIP]
> Single quotes are used above to protect the whole **Ruby** expression from the shell.
> Then double quotes are used for strings in the **Ruby** expression to not mix with the shell.

- Find files modified in the last 100 days

  ```ruby
  ->(f){f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))<100}
  ```

- Find files older than 1 year

  ```ruby
  ->(f){f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))>365}
  ```

- Find files larger than 1 MB

  ```ruby
  ->(f){f["type"].eql?("file") and f["size"].to_i>1000000}
  ```

- Filter out files beginning with `._` or named `.DS_Store`:

  ```ruby
  ->(f){!(f["name"].start_with?("._") or f["name"].eql?(".DS_Store"))}
  ```

- Match files using a [Ruby Regexp](https://ruby-doc.org/core/Regexp.html): `\.gif$`

  ```ruby
  ->(f){f["name"].match?(/\.gif$/)}
  ```

<%=tool%> commands can be piped to combine operations, such as **find and delete**:

```shell
<%=cmd%> node access_keys do self find / @ruby:'->(f){f["type"].eql?("file") and (DateTime.now-DateTime.parse(f["modified_time"]))>365}' --fields=path --format=csv | <%=cmd%> node --bulk=yes delete @lines:@stdin:
```

> [!NOTE]
> The pipe character `|` on the last line chains the two commands together.

### Listing transfer events

When you run a transfer, its information is stored (typically for 1 day) in the HSTS database (Redis).
To view this information, use the command `transfer list`.

When you have many transfers, the list is built from multiple API calls.

To list only new events since the last run, use the option `once_only`:

```shell
<%=cmd%> node transfer list --once-only=yes
```

<%=tool%> stores an `iteration_token` in its persistence repository to track the latest event.
To reset it, add the option `--query=@json:'{"reset": true}'`.
To limit how many events are listed, use the `max` parameter in the query.
Other query parameters are passed through to the underlying API (`GET /ops/transfers`).

### Central

The `central` sub-command uses the **reliable query** API (session and file).
Use it to list transfer sessions and transferred files.

To list transferred files:

```shell
<%=cmd%> node central file list
```

To validate transfers offline, use the `validator` option.

> [!NOTE]
> See the HSTS documentation for more details.

### Sync

The `node` plugin provides three commands for file synchronization:

| Command | `node` | `shares` | `aoc` | `server` | Description |
|-----|-----|-----|-----|-----|-----------------------------------------------|
| `sync`  | Yes | Yes | Yes | Yes | Perform a local sync by executing `async` locally. |
| `async` | Yes |     |     |     | Uses API `/async`.<%=br%>Get status on sync operations on the server side, as in Aspera Console. |
| `ssync` | Yes |     |     |     | Uses API `/asyncs`.<%=br%>Start a sync on the server side and monitor only those operations. |

For details on the `sync` action, see [IBM Aspera Sync](#ibm-aspera-sync).

For the `async` subcommands `show` and `delete`, you can use the special identifier `ALL`.

### FASP Stream

You can start a FASP Stream session from the Node API.

Run the following command:
`<%=cmd%> node stream create @json:<%=ph :value%>`
with the following [**transfer-spec**](#transfer-specification):

```json
{"direction":"send","source":"udp://233.3.3.4:3000?loopback=1&ttl=2","destination":"udp://233.3.3.3:3001/","remote_host":"localhost","remote_user":"stream","remote_password":"<%=ph :password%>"}
```

### Watchfolder

For watch folder creation, see [Aspera Server documentation](https://www.ibm.com/docs/en/ahte/4.4.x?topic=wffcl-watch-folder-json-configuration-file-reference) or [Aspera Watchfolder API Documentation](https://developer.ibm.com/apis/catalog/aspera--aspera-watch-folders-api/api/API--aspera--ibm-aspera-watch-folders-api).

You can run watchfolder operations remotely through the Node API:

- Start the `watchd` and `watchfolderd` services as a system user that has access to the files
- Configure a **Watchfolder** to define automated transfers

```shell
<%=cmd%> node service create @json:'{"id":"mywatchd","type":"WATCHD","run_as":{"user":"<%=ph :username%>"}}'
<%=cmd%> node service create @json:'{"id":"mywatchfolderd","type":"WATCHFOLDERD","run_as":{"user":"<%=ph :username%>"}}'
<%=cmd%> node watch_folder create @json:'{"id":"mywfolder","source_dir":"/watch1","target_dir":"/","transport":{"host":"10.25.0.4","user":"<%=ph :username%>","pass":"<%=ph :password%>"}}'
```

### Out of Transfer File Validation

To activate this feature, follow the Aspera Transfer Server configuration.

The following command lists one file that requires validation and assigns it to the unique validator identifier you provide:

```shell
<%=cmd%> node central file list --validator=<%=cmd%> @json:'{"file_transfer_filter":{"max_result":1}}'
```

```text
╭──────────────┬──────────────┬────────────┬─────────────────────────────────────╮
│ session_uuid │ file_id      │ status     │ path                                │
╞══════════════╪══════════════╪════════════╪═════════════════════════════════════╡
│ 1a74444c-... │ 084fb181-... │ validating │ /home/xfer.../PKG - <%=ph :title%>/200KB.1 │
╰──────────────┴──────────────┴────────────┴─────────────────────────────────────╯
```

To update the status of the file, use the following command:

```shell
<%=cmd%> node central file modify --validator=<%=cmd%> @json:'{"files":[{"session_uuid": "1a74444c-...","file_id": "084fb181-...","status": "completed"}]}'
```

```text
updated
```

### Example: SHOD to ATS

Scenario: Access to a **Shares on Demand** (SHOD) server on AWS is provided by a partner.
We need to transfer files from this third party SHOD instance into our Azure BLOB storage.
Create an **Aspera Transfer Service** instance, which provides access to the Node API.
Then create an [Option Preset](#option-preset) with the Node API URL and credentials of the **SHOD** instance, named `aws_shod`.
Create another [Option Preset](#option-preset) for the Azure ATS instance, named `azure_ats`.
Then execute the following command:

```shell
<%=cmd%> node download /share/sourcefile --to-folder=/destination_folder --preset=aws_shod --transfer=@preset:azure_ats --transfer.agent=node
```

This will get transfer information from the SHOD instance and tell the Azure ATS instance to download files.

### Node file information

When Node API is used with an **Access key**, extra information can be retrieved, such as preview.

> [!NOTE]
> Display of preview on terminal requires installation of extra gem: `rmagick`

```shell
dnf install -y ImageMagick-devel
gem install rmagick rainbow
```

For example, it is possible to display the preview of a file, if it exists, using an access key on node:

```shell
<%=cmd%> node access_keys do self thumbnail /preview_samples/Aspera.mpg
```

Previews are mainly used in AoC; this also works with AoC:

```shell
<%=cmd%> aoc files thumbnail /preview_samples/Aspera.mpg
```

> [!TIP]
> To specify the file by its file ID, use the selector syntax: `%id:<%=ph :file_id%>`

> [!NOTE]
> To force textual display of the preview on **iTerm**, prefix command with: `env -u TERM_PROGRAM -u LC_TERMINAL`

### Creating an access key

```shell
<%=cmd%> node access_keys create @json:'{"id":"<%=ph :access_key%>","secret":"<%=ph :secret%>","storage":{"type":"local","path":"/data/mydir"}}'
```

> [!TIP]
> The `id` and `secret` fields are optional.
> If not provided, they will be generated and returned in the result.
> In that case, provide option `--out.secrets=yes` to get the generated secret.

Access keys support extra overriding parameters using parameter: `configuration` and sub keys `transfer` and `server`.
For example, an access key can be modified or created with the following options:

```json
{"configuration":{"transfer":{"target_rate_cap_kbps":500000}}}
```

The list of supported options can be displayed using command:

```shell
<%=cmd%> node info --fields=@ruby:'/^access_key_configuration_capabilities.*/'
```

### Generating and using a bearer token

Bearer tokens are part of the **gen4/access key** API.
It follows the model of OAuth 2.
For example, they are used in Aspera on Cloud.
This is also available for developers for any application integrating Aspera.
In this API, files, users and groups are identified by an ID (a `String`, for example, `"125"`, not necessarily numerical).

Bearer tokens are typically generated by the authenticating application and then recognized by the Node API.
A bearer token is authorized on the node by creating `permissions` on a **folder**.

Bearer tokens can be generated using <%=tool%> command `bearer_token`: it takes two arguments:

- The private key used to sign the token.
- The token information, which is a `Hash` containing the following elements:

| Parameter              | Default                 | Type    | Description                           |
|----------------------|---------------------------|---------|---------------------------------------|
| `_scope`               | `user:all`              | Special | Either `user:all` or `admin:all`      |
| `_validity`            | 86400                   | Special | Validity in seconds from now.         |
| `user_id`              | -                     | Mandatory | Identifier of user                    |
| `scope`     | `node.<%=ph :access_key%>:_scope`     | Mandatory | API scope<%=br%>for example, `node.<%=ph :access_key%>:<%=ph :node_scope%>`         |
| `expires_at`           | `now+_validity`     | Mandatory | Format: `%Y-%m-%dT%H:%M:%SZ`<%=br%>for example, `2021-12-31T23:59:59Z` |
| `auth_type`            | `access_key`          | Optional  | `access_key`, `node_user`             |
| `group_ids`            | -                     | Optional  | List of group IDs                     |
| `organization_id`      | -                     | Optional  | Organization ID                       |
| `watermarking_json_base64` | -                 | Optional  | Watermarking information (not used)   |

> [!NOTE]
> For convenience, <%=tool%> provides additional parameters `_scope` and `_validity`.
> They are not part of the API and are removed from the final payload.
> They provide a convenient way to set `scope` and `expires_at`.

#### Bearer token: Environment

An access key shall be created to grant access for transfers to its storage.
The access key and its secret represent administrative access to the storage as it has access rights to the whole storage of the access key.

The way to create access keys depends slightly on the type of HSTS:

- If a self-managed Aspera node is used, then a **node user admin** must be created:
  It has no `docroot` but has at least one file restriction (for testing, one can use `*` to accept creation of an access key with any storage root path).
  See the Aspera HSTS documentation.

- If Cloud Pak for Integration is used, then the node admin is created automatically.

- If Aspera on Cloud or ATS is used, then the SaaS API for access key creation is used.

> [!NOTE]
> See [HSTS manual](https://www.ibm.com/docs/en/ahts): `Access key authentication` section for more details on access key creation.

The following sections assume that an access key has been created and that <%=tool%> is configured to use this access key by default using `node`.

#### Bearer token: Preparation

Assume that the access key was created, and a default configuration is set to use this **access key**.
Using <%=tool%>, an access key can be created using the `access_keys create` command on the node (using main node credentials) or on ATS.

Create a private key (organization key) that will be used to sign bearer tokens:

```shell
my_private_pem=./myorgkey.pem
<%=cmd%> config genkey $my_private_pem
```

> [!NOTE]
> This private key is not used for authentication.
> It is used to sign bearer tokens.
> See [private key](#private-key) for more details on generation.

The corresponding public key shall be placed as an attribute of the **access key** (done with `PUT /access_keys/<%=ph :id%>`):

```shell
<%=cmd%> node access_keys set_bearer_key self @file:$my_private_pem
```

> [!NOTE]
> Either the public or private key can be provided, and only the public key is used.
> This enables checking the signature of bearer tokens.
> Above command is executed with access key credentials.

Alternatively, use the following equivalent command, as `config genkey` also saves the public key with extension `.pub`:

```shell
<%=cmd%> node access_keys modify %id:self @ruby:'{token_verification_key: File.read("'$my_private_pem'.pub")}'
```

#### Bearer token: Configuration for user

- Select a folder for which to grant access to a user, and get its identifier:

  ```shell
  my_folder_id=$(<%=cmd%> node access_keys do self show / --fields=id)
  ```

> [!NOTE]
> This example uses `/`, but any folder can be selected in the access key storage.

- Designate a user by ID:

  ```shell
  my_user_id=777
  ```

> [!NOTE]
> This is an arbitrary identifier, typically managed by the web application.
> Not related to Linux user IDs or anything else.

- Grant this user access to the selected folder:

  ```shell
  <%=cmd%> node access_keys do self permission %id:$my_folder_id create @json:'{"access_type":"user","access_id":"'$my_user_id'"}'
  ```

- Create a Bearer token for the user:

  ```shell
  <%=cmd%> node bearer_token @file:./myorgkey.pem @json:'{"user_id":"'$my_user_id'","_validity":3600}' --out.secrets=yes --out.file=bearer.txt
  ```

> [!NOTE]
> The Bearer token can also be created using command `asnodeadmin` on HSTS.
> See the [HSTS manual](https://www.ibm.com/docs/en/ahts): `Bearer tokens` section.
> Code for token generation is provided in [`lib/aspera/plugins/node/api.rb`](<%=link_repo('lib/aspera/plugins/node/api.rb')%>)

#### Bearer token: User side

Assume the role of the user, with the following information:

- The URL of the Node API
- A Bearer token
- A file ID for which we have access

To use this information:

```shell
<%=cmd%> node -N --url=https://... --password="Bearer $(cat bearer.txt)" --root-id=$my_folder_id access_keys do self browse /
```

<%=include_commands_for_plugin(:node)%>

### Open Telemetry

The `node` plugin supports Open Telemetry (OTel) for monitoring and tracing.

> [!NOTE]
> This is an experimental feature and currently only available for the `node` plugin and Instana backend.

<%=tool%> polls the Node API for transfer events and sends them to an OTel collector.

The command expects the following parameters provided as a `Hash` positional parameter:

| Parameter   | Type     | Default | Description                                  |
|-------------|----------|---------|----------------------------------------------|
| `url`       | `String` | -       | URL of the Instana HTTPS backend for OTel.   |
| `key`       | `String` | -       | Agent key for the backend.                   |
| `interval`  | `Float`  | 10      | Polling interval in seconds.<%=br%>`0` for single shot. |

To retrieve OTel backend information: Go to the Instana web interface, **More** &rarr; **Agents** &rarr; **Docker** and identify the agent endpoint and key, for example, `endpoint=ingress-blue-saas.instana.io`.
Identify the region and the endpoint URL will be `https://otlp-[region]-saas.instana.io`, that is, replace `ingress` with `otlp`.

For convenience, those parameters can be provided in a preset, for example, named `otel_default`.

```shell
<%=cmd%> config preset set otel_default @json:'{"url":"https://otlp-orange-saas.instana.io:4318","key":"<%=ph :key%>","interval":1.1}'
```

Then it is invoked like this (assuming a default node is configured):

```shell
<%=cmd%> node telemetry @preset:otel_default
```

In Instana, create a custom Dashboard to visualize the OTel data:

- Add Widget: Histogram
- Data Source: Infrastructure and Platforms
- Metric: search `transfer`

### Node emulator

> [!NOTE]
> This is not a feature for production.
> It's provided for testing only.

The command `emulator` starts a local web server that answers a subset of the Node API, and executes transfers with the Transfer Daemon (`transferd`).
It allows testing, without HSTS, the [Node API agent](#agent-node-api) (`--transfer.agent=node`) and the `node` commands `info`, `browse`, `transfer list|show|modify|cancel`.

The Transfer Daemon and the gem `grpc` must be installed (see [Agent: Transfer Daemon](#agent-transfer-daemon)).
The emulator starts its own `transferd`, and stops it on exit.

It takes an optional `Hash` argument with the following parameters:

<%=schema_to_table('node_opts:components.schemas.NodeEmulatorOptions')%>

For details on `url` and HTTPS, see [Web service](#web-service).

Like on a real node, the files of the emulator are in its `docroot`: paths of `browse`, and local paths of transfers, are relative to it.
Local paths are the sources of an upload (`send`), and the destination of a download (`receive`).
Paths leading out of the `docroot`, also through symbolic links, are rejected.

Start the emulator, it runs until interrupted:

```shell
<%=cmd%> node emulator @json:'{"url":"http://localhost:12348","username":"sim","password":"<%=ph :password%>","docroot":"/data"}'
```

Generate the password with `openssl rand -hex 32`.
A weak password is refused at startup: its strength is estimated in bits, and shall be at least `password_min_bits`.
`username` and `password` are mandatory when `url` is not a loopback address (see [Web service](#web-service)): anyone reaching the emulator could send the files of the `docroot` to any host.

Then, in another terminal, use it as a node, for example, to list the files in `/data`:

```shell
<%=cmd%> node --url=http://localhost:12348 --username=sim --password=<%=ph :password%> browse /
```

Or as the transfer agent, for example, to upload the file `/data/my_file.dat` to a transfer server:

```shell
<%=cmd%> server upload /my_file.dat --transfer.agent=node --transfer.url=http://localhost:12348 --transfer.username=sim --transfer.password=<%=ph :password%>
```

The transfer is executed by `transferd`, and its status is available on the emulator:

```shell
<%=cmd%> node --url=http://localhost:12348 --username=sim --password=<%=ph :password%> transfer list
```

Supported endpoints:

| Verb     | Path                  | Action                                                                                            |
|----------|-----------------------|---------------------------------------------------------------------------------------------------|
| `GET`    | `/info`               | Node information, version and license from `transferd`.                                           |
| `GET`    | `/ops/transfers`      | List transfers. Query parameters: `active_only`, `direction`, `count`.                            |
| `POST`   | `/ops/transfers`      | Start a transfer with `transferd`.                                                                |
| `GET`    | `/ops/transfers/{id}` | Transfer information, with sessions and files.                                                    |
| `PUT`    | `/ops/transfers/{id}` | Modify `target_rate_kbps`, `min_rate_kbps` or `rate_policy`, or cancel with `status`: `canceled`. |
| `CANCEL` | `/ops/transfers/{id}` | Cancel a transfer.                                                                                |
| `POST`   | `/files/browse`       | List a folder of the `docroot`.                                                                   |

Limitations:

- Only transfers started through the emulator are known. They are kept in memory, and lost when the emulator stops. Ended transfers are removed from the list after `retention_sec` (default: one day).
- Only Basic authentication is supported: when `username` and `password` are set, bearer tokens and access keys are rejected. When they are not set (loopback `url` only), all requests are accepted.
- Not supported: `files/upload_setup` and `files/download_setup` (so, `node upload|download` on the emulator), `ops/transfers/bandwidth`, pause and resume of transfers, query parameters `iteration_token` and `tag`.

