## Plugin: `faspex5`: IBM Aspera Faspex v5

Faspex 5 is IBM Aspera's newer self-managed application.

The following authentication methods are supported (option `auth`):

| Method        | Description                                                         |
|---------------|---------------------------------------------------------------------|
| `jwt`         | General purpose, private-key based authentication                   |
| `web`         | Requires authentication with web browser                            |
| `public_link` | Public link authentication (set when option `url` is a public link) |
| `boot`        | Use authentication token copied from browser (experimental)         |

> [!TIP]
> If you have a Faspex 5 public link, provide it, as-is, through the option `url`.

### Faspex 5 quick start with wizard

For a quick start, one can use the wizard, which will help to create an [Option Preset](#option-preset):

```shell
<%=cmd%> config wizard
```

Then, answer questions interactively:

```text
argument: url> faspex5.example.com
```

If multiple applications are detected, the wizard asks which one to use (this step is skipped if only Faspex is detected):

```text
Multiple applications detected:
╭─────────┬───────────────────────────────────────────┬─────────────╮
│ product │ url                                       │ version     │
╞═════════╪═══════════════════════════════════════════╪═════════════╡
│ faspex5 │ https://faspex5.example.com/aspera/faspex │ F5.0.6      │
│ server  │ ssh://faspex5.example.com:22              │ OpenSSH_8.3 │
╰─────────┴───────────────────────────────────────────┴─────────────╯
product> faspex5
```

When Faspex is detected, the wizard asks for a private key (a value like `@file:<path>`).
If you do not have a private key, leave that field blank, and one will be generated or a previously generated key will be used.

```text
Using: Faspex at https://faspex5.example.com/aspera/faspex
Private RSA key, e.g. @file:<path> (leave empty to generate):
option: private_key>
Using existing key:
/Users/someuser/.aspera/<%=cmd%>/my_key
```

Then, the email of the user shall be provided:

```text
option: username> someuser@example.com
```

The administrator of Faspex shall provide you with a `client_id`, as specified below.

```text
Ask the <%=cmd%> client ID and secret to your Administrator.
Admin should login to: https://faspex5.example.com/aspera/faspex
Navigate to: ::  → Admin → Configurations → API clients
Create an API client with:
- name: <%=cmd%>
- JWT: enabled
Then, logged in as someuser@example.com go to your profile:
(User) → Account Settings → Preferences → Public Key in PEM:
-----BEGIN PUBLIC KEY-----
redacted
-----END PUBLIC KEY-----
Once set, fill in the parameters:
option: client_id> <%=ph :client_id%>
option: client_secret> ****
Preparing preset: faspex5_example_com_user
Setting config preset as default for faspex5
Done.
You can test with:
<%=cmd%> faspex5 user profile show
Saving configuration file.
```

> [!NOTE]
> Paste the entire public key, including the BEGIN and END lines, into the user's profile.

For more information on the JWT method, refer to the section below.

If you have generated a private key with the wizard and lost the public key, you can retrieve the public key like this:

```shell
<%=cmd%> faspex5 --show-config --out.secrets=yes --fields=private_key | <%=cmd%> config pubkey @stdin: --out.secrets=yes
```

### Faspex 5 JWT authentication

This is the general purpose and **recommended** method to use.

Activation is in two steps:

- The administrator must create an API client in Faspex with JWT support

  This operation is generally done only once:

  - As Admin, Navigate to the web UI: Admin &rarr; Configurations &rarr; API Clients &rarr; Create
  - Give a name, like <%=tool%>
  - Activate JWT
  - There is an option to set a global public key allowing the owner of the private key to impersonate any user.
    Unless you want to do this, leave this field empty.
  - Click **Create**
  - Take note of Client ID (and Client Secret, but not used in current version)

- The user will authenticate with a private key and set the public key in their Faspex 5 profile.

  This operation is done by each user using the CLI.

  - As a user, click the user logo located to the left of the app switcher in the top-right corner.
  - Select `Account Settings`.
  - At the bottom, in the `Public key in PEM format` field, paste the **public key** that corresponds to the private key assigned to your account.

> [!TIP]
> If you don't have a private key, see [Private Key](#private-key) to generate one.

Then use these options:

```text
--auth=jwt
--client-id=<%=ph :client_id%>
--client-secret=<%=ph :secret%>
--username=<%=ph :username%>
--private-key=@file:.../path/to/key.pem
```

> [!NOTE]
> Use the `private_key` option to provide the PEM content (not the file path).
> To load from a file, prefix the path with `@file:`, for example, `@file:/path/to/key.pem`.

Typically, users create a preset so they don't have to enter these options each time.

Example:

```shell
<%=cmd%> config preset set <%=ph :f5_preset%> @: auth=jwt client_id=<%=ph :client_id%> client_secret=<%=ph :secret%> username=<%=ph :username%> private_key=@file:.../path/to/key.pem

<%=cmd%> config preset set default faspex5 <%=ph :f5_preset%>

<%=cmd%> faspex5 user profile show
```

### Faspex 5 web authentication

For web-based authentication, the administrator must create an **API client** in Faspex to support an external web app:

- As Admin, Navigate to the web UI: Admin &rarr; Configurations &rarr; API Clients &rarr; Create
- Do not Activate JWT
- Set **Redirect URI** to `https://127.0.0.1:8888`
- Click **Create**
- Take note of the Client Id, and of the Client Secret if HTTP basic authentication is enabled on the API client

The user will use the following options (`client_secret` only if HTTP basic authentication is enabled on the API client):

```text
--auth=web
--client-id=<%=ph :client_id%>
--client-secret=<%=ph :secret%>
--redirect-uri=https://127.0.0.1:8888
```

<%=tool%> uses PKCE (RFC 7636, method `S256`): the authorization code can be exchanged for a token only by the <%=tool%> process that requested it.
Faspex checks it since version 5.0.16, earlier versions ignore it.

### Faspex 5 public link authentication

If all you have is a public link received by email or other, you can still do authorized actions with it.

For example, for a public link to post a package:

```shell
<%=cmd%> faspex5 packages send --url='https://faspex5.example.com/?context=<%=ph :context%>'
```

### Faspex 5 bootstrap authentication

For `boot` method: (will be removed in future)

- As user: Open a Web Browser
- Start developer mode
- Login to Faspex 5
- Find the first API call with `Authorization` header, and copy the value of the token (series of base64 values with dots)

Use this token as password and use `--auth=boot`.

```shell
<%=cmd%> config preset set f5boot @: url=https://localhost/aspera/faspex auth=boot password=<%=ph :token%>
```

<%=include_commands_for_plugin(:faspex5)%>

Most commands correspond directly to REST API calls.
Parameters to commands are carried through option `query`, as [Extended Value](#extended-value-syntax), for `list`, or through **Command Parameter** for creation.
For a single parameter, the dot-path option form is the most direct (for example, `--query.status=completed`).
For multiple parameters or when copying directly from API documentation, `@json:` is more suitable.

> [!TIP]
> The API is listed in [Faspex 5 API Reference](https://developer.ibm.com/apis/catalog?search="faspex+5") under **IBM Aspera Faspex API**.

### Faspex 5: Inbox selection

By default, package operations `receive` and `list` are performed on all the user's inboxes, not archived (`inbox_all`).

To select another inbox, use option `box` with one of the following values:

| `box`               | Comment                                  |
|---------------------|------------------------------------------|
| `inbox_all`         | All packages (not archived) **Default**. |
| `inbox_all_history` | All archived packages.                   |
| `inbox`             | My packages. (not archived)              |
| `inbox_history`     | My archived packages.                    |
| `outbox`            | Sent packages.                           |
| `outbox_history`    | Archived sent packages.                  |
| `pending`           | Pending packages.                        |
| `pending_history`   | Archived pending packages.               |
| `all`               | All boxes accessible by current user.    |
| `ALL`               | All boxes of all users. **admin only**.  |
| `<%=ph :name%>`            | Name of shared inbox or workgroup.<%=br%>If option `group_type` is `shared_inboxes`: name of a shared inbox (default).<%=br%>If `group_type` is `workgroups`: name of workgroup. |

> [!NOTE]
> In case the name of the `box` is an open value, use option `group_type` set to either `shared_inboxes` or `workgroups`.
> A `submit_only` user cannot list packages in a shared inbox.

### Faspex 5: Send a package

Use the following command to send a package:

```shell
<%=cmd%> faspex5 packages send <%=ph :package_data%> <%=ph :file_list%> ...
```

The `Hash` passed as a command parameter corresponds to the Faspex 5 API endpoint [`POST /packages`](https://developer.ibm.com/apis/catalog/aspera--ibm-aspera-faspex-5-0-api/api/API--aspera--ibm-aspera-faspex-api#createPackageRecord).
See the API reference for a full list of supported fields, or inspect such a request in the browser developer tools.

The following fields are required:

- `title` - the package title
- `recipients` - the intended recipients

> [!NOTE]
> The `box` option does not select a recipient shared inbox.
> Use parameter `recipients` to send a package to a specific shared inbox.

Basic example (assuming a default preset has been configured for connection information):

```shell
<%=cmd%> faspex5 packages send @json:'{"title":"some title","recipients":["user@example.com"]}' <%=ph :file_path%>
```

#### Specifying Recipients

The Faspex 5 API expects recipients to be an `Array` of `Hash`, each containing a `name` field and an optional `recipient_type` field:

```json
{"title":"some title","recipients":[{"recipient_type":"user","name":"user@example.com"}]}
```

Valid values for `recipient_type` are (API):

- `user`
- `workgroup`
- `external_user`
- `distribution_list`
- `shared_inbox`

Other "recipient" fields are also defined in the API and can be used:

- `private_recipients`
- `notified_on_upload`
- `notified_on_download`
- `notified_on_receipt`

If the provided list is only an `Array` of `String`, then fields `name` and `recipient_type` are resolved automatically using the user's `contacts`.

#### Simplified recipient format

As a convenience, <%=tool%> also accepts plain `String`s in the recipients `Array` rather than `Hash`es:

```json
{"title":"some title","recipients":["user@example.com"]}
```

When `Strings` are provided, <%=tool%> automatically looks up the contact across all recipient types.
If exactly one match is found, the `name` and `recipient_type` fields are resolved automatically.
If no match or multiple matches are found, an exception is raised.

> [!NOTE]
> The lookup is case-insensitive and on partial matches.

#### Sending to a shared inbox

To address a shared inbox, set `recipient_type` to `shared_inbox`:

```json
{"title":"some title","recipients":[{"recipient_type":"shared_inbox","name":"box name"}]}
```

#### Restricting the lookup to specific recipient types

To limit automatic contact lookup to one or more specific types, include the `recipient_types` field with either a single value or an `Array` of values:

```json
{"title":"test title","recipient_types":"user","recipients":["user1@example.com","user2@example.com"]}
```

#### Content Protection (Encryption at Rest)

To enable content protection (CSEAR), set parameter `ear_enabled` to `true` in the package creation payload.
See the Faspex package creation API for full details.

The following error is returned by Faspex if CSEAR was not specified in the package creation and if it is configured as mandatory on the server:

```text
the provided encryption value (no) does not match the expected server side encryption value (yes)
```

#### Package with metadata

To attach metadata to a package, include the `metadata` field in the package creation payload.
See the API documentation.
Each key corresponds to a metadata field name, and its value is the metadata value:

```json
{"title":"test title","recipients":["<%=ph :sh_inbox_name%>"],"metadata":{"Confidential":"Yes","Drop menu":"Option 1"}}
```

### Faspex 5: List packages

Option `box` can be used to list packages from a specific box (see [Inbox Selection](#faspex-5-inbox-selection) above).

Option `query` can be used to filter the list of packages, based on native API parameters, directly sent to [Faspex 5 API `GET /packages`](https://developer.ibm.com/apis/catalog/aspera--ibm-aspera-faspex-5-0-api/api/API--aspera--ibm-aspera-faspex-api#getAllPackages).

| Parameter | Type  | Description                                       |
|---------|---------|---------------------------------------------------|
| `offset`| Native  | Managed by <%=tool%>: Offset of first package.<%=br%>Default: `0` |
| `limit` | Native  | Managed by <%=tool%>: # of packages per API call.<%=br%>Default: `100` |
| `q`     | Native  | General search string, case-insensitive.<%=br%>Matches if value is contained in one of several fields. |
| ...     | Native  | Other native parameters are supported.<%=br%>See API documentation. |
| `max`   | Special | Maximum number of **items** to retrieve<%=br%>Stop pages when the maximum is passed. |
| `pmax`  | Special | Maximum number of **pages** to request.<%=br%>Stop pages when the maximum is passed. |

A **Command Parameter** in last position, of type `Proc`, can be used to filter the list of packages.
The advantage of this method is that the expression can be any test, even complex, as it is Ruby code.
But the disadvantage is that the filtering is done in <%=tool%> and not in Faspex 5, so it is less efficient.

Examples:

- List only available packages: (filtering is done in Faspex)

  ```shell
  <%=cmd%> faspex5 packages list --query=@json:'{"status":"completed"}'
  ```

- Similar, using filtering in <%=tool%>:

  ```shell
  <%=cmd%> faspex5 packages list @ruby:'->(p){p["state"].eql?("released")}'
  ```

### Faspex 5: Browsing folder content

Several entities support folder browsing: Packages, Nodes, Shared Folders.
All support two modes: paging and legacy API.
By default, paging is used.

Option `query` is available with parameters supported by the API and <%=tool%>:

| Parameter | Evaluation   | Default           | Description                             |
|-----------|--------------|-------------------| ----------------------------------------|
| `paging`  | <%=tool%>    | `true`            | Use paging API.                         |
| `recursive`| <%=tool%>   | `false`           | List inside folders.                    |
| `max`     | <%=tool%>    | -                 | Maximum number of items.                |
| `filter`  | API          | `{"basenames":[]}`| See API doc.                       |
| `offset`  | API (legacy) | `0`               | Index of first item.                    |
| `limit`   | API (legacy) | `500`             | Number of items in one API call result. |
| `per_page`| API (paging) | `500`             | Number of items in one API call result. |

### Faspex 5: Content of a received Package

> [!NOTE]
> Listing content also applies to sent packages using `--box=outbox`.

To list the content of a received package, use command `faspex5 packages browse <%=ph :package_id%>`.
Optionally, provide a folder path.

### Faspex 5: Receive a package

To receive one, or several packages at once, use command `faspex5 packages receive`.
Provide either a single package ID, or an [Extended Value](#extended-value-syntax) `Array` of package IDs, for example, `@list:,1,2,3` as argument.

The same options as for `faspex5 packages list` can be used to select the box and filter the packages to download.
That is, options `box` and `query`, and the last **Command Parameter** `Proc` (filter).

Option `--once-only=yes` can be used, for "cargo-like" behavior.
Special package ID `INIT` initializes the persistency of already received packages when option `--once-only=yes` is used.

Special package ID `ALL` selects all packages (of the selected box).
In this case, typically, only `completed` packages should be downloaded, so use option `--query.status=completed` (or equivalently `--query=@json:'{"status":"completed"}'`).

If a package is password protected, then the content protection password is asked interactively.
To keep the content encrypted, use option: `--ts=@json:'{"content_protection":null}'`, or provide the password instead of `null`.

> [!TIP]
> If you use option `query` and/or positional `filter`, you can use the `list` command for a dry run.

### Faspex 5: List all shared inboxes and work groups

> [!NOTE]
> **Shared inboxes** (`faspex5 admin shared_inboxes`) are package recipients (dropboxes), accessible under the **Packages** app.
> They are distinct from **shared folders** (`faspex5 shared_folders`), which are node-based storage access points accessible under the **Files** app.

If you are a regular user, to list work groups you belong to:

```shell
<%=cmd%> faspex5 admin workgroups list
```

If you are admin or manager, add option `--query=@json:'{"all":true}'`: this lists items you manage, even if you do not belong to them.
Example:

```shell
<%=cmd%> faspex5 admin shared_inboxes list --query=@json:'{"all":true}' --fields=id,name
```

Shared inbox members can also be listed, added, removed, and external users can be invited to a shared inbox.

```shell
<%=cmd%> faspex5 admin shared_inboxes invite_external_collaborator '%name:the shared inbox' @: email_address=john@example.com
```

It is equivalent to:

```shell
<%=cmd%> faspex5 admin shared_inboxes invite_external_collaborator '%name:the shared inbox' @json:'{"email_address":"john@example.com"}'
```

Other payload parameters are possible for `invite_external_collaborator` in this last `Hash` **Command Parameter**:

```json
{"description":"blah","prevent_http_upload":true,"custom_link_expiration_policy":false,"invitation_expires_after_upload":false,"set_invitation_link_expiration":false,"invitation_expiration_days":3}
```

### Faspex 5: Create Metadata profile

```shell
<%=cmd%> faspex5 admin metadata_profiles create @json:'{"name":"the profile","default":false,"title":{"max_length":200,"illegal_chars":[]},"note":{"max_length":400,"illegal_chars":[],"enabled":false},"fields":[{"ordering":0,"name":"field1","type":"text_area","require":true,"illegal_chars":[],"max_length":100},{"ordering":1,"name":"fff2","type":"option_list","require":false,"choices":["opt1","opt2"]}]}'
```

### Faspex 5: Create a Shared inbox with specific metadata profile

```shell
<%=cmd%> faspex5 admin shared_inboxes create @json:'{"name":"the shared inbox","metadata_profile_id":1}'
```

### Faspex 5: List content in Shared folder and send package from remote source

> [!NOTE]
> **Shared folders** (`faspex5 shared_folders`) provide node-based storage access, accessible under the **Files** app.
> They are distinct from **shared inboxes** (`faspex5 admin shared_inboxes`), which are package recipients (dropboxes) accessible under the **Packages** app.

```shell
<%=cmd%> faspex5 shared_folders list --fields=id,name
```

```text
╭────┬──────────────╮
│ id │ name         │
╞════╪══════════════╡
│ 2  │ Server Files │
╰────┴──────────────╯
```

```shell
<%=cmd%> faspex5 shared_folders browse %name:'Server Files' /folder
```

```shell
<%=cmd%> faspex5 packages send @json:'{"title":"hello","recipients":[{"name":"<%=ph :recipient%>"}]}' --shared-folder=%name:partages /folder/file
```

> [!TIP]
> The shared folder can be identified by its numerical `id` or by name using the [percent selector](#percent-selector): `%<%=ph :field%>:<%=ph :value%>`. For example: `--shared-folder=3` or `--shared-folder=%name:partages`.

### Faspex 5: Receive all packages (cargo)

To receive all packages, only once, through persistency of already received packages:

```shell
<%=cmd%> faspex5 packages receive ALL --once-only=yes --query=@json:'{"status":"completed"}'
```

To initialize, that is, skip all current packages, so that next time `ALL` is used, only newer packages are downloaded:

```shell
<%=cmd%> faspex5 packages receive INIT --once-only=yes
```

### Faspex 5: Invitations

There are two types of invitations for package submission: public or private.

Public invitations are for external users; provide only the email address.

```shell
<%=cmd%> faspex5 invitations create @json:'{"email_address":"john@example.com"}' --fields=access_url
```

Private invitations are for internal users: provide the user or shared inbox identifier through field `recipient_name`.

### Faspex 5: Cleanup packages

> [!WARNING]
> Operation requires admin level.

The default automated cleanup period can be displayed with:

```shell
<%=cmd%> faspex5 admin configuration show --fields=days_before_deleting_package_records
```

This parameter can be modified with:

```shell
<%=cmd%> faspex5 admin configuration modify @json:'{"days_before_deleting_package_records":30}'
```

To start package purge, that is, permanently remove packages marked for deletion older than `days_before_deleting_package_records`, use command:

```shell
<%=cmd%> faspex5 admin clean_deleted
```

> [!NOTE]
> The expiration period taken by default is the one from `admin configuration show`.
> To use a different period than the default, specify it on command line with: `@json:'{"days_before_deleting_package_records":15}'`

To delete all packages, one can use the following command:

```shell
<%=cmd%> faspex5 packages list --box=ALL --format=yaml --fields=id | <%=cmd%> faspex5 packages delete @yaml:@stdin:
```

> [!NOTE]
> Above command will mark all packages for deletion, and will be permanently removed after the configured period (`clean_deleted` command).
> It is possible to add a filter to the list command to only delete packages matching some criteria, for example, using `--select=@ruby:'->(p){...}'` on `packages list`.

### Faspex 5: Admin: Unlock user

To unlock a user, you can deactivate and then re-activate the user:

```shell
<%=cmd%> faspex5 admin accounts modify %name:some.user@example.com @json:'{"account_activated":false}'
```

```shell
<%=cmd%> faspex5 admin accounts modify %name:some.user@example.com @json:'{"account_activated":true}'
```

> [!TIP]
> This example uses the [percent selector](#percent-selector), but the numerical ID can be used as well.

To send a password reset link to a user, use command `faspex5 admin accounts reset_password <%=ph :account_id%>`.

### Faspex 5: Faspex 4-style post-processing

The command `<%=cmd%> faspex5 postprocessing` emulates Faspex 4 post-processing script execution in Faspex 5.
It implements a web hook for Faspex 5 and calls a script with the same environment variables as set by Faspex 4.
Environment variables are set to the values provided by the web hook, which are the same as Faspex 4 post-processing.
Only values whose key starts with `faspex_` are passed: other keys are ignored, as they could change the behavior of the script (e.g. `PATH`).
A structured value (object or array) is passed as JSON.

It allows migrating workflows from Faspex 4 to Faspex 5 while preserving scripts.
Nevertheless, in the long term, a native approach shall be considered, such as using Aspera Orchestrator or other workflow engine, using Faspex 5 native web hooks or File Processing.

It is invoked like this:

```shell
<%=cmd%> faspex5 postprocessing
```

An optional positional parameter can be provided as [Extended Value](#extended-value-syntax) `Hash`:

<%=schema_to_table('faspex5_opts:components.schemas.Faspex4PostProcOptions')%>

For details on `url` and HTTPS (`cert`, `key`, `chain`), see [Web service](#web-service).

When a request on <%=tool%> is received the following happens:

- If `allowed_ips` is set, <%=tool%> checks the source IP address of the request (else HTTP 403).
- If `secret_token` is set, <%=tool%> checks the `token` parameter of the URL (else HTTP 401).
- <%=tool%> gets the path of the URL called.
- It removes the **base path** of base URL.
- It prepends it with the value of `script_folder`.
- It executes the script at that path, if it exists (else HTTP 404) and is inside `script_folder` (else HTTP 403).
- The script is killed if it does not finish within `timeout_seconds`.
- Upon success, a success code is returned.

For example:

```shell
<%=cmd%> faspex5 postprocessing @json:'{"url":"http://0.0.0.0:8080/processing","script_folder":"/opt/scripts","secret_token":"<%=ph :token%>"}'
```

Generate the token with `openssl rand -hex 32`.
A weak token is refused at startup: its strength is estimated in bits, and shall be at least `secret_token_min_bits`.
The estimate uses the optional gem `zxcvbn` if installed, else a built-in estimate.

In Faspex 5, the URL of the webhook endpoint shall be reachable from within Faspex containers.
For example, if <%=tool%> is running on the host, the URL hostname shall not be `localhost`, as this refers to the local address inside the Faspex container.
Instead, one can specify the **IP address of the host** or `host.containers.internal` (Check `podman` manual).
So, <%=tool%> shall listen on an address reachable from the containers: the IP address of the host, or `0.0.0.0` for all interfaces.

> [!NOTE]
> **Security**: by default the listener binds to loopback (`localhost`) and is not reachable from outside the host (see [Web service](#web-service)).
> When `url` is not a loopback address, at least one of the following protections is required:
>
> - **`secret_token`**: include the token in the Faspex webhook URL: `http://host:8080/processing/script1.sh?token=<%=ph :token%>`. Requests without the correct token are rejected with HTTP 401.
> - **`allowed_ips`**: restrict the listener to the known Faspex container IPs or network, e.g. `@json:'{"allowed_ips":["192.168.1.10","10.89.0.0/24"]}'`. Requests from other IPs are rejected with HTTP 403.

Define the web hook as follows:

**Webhook endpoint URI**: `http://host.containers.internal:8080/processing/script1.sh?token=<%=ph :token%>`

Then the post-processing script executed will be `/opt/scripts/script1.sh`.

A Ruby script can also be evaluated in the process of <%=tool%>, instead of being executed in a new process.
For this, add `lambda` to the query of the URL, e.g. `http://host.containers.internal:8080/processing/notify.rb?token=<%=ph :token%>&lambda`.
The script shall have extension `.rb`, and return a lambda, which is called with all the webhook values (`Hash`).
For example:

```ruby
->(params) { File.write('/tmp/last_package.txt', params['faspex_pkg_name']) }
```

The lambda runs with the privileges and configuration of <%=tool%>, and is stopped after `timeout_seconds`.

### Faspex 5: Faspex 4 Gateway

> [!NOTE]
> This is not a feature for production.
> It's provided for testing only.

For legacy Faspex client applications that use the `send` API (only) of Faspex v4, the command `gateway` provides the capability to present an API compatible with Faspex 4, and it will call the Faspex 5 API.

It takes an optional `Hash` argument:

<%=schema_to_table('faspex4_opts:components.schemas.Faspex4GatewayOptions')%>

For details on `url` and HTTPS (`cert`, `key`, `chain`), see [Web service](#web-service).

Example:

```shell
<%=cmd%> faspex5 gateway @json:'{"url":"https://localhost:12345/aspera/faspex","username":"fx4","password":"<%=ph :password%>"}'
```

Clients authenticate with HTTP Basic, as on Faspex 4, with the `username` and `password` of the gateway.
Generate the password with `openssl rand -hex 32`.
A weak password is refused at startup: its strength is estimated in bits, and shall be at least `password_min_bits`.
`username` and `password` are mandatory when `url` is not a loopback address (see [Web service](#web-service)): anyone reaching the gateway could send packages to anyone, as the Faspex 5 user.
When they are not set, requests are accepted without authentication.

There are many limitations:

- It's only to emulate the Faspex 4 `send` API (send package).
- No support for remote sources, only for an actual file transfer by the client.
- The client must use the transfer spec returned by the API (not `faspe:` URL).
- Tags returned in transfer spec must be used in transfer.
- Only a single authentication is possible (per gateway) on Faspex 5: all packages are sent by the same Faspex 5 user.

Behavior:
The API client calls the Faspex 4 API on the gateway, then the gateway transforms this into a Faspex 5 API call, which returns a transfer spec, which is returned to the calling client.
The calling client uses this to start a transfer to HSTS, which is managed by Faspex 5.

### Faspex 5: Get Bearer token to use API

If a command is missing, then it is still possible to call the API directly on the command line using `curl`:

```shell
curl -H "Authorization: $(<%=cmd%> faspex5 bearer_token --out.secrets=yes)" https://faspex5.example.com/aspera/faspex/api/v5/<%=ph :api_endpoint%>
```

